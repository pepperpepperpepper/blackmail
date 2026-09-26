# Project Brief — Classic Mail for iPad

You are building a private iPad email client for an older user. The overriding product requirement is **interface stability and familiarity**. The application should visually and behaviorally resemble Apple Mail on iPad circa iOS 10–11, not modern iPadOS Mail.

Do not reinterpret the design. Do not modernize it. Do not add "helpful" contemporary UI patterns unless explicitly required for functionality.

## Product objective
Create a reliable three-pane iPad mail client:

1. Left: mailboxes/folders.
2. Middle: message list.
3. Right: message viewer.
4. A fixed, sparse toolbar with familiar mail actions.
5. Controls never move based on context.
6. No categories, avatars, AI summaries, priority sorting, cards, contextual ellipsis menus, or adaptive button relocation.

The user should be able to use the app from memory after years of using old Apple Mail.

## Technical constraints
- Native Swift.
- UIKit is the primary UI framework.
- Use explicit view controllers and deterministic layout.
- Support iPadOS 15+ unless a later minimum is forced by dependencies.
- Use Swift Package Manager.
- Preferred mail engine: https://github.com/Cocoanetics/SwiftMail
- Secure credentials in Keychain.
- Never log passwords, OAuth tokens, app-specific passwords, or message bodies in production logging.
- Data model and UI must be separable so the mail engine can be swapped without rewriting the interface.

## Required first milestone
Before implementing live email, create a fully navigable **mock-data UI prototype** that matches the old Mail layout closely enough to evaluate visually.

The prototype must include:
- mailbox list,
- selected mailbox,
- message rows,
- unread state,
- timestamps,
- message preview,
- selected message,
- fixed top toolbar,
- compose modal,
- reply/forward menu,
- move-to-folder sheet,
- delete action.

Only after visual approval should you wire IMAP/SMTP.

## Reference target
Use the visual references listed in `references/REFERENCE_SCREENSHOTS.md`. Treat the iOS 10 three-pane iPad Mail screenshot as the primary composition reference, and iOS 11-era Mail as the secondary detail reference.

## Build sequence
Follow `docs/IMPLEMENTATION_PLAN.md` exactly unless blocked by a technical fact. If blocked, document the blocker and present the smallest alternative.

## Quality bar
- No crashes on empty folders, malformed MIME, offline mode, or missing attachments.
- Opening the app from a cold start should show cached inbox content immediately.
- UI positions must remain stable across launches.
- Target user should not need to learn gestures beyond tap and ordinary scrolling.
- Important buttons must have at least 44x44 pt hit targets even when the visible glyph is smaller.

## Deliverables
1. Xcode project.
2. Build instructions.
3. Configurable mail account setup hidden behind an administrator/settings screen.
4. Mock-data mode.
5. Functional IMAP mailbox sync.
6. Functional SMTP send.
7. Local cache.
8. Ad Hoc archive/export instructions.
9. Unit tests for mail repository logic and message parsing.
10. UI tests for the primary senior-user flows.

Read every file in this package before beginning implementation.
