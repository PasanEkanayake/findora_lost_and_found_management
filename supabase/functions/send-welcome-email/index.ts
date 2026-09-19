// Findora — send-welcome-email edge function.
//
// Called by the `on_email_confirmed` Postgres trigger (see
// supabase/07_email_confirmation.sql) the moment a new user clicks the
// "Confirm your email" link — i.e. exactly once per account, right after
// `auth.users.email_confirmed_at` is first set. Sends a short "you're
// verified!" email via Resend (https://resend.com — free tier is plenty
// for this) so signing up ends with a clear confirmation instead of
// silence.
//
// Deploy with:
//   supabase functions deploy send-welcome-email
//
// Required secret (Dashboard → Edge Functions → send-welcome-email →
// Secrets, or `supabase secrets set RESEND_API_KEY=re_xxx`):
//   RESEND_API_KEY       — from https://resend.com/api-keys
//
// Optional secret:
//   WELCOME_EMAIL_FROM   — defaults to "Findora <onboarding@resend.dev>",
//                          which only works for testing. For production,
//                          verify your own domain in Resend and set this to
//                          something like "Findora <hello@yourdomain.com>".

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL = Deno.env.get("WELCOME_EMAIL_FROM") ?? "Findora <onboarding@resend.dev>";

interface WelcomeEmailPayload {
  email: string;
  user_id: string;
  full_name: string | null;
}

// Kept in sync with supabase/email_templates/welcome_email.html — see that
// file's comment for why this lives inline rather than being read from
// disk.
function buildWelcomeEmailHtml(fullName: string | null): string {
  const displayName = fullName && fullName.trim().length > 0 ? escapeHtml(fullName.trim()) : "there";
  return `
<div style="margin:0;padding:0;background-color:#F4F6F8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#F4F6F8;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background-color:#FFFFFF;border-radius:16px;overflow:hidden;">
        <tr>
          <td style="background-color:#0F6E56;padding:32px 32px 24px 32px;text-align:center;">
            <div style="font-size:40px;line-height:1;">&#9989;</div>
            <div style="font-size:22px;font-weight:800;color:#FFFFFF;margin-top:8px;">You're all set!</div>
          </td>
        </tr>
        <tr>
          <td style="padding:32px 32px 8px 32px;">
            <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#3C3C43;">Hi ${displayName},</p>
            <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#3C3C43;">
              Your email is confirmed and your Findora account is ready to go.
              Here's what you can do next:
            </p>
            <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;margin:0 0 20px 0;">
              <tr><td style="padding:8px 0;font-size:14px;color:#3C3C43;">&#128248;&nbsp;&nbsp;Report a lost or found item — our on-device AI reads the photo for you</td></tr>
              <tr><td style="padding:8px 0;font-size:14px;color:#3C3C43;">&#129309;&nbsp;&nbsp;Get matched automatically against everyone else's reports</td></tr>
              <tr><td style="padding:8px 0;font-size:14px;color:#3C3C43;">&#128172;&nbsp;&nbsp;Chat safely once a match is confirmed, right in the app</td></tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:20px 32px;background-color:#FAFAF8;text-align:center;border-top:1px solid #ECECEC;">
            <div style="font-size:12px;color:#A3A9A5;">Findora — reuniting people with their things.</div>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</div>`;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!RESEND_API_KEY) {
    console.error("RESEND_API_KEY is not set — see this function's header comment.");
    return new Response(JSON.stringify({ error: "Email service not configured" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  let payload: WelcomeEmailPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!payload.email) {
    return new Response(JSON.stringify({ error: "email is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [payload.email],
      subject: "You're confirmed — welcome to Findora!",
      html: buildWelcomeEmailHtml(payload.full_name),
    }),
  });

  if (!resendResponse.ok) {
    const errorBody = await resendResponse.text();
    console.error("Resend API error:", resendResponse.status, errorBody);
    return new Response(JSON.stringify({ error: "Failed to send email" }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ sent: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
