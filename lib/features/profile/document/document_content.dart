// GENERATED CONTENT — the text of the in-app User manual, Safety guidelines,
// Privacy policy and Help & support pages, plus matching Markdown copies in
// docs/. This file is the authoritative in-app text; edit it directly.
// (The docs/*.md files are snapshots for publishing — e.g. a public Privacy
// policy URL for an app-store listing — and need updating by hand to match.)

import 'package:flutter/material.dart';

import 'document_blocks.dart';

/// Shown at the top of the privacy policy.
const String kPolicyUpdated = "28 September 2026";

const List<DocSection> kUserManual = [
  DocSection(
    title: "Welcome to Findora",
    icon: Icons.waving_hand_outlined,
    blocks: [
      DocParagraph("Findora helps people get lost things back. Someone who **lost** something reports it as **Lost**; someone who **found** something reports it as **Found**. Findora compares the two kinds of posts, suggests likely matches, and gives both people a private way to check that an item really belongs to the person asking for it and to arrange the handoff."),
      DocHeading("The whole journey in six steps"),
      DocSteps([
        "**Report** what you lost or found (only a title is required; photos help).",
        "Findora **looks for matches** between lost and found posts from different people.",
        "You **confirm a match** and a private chat opens.",
        "The owner **files a claim** with a detail only the real owner would know; the finder **approves** it.",
        "You **meet safely** and hand the item over.",
        "The finder taps **Mark as returned**. Both posts are retired, and you can **rate each other**.",
      ]),
      DocCallout(DocCalloutKind.tip, "You don't have to have lost or found anything to be useful. Browse the feed: the thing you spotted may be exactly what someone nearby is looking for."),
    ],
  ),
  DocSection(
    title: "Getting started",
    icon: Icons.rocket_launch_outlined,
    blocks: [
      DocHeading("Creating your account"),
      DocSteps([
        "Open the app and choose **Sign up**. Enter your name, email and a password (or continue with Google if it's offered).",
        "Check your email for the confirmation link and open it on your phone.",
        "Sign in. That's it.",
      ]),
      DocParagraph("Forgot your password? On the sign-in screen tap **Forgot password?**, enter your email, and we'll send a reset link."),
      DocHeading("Permissions the app may ask for"),
      DocBullets([
        "**Location** (optional): fills in where you lost or found something, shows posts near you on the map, and helps rank matches by distance.",
        "**Camera and photos** (optional): to photograph or choose pictures for your posts and your profile photo.",
        "**Notifications** (optional): so your phone can alert you to new messages and matches.",
      ]),
      DocParagraph("You can change any of these in your phone's Settings. Findora still works without them, just with less help."),
    ],
  ),
  DocSection(
    title: "Browsing posts",
    icon: Icons.search,
    blocks: [
      DocParagraph("The **Browse** tab shows posts that are still open, newest first, with a running count of lost and found posts."),
      DocBullets([
        "**Search** looks for your words in post titles and descriptions.",
        "The **All / Lost / Found** switch narrows the feed to one kind of post. The numbers show how many of each there are.",
        "**Category chips** (Electronics, Wallets, Keys and so on) narrow it further.",
        "The **list / map** toggle switches between cards and a map with a pin for each post that has a location.",
      ]),
      DocHeading("Opening a post"),
      DocParagraph("Tap a post to see its photos, description, where and when it happened, and who posted it. From there you can:"),
      DocBullets([
        "**View possible matches** for that post.",
        "**Contact** the poster to send a private message.",
        "Tap **This might be mine** or **I think I found this** to report your own matching post, so Findora can compare them.",
        "Tap the **flag** icon to report a post that looks like spam, a scam or otherwise doesn't belong.",
      ]),
      DocCallout(DocCalloutKind.info, "Posts that have been returned or deleted no longer appear in Browse. If you can't find something you saw earlier, that's usually why."),
    ],
  ),
  DocSection(
    title: "Reporting a lost or found item",
    icon: Icons.add_a_photo_outlined,
    blocks: [
      DocSteps([
        "Tap **Report item**.",
        "Choose **Lost** or **Found**.",
        "Add a **title**. This is the only required field.",
        "Add **photos** (optional but recommended). Tap a photo to change it, or the ✕ to remove it.",
        "Add a **description**, choose a **category** (Findora suggests one from your first photo), set the **location** (use your current location or pick a point on the map) and, if you know it, **when** it happened.",
        "Tap **Post**.",
      ]),
      DocHeading("What happens next"),
      DocBullets([
        "Photos are analysed **on your phone**. If one can't be analysed you're told, and you can retry from the scan icon on the Matches tab.",
        "Your title and description are compared with other people's posts too, so a post **without any photo can still be matched by its words**.",
        "New matches appear in the **Matches** tab.",
      ]),
      DocCallout(DocCalloutKind.tip, "Finders: don't post every identifying detail (a serial number, what's inside a bag, a lock-screen picture). Keep at least one back. It's what lets you verify the real owner later."),
      DocCallout(DocCalloutKind.tip, "Choose a location that's close to where it happened but not your front door. Other people can see the pin you choose."),
    ],
  ),
  DocSection(
    title: "Editing and deleting your posts",
    icon: Icons.edit_outlined,
    blocks: [
      DocParagraph("Go to **Profile → My reported items**."),
      DocBullets([
        "**Edit**: open a post, tap the **⋮** menu, then **Edit post**. You can change the title, description, category, location, time and photos (add, remove or replace). Nothing changes until you press **Save**.",
        "**Delete**: swipe a card to the left, or tap the bin icon, and confirm. The post disappears for everyone straight away.",
      ]),
      DocCallout(DocCalloutKind.info, "A post can't be switched between Lost and Found. If you picked the wrong one, delete it and post it again."),
    ],
  ),
  DocSection(
    title: "How matching works",
    icon: Icons.auto_awesome,
    blocks: [
      DocParagraph("Findora compares each of your open posts with **other people's open posts of the opposite kind** (your lost item against everyone's found items, and the other way round). It never matches two of your own posts and never requires the category to be the same."),
      DocHeading("Four signals, combined into one percentage"),
      DocBullets([
        "**📷 Photo**: an AI model on your phone turns each photo into a set of numbers describing what it looks like; photos with similar numbers score highly.",
        "**📝 Words**: your title and description are compared. When Findora's text service is available it understands meaning (\"wallet\" and \"purse\"); otherwise it compares the words themselves.",
        "**📍 Distance**: closer posts score higher.",
        "**🕐 Time**: things lost and found around the same time score higher.",
      ]),
      DocParagraph("Only the signals that exist are used. A post with no photo is scored on words, distance and time."),
      DocCallout(DocCalloutKind.warning, "A match is a **suggestion**, not proof. 100% means the signals agree, not that the item is yours. Always verify through the claim process before handing anything over."),
    ],
  ),
  DocSection(
    title: "The Matches tab",
    icon: Icons.auto_awesome_outlined,
    blocks: [
      DocParagraph("Each card shows **your post** on the left and the **possible match** on the right, with the overall percentage and the signals behind it. Tap either side to open that post."),
      DocBullets([
        "**This is it!** confirms the match and opens a private chat with the other person.",
        "**Not a match** dismisses it. It moves to 'Already decided'.",
        "**Filters**: All, Image only, Text only, Both, Nearby and Similar time.",
        "The **scan icon** (top right) analyses any of your photos that haven't been analysed yet. This also happens automatically when you open the app.",
      ]),
      DocCallout(DocCalloutKind.info, "Photo matching needs **both** posts' photos to have been analysed, and a photo can only be analysed on its owner's phone. If a match you expect is missing, the other person may simply not have opened the app yet."),
    ],
  ),
  DocSection(
    title: "The return process, step by step",
    icon: Icons.handshake_outlined,
    blocks: [
      DocSteps([
        "**Confirm the match.** Either person taps **This is it!** on the match card. A private chat opens.",
        "**Chat.** Say hello and ask questions. Don't share sensitive personal information.",
        "**File a claim.** The person who **lost** the item taps **File a claim** at the top of the chat and writes a private detail that only the true owner would know: a scratch, the wallpaper, what's inside.",
        "**Review the claim.** The **finder** reads it and taps **Approve** or **Reject**. If it's rejected, the owner can file a new claim.",
        "**Arrange the handoff.** Agree a public place and time. Read the Safety guidelines first.",
        "**Mark as returned.** After the item has actually been handed over, the **finder** taps **Mark as returned**. Both posts are marked returned together.",
        "**Rate each other.** Both people can leave 1 to 5 stars and an optional comment.",
      ]),
      DocCallout(DocCalloutKind.info, "Post status follows the process: **Open** → **Claimed** (a claim was approved) → **Returned**."),
      DocCallout(DocCalloutKind.warning, "Only the finder can mark an item as returned. If you're the owner, tell the finder as soon as you have your item back."),
      DocHeading("What \"returned\" does"),
      DocBullets([
        "Both posts disappear from Browse, search, the map and everyone else's matches, so they can't confuse other people's matching.",
        "Only the two of you can still see them, in **Profile → Returned items**.",
        "Your chat stays open so you can leave a rating.",
      ]),
    ],
  ),
  DocSection(
    title: "Messaging someone directly",
    icon: Icons.chat_bubble_outline,
    blocks: [
      DocParagraph("The **Contact** button on any post opens a private chat with whoever posted it. No match is needed. Use it for quick questions."),
      DocBullets([
        "Direct chats are plain conversations: there is no claim or rating step in them.",
        "For the full claim-and-return process the two posts must be a **confirmed match**. If you think a post is yours, tap **This might be mine** / **I think I found this** and report your own post so Findora can compare them.",
        "All your conversations are in the **Chats** tab, which shows a number badge in the bottom navigation whenever you have unread messages.",
      ]),
    ],
  ),
  DocSection(
    title: "Returned items",
    icon: Icons.task_alt,
    blocks: [
      DocParagraph("**Profile → Returned items** lists every return you were part of."),
      DocBullets([
        "Each entry shows **your post** and the **post it was returned with**, the date, and the ratings.",
        "Tap either post to open it, or **Open chat** to look back at the conversation or leave a rating.",
        "**Only you and the other person can see these posts.** Nobody else can find them.",
      ]),
    ],
  ),
  DocSection(
    title: "Ratings and reviews",
    icon: Icons.star_outline_rounded,
    blocks: [
      DocParagraph("After a return, each person can rate the other from 1 to 5 stars with an optional comment."),
      DocBullets([
        "**Profile → Ratings & reviews** shows your average, the number of ratings, a star breakdown, and every review you've **received**. The **Given** tab shows the ones you left.",
        "Your **average and count** appear under your name on your profile. The **written comment** on a rating can be read only by the two people involved.",
        "Ratings come only from real returns, one per person per item.",
      ]),
      DocCallout(DocCalloutKind.tip, "Be fair and specific. A short note such as \"turned up on time and was very kind\" helps the next person decide whether to trust you."),
    ],
  ),
  DocSection(
    title: "The Alerts tab",
    icon: Icons.notifications_outlined,
    blocks: [
      DocParagraph("The **Alerts** tab is a running list of everything that's happened on your posts: new matches, a match being confirmed, a claim filed or decided, an item marked as returned, and new ratings. It shows a number badge whenever something is unread."),
      DocBullets([
        "Tap an alert to jump straight to it — a new match opens that post's matches, a claim or return opens the right chat, and a rating opens Ratings & reviews.",
        "Unread alerts have a dot and a tinted background. Tap one, or use **Mark all read** at the top, to clear it.",
      ]),
      DocCallout(DocCalloutKind.info, "Ordinary chat messages aren't listed here — the **Chats** tab's own badge is where those show up, so this list stays focused on the less frequent, bigger moments."),
    ],
  ),
  DocSection(
    title: "Push notification settings",
    icon: Icons.notifications_active_outlined,
    blocks: [
      DocParagraph("**Profile → Notification settings** shows whether this phone is allowed to send you push alerts and lets you switch them on or off. If your phone blocks notifications, the screen tells you where to enable them."),
      DocParagraph("Whatever you choose, your matches, messages and alerts are always waiting in the app — in the **Matches**, **Chats** and **Alerts** tabs."),
    ],
  ),
  DocSection(
    title: "Your profile and account",
    icon: Icons.person_outline,
    blocks: [
      DocBullets([
        "**Edit profile**: your name, an optional phone number, and your photo.",
        "**Appearance**: Light, Dark, or match your phone.",
        "**Sign out** ends your session on this phone.",
        "**Delete account** signs you out for good and removes your name, photo and phone number. Your posts are hidden and you can't sign in again. Conversations other people had with you remain for them, and your name in them appears as \"Findora user\". This can't be undone.",
      ]),
    ],
  ),
  DocSection(
    title: "Privacy and safety at a glance",
    icon: Icons.shield_outlined,
    blocks: [
      DocBullets([
        "Meet in public, tell someone, and don't hand anything over until you're convinced by the claim.",
        "Your email is never shown to other users. Your phone number is only in your own profile.",
        "The **location you pick** for a post is shown to other people as a map pin.",
        "Returned posts and written reviews are private to the two people involved.",
      ]),
      DocParagraph("Read the full **Privacy policy** and **Safety guidelines** from the Profile tab."),
    ],
  ),
  DocSection(
    title: "Troubleshooting",
    icon: Icons.build_circle_outlined,
    blocks: [
      DocHeading("I'm not getting any matches"),
      DocBullets([
        "Matches only pair a **lost** post with a **found** one from a **different person**. Check the other kind exists.",
        "Add a clear photo, and put the object's name and colour in the title or description.",
        "Open the Matches tab and tap the **scan icon** to analyse any photos that were missed.",
        "For photo matches, the other person's photos must have been analysed too, which happens when they open the app.",
      ]),
      DocHeading("\"The AI could not analyze this photo\""),
      DocParagraph("Your post was saved. Open Matches and tap the scan icon to retry. If it keeps failing, check your internet connection and restart the app."),
      DocHeading("The map is blank or grey"),
      DocParagraph("The map needs an internet connection and a working map service. If it stays blank, contact support so it can be checked."),
      DocHeading("I can't find a post I saw earlier"),
      DocParagraph("It has probably been returned or deleted by its owner. Both are hidden from Browse."),
      DocHeading("Messages aren't appearing"),
      DocParagraph("Check your connection. The chat refreshes every few seconds, and reopening the chat forces a refresh."),
      DocHeading("I still need help"),
      DocParagraph("Use **Profile → Help & support → Contact support**."),
    ],
  ),
  DocSection(
    title: "Glossary",
    icon: Icons.menu_book_outlined,
    blocks: [
      DocBullets([
        "**Post**: a Lost or Found report.",
        "**Match**: a suggested pairing of one lost post and one found post from different people.",
        "**Claim**: the owner's private description proving the item is theirs, reviewed by the finder.",
        "**Returned**: the item has been handed back. Both posts are retired and kept private to their two owners.",
      ]),
    ],
  ),
];

