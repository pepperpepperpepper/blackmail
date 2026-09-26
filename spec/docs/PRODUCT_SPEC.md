# Product Specification

## User
One older iPad user who has years of muscle memory for older Apple Mail and becomes confused when Apple changes control placement or interaction models.

## Product principle
**Frozen interface beats feature growth.**

The product succeeds if the user can perform ordinary email tasks without relearning the application after operating-system updates.

## Primary flows

### Read mail
1. App opens into Inbox.
2. Message list is immediately visible from cache.
3. Tap a message.
4. Message appears in right pane.
5. Read/unread state updates.

### Switch mailbox
1. Tap Inbox, Sent, Drafts, Trash, Archive, or custom folder in left pane.
2. Middle pane changes to that folder.
3. Previously selected message clears or selects the first appropriate message.

### Reply
1. Open message.
2. Tap reply icon in fixed toolbar.
3. Small action sheet offers Reply / Reply All / Forward.
4. Composer appears.

### Delete
1. Open or select message.
2. Tap trash icon.
3. Message disappears immediately from current list using optimistic UI.
4. Backend move/delete happens asynchronously.
5. On failure, restore message and show a plain-language error.

### Move
1. Tap folder/move icon.
2. Display simple mailbox list.
3. Tap destination.
4. Move message.

### Compose
1. Tap compose icon.
2. Show classic modal composer.
3. Fields: To, Cc/Bcc toggle, Subject, Body.
4. Send button in fixed location.
5. Cancel button in fixed location.

## Required features — v1
- One mail account.
- IMAP mailbox/folder listing.
- Inbox sync.
- Read/unread state.
- Flag/unflag if straightforward.
- Compose.
- Reply.
- Reply all.
- Forward.
- Delete.
- Move.
- Sent.
- Drafts.
- Trash.
- Attachments: view/download/share.
- Search current mailbox.
- Pull-to-refresh may exist, but a visible Refresh button is preferable for discoverability.
- Cached reading offline.

## Explicitly excluded — v1
- Multiple accounts.
- Unified inbox.
- AI summaries.
- Thread intelligence beyond basic server/thread presentation.
- Categories.
- Snooze/remind-me.
- Scheduled send.
- Undo-send countdown.
- Contact avatars.
- Dynamic toolbar rearrangement.
- Swipe-only actions.
- Gesture-dependent critical functionality.

## Error handling
Use short, literal messages:
- "Can't connect to mail server."
- "Message was not sent."
- "Attachment could not be downloaded."
- "Password needs to be updated in Settings."

Never show raw IMAP protocol errors to the user. Put diagnostics in an administrator log screen.

## Senior-user safeguards
- Minimum 44 pt tap targets.
- No destructive swipe actions by default.
- Confirmation before permanently deleting from Trash.
- No automatic mailbox/category changes.
- Preserve scroll position where practical.
- Never move toolbar controls between portrait/landscape; if layout must collapse, preserve order and labels.
