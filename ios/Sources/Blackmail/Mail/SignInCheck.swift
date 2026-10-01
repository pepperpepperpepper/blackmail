import Foundation

/// What setup and Settings find out about a password before they keep it:
/// that Gmail lets it read the mail AND send it, without a letter going
/// anywhere. Apart from the forms so the host can run it against the
/// scripted servers, and so the words each outcome is given are pinned.
///
/// Both halves, because one proves nothing about the other (B-033): Gmail's
/// IMAP takes an app password under whatever address the LOGIN names and
/// opens the mailbox the password belongs to, while SMTP holds the two
/// together and refuses the pair. A password made while signed in to Google
/// as someone else passed setup when only IMAP was asked, drew that
/// account's mail, and failed every letter with a 535.
enum SignInCheck {

    enum Verdict: Equatable {
        /// Keep it. Sending was asked too, unless the submission server
        /// could not be reached, which says nothing against the password.
        case works
        /// IMAP refused the password.
        case passwordRefused
        /// IMAP refused the sign-in for another reason, with its ALERT text
        /// if it gave one (`MailError.signInRefused`).
        case signInRefused(alert: String?)
        /// IMAP took it and SMTP refused it, 535: a password of another
        /// Google account (B-033), or, it is said, Gmail turning away
        /// sign-ins to send for a while.
        case sendingRefused
        /// IMAP took it and SMTP refused the sign-in for now, 534, with
        /// Gmail's words where it gave any (`SMTPClient.SignInRefusal`):
        /// most often a sign-in on the web wanted first. Kept, as a password
        /// that works is: IMAP has just taken it, the one in place may be
        /// revoked, and nothing a helper types next would be taken for
        /// sending either until Gmail lets go. The letters say so as before
        /// (`MailError.sendingSignInRefused`).
        case sendingSignInRefused(text: String?)
        /// Gmail's IMAP could not be reached.
        case unreachable
    }

    /// What the form does with a verdict.
    enum Outcome: Equatable {
        /// Saves the password and signs in with it at once, as a password
        /// that works is (`PasswordChange`), and once the screens are built
        /// again puts up `notice`, where there is one.
        case keep(notice: MailAlert?)
        /// Keeps what was there, and says `sentence` under the button.
        case refuse(sentence: String)
    }

    /// Which form is asking. Settings keeps the old password when the new
    /// one fails, and says so.
    enum Form {
        case setup
        case settings
    }

    /// Signs in to IMAP, lists the folders and signs out; then, only if that
    /// worked, signs in to SMTP and says goodbye (`SMTPClient.checkSignIn`).
    /// IMAP first and alone when it fails, so a password Gmail has just
    /// refused is not sent a second time for SMTP to refuse too.
    ///
    /// A submission server that cannot be reached, or that says "not now",
    /// does not stop the password being kept: IMAP has just taken it, the
    /// letters will say so if sending fails, and a Wi-Fi that blocks port
    /// 465 must not leave a revoked password in place with no mail at all.
    /// Nor does SMTP's 534, a sign-in Gmail wants made some other way first,
    /// which says nothing against the password either; it is kept, and the
    /// helper told (`sendingSignInRefused`). Only a verdict against the
    /// account stops it.
    static func run(account: MailAccount, password: String,
                    transport: @escaping MailTransportFactory) async -> Verdict {
        let imap = IMAPClient(account: account, transport: transport)
        do {
            try await imap.connect(password: password)
            _ = try await imap.listMailboxes()
            await imap.disconnect()
        } catch {
            await imap.disconnect()
            switch (error as? MailError) ?? .cannotConnect {
            case .passwordNeedsUpdating: return .passwordRefused
            case .signInRefused(let alert): return .signInRefused(alert: alert)
            default: return .unreachable
            }
        }
        do {
            try await SMTPClient(account: account, transport: transport)
                .checkSignIn(password: password)
        } catch MailError.passwordNeedsUpdating {
            Diagnostics.log(.note, "SIGN-IN CHECK imap=ok smtp=refused")
            return .sendingRefused
        } catch let refusal as SMTPClient.SignInRefusal {
            Diagnostics.log(.note, "SIGN-IN CHECK imap=ok smtp=sign-in-refused")
            return .sendingSignInRefused(text: refusal.text)
        } catch {
            Diagnostics.log(.note, "SIGN-IN CHECK imap=ok smtp=not-checked")
        }
        return .works
    }

    /// Whether the form keeps the password for `verdict`, and what it says.
    static func outcome(of verdict: Verdict, address: String, in form: Form) -> Outcome {
        switch verdict {
        case .works:
            return .keep(notice: nil)
        case .sendingSignInRefused:
            return .keep(notice: MailAlert(title: "Cannot Send Mail",
                                           message: sentence(for: verdict, address: address,
                                                             in: form) ?? "",
                                           offersSettings: false))
        default:
            return .refuse(sentence: sentence(for: verdict, address: address, in: form) ?? "")
        }
    }

    /// What the form says of `verdict`, nil for one that works, where the
    /// form closes and says nothing. `address` is the account's, for the
    /// Google account a password has to be made in.
    ///
    /// A 535 to a password IMAP has just taken is most often Gmail's
    /// wrong-account trap, and the sentence sends the helper to make it
    /// again in the right account. But Gmail is said to answer 535 too
    /// while it turns away an account's sign-ins to send for a while, and
    /// then a password made in the right account would fail the same way,
    /// and so would the next; so the sentence says what to do if it was
    /// made there. B-033 first took an afternoon's 535s for that, before the
    /// wrong account was found to explain every one of them.
    ///
    /// A 534 is said once the password is kept and the screens are built
    /// again: reading works, sending does not for now, and Gmail's own
    /// words where it gave any, after Mail's "The server returned the
    /// error:" as for IMAP's refusal.
    static func sentence(for verdict: Verdict, address: String, in form: Form) -> String? {
        let kept = form == .settings ? " Your old password is still in place." : ""
        switch verdict {
        case .works:
            return nil
        case .passwordRefused:
            return form == .settings
                ? "Google refused that password. Check it is an APP password."
                : "Google refused that password. Check it is an APP password, not your normal one."
        case .signInRefused(let alert):
            return (MailError.signInRefused(alert: alert).errorDescription ?? "") + kept
        case .sendingRefused:
            return "Gmail took that password for reading mail but refused it for sending. "
                + "Make the app password while signed in to Google as \(address). "
                + "If you are sure it was made as \(address), wait an hour and try again." + kept
        case .sendingSignInRefused(let text):
            return "Gmail accepted the password for reading mail but is refusing to send for now."
                + (text.map { " The server returned the error: \($0)" } ?? "")
        case .unreachable:
            return form == .settings
                ? "Could not reach Gmail. Your old password is still in place."
                : "Could not reach Gmail. Check the network and try again."
        }
    }
}

extension MailAccount {

    /// The account setup's Connect saves for `address`, named `name`: the
    /// account stored already where it is this address's, with its name
    /// changed and nothing else, and a new one for any other address.
    ///
    /// Setup is shown again whenever the password cannot be read at launch,
    /// and a Connect that built a new account every time saved it over the
    /// stored one, taking his signature and its formatted twin with it,
    /// which nothing on the iPad can put back but Restore Original
    /// Signature. The address is compared as a Keychain key is, trimmed and
    /// without case.
    static func settingUp(_ address: String, name: String, over stored: MailAccount?) -> MailAccount {
        func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var account: MailAccount
        if let stored, key(stored.address) == key(address) {
            account = stored
        } else {
            account = MailAccount(address: address, username: address)
        }
        account.displayName = name
        return account
    }
}
