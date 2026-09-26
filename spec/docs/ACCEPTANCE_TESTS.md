# Acceptance Tests

## UI
- [ ] Landscape launch shows mailbox, message list, and message detail simultaneously on supported iPad width.
- [ ] No avatars appear in message list.
- [ ] No categories appear.
- [ ] No AI summaries appear.
- [ ] No essential command is hidden under an ellipsis menu.
- [ ] Toolbar actions stay in the same positions across messages and folders.
- [ ] All toolbar hit targets are >= 44x44 pt.
- [ ] Inbox row density visually resembles old Apple Mail, not modern card UI.
- [ ] Navigation uses compact titles, not modern large-title bars.

## Reading
- [ ] Cached Inbox appears within 500 ms of first rendered app UI on a normal device.
- [ ] Selecting a row opens the correct message.
- [ ] Unread styling clears when message is opened.
- [ ] HTML message fits pane width without horizontal scrolling in ordinary cases.

## Mail actions
- [ ] Reply pre-populates recipient and subject correctly.
- [ ] Reply All preserves intended recipients without duplicating the user.
- [ ] Forward includes subject prefix and message content.
- [ ] Delete removes message from current mailbox and reconciles with server.
- [ ] Move updates both UI and server state.
- [ ] Compose sends a plain text message successfully.
- [ ] Draft can be saved and later reopened.

## Failure behavior
- [ ] Offline launch still shows cached messages.
- [ ] Network failure does not erase cache.
- [ ] Auth failure shows a human-readable message and routes administrator to settings.
- [ ] Failed optimistic delete/move restores the message state.
- [ ] No credentials or message bodies appear in production logs.

## Senior usability test
Give the user these tasks without instruction:
1. Open Inbox.
2. Read the newest email.
3. Reply to it.
4. Delete another email.
5. Find Sent.
6. Write a new email.

Pass criterion: user completes all six using only visible controls and prior Mail muscle memory.
