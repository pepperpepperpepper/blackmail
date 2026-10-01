import Foundation

/// A new password saved in Settings, signed in with at once rather than at
/// the next launch.
///
/// The repository used to keep the password it was made with for the whole
/// launch, and Settings only asked for a Refresh, which ran on it. Google
/// revokes every app password when the Google password changes, the
/// likeliest failure over the years this app is meant to run; a helper then
/// made a new one, Settings checked it and closed, and the list went on
/// saying "Password Needs Updating", the Outbox stayed where it was, and
/// every tap sent the revoked password again, until iOS happened to end the
/// app, which on an iPad left alone can be days. The helper's conclusion was
/// that the new password was wrong too.
///
/// Now the screens are built again over a new repository, as setup does
/// once it has an account (`AppDelegate.makeRoot`): nothing of the old
/// password's mailbox, which after the app-password trap (B-033) can be
/// another account's, is left on screen or in memory, and the copy kept on
/// the iPad starts afresh, as `CredentialStore.save` has just thrown it
/// away. The letters kept by `LocalDrafts`, the Outbox's among them, stay
/// exactly where they are.
@MainActor
enum PasswordChange {

    /// Retires `old`, so nothing still holding it sends the old password
    /// again or reaches the mailbox it opened (`MailRepository.retire`);
    /// brings the letters kept on the iPad up to date with the save, as a
    /// launch would (`LocalDrafts.passwordSaved`); and returns the new
    /// repository `signIn` makes, for the screens to be built over. The
    /// password has been checked and saved by then (`SignInCheck`,
    /// `CredentialStore.save`).
    static func handOver(from old: MailRepository?, drafts: LocalDrafts,
                         signIn: () -> MailRepository) async -> MailRepository {
        await old?.retire()
        drafts.passwordSaved()
        return signIn()
    }
}