const List<DocSection> kSafetyGuidelines = [
  DocSection(
    title: "Before you meet",
    icon: Icons.handshake_outlined,
    blocks: [
      DocBullets([
        "**Verify first.** Don't arrange a handoff until you've used the claim process and the claim genuinely convinces you.",
        "**Keep something back.** Finders, don't publish every identifying detail. Ask the claimant to describe something only the owner would know.",
        "**Stay in the app.** Use Findora's chat while you're getting to know the other person. Be cautious about moving to other apps or sharing your number early.",
        "**Read the profile.** Check the other person's ratings and reviews. No ratings isn't a red flag by itself, but it means less to go on.",
      ]),
    ],
  ),
  DocSection(
    title: "Meeting up",
    icon: Icons.place_outlined,
    blocks: [
      DocBullets([
        "Meet in a **busy public place**: a café, shopping-centre entrance, a bank or a police-station lobby. Never a private home or an isolated spot.",
        "Choose **daylight hours** where you can, and somewhere with cameras and other people around.",
        "**Tell someone** you trust where you're going, who you're meeting and when you expect to be back.",
        "**Bring a friend** if you can, especially for valuable items.",
        "Arrange your own transport so you can leave whenever you want.",
        "If anything feels wrong, **leave**. Nothing is worth your safety. You can always reschedule.",
      ]),
    ],
  ),
  DocSection(
    title: "Handing over valuable items",
    icon: Icons.diamond_outlined,
    blocks: [
      DocBullets([
        "For phones and laptops, ask the owner to **unlock or sign in** to prove it's theirs, and never ask for their passcode.",
        "For wallets and bags, let the owner describe the contents **before** you open them.",
        "For IDs and bank cards, consider handing them to a police station or the issuing bank instead of meeting anyone.",
        "**Never accept or ask for money** for returning an item. A small thank-you offered freely is the owner's choice, but Findora is not a marketplace.",
      ]),
    ],
  ),
  DocSection(
    title: "Protecting your privacy",
    icon: Icons.lock_outline,
    blocks: [
      DocBullets([
        "Don't share your home address, workplace, ID numbers, financial details or passwords in chat.",
        "When you pick a location for a post, choose the **area** where it happened, not your doorstep. The pin is visible to other users.",
        "Photos can show more than you intend (documents, addresses, faces). Check the background before posting.",
        "Messages are protected in transit but are **not end-to-end encrypted**. Don't send anything you wouldn't want stored.",
      ]),
    ],
  ),
  DocSection(
    title: "Spotting scams",
    icon: Icons.warning_amber_rounded,
    blocks: [
      DocParagraph("Be wary if someone:"),
      DocBullets([
        "asks for **money, gift cards, or a \"delivery fee\"** before returning an item, or offers a reward you must pay tax on;",
        "**can't describe** anything specific about the item, or their details keep changing;",
        "pressures you to **hurry** or to leave the app;",
        "asks for a **verification code**, a password, or a link to be opened;",
        "claims an item you posted before you've said what it is.",
      ]),
      DocCallout(DocCalloutKind.warning, "Findora will never ask you for your password or a verification code in a chat message."),
    ],
  ),
  DocSection(
    title: "Reporting a problem",
    icon: Icons.flag_outlined,
    blocks: [
      DocSteps([
        "Open the post and tap the **flag** icon in the top right.",
        "Choose a reason: spam or scam, inappropriate content, and so on. Then submit.",
        "A moderator reviews the report.",
      ]),
      DocParagraph("For **threats, harassment or anything that puts someone in danger**, contact your local emergency services first. You can also email support@findora.app and describe what happened."),
    ],
  ),
  DocSection(
    title: "If something goes wrong",
    icon: Icons.support_agent_outlined,
    blocks: [
      DocBullets([
        "Stop replying to anyone who is threatening or pressuring you.",
        "Keep screenshots of the conversation.",
        "Report the post, and email support@findora.app with the details.",
        "If you handed over something in error or were deceived, contact the police and give them the chat details.",
      ]),
    ],
  ),
];

