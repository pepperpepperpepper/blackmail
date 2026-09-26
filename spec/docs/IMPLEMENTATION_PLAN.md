# Implementation Plan

## Phase 0 — Identify exact visual era
Before polishing, show the owner screenshots from iOS 10 and iOS 11 and select the primary target.
Default target if no further input: iOS 10 three-pane iPad Mail composition, iOS 11 detailing.

## Phase 1 — UI prototype with mock data
Build the complete app shell without networking.

Deliver:
- three-pane landscape interface,
- mailbox list,
- message list,
- message viewer,
- fixed toolbar,
- compose controller,
- reply/reply-all/forward flow,
- move flow,
- delete flow,
- search field,
- portrait fallback.

Do not proceed until this is visually approved.

## Phase 2 — Domain + repository abstraction
Create domain structs and `MailRepository` protocol.
Keep UI unaware of IMAP details.

## Phase 3 — Local persistence
Persist mailbox and message summaries first.
Then cache message bodies.
App must render cached Inbox before any network request completes.

## Phase 4 — IMAP integration
Using SwiftMail:
1. Connect over TLS.
2. Authenticate.
3. LIST folders.
4. Identify special-use folders.
5. SELECT Inbox.
6. Fetch recent headers/summaries.
7. Fetch full message on selection.
8. STORE read/unread.
9. MOVE/delete.
10. APPEND draft if supported/appropriate.

## Phase 5 — SMTP
Implement sending with:
- To,
- Cc,
- Bcc,
- Subject,
- text body,
- HTML if needed,
- attachments.

After successful send, reconcile with Sent folder rather than assuming local state is authoritative.

## Phase 6 — Attachments
- Decode common MIME attachments.
- Show filename and size.
- Tap to preview with Quick Look where possible.
- Share sheet is allowed.

## Phase 7 — Search
Start with local cached search.
Add IMAP server search if necessary.
UI must remain simple.

## Phase 8 — Reliability hardening
Test:
- no network,
- slow network,
- wrong password,
- expired token,
- HTML-only email,
- malformed MIME,
- very large mailbox,
- 20MB attachment,
- folder with zero messages,
- deleted message selected during sync,
- server MOVE unsupported,
- app killed during sync.

## Phase 9 — Device deployment
- Create App ID.
- Register target iPad.
- Archive in Xcode.
- Export Ad Hoc IPA.
- Install on registered iPad.
- Enable Developer Mode if required.
- Document annual signing/profile maintenance.

## Phase 10 — Freeze
After user acceptance:
- disable unnecessary animation changes,
- lock layout constants,
- document screenshots of every screen,
- require explicit approval for future UI modifications.
