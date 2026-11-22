# Findora — Setup Guide & Reference

Findora is a lost & found app: report a lost or found item, and the AI
compares it against everyone else's — by title and description always,
and by photo too if one's attached — to suggest a match.

This README has two parts. **Part A** is a complete, from-zero, step by
step walkthrough to get the app running on your own Android phone from
VS Code — every step is spelled out, including the ones that feel too
obvious to mention. **Part B** (further down) documents how each part of
the app actually works, organized by build phase, for when you're ready
to extend it.

If you've already been through setup once and just hit a Gradle error,
jump straight to **"Troubleshooting Gradle errors"** in Part A.

---

## What's new since the original build

A later upgrade pass added the following.

⚠️ **`05_multimodal_matching.sql` and `08_soft_delete.sql` are not
optional** — unlike everything else in this section, skipping them
doesn't just mean missing a feature, it **breaks browsing and posting
outright**. `08_soft_delete.sql` adds `items.deleted_at`, and the updated
app code filters every item read (the main feed, My Items, item detail)
on that column existing — run this update's Dart/Flutter code against a
database that hasn't had `08_soft_delete.sql` applied yet, and
`items.deleted_at` doesn't exist, so those queries fail outright and
**the browse feed appears empty** (really: failed to load) even though
your posts are still sitting in the database untouched.
`05_multimodal_matching.sql` similarly adds `items.event_time`, which
posting a new item with a lost/found time set will now try to write —
without that migration, that specific post attempt fails the same way.
If you've pulled this update's code but haven't touched Supabase yet,
**run those two migrations before testing anything**
(`06_contact_messaging.sql` and `07_email_confirmation.sql` are
genuinely optional — see their own rows below).

