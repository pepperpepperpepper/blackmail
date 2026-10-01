import Foundation

/// What the alert says when getting his mail, or acting on it, failed: a
/// folder or a letter that would not load, a Refresh, a jump to a day, a
/// Flag, Move or Delete the server did not take. Apart from
/// `ErrorPresenter`, which puts it up, so the words are pinned on the host.
///
/// Every one of these used to say "Can't connect to mail server." whatever
/// had been caught, and only the small line under the list told a refused
/// password apart, so the first half hour on the telephone went on the
/// Wi-Fi. Now the error caught is what is said.
struct MailAlert: Equatable {
    /// Nil for an alert that is its message alone, as they all were.
    let title: String?
    let message: String
    /// A Settings button beside OK, which opens Settings at the password.
    let offersSettings: Bool

    /// Mail's own alert for a refused password, as its users quote it,
    /// word for word, for a Gmail account: "Cannot Get Mail", "The user name
    /// or password for “Gmail” is incorrect.", here with a Settings button
    /// before OK, which is where the password is mended; whether Mail's has
    /// one was not found in anything quoted. The same title over a sign-in
    /// refused for another reason, with Google's own sentence where it gave
    /// one (`MailError.signInRefused`); no Settings button there, since no
    /// password typed into it would help. Anything else as it always was.
    static func reaching(_ error: MailError) -> MailAlert {
        switch error {
        case .passwordNeedsUpdating:
            return MailAlert(title: "Cannot Get Mail",
                             message: "The user name or password for “Gmail” is incorrect.",
                             offersSettings: true)
        case .signInRefused:
            return MailAlert(title: "Cannot Get Mail", message: error.errorDescription ?? "",
                             offersSettings: false)
        default:
            return MailAlert(title: nil, message: error.errorDescription ?? "",
                             offersSettings: false)
        }
    }

    /// For whatever was caught: a `MailError` as it is, anything else as
    /// the connection's failure, as it always was.
    static func reaching(_ error: Error) -> MailAlert {
        reaching((error as? MailError) ?? .cannotConnect)
    }
}
