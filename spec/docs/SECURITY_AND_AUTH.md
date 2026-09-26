# Security and Authentication

## Rule 1
Never place credentials directly in source code, plist files committed to source control, `.env` files shipped in the application bundle, analytics, or logs.

## Store secrets
Use Keychain for:
- IMAP password / app-specific password,
- SMTP password,
- OAuth refresh/access tokens.

## Provider modes
Implement auth behind a provider-neutral interface.

### Simple IMAP/SMTP
Best case for a private one-user deployment.
Required:
- IMAP host/port/TLS.
- SMTP host/port/TLS.
- username.
- password/app-specific password.

### Gmail
SwiftMail documentation indicates app-specific passwords can be used for its IMAP/SMTP demos. For a private single-user build, this may be simpler than a public OAuth consent flow if the account permits it.

### Microsoft 365 / Outlook
Expect OAuth/XOAUTH2. SwiftMail supports XOAUTH2 at the protocol layer, but the app is responsible for obtaining/refreshing tokens.

### iCloud
Use provider-supported IMAP/SMTP authentication; likely an app-specific password for this private client. Validate against current Apple account rules during implementation.

## Administrator setup screen
Hide behind one of:
- Settings button requiring a PIN, or
- a non-obvious but documented gesture only the administrator uses.

The senior user should never encounter raw server settings during ordinary operation.