const List<DocSection> kPrivacyPolicy = [
  DocSection(
    title: "Summary",
    icon: Icons.info_outline,
    blocks: [
      DocParagraph("Findora exists to reunite people with their belongings. To do that, it needs some information about you and about the items you post. This policy explains what we collect, why, who can see it, and the choices you have."),
      DocBullets([
        "We **don't sell** your personal information and we **don't show ads**.",
        "The photos you post are analysed **on your phone**. Only a set of numbers describing the photo is uploaded, together with the photo itself.",
        "Other signed-in users can see your **open posts**, including the map pin you choose. They cannot see your email address.",
        "Once an item is **returned**, both posts are hidden from everyone except the two people involved.",
        "You can **edit** your data in the app and **delete your account** at any time.",
      ]),
      DocParagraph("Last updated: 28 September 2026"),
    ],
  ),
  DocSection(
    title: "Information we collect",
    icon: Icons.folder_open_outlined,
    blocks: [
      DocHeading("Account information"),
      DocParagraph("Your name, email address and password (or the name and email from Google if you sign in with Google). Passwords are handled by our authentication provider and stored in hashed form. Optionally, a phone number and profile photo."),
      DocHeading("Posts"),
      DocParagraph("For each lost or found post: title, description, category, type (lost or found), photos, the location you choose (coordinates and a text label), when it happened, and its status."),
      DocHeading("Photo analysis data"),
      DocParagraph("When you add a photo, an AI model running **on your phone** produces (a) a list of about 1,280 numbers (an \"embedding\") describing how the photo looks, (b) a best-guess label such as \"cellular telephone\", and (c) a confidence score. These are uploaded and stored with the photo and used only to find matches."),
      DocHeading("Text analysis data"),
      DocParagraph("Where the optional text-matching service is enabled, your post's title and description are sent to it to produce a numeric representation used to compare meaning. If it isn't enabled or is unavailable, words are compared directly in our database instead."),
      DocHeading("Location"),
      DocParagraph("If you allow it, your phone's location is used when you tap \"use my location\" and to show posts near you. We calculate distances between posts to score matches. We don't track your location in the background."),
      DocHeading("Messages, claims and ratings"),
      DocParagraph("The messages you send, claim descriptions, and ratings and reviews you give or receive."),
      DocHeading("Reports and moderation"),
      DocParagraph("If you report a post, we store the report, its reason and who made it."),
      DocHeading("Device and notification data"),
      DocParagraph("If you enable push notifications, a device token is stored on your profile so alerts can reach your phone."),
      DocParagraph("We don't use advertising or analytics trackers in the app."),
    ],
  ),
  DocSection(
    title: "How we use it",
    icon: Icons.settings_suggest_outlined,
    blocks: [
      DocBullets([
        "To run the app: sign you in, show posts, and deliver messages.",
        "To **find matches** between lost and found posts using photo, text, distance and time.",
        "To let people **verify claims and arrange returns**, and to show ratings.",
        "To **keep the community safe**: review reports and act on spam, scams and abuse.",
        "To maintain and improve the service and fix problems.",
      ]),
      DocParagraph("We do not use your data to build advertising profiles, and we do not sell it."),
    ],
  ),
  DocSection(
    title: "Who can see what",
    icon: Icons.visibility_outlined,
    blocks: [
      DocBullets([
        "**Open posts** (title, description, photos, category, location pin, time, your display name and profile photo): visible to other signed-in users.",
        "**Your email address**: not shown to other users.",
        "**Your phone number**: visible in your own profile only.",
        "**Messages and claim text**: visible to the participants of that conversation.",
        "**Ratings**: your average and the number of ratings appear on your profile. The written comment and who gave it can be read only by the two people involved.",
        "**Returned posts**: visible only to the two owners, in Profile → Returned items. Moderators can see posts when they need to review a report.",
        "**Reports you file**: visible to moderators.",
      ]),
      DocCallout(DocCalloutKind.warning, "Photos are stored in a storage area that can be opened by anyone who has the exact link. The links are long, random and not listed anywhere, but if you share one, or someone you sent a photo to shares it, it can be opened. Don't post photos you wouldn't want seen."),
      DocCallout(DocCalloutKind.warning, "Messages are encrypted in transit but are not end-to-end encrypted. Don't send sensitive information."),
    ],
  ),
  DocSection(
    title: "Who we share it with",
    icon: Icons.share_outlined,
    blocks: [
      DocParagraph("We use service providers to run Findora. They process data on our behalf and only for that purpose:"),
      DocBullets([
        "**Supabase**: database, sign-in, file storage and live updates.",
        "**Google**: map display, Google sign-in if you choose it, and Firebase Cloud Messaging for push notifications (which receives your device token). Your phone's built-in address lookup may also be provided by Google.",
        "**Our text-analysis host**: receives post text when text matching is enabled.",
      ]),
      DocParagraph("We may disclose information if the law requires it, to protect people's safety, or to enforce our rules. If Findora is ever transferred to another organisation, your information may transfer with it and this policy would continue to apply."),
    ],
  ),
  DocSection(
    title: "Keeping and deleting your data",
    icon: Icons.delete_outline,
    blocks: [
      DocBullets([
        "**Delete a post**: it is hidden from everyone immediately. For safety and recovery it is kept in our systems, out of sight, rather than erased. Email support@findora.app if you need a post fully removed.",
        "**Delete your account** (Profile → Delete account): your name, photo, phone number and notification token are removed from your profile, your posts are hidden, and you can't sign in again.",
        "**What remains**: conversations you had with other people remain visible to them (showing your name as \"Findora user\"), and ratings you gave or received are kept so other people's ratings stay accurate.",
        "**Returned posts** are kept so the two people involved keep their history.",
      ]),
      DocParagraph("To ask for a copy of your data, or for anything that isn't covered by the in-app options, email support@findora.app."),
    ],
  ),
  DocSection(
    title: "Your choices and rights",
    icon: Icons.tune_outlined,
    blocks: [
      DocBullets([
        "Edit your name, phone and photo in **Profile → Edit profile**.",
        "Edit or delete any of your posts.",
        "Turn location, camera and notifications on or off in your phone's Settings, and in **Notification settings**.",
        "Delete your account in the app.",
        "Depending on where you live, you may have rights to access, correct, delete, restrict or port your data, and to object to certain uses. Email support@findora.app and we'll help.",
      ]),
    ],
  ),
  DocSection(
    title: "Security",
    icon: Icons.lock_outline,
    blocks: [
      DocParagraph("Data is encrypted in transit. Access to data is restricted by database rules so that people can only read what this policy says they can. No system is perfectly secure, so please use a strong, unique password and keep your phone locked."),
    ],
  ),
  DocSection(
    title: "Children",
    icon: Icons.child_care_outlined,
    blocks: [
      DocParagraph("Findora is not intended for children under 13, and we don't knowingly collect their information. If you are below the age at which you can consent to data processing in your country, you need a parent or guardian's permission to use the app. If you believe a child has given us information, contact us and we'll delete it."),
    ],
  ),
  DocSection(
    title: "Changes and contact",
    icon: Icons.mail_outline,
    blocks: [
      DocParagraph("We may update this policy as the app changes. The date at the top shows when it last changed, and we'll tell you in the app about significant changes."),
      DocParagraph("Questions or requests: **support@findora.app**."),
    ],
  ),
];