| Feature | What changed | Setup needed? |
|---|---|---|
| Delete your own posts | Owner-only "Delete post" (item detail's menu, swipe-to-delete in My Items) — now a **soft delete**, see below | **Required:** run `supabase/08_soft_delete.sql` |
| Home screen header | Gradient greeting header with a live lost/found count, replacing the old blank title bar | None |
| CNN photo auto-fill | Now also suggests a **title**, not just category | None |
| Lost/found time | Optional date+time picker when posting | **Required:** run `supabase/05_multimodal_matching.sql` |
| Contact any poster | New "Contact poster" direct-message thread, separate from the confirmed-match chat (Chats tab now has two tabs) | Optional — run `supabase/06_contact_messaging.sql`; skipping it just makes "Contact poster" show an error snackbar, nothing else breaks |
| Multimodal matching | Match score now blends image (CNN), text (NLP), and GPS proximity, not just image | **Required:** run `supabase/05_multimodal_matching.sql`; optionally also deploy `ai_service/` for the text signal |
| App icon | Same logo, white background instead of light blue | None — already regenerated. Re-run `python scripts/generate_icon_pngs.py` only if you change the logo |
| Email confirmation UX | Branded confirm email, opens the app on mobile / closes the tab on desktop, plus a second "you're verified" email | Optional — see "Email confirmation flow" below; skipping it just means Supabase's plain default confirmation email/redirect is used instead |
| Password strength | Live checklist + 5 rules enforced on signup | None |
| Manual location pin | "Adjust pin on map" alongside GPS auto-detect when posting | None |
| Exit confirmation | Back button on the Browse tab's root now asks before closing the app | None |
| Light/dark theme toggle | Profile → Appearance — Light/Dark/System, persisted | None |
| Soft delete | Deleting a post (by its owner or an admin) now hides it instead of removing the row — see "Soft delete: items are hidden, never erased" below | **Required:** run `supabase/08_soft_delete.sql` |
| "NEW" badge | Items posted within the last 3 days show a NEW pill on their card and detail page | None |
| Browse tab always goes home | Tapping "Browse" in the bottom nav now always shows the list, even if the map view was left open | None |
| Google signup confirmation | A first-time Google sign-in now lands on a "You're signed up!" screen before entering the app, instead of silently landing in /feed indistinguishably from a normal login | None — Google sign-in itself still needs its own setup, see "Google sign-in setup (Phase 2)" |
| Edit posts | Owner-only "Edit post" (item detail's menu, next to Delete) — title, description, category, location, event time. Not photos or lost/found type — see `ItemsRepository.updateItem`'s doc for why | None |
| Delete account | Profile → "Delete account" — soft-deletes their items, scrubs their name/photo/phone, blocks future sign-in. See "Account deletion" below for exactly what this does and doesn't do | **Required:** run `supabase/09_account_deletion.sql` |
| Chat flicker fixed | Both message screens (confirmed-match chat and direct messages) no longer flicker mid-conversation — rewritten to update incrementally instead of re-fetching the whole list on every change | None |
| AI matching fixed | Found and fixed the actual bug: photo embeddings were being sent in a format Postgres's `vector` type couldn't reliably parse, so no item ever had a usable embedding and matches could never be created | None — already fixed in code. **But also see "Generating the on-device model (Phase 4)" above** — a still-empty `assets/models/` is an equally common reason matches never appear, and is separate from this bug |
| Matching opened up | Category no longer gates matching — a lost item and a found item in different categories can still match on image/text/GPS/time. Added event-time proximity as a fourth scoring signal, and filter chips (Text match / Nearby / Similar time) on the Matches screen | **Required:** run `supabase/10_open_matching_and_time.sql` |

| Splash tagline | Now reads "The Smart Lost & Found Detective" | None |
| Live chat fixed | Messages (both the confirmed-match chat and direct messages) now show up immediately — the database was never told to broadcast them (`messages` / `contact_messages` were missing from the `supabase_realtime` publication). Also: your own message appears the instant you send it, incoming messages are marked read while the chat is open, a 5-second background sync covers a flaky connection, and the Chats/Matches tabs refetch when opened | **Required:** run `supabase/11_realtime_and_matching_fixes.sql` |
| Exit confirmation fixed | The "Leave Findora?" popup now really appears — the back-button guard moved from `MainShell` into each tab's own route (see "Exit confirmation" below) | None |
| AI matching, second fix | The bundled model's two outputs come out in the opposite order to what the app assumed, so every photo was posted with no embedding and nothing could ever match. The app now detects the order itself. Also: a **scan icon on the Matches tab** (and an automatic scan on opening it) that embeds photos posted before the fix, a visible warning when a photo can't be analyzed, a lower and tunable similarity cut-off, and a trigger so a photo embedded later still gets matched | **Required:** run `supabase/11_realtime_and_matching_fixes.sql`, then follow **A4b** below |

| Photos optional | A post now needs only a **title**. With no photo, the app shows the Findora logo on a neutral tile everywhere a photo would appear (feed, My reported items, matches, chats, post detail). The placeholder is drawn by the app — nothing is uploaded or stored for it. **Note:** it's still matched by title and description either way (see the next row) — a photo only adds a second, independent matching signal on top | None |
| Edit photos | Edit post now handles photos: add more, remove, or tap one to replace it. Changes are held until you press Save. A newly added photo is analysed on-device like at posting, so it can create matches straight away. Removing deletes the photo row and, best-effort, the file in Storage | None (the existing delete policies already cover it) |
| Match by title/description | Posts are now compared by their title and description too, not only their photo — so a post with no photo, or one whose photo failed AI analysis, can still be matched. Runs the moment a post is made or its title/description is edited. Uses a proper meaning-based comparison when the optional `ai_service/` text service is configured and awake, otherwise falls back to comparing the words themselves (no setup needed) | **Required for posts made before this:** run `supabase/12_text_matching.sql`, then `select public.rematch_all_text();` |
| Clearer matches | Each match card shows **your item on the left and the item it matched on the right** (photo, lost/found, title), and tapping either opens that post | None |

| Delete crash fixed | Swiping a post away in "My reported items" could crash with "A dismissed Dismissible widget is still part of the tree" if the server hadn't confirmed the delete by the next frame. The card is now hidden the instant the delete succeeds, instead of waiting on that round trip | None |

| Matches from a post | A post's detail page now has a "View possible matches" row: the owner sees every match found for it (or a note that the AI checks automatically if there are none yet); anyone else sees it only once the post is already matched against one of their own — tapping it opens the same Confirm / Not a match / Message actions as the Matches tab | None |

| Claim status crash + staleness | Filing/approving a claim could crash with a framework tree-consistency error ("_owner != null" / "_children.contains(child)"), because match cards in a list had no stable identity for Flutter to track when a match moved from pending to decided. Separately, the claim/return status banner in a chat only ever loaded once, so the other person's already-open chat never showed a claim was filed, approved, etc. until they left and reopened it | None |

| Matches filter, and bigger claim buttons | The Matches tab's filter chips now split "Text match" into **Image only / Text only / Both** — meaningful since a match can now come from text alone (see the previous row). Reject/Approve on a claim are now full-width, like every other paired button in the app, instead of the small content-sized pair from the last fix — bigger and easier to tap | None |

| Returned items go private | Once the finder taps "Mark as returned", **both** posts (found and lost) are retired together and hidden from Browse, search, the map, and everyone else's matches — visible only to their two owners, in **Profile → Returned items**. Before this, only the found post was ever resolved, so its matched lost post kept appearing and kept confusing other people's matching | **Required:** run `supabase/13_returned_items_and_ratings.sql` |
| Ratings & reviews screen | **Profile → Ratings & reviews** shows your average, a star breakdown, and every review — received and given — with its own tab for each. A rating's written comment is now private to the two people involved (previously any signed-in user could read it) | Included in migration 13 above |
| Home feed: Lost / Found filter | A three-way **All / Lost / Found** switch under the search box, each with a live count. Applied client-side (instant, no reload) alongside the existing category and search filters | None |
| User manual, Privacy policy, Safety guidelines | Three full documents under Profile, plus **Help & support** now links to all three and groups its FAQs by topic. Content lives in one place (`lib/features/profile/document/document_content.dart`) with matching Markdown copies in `docs/` for publishing (e.g. an app-store privacy-policy URL) | None |

| Maps back on Google | The app briefly ran on OpenStreetMap/`flutter_map` with no API key needed; now that you have a working Google Maps key, it's back to `google_maps_flutter` + `geocoding` as before (see **A5.1**) | None — but run `flutter pub get` (dependencies changed back) |
| Item detail: errors are now diagnosable | "Couldn't load this item" used to hide the actual error. It now shows the real message, logs the full error and stack trace, and adds a **Try again** button. If a post won't load, this is now the first thing to check | None |

| Alerts tab + unread badges | A new **Alerts** tab (between Chats and Profile) lists new matches, match confirmations, claim filed/approved/rejected, items returned, and new ratings — tap one to jump straight to it, or **Mark all read**. It and the **Chats** tab now show a number badge in the bottom nav when there's something unread. Ordinary chat messages aren't included in Alerts on purpose — the Chats badge already covers those; see `supabase/14_notifications.sql`'s header | **Required:** run `supabase/14_notifications.sql` |

| Push notification secrets: Windows-safe now | Step 3 of the push-notification setup used a bash one-liner (`NAME="$(cat file)"`) that silently breaks in PowerShell — `cat` there returns an array of lines that gets rejoined with spaces, not newlines, so the secret arrives mangled and the CLI rejects it with a confusing error. Replaced with a `--env-file`-based PowerShell version that avoids the problem entirely; the original one-liner is kept as the bash/WSL alternative | None |
| Real push notifications (code ready, needs your setup) | The missing half of push notifications is now written: `supabase/functions/send-push-notification/index.ts` sends a real push whenever a notification is created, and the app now navigates correctly when one is tapped, cold start included. This needs your own Firebase service account and a few `supabase` CLI commands — it can't be finished from here. See **"Sending real push notifications"** below | None (no new migration — it sends off the existing `notifications` table) |

| Undo a match decision | After **Not a match** / **This is it!** a snackbar offers **Undo** for 6 seconds, and every card under *Already decided* has an **Undo** (dismissed) / **Undo confirmation** (confirmed) button that returns the match to *Needs your input*. Undoing a confirmation asks first (the chat is hidden for both people until it's confirmed again) and is refused once a claim has been filed or the item is claimed/returned. Uses the existing update policy on `matches` | None |
| Sign-out confirmation | Profile → **Sign out** now asks "Sign out?" first | None |
| Posts linked from chats | Both chat types show a slim 48 dp bar under the app bar: match chats link **your post** and **their post**, direct messages link **the post the thread is about** (replacing the old "About …" caption). Tapping opens the post; the bar hides while the keyboard is open. `ContactChatArgs` gained a required `itemId` | None |
| Map button visible in light mode | The list/map toggle on the map view was white-on-white in light mode (it only looked right over the blue header or in dark mode); it now uses theme colours there | None |

| Snackbars that never went away | The match **Undo** snackbar (and the login "Resend" one) stayed on screen forever: since Flutter 3.29 a `SnackBar` with an action defaults to `persist: true` and ignores `duration`. Both now set `persist: false`. Any new snackbar with an action needs the same | None |
| Location picker opened on a blank blue map | "Adjust pin on map" before auto-detecting started at (0, 0) — open ocean. It now opens on the device's position (with a spinner), has a **My location** button, and if no position is available opens zoomed out and asks you to zoom in before it accepts a pin | None |
| Matches list bottom padding | Extra room under the last card so its buttons (e.g. **Undo**) can scroll clear of the floating **Report item** button | None |

| Editing a post refreshes its matches | A match stores a snapshot of its image / text / distance / time scores, and nothing refreshed it when a post was edited — so moving a post left the old "9 m" on its match cards. New triggers now recompute all four signals from the posts' current data whenever location, event time, title/description or photos change (scores only: matches are never created, removed, confirmed or dismissed by it). Editing the title/description also now refreshes the post's stored text embedding (it was never updated on edit), or clears it if the AI service doesn't answer so matching falls back to the actual words | **Required:** run `supabase/15_refresh_matches_on_edit.sql`, then once `select public.refresh_all_matches();` |
| Photo analysis refills on a new photo | Posting: changing the first photo now refreshes the auto-filled **Title** and **Category** instead of keeping the first photo's guess. Anything you typed or picked yourself is never overwritten; removing the first photo re-analyses the next one (or clears the auto-filled values if none is left) | None |

| Deleted accounts release their email | Deleting an account used to keep the `auth.users` row (banned) with the email still on it, so that email could never sign up again — and was still stored. Now the row is **anonymised** (placeholder email, phone/password/metadata cleared, linked Google identity and sessions removed, still banned), so the same email can create a brand-new account with no history. A **14-day cooldown** applies after deletion (only a hash of the email is kept for it), enforced by a database trigger and checked up-front on the sign-up screen with a clear message. `block_email()` can block an address permanently after moderation. The delete-account dialog and sign-in message were reworded to match | **Required:** run `supabase/16_release_email_on_delete.sql` (it also anonymises accounts deleted before it) |

| Security hardening (audit phase 0) | Row-level rules now also limit **what** may be written, not only who may write it. Closed: any user making themselves admin or editing their rating (only `full_name`/`username`/`avatar_url` are client-writable on `profiles`); phone numbers and push tokens readable by everyone (moved to owner-only `profile_private`); forged ratings (now `submit_rating()` — only the two people in a completed return, once each); self-approved claims (must be `pending`, for an open found post, by someone with a confirmed match; one live claim each; the owner can only approve/reject); messages into matches you're not in, and edits to received messages; matches rewritten by their owners (now `decide_match()`, which also refuses to un-confirm once a claim exists — the app's Undo goes through it); removed posts still served by the API and restorable by their owner; posts created/edited with a fake `status`; signed-out table access. Also: 10 MB / image-type limits on the storage buckets, length limits (title 120, description 2000, message 2000, claim answer and comment 500), one open report per person per post. Push: the token is cleared on sign-out; the webhook function now **refuses to run without `WEBHOOK_SECRET`**, compares it in constant time, and de-duplicates notifications. Photos are resized to ≤1600 px before upload | **Required:** run `supabase/17_harden_policies.sql`, redeploy `send-push-notification` (`supabase functions deploy send-push-notification`), install the updated app. Then run `supabase/tests/17_policy_checks.sql` |
| Android hardening (manual) | `android:allowBackup="false"` (session tokens in app data were being backed up) and removal of the unneeded `READ_MEDIA_IMAGES` permission. `AndroidManifest.xml` is git-ignored and holds your real Maps key, so these two edits were **not** shipped as a file — apply them by hand (see "Android hardening" below) | Manual edit, then rebuild |

| Calibrated match scores | A "100% match" used to be possible with identical one-word titles and a nearby location, because the score was an average of whichever signals existed and a pair found by text never had its photos compared. Now: the photo comparison is **always** computed when both posts have a photo (low = "photos disagree", shown as such); text agreement is weighted by **specificity** (shared brand/model/colour words count fully, agreeing only on generic words like "phone" counts 60%); disagreeing photos pull the score down smoothly; and with no photo comparison available the score is capped (70% if the wording agrees specifically, otherwise 50%). The app leads with a tier — **Strong** (≥ 80%), **Likely** (≥ 55%), **Possible** — with the percentage beside it, explains a missing/low photo score on the card, lists best-evidence first, and the *Image only / Text only / Both* filters now mean "photos/wording **agree**" rather than "a score exists". Which pairs get proposed, and notifications, are unchanged. The numbers and the word list are starting points — see the tuning notes at the end of the migration | **Required:** run `supabase/18_calibrated_match_score.sql` (re-scores all existing matches; install the matching app build for the tiers) |

| Paged feed, faster queries | The Browse list used to download **every** open post at once — with each post's full-size embedding vector, raw location and *all* its photos. It now loads **20 at a time** (infinite scroll, with a spinner and a Retry row if a page fails), downloads only the columns a card shows and only each post's first photo, and uses keyset paging so posts added while you scroll don't cause repeats or gaps. The lost/found tabs are now filtered **server-side** (switching reloads), and the "N lost · N found" header totals come from a small `feed_counts()` query so they're correct for the whole list, not just what's loaded. `19_indexes.sql` adds the missing indexes (feed order, "my posts", photos per post, matches by either item, claims, ratings, unread messages, contact threads, trigram search, text-embedding HNSW). Search text is also cleaned before it goes into the filter, closing a filter-injection hole (`,` `(` `)` `"` `\\` `%` `_` `*` are replaced with spaces) | **Required for the totals + speed:** run `supabase/19_indexes.sql`; install the updated app |
| Photo autofill is humble | The on-device model (1,000 everyday-object classes, not lost-and-found classes) now only writes the **Title** when it's at least 50% sure, and pre-fills **Category** at 30% — never with "Other". Below that the card says "Not sure what this is" and offers its top 3 guesses as tappable chips instead of putting "can opener" in your title. A tapped chip counts as your own choice. Also fixed: the Category dropdown now actually updates when a later photo changes the suggestion (it only read its value when first created) | None |

| Chat safety | **New-message alerts:** a message now creates an in-app alert and a push ("Sam sent you a message — About \"Black wallet\"", never the message text) — only for the *first unread* message in a conversation, so a burst is one notification; opening the chat clears it. **Block / report:** a ⋮ menu in both kinds of chat — *Report this person* (spam, harassment, scam, inappropriate, other + optional note; only someone you share a conversation with can be reported; one open report per pair) and *Block this person* (the database refuses messages in **both** directions and stops them starting a direct thread; they aren't told; the chat and match disappear from your lists). **Profile → Blocked people** lists and un-blocks. Admins get a **People** tab in *Flagged reports*. **Safety nudges:** a dismissible "meet somewhere public, never send money or codes" banner at the top of chats (links to Safety guidelines), and a confirm step before sending something that looks like a phone number (9–13 digits, so IMEIs and short serials don't trigger it) | **Required:** run `supabase/20_chat_safety.sql`; install the updated app. Optionally run `supabase/tests/20_chat_safety_checks.sql` on staging |

| Push per device | A person had ONE push token, so signing in on a second phone silently turned notifications off on the first, and a phone passed to someone else could keep getting the old owner's alerts. Every device is now its own row in `device_tokens` (a phone belongs to whoever is signed in on it; signing in as someone else moves it), the Edge Function notifies all of a person's devices and deletes only the dead ones, sign-out and the notification switch remove just *this* device, and the switch in settings now reflects this device | **Required:** run `supabase/21_device_tokens.sql`, redeploy `send-push-notification`, install the updated app |
| Abuse limits + housekeeping + faster policies | Direct writes are limited (20 posts/day, 30 messages/minute, 15 new direct chats/day, 5 claims/day, 10 reports/day each kind) with a plain-language message the app shows as-is (admins and the database's own functions are exempt). `housekeeping()` deletes alerts older than 90 days (scheduled nightly if `pg_cron` is on, plus a weekly re-score of matches). Every older policy that called `auth.uid()` per row now uses `(select auth.uid())` — same meaning, evaluated once per query (Supabase's Performance Advisor recommendation) | **Required for the limits:** run `supabase/22_limits_and_housekeeping.sql` (it prints how many policies it rewrote and whether jobs were scheduled) |
| Time has a direction | Something can't be *found* before it was *lost*: when both posts have a time and the found one is more than 6 hours earlier, the time signal is cut to a quarter (previously only the gap mattered, in either direction). Existing matches are re-scored | **Required for this change:** run `supabase/23_time_direction.sql` |
| Private proof questions | Someone who *found* an item can set a question only the real owner could answer ("What's on the lock screen?") and, privately, the right answer. The claimant sees the question when filing a claim; the answer lives in an owner-only table, is shown only to the finder next to the claimant's answer, and is deleted when the post is removed. Optional — claims without one work as before | **Required:** run `supabase/24_proof_questions.sql`; install the updated app |
| Friendlier errors, real tests, CI | Our own limit/refusal messages (rate limits, "a claim has already been filed…") are now shown to the person instead of a generic failure; anything else stays generic. The leftover template `test/widget_test.dart` (which could never pass) now holds real tests, and `.github/workflows/ci.yml` runs `flutter analyze` and `flutter test` on every push/PR | None (CI needs the repo on GitHub; a stand-in empty `.env` is created in CI) |

| AI service locked down | `/embed/*` used to answer anyone on the internet. It now needs the caller's Supabase sign-in token (checked by asking Supabase, so no secret lives on the service), is rate limited per person (30/min), rejects uploads over 10 MB and over-long text, and has no CORS by default. It **refuses** requests (503) until `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are set on the host. The app sends the token automatically. 7 unit tests (`python -m unittest test_security`) ran and pass | **Required:** set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` on the AI service host (see `ai_service/README.md`) and redeploy it — until then the text signal is skipped |
| Sign-in session in encrypted storage | The Supabase session (including the long-lived refresh token) was stored as readable text in app data; it now lives in the Android Keystore (`flutter_secure_storage`). People already signed in are moved across automatically; if the Keystore can't be read the person just signs in again | **Run `flutter pub get`** (new dependency), then rebuild |
| Long chats, posting, drafts | Chats load the newest 50 messages with a *Load earlier messages* row; alerts (150) and My Items (200) are capped. Posting uploads photos 3 at a time, retries flaky uploads, keeps the original photo order, withdraws a half-created post (and deletes its uploaded files) if photos fail, and **saves an unfinished post as a draft** that is restored next time (photos must be re-added) | None |
| Small safety/trust/accessibility additions | *Suggest a safe meeting place* in the chat ⋮ menu; the finder sees the claimant's rating and member-since date when reviewing a claim; place search (by name/address) in the location picker; photo alt-text and decoded-size limits for thumbnails; a missing tooltip fixed | None |
| Match outcome log and data export | Every confirm/dismiss/undo records the match's scores (no personal data) in `match_outcomes`, readable only by admins, with `match_outcome_summary` showing how decisions fall across score bands — the evidence for tuning the Strong/Likely cut-offs. **Profile → Download my data** builds a JSON copy of everything held about the account (copy to clipboard) | **Required:** run `supabase/25_outcomes_and_data_export.sql` |

| Country on every post | A **compulsory Country** field on the post and edit forms (a searchable list, pre-filled from your profile / phone region and then from the pinned location, which you can override). Browse now shows each person the posts from **their** country — the flag at the top-left of Browse (and **Profile → Country**) opens the country settings — and match suggestions are never made between posts in different countries. The database refuses a new post from the app without a valid two-letter country code. **Older posts have no country and stay out of every feed until you give them one** — if they're all from one country: `update public.items set country_code = 'LK' where country_code is null;` (change `LK`) | **Required:** run `supabase/26_country.sql` (then the `update` above for existing posts); install the updated app |
| Posting guidelines | Opening *Report an item* first shows a short sheet on keeping the item private to its owner (describe it generally, show the outside only, add a proof question if you found it, keep the secret detail to yourself if you lost it, choose the country and the place, no contact details in the post). *Don't show this again* is available, and a **Posting tips** link on the form reopens it | None |
| Match label summary | The Matches tab now explains **Strong / Likely / Possible** (what each means and its score range) in a card at the top (dismissible with *Got it*) and under the ⓘ button in the app bar; the score ranges come from the same constants the tiers use, so they can't drift apart | None |

| Country at sign-up and in settings | **Create account** now asks for the country (compulsory, pre-filled from the phone's region) and saves it on the profile, so Browse is filtered from the first launch; people without one (older accounts, Google sign-in) are asked once. **Profile → Country** (also the flag at the top-left of Browse) shows the *home country* — changeable **once every 30 days** (the first choice is free) — and a *Travelling?* option to browse another country for **3, 7, 14 or 30 days**, after which the home country comes back by itself (ends early on request; can't be the home country; max 30 days). Posts are unaffected: each keeps the country of its place. The limits are enforced by the database, with the next possible date shown | **Required:** run `supabase/27_country_settings.sql`; install the updated app |
| Two display bugs fixed | The country chip between the search bar and the filters was white text on a light background (invisible) — removed, replaced by the flag button. The posting-guidelines sheet showed only the dim background because it combined a drag handle with dragging switched off (an invalid combination) — it's now an ordinary dialog | None |

| Filter & sort on Browse | A **filter button** in the Browse search bar (with a dot when something is set) opens *Filter & sort*: **Posted** — any time / last 24 hours / 7 days / 30 days — and **Sort by** — newest first (default) / oldest first / **nearest to me** (uses the phone's location, ordered by distance in the database; posts without a location come last; falls back to newest if location isn't available). The header totals follow the window. Paging works in every order | **Required for the window and nearest sort:** run `supabase/28_saved_searches.sql`; install the updated app |
| Saved searches with alerts | From the same sheet, **Save this search** (words and/or a category, optionally Lost or Found, in your country). When a **new** matching post is made you get an alert (in the app and as a push) that opens the post. Up to 10 searches; never for your own posts or blocked people; one alert per post and at most one per search every 30 minutes; each can be switched off or deleted under **Profile → Saved searches**. Included in *Download my data*; removed when the account is deleted | **Required:** run `supabase/28_saved_searches.sql`, redeploy `send-push-notification`, install the updated app |
| Bug fixed: later Browse pages ignored the country | While scrolling, pages after the first were fetched without the country filter, so posts from other countries could appear further down. Fixed together with the new filters | None |

| Paging: Matches tab, a post's matches, admin reports | The Matches tab used to download **every** match at once (plus a second query for your own posts' photos); the two admin report queues (Posts / People) did the same. Now each list shows **20** and ends with a **Show more** button (+20 each tap), with a spinner while it loads. The Matches tab's two sections (*Needs your input*, best score first; *Already decided*, newest first) page separately, and the filter chips (Image only / Text only / Both / Nearby / Similar time) are now applied **on the server** — filtering the phone's loaded list would have hidden matches that simply weren't loaded yet. The list asks for the newest *N* rows rather than "the rows after the last one", so the 15-second refresh, a decision (Confirm / Not a match / Undo) or a dismissed report just re-reads the same *N* rows: nothing collapses back to the first page, and nothing is skipped or repeated. People you've blocked are now left out by the database too (so a page never looks short). A post's **View possible matches** screen is paged the same way, and its "Message about this item" button asks only for *confirmed* matches. The server caps one request at 500 rows | **Required:** run `supabase/29_matches_paging.sql` (adds `my_matches_page()` + two indexes); install the updated app. Without it the Matches tab and post pages show "Couldn't load matches". Optional check: `supabase/tests/29_checks.sql` |

| Offline banner | A slim banner slides in at the top — "You're offline — showing what's already loaded" — whenever the phone can't reach Findora's backend, and turns green for two seconds ("Back online") when it can again. It checks by opening a plain connection to your Supabase host (`SUPABASE_URL`) every 15 s (every 5 s while offline, and whenever the app returns to the foreground), so it also catches "connected to Wi-Fi but no internet", which a Wi-Fi/mobile-data check would miss; two failed checks in a row are needed before it appears, so one dropped packet doesn't flash it. It sits above the screens (never over an app bar) and lists that failed while offline (Browse, Matches, Alerts) reload on their own when the connection returns. No new package, permission or migration. Code: `lib/core/connectivity/connectivity_provider.dart`, `lib/core/widgets/offline_banner.dart` | None |

| Photos and typing indicators in chats | **Photos:** a new photo button beside the message box (both the confirmed-match chat and a direct "Contact poster" thread) — take a photo or pick one, optionally add text as a caption, and it sends with a progress bar. Photos are resized to 1600 px, tap to view full screen with pinch-zoom, and a photo-only message shows "📷 Photo" in the Chats list. They are stored in a **private** `chat-images` bucket (unlike post photos, since people may send things like a found phone's lock screen): only the two people in that conversation can read or add files in its folder, the app shows them through one-hour signed links (cached by path, so they stay cached), and a message can only point at a file in its own conversation's folder. If sending fails after the upload, the file is removed again. **Typing:** the other person's "…" bubble shows above the message box while they type (and a few seconds after they stop, or as soon as their message arrives). It uses Realtime *Broadcast* — never written to the database — on a channel named after the conversation's unguessable id, carrying only the sender's id and true/false. Both chat screens now share one composer and one bubble widget | **Required for photos:** run `supabase/30_chat_photos.sql` (adds `image_path` to both message tables, the private bucket and its rules, "📷 Photo" previews). Typing needs no SQL (Realtime must be on for the project, as it already is for chat). Optional check: `supabase/tests/30_checks.sql` |

| Two-sided match confirmation | Before, **one** person tapping "This is it!" confirmed a match for both and opened the chat — so someone could open a private chat with a person who had never agreed it was their item. Now each owner records their **own** decision and a match is *confirmed* (chat opens, claims allowed) only when **both** have confirmed. Cards show where things stand: *Needs your input* (with "The other person says this is a match" if they went first), *Waiting for the other person* (you confirmed; **Undo my confirmation** available), *Already decided*. "Not a match" from either side ends the match for both, without saying who. A new alert (**Match waiting for you**) tells you the other person confirmed; the existing **Match confirmed** alert now reaches the person who confirmed first, when the second confirms. Everything that already depended on a confirmed match (chat, photos, claims, returns) is unchanged and now means "mutual". Existing confirmed matches are grandfathered as confirmed on both sides, so no live chat or claim is affected; old dismissed matches can still be undone. Taking back a confirmation is still blocked once a claim exists. The in-app guide and FAQ were updated. Admin score-band stats: *confirmed* now means mutual | **Required:** run `supabase/31_two_sided_confirmation.sql` **before** installing the new app (it changes `decide_match()` to return the match status, adds the per-owner decision columns and the new matches query). Optional check: `supabase/tests/31_checks.sql` |

| Auto-hide after reports, audit log, appeals | **Auto-hide:** when a post collects open reports from **3 different people** it is hidden at once instead of waiting in the queue. Reports only count from accounts at least **2 days old** and never from the post's own owner, so a throwaway account can't hide someone's post alone (both numbers are tunable functions in the SQL: `auto_hide_report_threshold()`, `auto_hide_min_reporter_age()`). "Hidden" reuses the existing soft delete (`items.deleted_at`) so the post vanishes from Browse, the map, search, matching and alerts exactly like a deleted post, with nothing else to keep in step; a new `items.moderation_state` (`auto_hidden` / `removed`) records *why*, and only moderators can change it. Nothing is erased. **Audit log:** `moderation_log` records every moderation event — auto-hides, removals, restorations, every report dismissed or marked reviewed (posts and people), appeals sent and decided — with who (an admin, the system, or the owner), when, which post, and any note. It is **append-only** (the database refuses edits and deletes, even for admins; the one allowed change is an account's name being blanked when that account is deleted) and readable only by admins: *Flagged reports → Activity*. **Appeals:** the owner gets an alert and sees the post under *Profile → Hidden posts* (shown only when there is something to show), where they can **appeal once** per hiding (10–1000 characters). Admins see appeals oldest-first in *Flagged reports → Appeals* and **Restore** (post comes back, owner told) or **Deny** with a required reason the owner reads; denial is final. Admin removal and restoring now go through functions (`admin_remove_item`, `admin_restore_item`, `admin_decide_appeal`) so each is logged and the owner is told; the Posts tab shows a *Hidden automatically* label and a **Restore post** button. New alerts: *Your post was hidden / removed / is back*, *Appeal denied* (owner) and *Post auto-hidden / Appeal received* (admins) | **Required:** run `supabase/32_moderation.sql`, then install the updated app (older app builds still work but their admin removals aren't logged or announced). Optional check: `supabase/tests/32_checks.sql` |

| Approximate public locations | Closes the biggest privacy gap. Before, every post stored — and showed everyone — the **exact** point its owner pinned (the map returned exact coordinates, the match card's "N m away" was the exact distance between two exact spots, enough with a few test posts to work out where someone's item, often their home or workplace, really was) and the label was a **street address** ("12 Orchard Rd, Singapore"). Now `items.location` holds only an **approximate point**: the exact one snapped to the centre of a ~550 m grid cell (`public_location_grid_degrees()`; a grid can't be averaged back to the real spot by asking repeatedly, and needs no secret). Everything that already read `items.location` — map, "Nearest to me", saved-search alerts, matching, the distance on a match card — became approximate automatically. The **exact point** lives in a private table (`item_exact_locations`) no client can read; only the **owner** gets it back (to edit their post) through `get_item_coordinates()`, which now also returns `is_exact`. Labels are reduced to a neighbourhood or town (the app now sends only that; the database strips a street part from anything an older app sends, keeping the original privately). A trigger does all this on every insert and edit, whatever app version wrote the row, so an old app can't leak the exact spot or overwrite it with the approximate one. In the app: others see a **shaded circle** (not a pin) on the post page and map, with "Approximate area"; the owner sees their exact pin; the post and edit screens say what others will see; the guide, FAQ and privacy text were updated; *Download my data* now includes the exact location. Existing posts are converted by the migration (their match distances refresh because their location changes) | **Required:** run `supabase/33_approximate_locations.sql` (changes data: keep a backup / run on staging first), then install the updated app. Optional check: `supabase/tests/33_checks.sql` |

| Widget and integration tests of the main flows | New tests drive the **real screens** — Matches tab, admin moderation queue, owner's Hidden posts, offline banner, chat composer / bubble / typing dots — against **in-memory fakes** of the repositories (the app can't start in a test: `Supabase.instance.client` only exists after `Supabase.initialize()` with a real project). The matches fake follows the same two-sided rules as `decide_match()`, so the tests cover real journeys: *confirm → waiting → undo → other confirms → mutual → Message button*; *they confirmed first*; *Not a match → Undo* (and no Undo when the other person dismissed); *20 matches then Show more*; *filter chips sent to the server*; *admin restores an auto-hidden post, removes one, must give a reason to deny an appeal, finds it all in the activity log*; *owner appeals only with a real explanation, only once*; *offline banner appears, says Back online, and a half-typed message survives*. Each journey is written once (`test/support/flows.dart`) and runs both as a fast widget test (`flutter test`) and on a device (`flutter test integration_test -d <device>`, no backend or network needed). Not covered (need a live backend): sign-in, posting with photos and AI matching, real chat and Realtime — see A6b | Run `flutter pub get` (adds the SDK's `integration_test`), then **A6b** |

| Server-side thumbnails | Lists (Browse, My posts, Matches, Chats, the map) used to download the **full** photo (up to 1600 px, often several hundred KB) for a tile a few hundred pixels wide — a page of 20 cards could be 5–10 MB of mobile data. Now each photo gets a small companion (480 px long side, JPEG, ~30–60 KB) made by a new **`make-thumbnails` Edge Function** (ImageScript; no paid image-transformation plan needed) right after upload, stored next to the original as `thumb_<name>.jpg` with its URL in `item_images.thumb_url`. Every list query returns `coalesce(thumb_url, image_url)` — the thumbnail when there is one, the full photo otherwise — so nothing breaks before a thumbnail exists (older posts, a failed run, the function not deployed). The post page's gallery, matching and AI embedding keep using the full photo. The app asks for thumbnails after a post or a photo edit, and **once per session for the person's own older photos** (30 at a time, batches of 10, silent), so the backlog clears as people open the app; an admin can clear it all at once with a `curl` loop (see the function's README). Only the function (service role) can set `thumb_url`: a trigger ignores it from the app and clears it when a photo is replaced. Removing a photo deletes its thumbnail too. Failures are invisible and retried next session. Limits: JPEG/PNG/TIFF originals (HEIC, WebP and animated GIFs keep using the full image), originals ≤ 15 MB | **Required (in this order):** run `supabase/34_thumbnails.sql`, then `supabase functions deploy make-thumbnails`, then install the app (the app's list queries select `thumb_url`, so the migration must come first). Optional: backfill and checks — `supabase/functions/make-thumbnails/README.md`, `supabase/tests/34_checks.sql` |

| Post expiry and "still looking?" reminders | Posts used to stay live for ever — found, replaced or forgotten items kept appearing in Browse and the map, kept being matched, and kept sending people to chat with someone who'd stopped caring. Now a post lasts **60 days** (`post_lifetime()`). **7 days before, and again 1 day before**, the owner gets a *Still looking for "…"?* alert (tap → the post page, where a banner offers **Keep it up**, a fresh 60 days; the same button is on the My posts card). When the time is up the status becomes **`expired`**: it leaves Browse, the map and matching exactly like a resolved post (those already only look at `status = 'open'`), its matches stop showing, and nobody can start a chat about it — but it is **not deleted**: it stays in the owner's My posts marked *Expired* with a **Renew** button, which brings it back for another 60 days and re-matches its photos against everything open now. A post is **never expired while a conversation about it is under way** (a confirmed match, or a pending/approved claim). Only the database sets `expires_at` (the app can't change it); a nightly `pg_cron` job (`process_item_expiry()`, 08:23 UTC) sends the reminders and does the expiring (without pg_cron, run that function once a day). **Existing posts get a grace period**: they expire 60 days after posting but not sooner than 14 days after this migration. New alert types: `item_expiring`, `item_expired`. The guide and FAQ explain it | **Required:** run `supabase/35_post_expiry.sql` (adds the `expired` status — if your SQL editor complains about using the new value, run the first `alter type` line on its own, then the rest), enable **pg_cron** (Database → Extensions) if you want the schedule, then install the app. Optional check: `supabase/tests/35_checks.sql` |

| Share-a-post links | A **share icon** on an open post's page sends the post's **title and a link** (`https://<your host>/p/<post id>`) through the phone's share sheet (falling back to copying the link). Opening the link: **with the app** installed, Android opens the post directly (an App Link: the https filter in the manifest, host from `findora.shareHost` in `android/gradle.properties`, verified via `assetlinks.json`); someone **signed out** is sent to sign in and then lands on the post, not the feed (`pendingDeepLink`); **without the app** the link opens `web/share.html` — a small preview card (type, title, area, thumbnail) with **Open in Findora** (a `findora://open/p/<id>` link / Android intent) and **Get Findora** buttons. The card is fed by a new public Edge Function, `post-preview`, which is deliberately tiny: only type, title, neighbourhood/town label and thumbnail — **never** the description, the poster, any coordinates, or matches/chats — and an expired, resolved, deleted or moderated post answers exactly like one that doesn't exist. Ids in links are validated as uuids before the app routes anywhere. The Share button is hidden until `SHARE_BASE_URL` is set, so the app works unchanged without any of this. No migration | **Optional (but the button stays hidden without it):** follow **A9. Share-a-post links** (host `web/share.html` + `web/_redirects`, `supabase functions deploy post-preview --no-verify-jwt`, set `SHARE_BASE_URL` and `findora.shareHost`, optionally `assetlinks.json`), then `flutter pub get` (adds `share_plus` 13) and rebuild |

| Localization scaffolding: English, Sinhala, Tamil | The app can now be shown in **English, සිංහල (Sinhala) and தமிழ் (Tamil)**. **Profile → Language** lets a person pick one (each shown in itself, so it can be found from any other) or follow the phone's language; the choice is remembered. Built on Flutter's standard `gen-l10n`: strings live in `lib/l10n/app_en.arb` (the template, with a description for every message) and `app_si.arb` / `app_ta.arb`; `flutter pub get` generates `AppLocalizations` (not committed). Material's own text (date pickers, "Back" tooltips…) is translated by Flutter in all three; dates and numbers follow the language too (`intl` is told which one is showing, so existing `DateFormat` calls need no change). Plurals use each language's own rules (the "expires in N days" banner is the worked example). **This is scaffolding, not a finished translation:** the pipeline is complete and the following are translated — the bottom navigation and *Report item* button, the offline banner, **the whole Matches tab and match card** (sections, filter chips, buttons, notes, snackbars, the undo dialog), the post-expiry banner and *Keep it up / Renew*, *Show more* and the language picker itself. **Everything else is still English** (the post, chat, profile, admin and sign-in screens, the in-app guide, error messages from the database, and push-notification text written by the server) and falls back gracefully. The Sinhala and Tamil text is a **first draft written without a native-speaker review** — have a speaker of each check it before release (the ARB descriptions say where each string appears). Tests check that all three files have identical keys and placeholders, and that the Matches tab renders in each language | Run `flutter pub get` (adds `flutter_localizations`; generates the translations), then **A10**. No migration |

| Security and privacy audit follow-up | A full audit of the app found four high-severity gaps, now fixed in code/SQL: **(H1)** photos kept their **GPS/date/device metadata** and are stored in a public bucket — the app now strips it before upload (`lib/core/images/strip_metadata.dart`, fails closed) and `scripts/scrub_photo_metadata.py` cleans photos already stored; **(H2)** the thumbnail function trusted a database URL (SSRF / write into other users' folders) — now validated and pinned to the owner's own folder; **(H3)** a photo or avatar could point at any web address (IP tracking) — now must live in Findora's own storage; **(H4)** anyone with the public key could list every file and user id in the photo buckets — now own folder only. Also: a maintenance function no longer callable by anyone, direct contact-thread inserts removed, privacy policy brought up to date. The full report (`FINDORA_SECURITY_AUDIT.md`) lists every finding with severity, evidence and fix, including items that need *you*: erasing files on delete, locking down profile reads, admin MFA, release signing/backup, dashboard auth settings | **Required:** run `supabase/36_security_hardening.sql` (and set `storage_host`), redeploy `make-thumbnails` and `post-preview`, ship the new app, then `python scripts/scrub_photo_metadata.py --apply` once. Checks: `supabase/tests/36_checks.sql` |

| Sign up with Google + the deleted-email wait for Google | The **sign-up page** now has **Sign up with Google** under *Create account* (the sign-in page keeps *Continue with Google*; one shared button). An address that belonged to an account deleted in the last 14 days was already refused for Google by the database trigger (`a_enforce_email_reuse_block`, migration 16) — but nobody was told why: Google's redirect comes back with Supabase's generic *"Database error saving new user"* and the app showed nothing. Now the app **listens for failed browser sign-ins** (`authErrorNoticeProvider` + an app-wide snackbar) and shows the same explanation as the email sign-up: *"…an account with this email was recently deleted, you can sign up with it again once the waiting period (usually 14 days) has passed."* Email sign-up and Google now share the wording (`lib/core/auth/signup_block_messages.dart`). **Optional, for the exact date:** with Google the app can't know the address until after Supabase has it, so the date can only come from the server — `supabase/37_signup_hook.sql` adds a Supabase *Before User Created* hook that returns the exact sentence (*"…you can sign up with it again on Nov 5, 2026."*) which the app then shows as is; enable it in Authentication → Auth Hooks (steps in the file). Without the hook everything still works, with the generic-date wording | Optional: run `supabase/37_signup_hook.sql` and switch the hook on for the date. Test with a Gmail address you deleted through the app minutes ago |

| Limit on repeated claims | A rejected claim didn't count against anyone: the same person could file again at once, as often as they liked (the only limits were *one live claim per post* and *5 claims a day across all posts*), so someone could keep guessing the finder's verification question. Now, **per person per post: at most 3 claims in total, and a 1-hour wait after each rejection** — both enforced by the database (`claim_max_attempts()`, `claim_retry_wait()`, trigger `claims_attempt_limit`, which runs before the daily limit so the specific reason is shown first). **Warnings before the limit:** the claim form says *"Attempt 2 of 3 … you'll have 1 attempt left"* and, on the last one, shows a red *"This is your last attempt — if it isn't approved you won't be able to claim this post again"*; the chat shows *"You can try up to 3 times for each post"* before the first claim and *"You have N attempts left"* (with the minutes to wait) after a rejection; the rejection **alert** now says how many attempts are left, with a stronger one for the last. **At the limit:** the alert says *"no attempts left — you can't claim it again"*, the chat banner says so and offers no button, and a further attempt is refused with the same words. Claims rejected **before** this change don't count (everyone starts fresh). A moderator can give attempts back: `select admin_reset_claim_attempts('<post id>', '<claimant id>');` (logged in the moderation log; the person is told) | **Required:** run `supabase/38_claim_attempt_limit.sql`, then install the app (an app without the migration just shows no counts; one without the new app still gets the database's refusal messages). Checks: `supabase/tests/38_checks.sql` |

| Claim form fixes: a unique detail is required | A second look at *File a claim* found several bugs. **(1) Submit with an empty answer closed the form and did nothing** — no message, no claim — and the database accepted claims with **no answer at all**, so the "describe a unique detail" requirement wasn't enforced anywhere. Now the form's **Submit stays disabled** until the answer is real (**15+ characters** when the finder set no question, **2+** when there is a question, since "red" is a fine answer there), explains what's missing under the box, and the **database enforces the same rule** (`39_claim_answer_rules.sql`) for any app version. **(2)** The same answer the finder already rejected can't be re-sent (it would waste one of the 3 attempts) — blocked in the form and in the database. **(3)** Tapping outside the form no longer throws away a typed answer. **(4)** The form scrolls, so a long question + the attempt warning + the keyboard don't push Submit off a small screen. **(5)** A second tap on *File a claim* while the first is being sent can't open another form. **(6)** The chat no longer offers *File a claim* / *File a new claim* once the post can't be claimed (another claim approved, or the post expired) — it says so instead of failing with a vague error; other failures now explain themselves. The guide and FAQ state the rule | **Required:** run `supabase/39_claim_answer_rules.sql`, then install the app. Tests: `test/claim_answer_test.dart` |

New/changed SQL files, run **in order** after `04_storage_setup.sql` —
`05` and `08` are required, `06`/`07` are optional but harmless to run
anyway:
`05_multimodal_matching.sql`, `06_contact_messaging.sql`,
`07_email_confirmation.sql` (the last one has manual placeholders to fill
in — see its header comment and "Email confirmation flow" below),
`08_soft_delete.sql`, `09_account_deletion.sql`,
`10_open_matching_and_time.sql`,
`11_realtime_and_matching_fixes.sql` (live chat + AI matching fixes —
required), `12_text_matching.sql` (matching by title/description,
independent of photos — required),
`13_returned_items_and_ratings.sql` (returned posts become private to
their two owners, plus the Returned items and Ratings & reviews sections
— required), `14_notifications.sql` (the Alerts tab —
required), `15_refresh_matches_on_edit.sql` (editing a post
now refreshes its existing matches — required for that fix; afterwards
run `select public.refresh_all_matches();` once), and finally
`16_release_email_on_delete.sql` (deleting an account frees its email —
required for that behaviour; it also backfills accounts deleted earlier), and
finally `17_harden_policies.sql` (closes the security holes found in the
audit — **required**; read its header first, and also redeploy the
`send-push-notification` function and install the matching app build).
`supabase/tests/17_policy_checks.sql` can then be run to prove it worked.
After that comes `18_calibrated_match_score.sql` (match scores now require
evidence — required for the new scoring; it re-scores all existing matches).
Then `19_indexes.sql` (indexes for the feed, chat and match lookups, plus the
`feed_counts()` function behind the Browse header totals — the totals simply
don't show until it's run).
Finally `20_chat_safety.sql` (new-message alerts, blocking, reporting people —
required for those features; `supabase/tests/20_chat_safety_checks.sql`
checks it).
Then four more, in order: `21_device_tokens.sql` (push per device —
redeploy `send-push-notification` too), `22_limits_and_housekeeping.sql`
(abuse limits, nightly cleanup, faster policies), `23_time_direction.sql`
(matching: found can't precede lost) and `24_proof_questions.sql` (a finder's
private proof question). `supabase/tests/21_24_checks.sql` checks all four.
And finally `25_outcomes_and_data_export.sql` (a log of match decisions for
tuning, and the "Download my data" function; `supabase/tests/25_checks.sql`).
Then `26_country.sql` (every post has a country; the feed and match suggestions
are per country — **read its header first: older posts have no country and won't
show in the feed until you set one**; `supabase/tests/26_checks.sql`).
Then `27_country_settings.sql` (country asked at sign-up, home-country limit,
temporary "travelling" country; `supabase/tests/27_checks.sql`).
Then `28_saved_searches.sql` (saved searches with alerts, the "nearest first"
query and the date window for Browse; `supabase/tests/28_checks.sql`) — and
redeploy `send-push-notification` so a saved-search alert opens the post.
Then `29_matches_paging.sql` (paged matches and admin report queues;
`supabase/tests/29_checks.sql`), then `30_chat_photos.sql` (photos in chats;
`supabase/tests/30_checks.sql`), then `31_two_sided_confirmation.sql`
(`supabase/tests/31_checks.sql`), then `32_moderation.sql`
(`supabase/tests/32_checks.sql`), then `33_approximate_locations.sql`
(`supabase/tests/33_checks.sql`), then `34_thumbnails.sql` (and deploy the
`make-thumbnails` function; `supabase/tests/34_checks.sql`), then `35_post_expiry.sql`
(`supabase/tests/35_checks.sql`), then `36_security_hardening.sql`
(`supabase/tests/36_checks.sql`), then — optional — `37_signup_hook.sql`, then `38_claim_attempt_limit.sql`
(`supabase/tests/38_checks.sql`), then `39_claim_answer_rules.sql`.

---

# Part A — Setup, step by step

## A1. Install the prerequisites (once per machine)

Skip anything you've already got installed — `flutter doctor` (step A1.5)
will tell you what's still missing either way.

### A1.1 Install the Flutter SDK

1. Go to https://docs.flutter.dev/get-started/install and download the
   Flutter SDK for your operating system (Windows/macOS/Linux).
2. Extract/install it somewhere permanent — not a Downloads folder you
   might clear out. A common choice is `C:\src\flutter` on Windows or
   `~/development/flutter` on macOS/Linux.
3. Add Flutter's `bin` folder to your system `PATH`:
   - **Windows**: Search "Environment Variables" in the Start menu → Edit
     the system environment variables → Environment Variables → under
     "User variables", select `Path` → Edit → New → add the full path to
     the `flutter\bin` folder → OK on every dialog.
   - **macOS/Linux**: open your shell profile (`~/.zshrc`, `~/.bashrc`, or
     `~/.bash_profile`) in a text editor and add a line:
     `export PATH="$PATH:/full/path/to/flutter/bin"`, save, then run
     `source ~/.zshrc` (or whichever file you edited) or just open a new
     terminal window.
4. Close and reopen every terminal/VS Code window so the new `PATH` takes
   effect, then confirm it worked:
   ```bash
   flutter --version
   ```
   This should print a Flutter and Dart version, not "command not found".

### A1.2 Install Android Studio (for the Android SDK — you won't write code in it)

Even though you're developing in VS Code, Android Studio is the easiest
way to install and manage the Android SDK, platform tools, and an
emulator.

1. Download and install Android Studio from
   https://developer.android.com/studio.
2. Open it once. On first launch it runs a "Setup Wizard" — accept the
   defaults and let it download the Android SDK, SDK Platform-Tools, and
   a recent Android SDK Platform. This can take a while on a slow
   connection.
3. Once it's open, go to **More Actions → SDK Manager** (or **Settings →
   Languages & Frameworks → Android SDK** if a project is already open).
   Under the **SDK Tools** tab, make sure these are checked, then click
   **Apply**:
   - Android SDK Command-line Tools (latest)
   - Android SDK Platform-Tools
   - Android SDK Build-Tools (latest)
4. Accept the Android SDK licenses from a terminal:
   ```bash
   flutter doctor --android-licenses
   ```
   Press `y` and Enter to accept each one.

### A1.3 Make sure Gradle will use Java 17

This project's Android build is configured for Java 17 specifically (see
"Troubleshooting Gradle errors" below for why). Android Studio ships its
own bundled JDK that's new enough, so the simplest fix is pointing
`JAVA_HOME` at it.

1. Find Android Studio's bundled JDK folder:
   - **Windows**: usually
     `C:\Program Files\Android\Android Studio\jbr`
   - **macOS**: usually
     `/Applications/Android Studio.app/Contents/jbr/Contents/Home`
   - **Linux**: usually
     `/usr/local/android-studio/jbr` or wherever you installed it, under
     a `jbr` folder
2. Set `JAVA_HOME` to that path:
   - **Windows**: Environment Variables (same dialog as step A1.1) → under
     "User variables" → New → Variable name `JAVA_HOME`, Variable value =
     the path from step 1 above.
   - **macOS/Linux**: add to the same shell profile file as step A1.1:
     `export JAVA_HOME="/path/from/step/1"`, save, and reload the shell.
3. Open a **new** terminal window and confirm:
   ```bash
   java -version
   ```
   This should report version `17.x`.

### A1.4 Install VS Code + the Flutter extension

1. Download VS Code from https://code.visualstudio.com if you don't have
   it already.
2. Open VS Code → Extensions icon in the left sidebar (or `Ctrl+Shift+X` /
   `Cmd+Shift+X`) → search for **"Flutter"** → install the official one
   published by Dart Code. This automatically installs the **Dart**
   extension too.

### A1.5 Verify everything with flutter doctor

```bash
flutter doctor -v
```

Look for a checkmark next to "Flutter", "Android toolchain", and "VS
Code". Fix anything marked with `✗` before moving on — the tool
usually tells you exactly what command to run. It's normal to see
warnings about Chrome or Xcode if you don't plan to build for web/iOS.

## A2. Get the project open in VS Code

1. Unzip the project folder you were given, anywhere you like (e.g.
   `Documents/findora`).
2. Open VS Code → **File → Open Folder…** → select the unzipped `findora`
   folder (the one that directly contains `pubspec.yaml`, `lib/`,
   `android/`, etc.).
3. VS Code will likely show a popup "This workspace contains a Flutter
   project — get the Dart/Flutter extensions?" — since you already
   installed them in A1.4, you can dismiss this.
4. Open a terminal inside VS Code (**Terminal → New Terminal**) and run:
   ```bash
   flutter pub get
   ```
   This downloads every Dart package listed in `pubspec.yaml`. It should
   finish with no red error text.

## A3. Set up the Supabase backend

1. Create a free project at https://supabase.com/dashboard (sign up if
   you don't have an account, then **New Project**).
2. Wait for the project to finish provisioning (a minute or two).
3. In the left sidebar, click **SQL Editor**, then **New query**.
4. Open `supabase/01_extensions_and_tables.sql` from the project folder
   in VS Code, select all the text (`Ctrl+A`/`Cmd+A`), copy it, paste it
   into the Supabase SQL editor, and click **Run** (or `Ctrl+Enter`).
   Confirm it says "Success. No rows returned" and not an error.
5. Repeat step 4 for `02_functions_and_triggers.sql`.
6. Repeat step 4 for `03_rls_policies.sql`.
7. Repeat step 4 for `04_storage_setup.sql`.
   ⚠️ **Run these four in this exact order** — each one depends on
   tables/functions the previous one created.
7b. Same again for `05_multimodal_matching.sql`, then
   `06_contact_messaging.sql`, then `07_email_confirmation.sql` (also in
   order) — these add event time, multimodal (image+text+GPS) matching,
   direct contact messaging, and the welcome-email trigger. The app runs
   without them too (older columns/functions these `create or replace`
   just won't exist yet), but My Items' delete, Contact poster, and the
   richer match scoring all depend on them. `07_email_confirmation.sql`
   specifically has two placeholders to edit before running it — see
   "Email confirmation flow" further down.
7c. Then `08_soft_delete.sql`, `09_account_deletion.sql`,
   `10_open_matching_and_time.sql`, `11_realtime_and_matching_fixes.sql`,
   `12_text_matching.sql`, `13_returned_items_and_ratings.sql`,
   `14_notifications.sql`, `15_refresh_matches_on_edit.sql` and
   `16_release_email_on_delete.sql`, `17_harden_policies.sql` and
   `18_calibrated_match_score.sql`, `19_indexes.sql`, `20_chat_safety.sql`, `21_device_tokens.sql`, `22_limits_and_housekeeping.sql`, `23_time_direction.sql`, `24_proof_questions.sql`, `25_outcomes_and_data_export.sql`, `26_country.sql`, `27_country_settings.sql`, `28_saved_searches.sql` and `29_matches_paging.sql`, in that order. Each is safe to re-run. `08`,
   `10`, `11`, `12`, `13`, `14`, `15`, `16`, `17`, `18`, `19`, `20`, `21`, `22`, `23`, `24`, `25`, `26`, `27`, `28` and `29` are needed for the current app code to
   work properly (see the top of this file). `13` runs a one-time backfill
   automatically for posts already returned before it; see that
   migration's header.
8. In the left sidebar, click the gear icon (**Project Settings**) →
   **API Keys**. Copy two values, you'll need them in the next step:
   - **Project URL** (looks like `https://xxxxx.supabase.co`)
   - **Publishable key** (starts with `sb_publishable_...`) — Supabase is
     retiring the old "anon" key naming in favor of this; make sure you
     copy the *publishable* one, not the *secret* one.

## A4. Configure your environment variables

1. In VS Code's file explorer, find `.env.example` in the project root.
2. Make a copy of it in the same folder named exactly `.env` (no `.example`).
   You can right-click → Copy, then right-click → Paste, then rename, or
   from the terminal:
   ```bash
   cp .env.example .env
   ```
3. Open `.env` and replace the placeholder values with the real ones from
   step A3.8:
   ```
   SUPABASE_URL=https://your-actual-project-ref.supabase.co
   SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_actual_key
   ```
   Two more keys exist below those and can stay blank for now —
   `AUTH_CALLBACK_URL` (see "Email confirmation flow") and
   `AI_SERVICE_URL` (see `ai_service/README.md`) — both are optional and
   the app degrades gracefully without them.
4. Save the file. `.env` is already listed under `assets` in
   `pubspec.yaml`, so Flutter bundles it automatically — you don't need
   to do anything else for it to be picked up. It's also already excluded
   from `.gitignore` conventions for this kind of file; if you put this
   project under version control, double check `.env` isn't committed.

## A4b. Set up AI matching — start to finish (do this before `flutter run`)

Everything AI-related, in order. Nothing here needs Python or TensorFlow
on your machine: the project already ships the model files.

**Step 1 — Make sure all 12 migrations have been run.**
In the Supabase SQL Editor, run the migrations from A3 in numeric order
(`01` … `12`). Skipping ahead is the usual cause of confusing errors, so if
you're not sure which ones you ran, just run any you're unsure of again —
they are all safe to re-run.

**Step 2 — Confirm migrations 11 and 12 took effect.**
Run each of these on its own:
```sql
-- both chat tables should be listed (this is what makes chat live):
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public';

-- should return 0.6:
select public.matching_threshold();

-- should return 0.3:
select public.text_matching_threshold();

-- should list BOTH item_images_record_matches and
-- item_images_record_matches_on_embedding:
select tgname from pg_trigger
where tgrelid = 'public.item_images'::regclass and not tgisinternal;

-- should list BOTH items_record_text_matches_insert and
-- items_record_text_matches_update:
select tgname from pg_trigger
where tgrelid = 'public.items'::regclass and not tgisinternal;
```
Or run query 4 in `supabase/diagnostics_matching.sql` — every column in its
result should say `true`.

**Step 3 — Confirm the model files are in place.** From the project root
(PowerShell or Command Prompt):
```powershell
dir assets\models
```
You should see `mobilenet_v2_embedder.tflite` (about 3.8 MB) and
`imagenet_labels.txt`. Both ship with the project. Only if either is
missing, generate them with the steps under "Generating the on-device
model (Phase 4)" in Part B.

**Step 4 — (Optional) text matching service.**
Photo matching works without it. It only adds the "📝 text similarity"
signal. If `AI_SERVICE_URL` in `.env` points at your deployed
`ai_service/` (see `ai_service/README.md`), nothing else to do. Free hosts
put idle services to sleep and take 30–60 seconds to wake, so the app now
pings the service the moment the "Report item" form opens, giving it time
to wake while you fill in the form. If the service still isn't ready when
you tap Post, the item is posted without a text signal — photo matching is
unaffected.

**Step 5 — Do a full restart (not hot reload).**
Asset and model changes are only picked up by a fresh build:
```powershell
flutter pub get
flutter run
```
If a run was already going, stop it first.

**Step 6 — Check the model loaded correctly.**
Open **Report item** (or the **Matches** tab). In the `flutter run` console
you should see lines like:
```
TFLite output 0: shape=[1, 1000]
TFLite output 1: shape=[1, 1280]
TFLite ready: embedding=output 1, classes=output 0 (1000), 1000 labels
```
The exact indices depend on the model file; what matters is that one
output is `1280` wide and the "ready" line appears. If instead you see an
error mentioning "no 1280-wide output", the model file isn't the one this
project expects — regenerate it (Part B, "Generating the on-device model").

**Step 7 — Fix posts made earlier (every account needs this once).**

Title/description matching runs automatically for anything posted **after**
migration 12 — nothing to do for those. For posts made *before* it, run
this once in the SQL Editor (safe to re-run):
```sql
select public.rematch_all_text();
```

Photos are separate — see the next step.

**Step 8 — Fix photos posted earlier (every account needs this once).**
Photos posted before this fix have no AI data, so they can't be matched.
The app now analyses them automatically **as soon as it launches** (the
console prints `Embedding backfill: …`), and the Matches tab's scan icon
does the same on demand.

The catch: a photo can only be analysed on its **owner's** phone. A match
needs *both* photos of the pair analysed, so if account A hasn't opened the
updated app yet, nobody sees matches against A's items — even though their
own photos are fine. When testing with several accounts, sign in to **each**
one once on the updated build and wait a few seconds (the Matches tab's
scan icon shows a progress bar while it works). Matches then appear for
everyone involved without any further action.

**Step 9 — Test it properly, with two accounts.**
Matching deliberately never pairs two items from the *same* account, and
only pairs a **lost** item with a **found** one. So:
1. Account A: report a **Lost** item with a clear photo.
2. Account B (another phone/emulator, or sign out and sign in as someone
   else): report a **Found** item with a photo of the same — or a very
   similar — object.
3. Open **Matches** as either account. Even with no photo on either side,
   similar enough titles/descriptions should already show a match.

If nothing appears, run `supabase/diagnostics_matching.sql` in the SQL
Editor, one query at a time. **Start with 2b** — it lists every item with
its owner, type and `has_embedding`. A Lost and a Found item from different
owners that are both `true` should have matched by photo; regardless of
that column, they should also have matched by text unless their wording is
genuinely dissimilar. A `false` `has_embedding` just means that owner still
needs to open the updated app for photo matching specifically (Step 8).
Then:
- **3d** — the real text similarity of each cross-account pair. If your
  test pair scores below `0.3`, the words themselves don't overlap enough
  — try more similar wording, or lower the number in
  `text_matching_threshold()` (edit that function in migration 12, re-run
  it, then run `select public.rematch_all_text();`).
- **3c** — does each account have photos *with* an embedding? Any
  `without_embedding` above 0 means open that account's Matches tab (Step 8).
- **3b** — the real image similarity of each cross-account pair. If your
  test pair scores below `0.60`, the model doesn't consider the photos
  alike. Either use a clearer photo or lower the number in
  `matching_threshold()` (edit that function in migration 11, re-run it,
  then run `select public.rematch_all_images();`).
- **5** — the `matches` table itself.

**What to do if a post says "the AI could not analyze N photos".**
The item is posted, but those photos can't be matched yet. Open Matches
and tap the scan icon to retry. If it fails again, the error text shown
there says why — a model that failed to load (Step 6), no internet, or
migration 11 missing.

## A5. Android configuration — what's already done, and what's left

To save you a step, the Android manifest and Gradle files in this project
already have the following applied:

- ✅ Camera, location, media, and notification permissions
  (`android/app/src/main/AndroidManifest.xml`)
- ✅ Core library desugaring, Java 17, and `minSdk 24`
  (`android/app/build.gradle.kts`) — required by
  `flutter_local_notifications` 22+; see "Troubleshooting Gradle errors"
  for why this matters.
- ✅ App icon PNGs already generated in `assets/images/`

Two things are placeholders you can fill in when you're ready — the app
runs fine on a device without either of them, just with reduced features:

### A5.1 (Optional) Google Maps

The map view will show a blank/grey map until you add a real API key.

1. Go to https://console.cloud.google.com/, create or select a project.
2. Enable the **"Maps SDK for Android"** API (search for it in the API
   Library).
3. Create an API key under **APIs & Services → Credentials → Create
   Credentials → API key**.
4. Open `android/app/src/main/AndroidManifest.xml` and replace
   `YOUR_GOOGLE_MAPS_API_KEY_HERE` with your real key.

### A5.2 (Optional) Google Sign-In and push notifications

These need more setup (a Firebase project, Supabase provider config) and
are documented in Part B under "Google sign-in setup" and "Firebase setup
for push notifications". Skip them for now — email/password login and
the rest of the app work without them.

### A5.3 Regenerate the app icon (only if you change the design)

The launcher icon PNGs are already generated (white background, logo from
`assets/images/logo.png`) and referenced from `pubspec.yaml`. If you ever
redesign `assets/images/logo.png` and want to regenerate every launcher
icon (Android, adaptive icon foreground, web/PWA, favicon) from it:

```bash
python scripts/generate_icon_pngs.py
```

(Every Python command in this README uses `python` — that's what
Windows' official installer registers. On macOS/Linux, `python` is
sometimes missing or points to Python 2, so use `python3` there instead
if `python` doesn't work.)

or, equivalently for just the Android files, the standard Flutter tool:

```bash
dart run flutter_launcher_icons
```

See `assets/images/README.md` for what each generated file is for.

## A6. Connect your physical Android device

### A6.1 Enable Developer options and USB debugging on the phone

1. Open **Settings** on your Android phone.
2. Go to **About phone** (exact wording varies slightly by manufacturer).
3. Find **Build number** and tap it **7 times** in a row. You'll see a
   countdown toast like "You are now 3 steps away from being a
   developer." After the 7th tap, it'll say "You are now a developer!"
4. Go back to the main **Settings** screen → **System** → **Developer
   options** (on some phones this is its own top-level entry in Settings
   instead of under System).
5. Turn on **Developer options** if it's not already on, then scroll down
   and enable **USB debugging**.

### A6.2 Plug in the phone and authorize your computer

1. Connect the phone to your computer with a USB cable that supports data
   transfer (not a charge-only cable).
2. If your phone shows a popup asking about the USB connection mode,
   choose **File Transfer** or **PTP** (not "Charging only").
3. A dialog should appear on the phone: **"Allow USB debugging?"** with
   your computer's RSA key fingerprint. Check **"Always allow from this
   computer"** and tap **Allow**. If you don't see this dialog, unplug and
   replug the cable.
4. Verify your computer sees the device:
   ```bash
   flutter devices
   ```
   You should see your phone listed by name. If it shows "no devices
   detected" or "unauthorized", see "Device not showing up" in the
   troubleshooting section below.

### A6.3 Run the app

In VS Code:

1. Look at the bottom-right status bar — there should be a device name
   shown (or "No Device"). Click it and select your phone from the list.
2. Press **F5**, or open the **Run and Debug** panel (left sidebar) and
   click the green play button, or from the terminal:
   ```bash
   flutter run
   ```
3. The first build will take a few minutes (Gradle has to download
   dependencies and compile everything). Subsequent runs are much faster.
4. If it builds successfully, the app installs and opens on your phone,
   landing on the splash screen and then the login screen.

If step 3 fails with a Gradle-related error, continue to the next section.

**A note on AI features specifically**: `assets/models/` ships with the
model file and label list, so photo auto-tagging and image matching work
once the database side is set up. **Follow "A4b. Set up AI matching" above
before your first run** — it covers the SQL migration, checking the model
loads, and testing with two accounts. If the model is ever missing or
broken, the app doesn't crash: posting still works, but it now warns you
that the photo couldn't be analyzed (see `core/ml/tflite_provider.dart`).

## A6b. Run the automated tests

```
flutter pub get
flutter test                              # unit + widget tests, about a minute, no device needed
flutter test integration_test -d <id>     # the same main flows on a phone/emulator (flutter devices lists ids)
flutter test test/matches_screen_test.dart   # one file
```

- **What they test.** Pure logic (match tiers, paging, models, labels, notification routes) and the main flows on the real screens, listed in the What's new row *Widget and integration tests of the main flows*. The flows live in `test/support/flows.dart`; the fakes that stand in for the database live beside it.
- **Why fakes.** The app can't be started without a Supabase project (and Firebase), so the tests replace the repositories a screen reads with in-memory ones that apply the same rules as the SQL (e.g. a match is confirmed only when both people confirm). They prove the app's behaviour; they do **not** prove the SQL — run `supabase/tests/NN_checks.sql` on a staging project for that.
- **Adding a flow.** Write a `Future<void> myFlow(WidgetTester tester, {bool resizeView = true})` in `flows.dart`, call it from a `testWidgets` in `test/` and again from `integration_test/main_flows_test.dart`.
- **If a test fails after you change UI text,** the flows find widgets by their visible text — update the string in `flows.dart` too.

## A9. Share-a-post links

Full steps, with the commands: [`supabase/functions/post-preview/README.md`](supabase/functions/post-preview/README.md). In short:

1. `supabase functions deploy post-preview --no-verify-jwt`
2. Edit the three constants at the top of `web/share.html` (preview URL, Play Store URL, Android package), then host `web/share.html` **and** `web/_redirects` on a static host (Cloudflare Pages / Netlify — the same kind of place as `web/auth-callback.html`; **not** a Supabase Storage bucket).
3. `.env`: `SHARE_BASE_URL=https://<your host>` — the Share button appears on open posts.
4. `android/gradle.properties`: `findora.shareHost=<your host>`, rebuild. Tapping a link now opens the preview page's **Open in Findora** into the app.
5. To make the https link open the app *directly* (no browser hop), serve `https://<your host>/.well-known/assetlinks.json` with your signing key's SHA-256 (steps in the function README) and check with `adb shell pm get-app-links com.example.findora`.

Try it: share a post from one phone, open the link on another — signed in (lands on the post), signed out (sign in, then lands on the post), and without the app (preview card).

## A10. Languages (English, Sinhala, Tamil)

**Try it:** Profile → Language → සිංහල or தமிழ். The Matches tab, the bottom bar and the offline banner switch at once. "System default" follows the phone's language (English if the phone's language isn't one of the three).

**Where things are**

| What | Where |
|---|---|
| English text (the template) and a description of each message for translators | `lib/l10n/app_en.arb` |
| Sinhala / Tamil text | `lib/l10n/app_si.arb`, `lib/l10n/app_ta.arb` |
| gen-l10n settings | `l10n.yaml` |
| The list of languages and each one's name in itself | `lib/core/l10n/locale_controller.dart` (`kSupportedLocales`, `kLanguageSelfNames`) |
| The saved choice | `LocaleController` (`findora.locale` in shared preferences) |
| Generated code (don't edit, not committed) | `lib/l10n/app_localizations*.dart` — made by `flutter pub get` / `flutter run`; `flutter gen-l10n` forces it |

**Translating another string**
1. Add it to `app_en.arb` with a `@key` description, and to `app_si.arb` and `app_ta.arb` (the tests fail until all three have it).
2. In Dart: `AppLocalizations.of(context).yourKey` (import `package:findora/l10n/app_localizations.dart`). In a callback that runs after an `await`, read it **before** the await and keep the object (it stays valid after the widget is gone — see `MatchCard._act`).
3. Placeholders: `"hello": "Hello {name}"` with `"@hello": {"placeholders": {"name": {"type": "String"}}}`. Plurals: see `expiryExpiringDays`. **A literal apostrophe is written twice** (`don''t`) — a test enforces this.
4. Leave emoji where the English has them (the filter chips).

**Adding a language** (say Hindi, `hi`): copy `app_en.arb` to `app_hi.arb`, translate, change `@@locale`, add `Locale('hi')` and its name in itself to `locale_controller.dart`, and add the language to the picker's test expectations. Flutter must support it for Material's own text (`flutter_localizations` covers most languages).

**Fonts.** Sinhala and Tamil are drawn with the phone's system fonts (Noto Sans Sinhala / Tamil on current Android, since the Inter and Manrope fonts have no such letters). Check a real low-end phone: very old Android versions without those system fonts would show empty boxes, and bundling Noto fonts as assets would be the fix.

**Not translated yet (do these next, screen by screen):** post, chat, profile, admin and sign-in screens, the in-app guide/FAQ (`document_content.dart`), the tooltips and scan snackbars on the Matches tab, and **server-written text** — push notification titles/bodies and alert texts created in SQL (`create_notification(...)`) are English; translating them needs the recipient's language stored on their profile and the SQL to pick the text from it.

## A7. Troubleshooting Gradle errors

### "Timeout waiting to lock build logic queue" / a second Gradle instance

This means two Gradle processes are fighting over the same project — most
commonly VS Code's Java extension trying to auto-import `android/` as a
standalone Gradle project in the background, using its own Gradle
version and JDK, completely separately from Flutter's own build. Add
this to `.vscode/settings.json` (already done in this project) to stop
it happening:
```json
{
    "java.import.gradle.enabled": false,
    "java.import.exclusions": ["**/android/**"]
}
```
Then close VS Code, kill any lingering `java.exe` processes in Task
Manager, delete `android/.gradle`, and reopen.

### "Could not close incremental caches" / `BuildToolsApiCompilationWork` failures

If you see this for one or more plugins (commonly
`firebase_core`, `geocoding_android`, `image_picker_android`,
`google_maps_flutter_android`, or similar), it's **not a bug in this
project** — it's a currently-active Flutter ecosystem migration issue.
Flutter is transitioning Android builds to a new "Built-in Kotlin" model
required by AGP 9+ (which this project's `flutter create` selected), and
as of this writing, many widely-used plugins haven't finished migrating
to it yet. Their old-style Kotlin compilation is hitting a cache-closing
bug under this newer toolchain. This is being tracked upstream at
flutter/flutter#173456, #187225, and #185121 — it isn't unique to this
project or something specific to Findora's code.

**First**, this project's `android/gradle.properties` already has
`kotlin.incremental=false`, a documented, low-risk workaround that
avoids the buggy code path (slightly slower rebuilds, no other effect).
If you're seeing this error, do a clean rebuild first to make sure that
setting actually takes effect:
```bash
flutter clean
cd android
./gradlew clean          # on Windows: gradlew.bat clean
cd ..
flutter pub get
flutter run
```

**If it still fails after a clean rebuild**, this is an active upstream
issue and the most reliable fix available to an app developer (rather
than waiting on each plugin's maintainers) is dropping to a slightly
older, more mature Flutter release that predates this migration push:
```bash
flutter downgrade
```
This walks you through installing the previous stable release. Check
https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin
for the current state of the migration before deciding how far back to
go — plugin authors are actively updating, so this may resolve itself
with a `flutter pub upgrade` in the near future without downgrading at all.

### "Out of memory" / `allocation.cc: error: Out of memory` during the build

If the crash trace mentions `kernel_snapshot_program` or points into the
Dart VM's own allocation code, this is happening in the **Dart compiler
running on your development machine**, not the Android device — the
device name in the "Launching..." line is a red herring here. It means
your PC ran out of available RAM while compiling the app, usually from
too much running at once: the Gradle daemon (which by default reserves a
large heap — already turned down in this project's `gradle.properties`
from 8GB to 3GB), a separate Kotlin daemon, the Dart compiler itself, and
whatever else is open (Android Studio, browser tabs, VS Code extensions).

If you hit this:
1. Stop any lingering Gradle/Kotlin daemons before retrying — repeated
   failed builds can leave several idling in memory simultaneously:
   ```bash
   cd android
   ./gradlew --stop          # on Windows: gradlew.bat --stop
   cd ..
   ```
2. Close other memory-heavy applications (Android Studio if it's open
   separately, browser windows, etc.) before running `flutter run` again.
3. If it still happens on a machine with 16GB or less, the `-Xmx3G` in
   `gradle.properties` can be turned down further (e.g. `-Xmx2G`) — Gradle
   will just run a bit slower, which is a better trade than failing outright.

### "Inconsistent JVM Target Compatibility Between Java and Kotlin Tasks"

This shows up as something like:
```
Inconsistent JVM-target compatibility detected for tasks 'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (21).
```
for a specific plugin (`tflite_flutter` and others are known to hit this).
It means that plugin's own bundled Android build config — which lives in
the pub cache, not this project, so it can't be edited directly — sets a
Java target that doesn't match the Kotlin target Gradle resolves for it.

This project's root `android/build.gradle.kts` fixes this by reading
each module's own Java target (set by that plugin's own build file,
never touched by this project) and pointing that module's Kotlin target
at the same value — via a `gradle.taskGraph.whenReady` hook, since that's
the only point at which every module's configuration (including AGP's
own internal wiring) is guaranteed to have already finished.

This took three attempts to get right, and it's worth knowing the
history in case you ever touch this block:
1. A plain `subprojects { tasks.withType<JavaCompile>().configureEach {} }`
   only partially worked — it fixed Kotlin but not Java, since AGP sets
   each plugin's own `compileOptions` on its `JavaCompile` task during
   that plugin's own configuration, which can run *after* an ordinary
   configuration block's action fires.
2. Forcing `JavaCompile`'s `sourceCompatibility`/`targetCompatibility` to
   17 directly via `taskGraph.whenReady` did fix the mismatch, but broke
   something worse: it interfered with AGP's own classpath wiring for
   that task, and `android.jar` (Android's own SDK classes) silently
   vanished from the compile classpath entirely — surfacing as
   `package android.app does not exist` and similar errors for basic
   Android classes, for a module that had nothing wrong with its actual
   code.
3. The current version never touches `JavaCompile` at all — it only
   *reads* each module's already-correct Java target and aligns Kotlin
   to match it, leaving AGP's classpath wiring completely undisturbed.

If you add a new plugin and hit this again, no action should be needed —
the override reads each module's target dynamically rather than assuming
a fixed value. If it somehow persists, a `flutter clean` followed by a
rebuild clears any stale per-module build cache that might be masking
the fix taking effect.

### "Dependency ':flutter_local_notifications' requires core library desugaring to be enabled"

This is already fixed in this project's `android/app/build.gradle.kts`
(`isCoreLibraryDesugaringEnabled = true` plus the matching
`coreLibraryDesugaring` dependency). If you still see this exact error,
double-check you're running the version of `build.gradle.kts` from this
project and haven't accidentally reverted it, then run a clean rebuild
(see below).

### "Manifest merger failed" mentioning minSdkVersion

`flutter_local_notifications` 22+ requires `minSdk 24` or higher, which
is also already set in `build.gradle.kts`. If a different plugin you add
later demands an even higher minimum, the error message will name the
exact number to use — update the `minSdk` line to match.

### "Your project is configured with Android NDK [X], but the following plugin(s) depend on a different Android NDK version"

This project has several plugins with native code (`google_maps_flutter`,
`tflite_flutter`, `geolocator`, `image`), and it's common for them to
disagree slightly on which NDK version they were built against. The
error message tells you exactly which version to use — copy it and add
(or edit) this line inside the `android { }` block of
`android/app/build.gradle.kts`:

```kotlin
android {
    ndkVersion = "27.0.12077973"  // use the exact version from your error message
    // ... rest of the block
}
```

### "Unsupported class file major version" or Java version errors

This means Gradle is using a Java version other than 17. Double check:

1. `java -version` in your terminal shows `17.x` (see step A1.3).
2. In VS Code, if you have the **Gradle for Java** extension installed,
   check its settings for a `java.home` or `java.import.gradle.java.home`
   override that might be pointing somewhere else.
3. As a last resort, you can point Gradle at a specific JDK regardless of
   `JAVA_HOME` by adding a line to `android/gradle.properties`:
   ```
   org.gradle.java.home=/full/path/to/a/jdk-17
   ```

### "SDK location not found" / "flutter.sdk not set in local.properties"

`android/local.properties` (auto-generated, not committed to version
control) needs to point at both your Flutter SDK and Android SDK. Delete
it and let Flutter regenerate it:

```bash
flutter clean
flutter pub get
```

### Device not showing up in `flutter devices`

- Make sure USB debugging is on (step A6.1) and you tapped "Allow" on the
  phone's dialog (step A6.2).
- Try a different USB cable or port — some cables are charge-only.
- Run `flutter doctor -v` and check the "Android toolchain" and any
  device-related lines for a more specific error.
- On Windows, you may need the phone manufacturer's USB driver installed.

### Clean rebuild (fixes a surprising number of stale-cache issues)

```bash
flutter clean
cd android
./gradlew clean          # on Windows: gradlew.bat clean
cd ..
flutter pub get
flutter run
```

### Still stuck?

Copy the **full** error text from VS Code's terminal (scroll up — the
first red line usually isn't the actual cause, the real error is often
further up) and share it. "Gradle error" alone can mean dozens of
different things; the exact message is what actually pins it down.

---

# Part B — Reference: how the app is built

This part documents what each phase of the build added and why, for when
you're ready to extend the app. It assumes you've completed Part A.

## App icon and branding

`assets/images/` has the Findora logo — a blue magnifying glass with a
cyan lens and an orange location pin, with circuit-style accents. This is
a real PNG asset (not hand-drawn vector shapes), composited into launcher
icons with Pillow.

- `logo.png` — the logo itself, transparent background, used directly via
  `Image.asset()` on the splash screen and login screen.
- `app_icon.png` — the logo composited onto a rounded **white** square
  (changed from the original light-blue background), the flat launcher
  icon source for `flutter_launcher_icons`.
- `app_icon_foreground.png` — the logo alone on transparent, padded for
  Android's adaptive icon safe zone. Its background color is set
  separately to white in `android/app/src/main/res/values/colors.xml`
  (`ic_launcher_background`) and `pubspec.yaml`
  (`flutter_launcher_icons.adaptive_icon_background`).

The app's whole color theme (`core/theme/app_colors.dart`) sources its
primary/secondary colors from this logo — vivid blue primary, cyan
accent, orange secondary — via `ColorScheme.fromSeed`, so the brand color
carries through every screen's buttons, chips, and selected states
automatically rather than needing per-screen updates.

To regenerate every launcher/PWA icon after changing the logo:

```bash
python scripts/generate_icon_pngs.py
```

See `assets/images/README.md` for details on what each output is used
for, and the equivalent `flutter_launcher_icons` command for just the
Android files.

## Profile sub-screens

Everything under Profile is wired to real functionality, not placeholder
taps:

- **Edit profile** (pencil icon next to the avatar) — updates
  `full_name`/`phone` on the `profiles` row, and uploads a new avatar to
  the `avatars` Storage bucket (already set up back in Phase 1).
- **My reported items** — posts still in play: open, matched or claimed.
  A **returned** post doesn't appear here any more — see the next item.
  Swipe a card left, or tap its trailing delete icon, to remove a post
  (`ItemsRepository.deleteItem` — a soft delete, see "Soft delete: items
  are hidden, never erased" below).
- **Returned items** (`ReturnedItemsScreen`,
  `ItemsRepository.fetchMyReturnedItems` → the `my_returned_items()` RPC)
  — every post of yours that's been handed back, next to the post it was
  returned with, with both people's ratings and a way to reopen the chat.
  This is the *only* place either post is still visible at all, and only
  to the two owners — see "Returned items become private" below.
- **Ratings & reviews** (`RatingsScreen`, the `my_ratings()` RPC) —
  average, star breakdown, and every review, split into Received/Given tabs.
- **Notification settings** — reads the actual OS-level permission via
  `FirebaseMessaging.getNotificationSettings()`, and a toggle that
  registers or clears this device's push token on your profile. Real
  state, not a decorative switch.
- **Appearance** — Light/Dark/System, persisted via `shared_preferences`
  (`core/theme/theme_mode_controller.dart`). Overrides the OS setting
  until switched back to "System default".
- **User manual** (`UserManualScreen`) — the whole app and process,
  collapsible sections.
- **Safety guidelines** (`SafetyGuidelinesScreen`) — meeting up safely and
  spotting scams.
- **Privacy policy** (`PrivacyPolicyScreen`) — what's collected, who can
  see it, and your choices.
- **Help & support** — links to all three documents above, an FAQ grouped
  by topic, and a "Contact support" button that opens a pre-filled
  `mailto:` email (`url_launcher`, plus a manifest `<queries>` entry for
  the `mailto:` scheme — Android 11+ hides apps from
  `canLaunchUrl`/`launchUrl` unless you declare you're looking for them).

All four documents' text lives in one place —
`lib/features/profile/document/document_content.dart` — as a list of
typed content blocks (`DocHeading`/`DocParagraph`/`DocBullets`/`DocSteps`/
`DocCallout`), rendered by `document/document_blocks.dart`. Matching
Markdown copies are in `docs/` (`USER_MANUAL.md`,
`SAFETY_GUIDELINES.md`, `PRIVACY_POLICY.md`) for publishing outside the
app — an app-store listing's privacy-policy URL, for instance. The two
aren't generated from each other; edit both if the content changes.

## The "Report item" button (Home and Matches only)

The floating "Report item" button used to show on all four tabs,
center-docked. It now only appears on Browse and Matches
(`MainShell._branchesWithReportFab`), and floats at the bottom-right
(`FloatingActionButtonLocation.endFloat`) instead of center-docked —
reporting an item isn't a relevant action while reading chats or looking
at your own profile.

## Splash screen

Rebuilt to match a provided reference design: a soft white-to-light-blue
gradient background, the logo at a larger size, "Findora" in bold blue
alongside an "AI-Powered Lost & Found" tagline, and a custom animated
loading ring (a rotating `CustomPainter`, not a stock
`CircularProgressIndicator`) with "Initializing AI Engine..." beneath it.
The actual session-check logic (redirecting to `/login` or `/feed`) is
unchanged — only the visual presentation changed.

## Google sign-in setup (Phase 2)

The "Continue with Google" button calls `signInWithOAuth`, but the
redirect back into the app needs setup outside of Dart code — in two
different places, for two different hops, easy to mix up:

1. **Google Cloud Console** → APIs & Services → Credentials → your OAuth
   2.0 Client ID (Web application type) → **Authorized redirect URIs** →
   add:
   ```
   https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
   ```
   This is the one people get wrong — **not** the app's custom scheme.
   The actual flow is app → Supabase → Google → back to Supabase → back
   to the app, and this URI is what Google redirects to (Supabase's own
   callback endpoint), not where the app ends up. Getting this wrong
   looks like Google's own error page: "Access blocked: this app's
   request is invalid" / "Error 400: redirect_uri_mismatch" — if you see
   that, it's this URI, not anything in Supabase's dashboard or in code.
2. **Supabase Dashboard** → Authentication → Providers → enable Google,
   and paste in that same OAuth client's ID/secret.
3. **Supabase Dashboard** → Authentication → URL Configuration → add
   `io.supabase.findora://login-callback` as a redirect URL — this one
   *is* the custom scheme, for the second hop (Supabase → app), which is
   entirely separate from step 1's URI and doesn't get registered with
   Google at all.
4. **Android**: the intent filter for this scheme is already in
   `android/app/src/main/AndroidManifest.xml` — nothing to add there.

Skip all of this and the email/password flow still works fine — the
Google button will just fail with an error page instead (which one
depends on exactly what's missing — "provider is not enabled" means step
2 hasn't been done yet at all; "redirect_uri_mismatch" means step 2 is
done but step 1 wasn't, or was entered with a typo).

## Item detail screen: carousel, map preview, delete, and contact

- The photo `PageView` now has animated dot indicators instead of no way
  to tell there's more than one photo, plus a rounded "sheet" content
  layout that overlaps the carousel slightly (`_ItemDetailBody`).
- A small non-interactive map preview (`google_maps_flutter` in
  `liteModeEnabled`) shows under the description when the item has a
  location — backed by a new `get_item_coordinates()` RPC, since a raw
  PostGIS geography value doesn't serialize predictably over PostgREST
  (same reasoning as `nearby_items()` back in Phase 6).
- **Owner**: an overflow menu (`_OwnerMenu`) with "Delete post" — a soft
  delete (see "Soft delete: items are hidden, never erased" below), not a
  real `delete`; RLS no longer permits the latter at all.
- **Everyone else**: two separate paths, kept deliberately apart rather
  than merged into one generic "message" button:
  - A confirmed AI match connecting one of *your* items to this one
    opens the verified claim/chat flow (`ChatScreen`) — still gated
    behind a confirmed match on purpose (Phase 5/7), so contact info
    isn't shared before ownership looks plausible.
  - Otherwise, a **"Contact poster"** button opens a lighter, separate
    direct-message thread (`contact_threads`/`contact_messages` — see
    `supabase/06_contact_messaging.sql` and the "Direct contact
    messaging" section below) — for a quick question before you're sure
    it's a match, without needing an AI match to exist first. The old
    "report your own matching item" shortcut is still there underneath
    it.

## Direct contact messaging

A second, parallel messaging system alongside the confirmed-match chat
from Phase 7 — added because item detail's old "no generic contact
button, on purpose" design (see above) was too strict for "quick
question before I'm sure it's mine" cases. Deliberately kept as a
*separate* table/flow rather than folding into `matches`/`messages`, so
the claim-verification lifecycle (`claims`, ratings, "mark returned")
stays exclusively reachable through a real AI match — direct contact is
just messaging, nothing more.

- `contact_threads` — one row per (item, person who reached out);
  `start_contact_thread()` is idempotent, so tapping "Contact poster"
  again just reopens the same thread.
- `contact_messages` — the messages themselves, RLS-restricted to the
  thread's two participants.
- `lib/features/contact/` — `ContactRepository`, `ContactChatScreen`
  (a deliberately plain bubble UI, no claim-lifecycle banner).
- `ChatListScreen` now has two tabs: **Matches** (unchanged) and
  **Direct messages** (new), so both conversation types stay visible
  from one place.

## Loading skeletons

`core/widgets/shimmer_list.dart` has two reusable shimmer placeholders —
`ShimmerCardList` (matches the image+title+subtitle card shape used by
the feed, matches, and my-items lists) and `ShimmerTileList` (matches the
chat list's avatar rows) — now shown during loading instead of a bare
`CircularProgressIndicator` that gives no sense of what's about to
appear. The `shimmer` package was already in `pubspec.yaml` from Phase 1
but had never actually been used until now.

## Onboarding

A 3-page carousel (`features/onboarding/onboarding_screen.dart`) explains
reporting an item, AI matching, and the verify-then-reunite flow before
first login. It's shown once per *device*, not per account — persisted
via `shared_preferences` (`core/onboarding/onboarding_prefs.dart`), added
as a direct dependency since it was previously only present transitively
through `supabase_flutter`. The splash screen's redirect logic now checks
this flag: signed out + onboarding not seen → `/onboarding`; signed out +
already seen → `/login`. `/onboarding` also had to be added to the
router's `isAuthRoute` set, or the redirect logic built in Phase 2 would
immediately bounce a signed-out user away from it back to `/login`.

## Accessibility pass

- Every icon-only button now has a `tooltip` (which also sets its
  screen-reader label in Flutter) — the password visibility toggle, send
  button, star-rating buttons, and the post-item form's close button were
  missing one.
- Two small overlay buttons (remove-photo on a thumbnail, change-avatar
  badge) had tap targets as small as 24dp — well under the 48dp minimum.
  Both are now wrapped with `Semantics` labels and padded hit areas; the
  photo-remove button only reaches ~40dp rather than the full 48dp, since
  the thumbnails sit only 12px apart and a full-size target would overlap
  the next photo.
- Replaced a hardcoded brand-blue hex color on the login screen with
  `theme.colorScheme.primary`. Material 3's `ColorScheme.fromSeed`
  generates a lighter, higher-contrast tone of the brand color
  specifically for dark mode — a fixed hex value skips that and could end
  up low-contrast against a dark background. (The splash screen's fixed
  light design is left as-is; splash screens commonly show a constant
  brand look regardless of system theme.)

## Auth state and routing (Phase 2)

**Profile data fix**: the signup form's "Full name" field used to be sent
as `username` — a column that had a `unique` constraint. Two users
signing up with the same name would make the *second* signup fail
outright with a database constraint violation, since the
`handle_new_user` trigger runs inside the same transaction as account
creation. Fixed by: dropping the unique constraint (there's no "pick a
unique handle" UX in this app, so it was never enforceable correctly
anyway), having signup send `full_name` instead, and having the trigger
derive `username` safely from the email prefix instead of user input.
`ProfileScreen` now reads the display name from the `profiles` table
(`full_name`, falling back to `username`, then email) instead of reading
raw Supabase Auth metadata directly, consistent with how rating and admin
status are already sourced. If you already ran `01_extensions_and_tables.sql`
and `02_functions_and_triggers.sql` before this fix, just re-run both —
both changes are written to be safely re-run.

`core/router/app_router.dart` gates navigation for real:

- `GoRouterRefreshStream` turns `supabase.auth.onAuthStateChange` into
  something go_router can listen to, so the router re-checks its
  `redirect` callback on every sign-in, sign-out, and token refresh.
- Signed-out users get bounced to `/login` from anywhere else in the app;
  signed-in users get bounced away from `/login`/`/signup` to `/feed`.
- Screens never navigate manually after a successful auth call — they
  just await the Supabase call and let the redirect react to the
  resulting state change. This is also why a session that expires
  mid-use sends the user back to `/login` on its own.

`core/providers/auth_providers.dart` exposes `currentUserProvider` for
any screen that wants to read the signed-in user reactively.

## Photo, location, and storage permissions (Phase 3)

`image_picker` and `geolocator` need the platform permissions already
declared in `android/app/src/main/AndroidManifest.xml` (camera, fine and
coarse location, media images). No Dart-side permission-request package
is needed beyond that — `image_picker` and `geolocator`'s
`requestPermission()` trigger the OS prompt automatically.

## How posting an item works (Phase 3 recap)

1. `PostItemScreen` picks photos with `image_picker` (camera or gallery,
   multiple photos supported) and keeps them as local `File`s until submit.
2. "Add current location" calls `Geolocator.getCurrentPosition()`, then
   `geocoding`'s `placemarkFromCoordinates()` (an instance method — see
   the version note at the top of `pubspec.yaml`) turns the coordinates
   into a readable label like "Galle Road, Negombo".
3. On submit, `ItemsRepository.createItem()` inserts the `items` row
   first (so it has an id), then uploads each photo to the `item-images`
   bucket under `{user_id}/{item_id}/...`, then inserts one `item_images`
   row per photo with its public URL plus that photo's AI classification.
4. `ItemFeedScreen` reads real rows via `itemsFeedProvider`, joined with
   category name and photo URLs in a single query — a plain
   `FutureProvider`, refreshed with pull-to-refresh or invalidated after
   a successful post, not a live Realtime subscription (Supabase's
   `.stream()` API doesn't support the embedded joins this screen needs).

## Generating the on-device model (Phase 4)

`assets/models/` needs two files. **This project already ships them**
— you only need this section if they're missing or you want to
regenerate them. Producing them requires downloading pretrained weights
from Google's servers:

```bash
cd scripts
pip install -r requirements.txt
python export_tflite_model.py
```

`tensorflow`'s wheel is large (~350–400MB) — on a slow or throttled
connection, pip's install can time out partway through. If it does,
retry with a longer timeout (pip resumes from its cache rather than
re-downloading from scratch): `pip install --default-timeout=1000 -r requirements.txt`.

This downloads pretrained MobileNetV2 (ImageNet) weights, wraps them so a
single forward pass returns both a 1280-d embedding and a 1000-way
classification, converts to TFLite with dynamic-range quantization, and
writes `imagenet_labels.txt` directly from Keras's own class index file
— both files go **directly into `assets/models/`**, no separate copy
step. (If you're working from a checkout old enough that the script's
own printout says "copy both into assets/models/" instead, update
`scripts/export_tflite_model.py` first — earlier versions wrote both
files into `scripts/` itself and left the copy as a manual last step,
which was very easy to skip without any error telling you so: the script
finishes cleanly, `assets/models/` silently stays empty, and AI
matching/auto-tagging just never do anything with no indication why.)

**Verify it actually landed in the right place** — this exact "ran fine
but the files ended up in the wrong folder" mistake is the single most
common reason AI matching doesn't seem to work:
```bash
dir ..\assets\models
```
```bash
# macOS/Linux
ls ../assets/models
```
You should see `mobilenet_v2_embedder.tflite` (a few MB) and
`imagenet_labels.txt` alongside the folder's own `README.md`. If those
two are missing, the app has nothing to run on-device classification
with, silently — see the next paragraph.

**Output order is detected automatically.** The TFLite converter doesn't
guarantee the two outputs stay in the order the script declares them
(the model shipped here has the classification as output 0 and the
embedding as output 1). `TfliteClassifier.load()` reads each output's
shape (1280 wide = embedding) and prints the mapping to the console, so
there's nothing to check or swap by hand. An earlier version hardcoded the
order, which made every classification fail silently — see the Phase 5
notes and `supabase/11_realtime_and_matching_fixes.sql`.

Until you run this script (and it's in `assets/models/`), the app
degrades gracefully rather than crashing: `PostItemScreen` catches the
missing-model error and posts without AI tagging — but that also means
**no image embedding ever gets stored, so posted items can never be AI
matched against anything**, silently, with no error surfaced anywhere in
the app. If matches never appear no matter what you post, this — not a
matching-logic bug — is the first thing to rule out. A quick way to
confirm either way, run in the Supabase SQL Editor:
```sql
select id, item_id, embedding is not null as has_embedding, created_at
from item_images
order by created_at desc
limit 10;
```
If `has_embedding` is `false` for items posted *after* you ran the
export script and rebuilt the app, the model still isn't being found at
runtime — double check the two files are really in `assets/models/`
(not `assets/models/models/` or similar) and do a full `flutter run`
again (not just hot reload — asset bundle changes need a full restart).

## How the AI matching actually works

1. On-device: the exported MobileNetV2 model runs on each photo,
   producing a predicted ImageNet label and a 1280-d embedding vector —
   this is the CNN half of matching, and it runs **entirely on the
   phone**, using the `.tflite` file bundled into the app itself. See
   "Does matching need my laptop connected?" below for what that means
   in practice.
2. A heuristic in `core/ml/category_mapper.dart` maps that fine-grained
   label (e.g. "Labrador_retriever") onto one of Findora's categories
   (e.g. "Pets") to pre-fill the post form. The label also pre-fills the
   **title** field (title-cased — `PostItemScreen._titleCaseFromLabel`),
   as long as the person hasn't already typed one themselves. This
   category is just a starting suggestion for the post form now, not a
   gate on matching — see point 5.
3. Only the embedding, label, and photo get uploaded — matching needs
   everyone else's items too, so it can't happen purely on-device.
4. Separately, if `AI_SERVICE_URL` is configured (see `ai_service/`),
   the title + description are sent there for a **text/NLP** embedding
   (Sentence-Transformers, with NLTK doing tokenization/stopword/
   lemmatization cleanup first — the "N" and "S" of the documented
   TensorFlow/OpenCV/Sentence-Transformers/NLTK stack) — best-effort,
   skipped entirely if unset, slow, or unreachable.
5. A trigger (`record_matches_for_image`, which now just calls
   `match_image()` — see `supabase/11_realtime_and_matching_fixes.sql`)
   fires the moment a photo with an embedding is inserted **or an
   existing photo gets its embedding filled in later** (the Matches tab's
   scan), comparing it against every opposite-type,
   open item via pgvector's cosine distance operator (`<=>`) to get an
   image-similarity candidate list (photos scoring at least
   `matching_threshold()`, currently 0.60) — **category is not part of this
   filter** (see "Why category doesn't gate matching" below) — then, for
   each candidate, blends in text similarity (if both sides have a text
   embedding), GPS proximity (if both sides have a location), and event
   time proximity (if both sides set one) into one **combined score**,
   written to `matches` (see
   `supabase/10_open_matching_and_time.sql`'s `combined_match_score()`).
6. Separately from all of that — and needing no photo at all —
   **title/description matching** runs the moment an item is posted, and
   again whenever its title or description is edited (triggers
   `items_record_text_matches_insert`/`_update`, `match_item_by_text()`,
   `supabase/12_text_matching.sql`). It compares text the same way point 4
   would, if that text embedding is available for both items; if not (no
   `ai_service/` configured, or it didn't respond before posting), it
   falls back to `pg_trgm`'s word/substring similarity on the raw title +
   description — always available, no setup, but literal (it helps when
   the words genuinely overlap; "wallet" vs "purse" won't score well
   without the semantic embedding). Either way the result lands in the
   same `matches` row a photo comparison would use — see
   `upsert_match_score()`, which lets whichever signal (photo or text)
   finds a pair first, and whichever finds it second enrich the same row
   rather than duplicate it or get silently dropped.
7. `MatchesScreen` reads those via `my_matches()`, which resolves each
   row into "my item" vs "the matched item" from the caller's
   perspective — either owner can confirm or dismiss it, sees the score
   breakdown ("📷 92% · 📝 78% · 📍 1.2 km · 🕐 6h apart"), and can filter
   the list down to matches that have a strong text/location/time signal
   via the chips at the top of the screen (client-side filtering over
   the already-fetched list — the dataset is just one person's matches,
   not worth a server round-trip per filter tap).

### Why category doesn't gate matching

Originally, `match_items()` only compared items within the same
category, on the theory that a lost wallet shouldn't be compared against
a found bicycle. In practice this caused real matches to be missed: the
on-device model's category guess is just a heuristic (an ImageNet label
mapped through `category_mapper.dart`'s rules), and two photos of the
literal same object can easily land in different guessed categories,
especially if one person's photo confuses the classifier and the other
person's doesn't — at which point those two items are silently never
compared *at all*, regardless of how visually identical the photos
actually are. Category is still collected and shown (useful for
browsing/filtering the main feed), it just no longer excludes a
candidate from being scored in `match_items()`.

### Does matching need my laptop connected?

No — once the app is running on your phone, the whole matching pipeline
is independent of the laptop:

- **On-device classification/embedding** (`tflite_classifier.dart`) runs
  using the `.tflite` file bundled into the installed app — this is
  local computation on the phone's own CPU, identical whether the phone
  is tethered to a laptop or sitting on the other side of the room.
- **Everything else** (storing the embedding, the `matches` trigger,
  fetching results) talks to **Supabase**, a cloud service — this needs
  *internet on the phone* (Wi-Fi or mobile data), which has nothing to
  do with the laptop being nearby.
- `flutter run`'s USB/wireless connection is a **development
  convenience only** — hot reload and streaming console logs back to
  your terminal. It's not something the running app depends on to
  function. Unplugging the cable is fine for using the app; the caveat
  is that on some devices, physically disconnecting *while* a debug
  session is actively attached can kill that debug session (and
  sometimes the app process along with it, depending on the device's USB
  debugging behavior) — annoying for testing, but a debug-tooling
  quirk, not evidence the app secretly needs the laptop. If you want to
  be completely sure there's no dependency at all, `flutter build apk
  --release` and install that APK normally — a release build has zero
  runtime connection to the development machine, ever.

## The matching engine, end to end (Phase 5, extended)

- **`record_matches_for_image`**: an `after insert` trigger on
  `item_images` for rows with a non-null `embedding`. Runs
  `match_items()` for the image-similarity **candidate list** (this is
  the fast ANN "recall" step — see the multimodal note below), computes
  text similarity + GPS proximity + time proximity for each candidate,
  and inserts the blended result into `matches`, `on conflict do
  nothing` so re-processing never duplicates. Runs inside the same
  transaction as the photo insert.
- **`match_items()` excludes same-user matches** — posting both a "lost"
  and "found" report yourself won't match against yourself. It still
  *accepts* an optional category filter parameter (unused by the
  trigger, which now passes `null` — see "Why category doesn't gate
  matching" above), kept in case a future caller wants it.
- **Multimodal scoring** (`supabase/10_open_matching_and_time.sql`):
  `match_items()` stays a pure image-similarity ANN search on purpose —
  it's the one step that can actually use `item_images.embedding`'s
  HNSW index, so it's what keeps matching fast as the table grows.
  Everything past that (text similarity via `items.text_embedding`, GPS
  proximity via `gps_proximity_score()`, time proximity via
  `time_proximity_score()`) only ever runs over the already-small
  candidate list `match_items()` returns, then `combined_match_score()`
  blends all four with weights 0.4 image / 0.25 text / 0.2 GPS / 0.15
  time, re-normalized over whichever signals are actually present for
  that pair (not every item has a location, a text embedding, or an
  event time set). `rescore_matches_for_item()` exists because the text
  embedding often arrives *after* the item row is first inserted (an
  async HTTP call to `ai_service/`, not guaranteed to finish before the
  first photo upload) — call it once that embedding lands to backfill
  `text_similarity`/`similarity_score` on that item's existing matches.
- **`my_matches()`**: resolves `item_a_id`/`item_b_id` into "my item" vs
  "the matched item" from `auth.uid()`'s perspective in one query, now
  including the `image_similarity`/`text_similarity`/`distance_meters`/
  `time_proximity` breakdown alongside the blended `similarity_score`.
- Item owners can `update` their own matches (confirm/dismiss), not just
  read them.
- **Title/description matching** (`supabase/12_text_matching.sql`) is a
  second, independent way a pair gets into `matches`, needing no photo:
  - `items_record_text_matches_insert`/`_update` — `after insert`, and
    `after update of title, description` (guarded by a `when` clause so it
    only actually re-runs when one of those values changed, since the
    app's edit form always sends both columns) — call
    `match_item_by_text()`.
  - `match_items_by_text()` is the text-matching analogue of
    `match_items()`: same opposite-type/different-owner/open/not-deleted
    filters, ordered by `text_similarity_between()` instead of vector
    distance, cut off by `text_matching_threshold()` (0.30) instead of
    `matching_threshold()`.
  - `text_similarity_between(a_id, b_id)` picks semantic similarity via
    `items.text_embedding` when both sides have one, else `pg_trgm`'s
    `similarity()` on the lowercased title (weighted 0.7) and description
    (0.3, skipped when either side has none) — see the function's own
    comment for why title outweighs description.
  - `upsert_match_score(item_a, item_b, image_similarity, text_similarity)`
    is what both `match_image()` and `match_item_by_text()` actually write
    through: it looks for an existing row for the pair **in either
    column order** (the unique constraint is on the ordered pair, but two
    items only ever describe one relationship) and updates it — keeping
    whichever of image/text similarity it already had for any signal the
    current call doesn't supply — instead of inserting a second row or
    silently discarding the new signal. GPS/time proximity are recomputed
    fresh from the two items' current data on every call, cheap enough not
    to bother caching.
  - `rematch_all_text()` — the text-matching equivalent of
    `rematch_all_images()`, for items posted before this migration.

## Google Maps setup (Phase 6)

Covered in Part A5.1. The map view builds and opens without a key, it
just renders a blank/grey map until one is added.

## Search, filters, and the map (Phase 6)

- Search and category filters are real server-side query parameters
  (`.eq('category_id', ...)`, `.or('title.ilike...,description.ilike...')`),
  not client-side filtering — `itemsFeedProvider` is a `.family` provider
  keyed on `ItemsFilter(categoryId, searchQuery)`. The search box
  debounces 400ms before refetching.
- **Lost / Found** is a third filter, but deliberately client-side: it's
  applied to whatever `itemsFeedProvider` already returned, with an
  instant switch and no refetch, and its own "N lost · N found" counts
  stay based on the *category/search* filter rather than itself (so
  picking "Lost" doesn't make the Found count disappear). See
  `_TypeSwitch` in `item_feed_screen.dart`.
- The map toggle swaps the list for `ItemsMapView`, centering on the
  device's location and plotting open items within 5km via `nearby_items()`
  — red pins for lost, green for found. Tapping a marker shows Google
  Maps' own info window (title + Lost/Found); it doesn't navigate
  anywhere, matching how this always behaved.
- `nearby_items()` returns plain `latitude`/`longitude` doubles (via
  `st_y`/`st_x`) rather than a raw PostGIS geography value, which doesn't
  serialize predictably over PostgREST.
- Not yet built: the map doesn't share the list's filters, and there's no
  date filter beyond the map's fixed radius.

## Returned items become private (Phase 9)

Once `mark_returned()` runs (see "Claims, trust, and moderation" above),
both posts in the pair leave every shared list:

- `supabase/13_returned_items_and_ratings.sql` replaces the items
  `select` policy: a `'resolved'` post is visible only to its own owner,
  the person it was returned with (`returned_with_user_id`), or an admin.
  Everything that reads items as the signed-in user — the feed, search,
  the map's `nearby_items()`, `my_matches()`, `my_conversations()`,
  `my_contact_threads()` — inherits this for free, since RLS applies no
  matter which query reaches the table.
- `item_images` get the same treatment one level down: a photo is visible
  exactly when its post is.
- `my_matches()` additionally excludes any match where either side has
  been resolved, so a just-returned pair also disappears from the
  Matches tab (not only from Browse).
- The pair is still reachable, by its two owners only, through
  `my_returned_items()` → **Profile → Returned items**
  (`ReturnedItemsScreen`).
- A found post resolved by the *old* code (before this migration) had no
  recorded counterpart — the migration backfills one where an approved
  claim and a confirmed match identify it unambiguously, and resolves the
  matching lost post too, so old returns end up looking the same as new
  ones. A pair that can't be paired this way still appears in Returned
  items for its owner, just without the other side.

## The Alerts tab and unread badges (Phase 9)

- **`supabase/14_notifications.sql`** adds a `notifications` table
  (RLS: a user can read and mark-read only their own rows; nothing can
  INSERT into it directly — see below) and a single helper,
  `create_notification()`, that every trigger writes through. Six
  triggers/functions call it, one per event, each firing from exactly one
  place so an event can't be double-notified or missed:
  - a genuinely **new** match → `upsert_match_score()`'s insert branch
    (12_text_matching.sql, redefined here), notifying both owners —
    re-scoring an *existing* match (its enrich branch) does not notify.
  - a match's status becomes **confirmed** → new trigger
    `matches_notify_confirmed`, notifying whichever owner didn't just
    tap "This is it!" (`MatchCard.updateStatus` is a plain client
    `update`, not an RPC, so a trigger is the only hook available).
  - a **claim is filed** → new trigger `claims_notify_filed`, notifying
    the found item's owner.
  - a claim is **approved/rejected** → new trigger
    `claims_notify_decision`, notifying the claimant.
  - an item is marked **returned** → `mark_returned()` (13_returned_items_
    and_ratings.sql, redefined here), notifying both owners.
  - a **new rating** → new trigger `ratings_notify_new`, notifying the
    person rated.
  - **Chat messages are deliberately not included** — seeing every
    message as a notification row would make this the single
    highest-write table in the app for no real benefit, and would bury
    the less-frequent events above. The Chats tab's own badge (next
    point) already covers messages.
- **Reading is a plain `select`/`update`**, not an RPC — the RLS policies
  above are enough on their own (`NotificationsRepository`,
  `lib/features/notifications/data/`). A SECURITY DEFINER function is
  only needed for *writing*, which the client never does directly.
- **The Chats badge** (`unreadChatsCountProvider`,
  `lib/core/providers/unread_counts_provider.dart`) is a derived
  provider, not its own query — it sums `unreadCount` across whatever
  `conversationsProvider`/`contactThreadsProvider` already returned, so it
  can never disagree with what the Chats list itself shows.
- **Keeping both badges live while on a different tab**: `MainShell`
  became a `ConsumerStatefulWidget` with one `Timer.periodic` (15s) that
  invalidates `matchesProvider`/`conversationsProvider`/
  `contactThreadsProvider`/`notificationsProvider` together — all four
  tabs stay mounted offscreen via `IndexedStack` already (see that
  class's doc), so one shell-level timer covers all of them rather than
  each tab polling on its own. Opening a tab still invalidates its own
  provider immediately too, same as before, so switching tabs doesn't
  have to wait for the timer's next tick.
- **The bottom nav tab is labelled "Alerts"**, not "Notifications" — five
  short labels fit a `NavigationBar` more comfortably than four, and it
  avoids reading as a duplicate of the existing **Notification
  settings** screen (the push-permission toggle, unchanged, still under
  Profile). The screen's own title is "Notifications"; only the nav
  label itself is shortened. Change `main_shell.dart`'s `label: 'Alerts'`
  if you'd rather it matched exactly.
- Not done here, and worth knowing: this is **polling, not push** —
  `notifications` isn't in the `supabase_realtime` publication, unlike
  `messages`/`contact_messages` (11_realtime_and_matching_fixes.sql).
  Badges update within 15 seconds, not instantly. Adding it to that
  publication and subscribing the same way ChatScreen does for messages
  would be the natural upgrade if instant matters more than simplicity.

## Firebase setup for push notifications (Phase 7)

Push notifications need a real Firebase project:

1. In the Firebase Console, add an Android app with package name
   `com.example.findora`, download `google-services.json`, and place it
   at `android/app/google-services.json`.
2. Add the Google Services Gradle plugin — in `android/build.gradle.kts`
   (project-level, inside the `plugins { }` block if one exists, or add
   one):
   ```kotlin
   plugins {
       id("com.google.gms.google-services") version "4.4.2" apply false
   }
   ```
   and in `android/app/build.gradle.kts` (module-level, inside the
   existing `plugins { }` block at the top):
   ```kotlin
   plugins {
       id("com.google.gms.google-services")
   }
   ```

The `POST_NOTIFICATIONS` permission is already in the manifest. With the
above in place, `Firebase.initializeApp()` in `main.dart` (called with no
explicit options, which works fine for an Android-only app without a
generated `firebase_options.dart`) will succeed, and
`initializePushNotifications()` requests permission, registers this
device's FCM token to the signed-in user's `profiles` row, and shows
foreground messages as local notifications. Skip this and the app still
runs fine — it's wrapped in a try/catch specifically so a missing
Firebase project degrades to "no push notifications" rather than a crash.

## Sending real push notifications (Phase 9)

Everything above gets the app *ready* to receive a push — permission,
token storage, foreground display — but nothing sends one yet. That
needed a server-side piece with a real secret this sandbox has no way to
hold, so it's the one part of this app that can't be finished without
your own hands on your own Firebase project. The code for it is written
and waiting: `supabase/functions/send-push-notification/index.ts`.

**What it does**: whenever a row lands in `notifications`
(supabase/14_notifications.sql — a new match, a match confirmed, a claim
filed or decided, an item returned, a new rating), it looks up that
person's device token, signs a Google OAuth2 token from a Firebase
service account (plain Web Crypto, deliberately not the `firebase-admin`
npm package — that package has a history of flaky deploys on Supabase's
Deno runtime), and sends the push via the FCM HTTP v1 API. Android shows
it automatically even with the app fully closed, no extra app code
needed for that part. Tapping it opens the same place tapping the Alerts
entry would (`lib/core/notifications/push_notifications.dart` already
has the tap-handling side of this wired up).

**Chat messages aren't included** — same reasoning as the Alerts tab
itself (see `14_notifications.sql`'s header): a push per message would
be far too frequent to be welcome, and messages already have their own
unread badge. If you want pushes for new messages specifically, that's a
genuinely different, higher-volume feature to design (likely batching
or muting rules), not a small addition to this one.

### Setup

1. **Firebase service account.** Firebase Console → Project Settings →
   Service Accounts → **Generate new private key**. This downloads a
   JSON file — treat it like a password; never commit it or share it.
2. **Install the Supabase CLI** if you haven't (`npm install -g
   supabase`, or see supabase.com/docs/guides/local-development/cli).
   Log in and link it to your project:
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```
   (The project ref is in your Supabase dashboard URL.)
3. **Set the function's secrets.** The service account file is
   multi-line JSON, and `NAME="$(cat file)"` — the usual bash way to set
   a secret from a file — doesn't survive PowerShell: `cat` there is an
   alias for `Get-Content`, which returns an *array of lines*, and
   PowerShell rejoins that array with plain spaces when it lands inside
   `"..."`, not real newlines. The result looks like one string in your
   terminal but isn't one as far as `supabase.exe`'s argument parsing is
   concerned, and the command fails confusingly (often on some word
   *inside* the key, like `PRIVATE`, rather than on the command itself).

   `--env-file` sidesteps all of this — it reads the file itself rather
   than going through a shell argument at all. **In PowerShell**, from
   the project root (adjust the path to your downloaded file):
   ```powershell
   $json = Get-Content -Raw "path\to\your-service-account.json" | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
   "FIREBASE_SERVICE_ACCOUNT_JSON=$json" | Set-Content -Encoding ascii supabase\.secrets.env
   "WEBHOOK_SECRET=$([guid]::NewGuid().ToString())" | Add-Content -Encoding ascii supabase\.secrets.env
   supabase secrets set --env-file supabase\.secrets.env
   Remove-Item supabase\.secrets.env
   ```
   The `ConvertFrom-Json | ConvertTo-Json -Compress` round trip isn't
   decoration — it collapses the file to one line with its internal
   newlines correctly re-escaped as `\n`, which is what guarantees the
   whole thing survives as a single `NAME=value` line regardless of how
   `--env-file` parses multi-line values. `[guid]::NewGuid()` is just a
   convenient way to get a long random string for `WEBHOOK_SECRET`
   without having to make one up. The last line deletes the temporary
   file immediately after use — it briefly holds your real secret in
   plain text, so don't leave it sitting on disk. `-Encoding ascii` is
   there on purpose too: older Windows PowerShell writes UTF-8 files
   with a BOM by default, which some simple line parsers misread as
   part of the first key's name — the file's contents here (JSON plus a
   GUID) are plain ASCII anyway, so this sidesteps the question entirely
   rather than hoping the parser on the other end is BOM-tolerant.

   **In bash/WSL/Git Bash** instead, the original one-liner works fine:
   ```bash
   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat path/to/your-service-account.json)"
   supabase secrets set WEBHOOK_SECRET="choose-a-long-random-string-here"
   ```

   Either way: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` don't need
   setting — every Edge Function gets those two automatically. Run
   `supabase secrets list` afterward to confirm both secrets took.
4. **Deploy the function:**
   ```bash
   supabase functions deploy send-push-notification
   ```
5. **Wire up the Database Webhook** — Supabase Dashboard → Database →
   Webhooks → **Create a new hook**:
   - Table: `notifications`. Event: `Insert` only.
   - Type: **Supabase Edge Functions**. Function: `send-push-notification`.
   - Under HTTP headers, add one: `x-webhook-secret` → the exact same
     string you set as `WEBHOOK_SECRET` in step 3. This is what stops
     anyone who finds the function's URL from sending themselves
     arbitrary pushes — the function checks it before doing anything else.
6. **Test it**: sign in on a real device (not an emulator without Google
   Play services — FCM needs it) so a token gets saved, then do
   something that creates a notification (post two matching items from
   different accounts) and the push should arrive within a few seconds,
   app open or fully closed. If it doesn't, check the function's logs:
   Dashboard → Edge Functions → `send-push-notification` → Logs.

## In-app chat (Phase 7)

- `messages` is scoped by `match_id`, not `item_id` — a conversation is
  between the two people on either side of a match, not about one item
  in isolation.
- Chat is gated behind a confirmed match — tapping "This is it!" on a
  match is what makes a "Message" button (and a `ChatListScreen` entry)
  appear, via `my_conversations()`.
- Messages use real Supabase Realtime (`messagesStreamProvider`), unlike
  the refetch-on-demand pattern used for the items feed and matches list,
  since a plain message list doesn't need the joins that block
  `.stream()` elsewhere in this app.
- Marking messages read only touches the current user's own incoming
  messages, enforced by RLS, not just app logic.

## Claims, trust, and moderation (Phase 8)

**The claim → return → rating lifecycle**, all inside `ChatScreen`:

1. Claims are always filed against whichever item in the match has type
   `'found'` — you claim something someone *found*, to prove you're the
   one who *lost* it.
2. The claimant writes a verification answer; the finder can Approve or
   Reject it.
3. Approving runs a trigger (`handle_claim_approved`) that moves the item
   to `'claimed'` automatically.
4. Once claimed, the finder gets a "Mark as returned" button. This calls
   the `mark_returned()` RPC (`supabase/13_returned_items_and_ratings.sql`)
   rather than a plain `update` — it re-checks that the return is real
   (an approved claim, a confirmed match) and resolves **both** posts
   together, recording which post/person each was returned with
   (`items.returned_with_item_id`/`returned_with_user_id`). A resolved
   post is then visible only to its two owners — see "Returned items
   become private" below — and shows up for both of them in
   **Profile → Returned items**.
5. Resolving surfaces a star-rating prompt (also reachable later from
   Returned items). Ratings write to a `ratings` table, and a trigger
   (`handle_new_rating`) recomputes `profiles.rating`/`rating_count` from
   it. A rating's written comment is readable only by the two people
   involved (migration 13's RLS policy) — the profile-wide average and
   count are still public.

**Item detail screen**: tapping a feed/map card opens `ItemDetailScreen`
— full description, every photo, and a "Report this item" action.

**Basic moderation**: `profiles.is_admin` gates a "Flagged reports" entry
in `ProfileScreen`, opening `AdminReportsScreen` (dismiss / remove item),
backed by RLS so a non-admin who found the route would just see nothing.
There's no in-app flow to grant admin — run this once in the Supabase SQL
editor for your first moderator:
```sql
update public.profiles set is_admin = true where id = '<user-uuid>';
```

## Event time and manual location adjustment (posting an item)

Two additions to `PostItemScreen`, both optional:

- **When it was lost/found** — a date+time picker (`_pickEventTime`),
  stored in `items.event_time`, separate from `created_at` (when the
  *report* was posted). Shown on the item detail screen alongside
  "Reported [date]" when set.
- **Adjust pin on map** — `LocationPickerScreen`
  (`core/location/location_picker_screen.dart`) fine-tunes whatever
  "Add current location" auto-detected, using a fixed center pin over a
  draggable map (not a draggable `Marker` — see that file's doc for why)
  plus a reverse-geocoded label on confirm.

## Password strength (signup)

`core/widgets/password_strength.dart` defines five rules (8+ characters,
upper/lowercase, a number, a special character) as data
(`List<PasswordRule>`) rather than inlined validator logic, so the same
rules back both the `TextFormField` validator and a live
`PasswordStrengthIndicator` (a progress bar + a checklist that lights up
each rule as it's satisfied) shown under the field as the person types.

## Exit confirmation (Browse tab)

Android's back button on a bottom-nav tab is handled by `TabBackGuard`
(`lib/core/widgets/tab_back_guard.dart`), a `PopScope` that wraps each
tab's root screen inside its route in `core/router/app_router.dart`:

- On **Matches / Chats / Profile**: back goes to Browse.
- On **Browse** with the map open: back returns to the list.
- On **Browse**'s list (the home page): back shows the "Leave Findora?"
  dialog (`showConfirmDialog`) and only calls `SystemNavigator.pop()` if
  you confirm.

**Why it lives in each route and not in `MainShell`.** The first version
put one `PopScope` in `MainShell` and the dialog never appeared: go_router
sends a back press to the *active tab's own nested navigator*, which has
just one route and no guard of its own, so it reported "nothing to pop"
and the OS closed the app without `MainShell` being consulted. The guard
has to be inside the route of the navigator that actually receives the
press. `MainShell` keeps a fallback `PopScope` that runs the same logic.

Also in `MainShell`: the bottom nav's `onDestinationSelected` resets
`feedShowsMapProvider` to `false` whenever Browse (index 0) is selected —
so tapping Browse always lands you on the list, even if you'd left the
map view open. This has to happen from `MainShell` rather than from
`ItemFeedScreen` resetting its own state, because go_router's
`StatefulShellRoute` keeps `ItemFeedScreen` mounted (just offscreen, in an
`IndexedStack`) while another tab is showing — nothing re-initializes it
on a tab switch, so its map/list choice had to move out of local `State`
and into that provider before anything outside the screen could reach it.

## Soft delete: items are hidden, never erased

Deleting a post — by its own owner (item detail's menu, My Items) or by
an admin removing a flagged item (Flagged reports) — no longer runs an
actual `delete` against the database. `08_soft_delete.sql` adds
`items.deleted_at` (nullable; null means active) and both delete paths
now just set it:

```dart
await supabase.from('items').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', itemId);
```

That same migration also **drops** the `items` table's `delete` RLS
policies entirely (both the owner one and the admin one) — so this isn't
just an app-code convention; a real `delete` against `items` fails at the
database level even for someone calling the Supabase client directly with
a valid session, bypassing the app. Every read this repository does
(`fetchOpenItems`, `fetchMyItems`, `fetchItemById`) filters
`deleted_at is null`, so a soft-deleted item disappears from the app
exactly as if it had been hard-deleted — the difference only shows up if
you go looking for it directly in the database (which is the point: an
accidental delete, or a moderation call worth revisiting, is one
`update ... set deleted_at = null` away from being undone).

Matching follows the same idea but with one deliberate exception:
`match_items()` and `my_matches()` (Phase 5) both exclude deleted items,
so a removed item stops being surfaced as a *candidate* match going
forward and any still-*pending* match against it disappears — but
`my_conversations()` (Phase 7, confirmed-match chat) is left unfiltered
on purpose, so an existing conversation about an item stays reachable
even after that item is later deleted. Chat history is worth keeping;
dangling "confirm or dismiss?" prompts about a removed item aren't.

Admin's `removeItem()` also updates any other still-open reports against
that item to `dismissed` — with a real delete, `reports.item_id`'s
cascade used to make them disappear from the moderation queue for free;
a soft delete leaves `reports` rows untouched unless this does it
explicitly, so without it they'd sit in the open queue forever pointing
at an item that's already been taken down.

## Account deletion

Profile → "Delete account" calls the `request_account_deletion()` RPC
(`supabase/09_account_deletion.sql`), which — for the same reason item
deletion is a soft delete (see above) — doesn't run a real `delete from
auth.users`: `profiles.id references auth.users(id) on delete cascade`,
so that would cascade-delete their profile and leave every *other*
user's matches/chats/reports referencing that id pointing at nothing.

Instead it, all in one `security definer` function (redefined in
`supabase/16_release_email_on_delete.sql`):
1. Soft-deletes every item the account posted (same `items.deleted_at`
   flag as a regular per-item delete).
2. Clears `profiles.full_name`/`username`/`avatar_url`/`phone`/
   `fcm_token` (since migration 21, the person's `device_tokens` rows are deleted instead) and sets a new `profiles.deleted_at` — the row survives,
   but with nothing personal left on it. Existing chats/matches
   referencing this user now just show "Findora user" wherever a name
   would have appeared, via the `coalesce(full_name, username, 'Findora
   user')` fallback already used in `my_contact_threads()` and similar.
3. **Anonymises the `auth.users` row** (`release_account_identity()`):
   the email becomes a unique placeholder
   (`deleted-<id>@deleted.invalid`), the phone, password hash and user
   metadata are cleared, linked identities (e.g. Google) and sessions
   are deleted, and `banned_until` is set 100 years out so the husk can
   never sign in. The row itself stays, because everything else points
   at that id. This runs as the function's *owner* (the `postgres` role,
   in a normal SQL-Editor-run migration), which has full access to the
   `auth` schema — no service-role key or Edge Function needed, only
   `security definer` plus deriving the target strictly from `auth.uid()`
   (never a parameter, so there's no "delete someone else" version of
   this to accidentally expose). Writing to the `auth` schema directly
   isn't an officially supported interface, so re-test account deletion
   after a Supabase platform upgrade.

**Can the same email sign up again?** Yes — because step 3 freed it, a
sign-up with that address creates a brand-new account (new id, new
profile, no items/ratings/chats). The old history stays attached to the
old id as "Findora user". Two guards:
- **Cooldown.** For `email_reuse_cooldown()` (14 days; edit the number in
  `16_release_email_on_delete.sql` and re-run it) after deletion, the
  address can't be used to sign up, so deleting and re-registering can't
  wipe a bad rating. Only a SHA-256 fingerprint of the address is kept
  (`email_reuse_blocks`, no API access, expired rows cleaned up).
  Enforced by the `a_enforce_email_reuse_block` trigger on `auth.users`
  (covers every sign-up method); the sign-up screen first asks
  `signup_email_status()` so it can say *when* the email is available
  again instead of Supabase's generic "Database error saving new user".
  It fails open if that check can't be made.
- **Moderation blocks.** `select public.block_email('x@y.com');`
  blocks an address permanently (or `, 90` for 90 days) — for people you
  removed, as opposed to people who deleted themselves.

Known limit: the fingerprint is of the exact address, so
`name+1@gmail.com` is a different address to it — the cooldown deters
casual reputation-resetting, it isn't identity checking. Also,
`signup_email_status()` is callable signed-out and so reveals whether an
address is currently blocked (and nothing about any other address).

Accounts deleted *before* migration 16 are anonymised by a one-off
backfill at the end of that file (`release_previously_deleted_emails()`),
counting their cooldown from when they were actually deleted.

The Flutter side calls `supabase.auth.signOut()` immediately after the
RPC returns — banning blocks *future* sign-ins/token refreshes, but
doesn't retroactively invalidate a JWT that's already been issued for
the current session, so the explicit sign-out is what actually ends
*this* session right away rather than leaving it valid until it happens
to expire.

## "NEW" badge

`core/widgets/new_badge.dart` defines `isRecentlyPosted(DateTime)` (true
for `newPostWindow`, currently 3 days, after `created_at`) and a small
`NewBadge` pill widget, shown on feed cards and the item detail screen's
badge row whenever that check passes. There's no timer or scheduled job
behind this — every build just re-checks the item's age against
`newPostWindow`, so the badge stops appearing on its own the next time
that part of the UI happens to rebuild (pull-to-refresh, reopening the
item, reopening the app) after the window has elapsed. Change how long
"new" lasts by editing `newPostWindow` in that one file.

## Email confirmation flow

Three pieces, all independently optional (skip any of them and Supabase's
own default confirmation email/redirect still works, just without this
project's mobile-handoff/auto-close/welcome-email additions):

1. **Branded confirmation email** — paste
   `supabase/email_templates/confirm_signup.html` into Supabase Dashboard
   → Authentication → Email Templates → "Confirm signup" (Message body),
   and set its Subject to `Confirm your email for Findora`.
2. **`web/auth-callback.html`** — a self-contained static page (no
   Flutter build needed) that `{{ .ConfirmationURL }}` redirects the
   browser to after confirming. On mobile it hands off into the app via
   the same `io.supabase.findora://` custom scheme already used for
   Google sign-in (supabase_flutter's built-in deep-link handling picks
   up the auth data automatically — no extra Dart code needed); on
   desktop it shows success and closes the tab (best-effort — see the
   file's comment on why `window.close()` can't be guaranteed).

   **Hosting it — don't use Supabase Storage for this.** Storage is
   built for arbitrary file/CDN delivery, not guaranteed HTML rendering,
   and in practice it can serve an uploaded `.html` file with a
   content-type that makes browsers display the raw source code as text
   instead of rendering it as a page — confusing since the upload itself
   "succeeds" with no error. Use a real static host instead — free,
   and a couple of minutes each:

   **Cloudflare Pages** (no git/account-linking needed, just a file):
   1. https://pages.cloudflare.com → sign in (or create a free account)
      → **Create a project** → **Upload assets**.
   2. Drag in `web/auth-callback.html`. Rename it to `index.html` during
      upload (drag-and-drop lets you rename before confirming) so it
      serves at your project's root URL rather than a
      `/auth-callback.html` sub-path — simpler to reference later,
      though either works.
   3. Deploy — you get a URL like `https://findora-auth.pages.dev`.
   4. Use that URL as `AUTH_CALLBACK_URL` (see step 4 below).

   Netlify Drop (https://app.netlify.com/drop) and GitHub Pages work
   the same way if you'd rather use one of those.

   **Prefer to keep this inside Supabase anyway?** It's possible, but
   only via the Storage REST API with an explicit content-type — the
   Dashboard's drag-and-drop uploader doesn't expose that control, which
   is exactly what goes wrong:
   ```powershell
   # PowerShell — replace YOUR_PROJECT_REF and YOUR_SERVICE_ROLE_KEY
   # (Project Settings → API Keys → service_role). Run
   # supabase/07_email_confirmation.sql first if you haven't — it
   # creates the public `site` bucket this targets.
   $headers = @{
     Authorization = "Bearer YOUR_SERVICE_ROLE_KEY"
     "Content-Type" = "text/html"
   }
   Invoke-WebRequest `
     -Uri "https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/site/auth-callback.html?upsert=true" `
     -Method Post -Headers $headers -InFile "web\auth-callback.html"
   ```
   Whichever host you use, open the resulting URL in a browser before
   moving on — you should see a rendered "Confirming your email…" page,
   not visible HTML markup. If you see markup (like the screenshot), the
   content-type is still wrong.

   Once you have a working URL:
   1. Dashboard → **Authentication** → **URL Configuration** →
      **Redirect URLs** → add it (Supabase rejects an `emailRedirectTo`
      that isn't on this allow-list).
   2. Paste the same URL as `AUTH_CALLBACK_URL` in `.env`.
3. **Follow-up "you're confirmed!" email** — `07_email_confirmation.sql`
   adds a trigger that fires the moment `auth.users.email_confirmed_at`
   is first set, calling the `send-welcome-email` Edge Function (Resend
   API) — see `supabase/functions/send-welcome-email/README.md` for
   deployment. That SQL file has two placeholders
   (`YOUR_PROJECT_REF`, `YOUR_SERVICE_ROLE_KEY`) to fill in before
   running it.

## A few things to double-check before shipping

- **pgvector inserts**: `ItemsRepository.createItem()` inserts a Dart
  `List<double>` straight into the `embedding` column, which works
  because a JSON array's text form matches pgvector's own input format —
  verify this once you have a real device, model, and Supabase project.
- **Ratings aren't tightly restricted**: the RLS policy lets any
  signed-in user insert a rating as themselves, not strictly only for an
  item they completed a return on — a reasonable trust boundary for a
  first version, not a hard guarantee.
- **TFLite plugin**: check pub.dev/fluttergems.dev periodically for
  whichever `tflite_flutter` release is currently best-maintained.

## Project structure

```
lib/
  core/
    theme/         AppColors + AppTheme (Material 3, light & dark),
                    ThemeModeController (persisted light/dark/system)
    router/         go_router config with a StatefulShellRoute bottom nav
    constants/      table names, bucket names, RPC function names
    providers/      currentUserProvider, authStateChangesProvider
    supabase/       shared Supabase client accessor
    ml/             TfliteClassifier, its provider, category_mapper,
                    TextEmbeddingService (optional ai_service/ client)
    location/       getCurrentPositionOrNull(), LocationPickerScreen
    notifications/  FCM setup + push token registration
    widgets/        MainShell (bottom nav + FAB + exit confirmation),
                    showConfirmDialog, PasswordStrengthIndicator
  features/
    splash/         shows the pin glyph on brand teal
    auth/           login, signup (+ password strength), forgot-password
    home/           browse tab: hero header, search/filters, items_map_view.dart
    items/
      data/          CategoryModel, ItemModel, NearbyItemModel, ClaimModel,
                      ItemsRepository, ClaimsRepository, providers
      post_item_screen.dart   photo picking, location (+ manual adjust),
                               event time, AI tagging, upload
      item_detail_screen.dart  full detail, delete (owner), contact (others)
    matches/
      data/          MatchModel, MatchesRepository, providers
      matches_screen.dart   real matches, confirm/dismiss, score breakdown
    chat/
      data/          ConversationModel, MessageModel, MessagesRepository
      chat_list_screen.dart   tabbed: confirmed matches + direct messages
      chat_screen.dart        live messages + claim/return/rate lifecycle
    contact/
      data/          ContactThreadModel, ContactMessageModel, ContactRepository
      contact_chat_screen.dart  plain messaging, no claim lifecycle
    profile/
      data/          ProfileModel, AdminRepository, ReportModel, providers
      profile_screen.dart      real rating, appearance picker, admin entry
      my_items_screen.dart     swipe/tap to delete
      admin_reports_screen.dart  moderation: dismiss / remove item
supabase/
  01_extensions_and_tables.sql
  02_functions_and_triggers.sql
  03_rls_policies.sql
  04_storage_setup.sql
  05_multimodal_matching.sql   event_time, text embeddings, image+text+GPS scoring
  06_contact_messaging.sql     direct "Contact poster" threads
  07_email_confirmation.sql    welcome-email trigger + public site bucket
  email_templates/             confirm_signup.html, welcome_email.html
  functions/send-welcome-email/  Deno Edge Function (Resend API)
ai_service/            optional FastAPI microservice — see its README.md
  requirements.txt            core: text embeddings (Sentence-Transformers + NLTK)
  requirements-image.txt      optional: image embeddings (TensorFlow/Keras + OpenCV)
  Dockerfile                  full build (both tiers)
  Dockerfile.text-only        smaller build, text tier only
scripts/
  export_tflite_model.py   generates the on-device model + labels
  generate_icon_pngs.py    regenerates every launcher/PWA icon PNG
  requirements.txt
assets/
  models/           drop the exported .tflite + labels file here
  images/           app_icon.svg/.png, logo_lockup.svg, pin_glyph_white.svg
web/
  auth-callback.html   email confirmation landing page (mobile handoff /
                       desktop auto-close) — see "Email confirmation flow"
```

## Android hardening (manual steps)

`android/app/src/main/AndroidManifest.xml` is git-ignored here (it carries
the Maps API key), so it isn't overwritten by updates. Make these edits in
your copy:

1. On the `<application ...>` element add `android:allowBackup="false"`.
   The Supabase session is stored in SharedPreferences, which Android
   otherwise includes in cloud/ADB backups.
2. Delete `<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />`.
   `image_picker` uses the system photo picker, which needs no storage
   permission, and Google Play reviews this permission closely.
3. (Recommended) Stop keeping the key in the manifest. In the manifest use
   `android:value="${mapsApiKey}"`, add `MAPS_API_KEY=your-key` to
   `android/local.properties` (already ignored), and in
   `android/app/build.gradle.kts` inside `defaultConfig { ... }` add:
   ```kotlin
   val localProps = java.util.Properties().apply {
       val f = rootProject.file("local.properties")
       if (f.exists()) f.inputStream().use { load(it) }
   }
   manifestPlaceholders["mapsApiKey"] = localProps.getProperty("MAPS_API_KEY") ?: ""
   ```
   Then the manifest can be committed. Also restrict the key in Google Cloud
   Console to your package name + SHA-1 and the Maps SDK for Android.

## Adding crash reporting (not done here — needs native setup)

Firebase is already in the project, so Crashlytics is the shortest path:
add `firebase_crashlytics` to `pubspec.yaml`, add the
`com.google.firebase.crashlytics` Gradle plugin in `android/` (see the
FlutterFire docs), then in `main()` after `Firebase.initializeApp`:

```dart
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
PlatformDispatcher.instance.onError = (error, stack) {
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
};
```

Mention it in the privacy policy / Play Data Safety form (crash logs and
device identifiers are collected). It isn't wired in automatically because
it changes what the app collects, which is your call.
