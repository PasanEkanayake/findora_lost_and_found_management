// Findora — send-push-notification
//
// Triggered by a Supabase Database Webhook on INSERT into public.notifications
// (see supabase/14_notifications.sql for what creates those rows, and
// README.md's "Sending real push notifications" for how to wire this up —
// that setup needs your own Firebase project and can't be done from here).
//
// What this does:
//   1. Reads the new notification row from the webhook payload.
//   2. Looks up the recipient's stored FCM device token.
//   3. Mints a short-lived Google OAuth2 access token from a Firebase
//      service account (plain Web Crypto RS256 signing — deliberately NOT
//      the firebase-admin npm package, which has a history of flaky
//      deploys on Supabase's Deno runtime; this needs nothing beyond
//      fetch() and crypto.subtle, both guaranteed stable here).
//   4. Sends the push via the FCM HTTP v1 API, with both a `notification`
//      block (so Android shows it automatically even when the app is
//      fully closed — no client code needed for that part at all) and a
//      `data` block carrying where to navigate on tap.
//   5. If FCM reports the token is dead, clears it from the profile so
//      this stops being retried every time.
//
// This file has no secrets in it. Everything it reads comes from Edge
// Function secrets (`supabase secrets set ...`), set up once against your
// own Firebase project — see the README section named above.

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

interface NotificationRow {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string | null;
  item_id: string | null;
}

interface WebhookPayload {
  type: string;
  table: string;
  record: NotificationRow;
}

// Mirrors NotificationModel.destinationRoute in
// lib/features/notifications/data/notification_model.dart — kept in sync
// by hand (Dart and this Deno function can't literally share code), so a
// tapped push lands in the same place tapping the in-app Alerts entry
// would. If you change one, change the other.
function destinationRoute(row: NotificationRow): string {
  if (row.type === "new_match" && row.item_id) return `/item/${row.item_id}/matches`;
  if (row.type === "item_returned") return "/profile/returned";
  if (row.type === "new_rating") return "/profile/ratings";
  return "/chats";
}

function base64UrlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const bin = String.fromCharCode(...new Uint8Array(bytes));
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

/** Google service-account JWT-bearer flow: sign a short-lived JWT with the
 *  service account's private key, trade it for an OAuth2 access token.
 *  Standard server-to-server flow — see Google's "Using OAuth 2.0 for
 *  Server to Server Applications" docs. */
async function getAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const header = base64UrlEncode(new TextEncoder().encode(JSON.stringify({
    alg: "RS256",
    typ: "JWT",
  })));
  const now = Math.floor(Date.now() / 1000);
  const claims = base64UrlEncode(new TextEncoder().encode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: FCM_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlEncode(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) {
    throw new Error(`Token exchange failed: ${response.status} ${await response.text()}`);
  }
  const data = await response.json();
  return data.access_token as string;
}

Deno.serve(async (req) => {
  // Defence in depth beyond Edge Functions' own JWT check: a Database
  // Webhook's outbound request carries whatever header you configured for
  // it, not a real Supabase session — this confirms the call actually
  // came from the webhook you set up, not from anyone who finds this
  // function's URL. Set the same value in both places; see the README.
  const expectedSecret = Deno.env.get("WEBHOOK_SECRET");
  const suppliedSecret = req.headers.get("x-webhook-secret");
  if (expectedSecret && suppliedSecret !== expectedSecret) {
    // Deliberately not logging either secret's value — only enough to
    // tell these two failure modes apart without leaking anything.
    console.error(
      suppliedSecret === null
        ? "Rejected: request had no x-webhook-secret header at all. Check the Database Webhook's custom HTTP headers in the Supabase dashboard."
        : `Rejected: x-webhook-secret header was present (${suppliedSecret.length} chars) but didn't match WEBHOOK_SECRET (${expectedSecret.length} chars). Re-check both values match exactly, including no trailing whitespace.`,
    );
    return new Response("Unauthorized", { status: 401 });
  }
  if (!expectedSecret) {
    // Not fatal — the request still goes through, since platform-level
    // verify_jwt (the service_role token pg_net sends automatically) is
    // real protection on its own — but this is worth knowing about.
    console.warn("WEBHOOK_SECRET isn't set, so the x-webhook-secret check is skipped entirely.");
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  if (payload.table !== "notifications" || payload.type !== "INSERT") {
    // Not something this function needs to act on — acknowledge rather
    // than error, in case the webhook is ever broadened to other events.
    return new Response("Ignored", { status: 200 });
  }
  const row = payload.record;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountJson) {
    console.error("Missing one of SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / FIREBASE_SERVICE_ACCOUNT_JSON");
    return new Response("Server misconfigured", { status: 500 });
  }
  const serviceAccount = JSON.parse(serviceAccountJson);

  // Service-role key bypasses RLS deliberately — this function needs to
  // read a token belonging to someone who isn't the caller (there is no
  // caller in the usual sense; this runs as the system, not as a user).
  const profileResponse = await fetch(
    `${supabaseUrl}/rest/v1/profiles?id=eq.${row.user_id}&select=fcm_token`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );
  const profiles = await profileResponse.json();
  const fcmToken = profiles?.[0]?.fcm_token as string | null | undefined;
  if (!fcmToken) {
    // No device registered for this user — nothing to send, not an error.
    return new Response("No device token", { status: 200 });
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken(serviceAccount);
  } catch (e) {
    console.error("Failed to mint FCM access token:", e);
    return new Response("Auth failed", { status: 500 });
  }

  const sendResponse = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: {
            title: row.title,
            body: row.body ?? "",
          },
          data: {
            route: destinationRoute(row),
            notification_id: row.id,
          },
          android: { priority: "high" },
        },
      }),
    },
  );

  if (!sendResponse.ok) {
    const errorBody = await sendResponse.text();
    console.error(`FCM send failed (${sendResponse.status}):`, errorBody);
    // UNREGISTERED (and some INVALID_ARGUMENT cases) mean this token will
    // never work again — typically the app was uninstalled, or Firebase
    // rotated the token server-side. Clearing it stops every future
    // notification for this user from retrying a dead token forever.
    if (errorBody.includes("UNREGISTERED") || errorBody.includes("NOT_FOUND")) {
      await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${row.user_id}`, {
        method: "PATCH",
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ fcm_token: null }),
      });
    }
    return new Response("FCM send failed", { status: 502 });
  }

  return new Response("Sent", { status: 200 });
});