/// Help & support FAQs: (topic, [(question, answer)]).
const List<(String, List<(String, String)>)> kHelpFaqs = [
  ("Getting started", [
    ("What is Findora?", "A lost-and-found app. Report something you lost or found, and Findora suggests matches and helps you check ownership and arrange a safe handoff."),
    ("Do I have to add a photo?", "No, only a title is required. But photos let the AI compare pictures, and a post without one is matched by its words, distance and time only."),
    ("I didn't get my confirmation email.", "Check your spam folder and that you typed your email correctly. If it still hasn't arrived, sign up again with the right address or contact support."),
    ("I forgot my password.", "On the sign-in screen tap Forgot password?, enter your email, and open the link we send you."),
  ]),
  ("Matches", [
    ("How does matching work?", "Your post is compared with other people's open posts of the opposite kind using photos, words, distance and time, and combined into one percentage. Photos are analysed on your phone. See the User manual for details."),
    ("Why do I have no matches?", "Matches only pair a lost post with a found one from someone else. Add a clear photo, describe the object in the title, and tap the scan icon on the Matches tab. For photo matching, the other person's photos must be analysed too, which happens when they open the app."),
    ("What do Image only / Text only / Both mean?", "They filter matches by which signals found them: photo similarity, word similarity, or both."),
    ("A match looks wrong. What now?", "Tap Not a match. It moves to Already decided and won't ask again."),
  ]),
  ("Alerts", [
    ("What shows up in the Alerts tab?", "New matches, a match being confirmed, a claim filed or decided, an item marked as returned, and new ratings — tap one to jump straight to it."),
    ("Why aren't my chat messages in Alerts?", "Messages have their own badge on the Chats tab instead, so Alerts stays focused on less frequent events."),
    ("How do I clear the Alerts badge?", "Open an alert, or tap Mark all read at the top of the Alerts tab."),
  ]),
  ("Claims and returns", [
    ("What is a claim?", "The owner's private description of something only they would know about the item. The finder reads it and approves or rejects it."),
    ("My claim was rejected.", "You can file a new claim with a more specific detail."),
    ("Who marks an item as returned?", "The finder, after the handoff. Both posts then move to Profile → Returned items and disappear for everyone else."),
    ("Where did my returned posts go?", "Profile → Returned items. Only you and the other person can see them."),
  ]),
  ("Ratings", [
    ("Where can I see my ratings?", "Profile → Ratings & reviews shows your average, breakdown and reviews you've received or given."),
    ("Who can read my reviews?", "Your average and the number of ratings appear on your profile. The written comment is visible only to the two people involved."),
  ]),
  ("Your posts and account", [
    ("How do I edit or delete a post?", "Profile → My reported items. Open a post, use the ⋮ menu to edit it, or swipe the card left to delete it. You can edit photos too."),
    ("Can I change a post from Lost to Found?", "No. Delete it and post it again."),
    ("How do I delete my account?", "Profile → Delete account. It signs you out for good and removes your name, photo and phone number. This can't be undone."),
    ("How do I turn notifications on or off?", "Profile → Notification settings, and your phone's own Settings."),
  ]),
  ("Safety", [
    ("Is it safe to meet?", "Follow the Safety guidelines: meet in a public place, tell someone, don't hand anything over until a claim convinces you, and never pay or accept money for a return."),
    ("How do I report a post?", "Open it and tap the flag icon at the top right."),
  ]),
  ("Problems", [
    ("The AI could not analyse my photo.", "The post is saved. Open Matches and tap the scan icon to retry. Check your internet connection if it keeps failing."),
    ("The map is blank.", "It needs an internet connection and a working map service. If it stays blank, contact support."),
    ("I can't find a post I saw earlier.", "It was probably returned or deleted by its owner."),
  ]),
];
