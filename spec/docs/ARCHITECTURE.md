# Architecture

## Layers

### UI
UIKit view controllers only for core navigation.
Suggested controllers:
- `RootSplitViewController`
- `MailboxListViewController`
- `MessageListViewController`
- `MessageViewController`
- `ComposeViewController`
- `MoveMessageViewController`
- `AdminSettingsViewController`

### Domain
Provider-neutral types:
- `Mailbox`
- `MessageSummary`
- `Message`
- `Attachment`
- `Draft`
- `AccountConfiguration`

### Repository
Define a protocol independent of SwiftMail:

```swift
protocol MailRepository {
    func listMailboxes() async throws -> [Mailbox]
    func listMessages(in mailboxID: String, page: Int) async throws -> [MessageSummary]
    func loadMessage(id: String, mailboxID: String) async throws -> Message
    func markRead(_ id: String, mailboxID: String, read: Bool) async throws
    func move(_ id: String, from: String, to: String) async throws
    func delete(_ id: String, from: String) async throws
    func send(_ draft: Draft) async throws
    func saveDraft(_ draft: Draft) async throws
}
```

Implementations:
- `MockMailRepository`
- `SwiftMailRepository`

### Persistence
Use SQLite/Core Data/GRDB; choose one and document why.
Store:
- mailbox metadata,
- message summaries,
- message body cache,
- attachment metadata,
- sync cursors/state.

Do not store credentials in the database.

### Credentials
Keychain only.

### HTML rendering
Use `WKWebView` with:
- remote content blocked by default if feasible,
- safe viewport CSS,
- no arbitrary navigation out of the app without confirmation,
- content sized to pane width.

## Sync model
1. Show cache immediately.
2. Start foreground sync.
3. Reconcile message list by stable IMAP UID.
4. Update UI incrementally.
5. Persist result.

Use IMAP IDLE while app is active if stable with the provider. Do not promise continuous background IMAP connectivity because iPadOS may suspend the app.

## SwiftMail dependency
Current SwiftMail manifest declares iOS 15 as its platform floor. Treat the package manifest, not stale README text, as authoritative.

Repository: https://github.com/Cocoanetics/SwiftMail

Useful capabilities include IMAP LIST/SELECT/FETCH/STORE/MOVE/APPEND, TLS, IDLE, and SMTP including XOAUTH2 support.
