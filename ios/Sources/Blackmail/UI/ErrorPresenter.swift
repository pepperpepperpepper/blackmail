// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The only thing allowed to put an error in front of him.
///
/// Four literal sentences, fixed by `PRODUCT_SPEC.md`. Raw protocol text goes
/// to the admin diagnostics log instead: "BAD Command Argument Error. 11"
/// teaches a 90-year-old only that he has broken something, which he has not.
enum ErrorPresenter {

    private(set) static var diagnostics: [String] = []

    static func show(_ error: MailError, on vc: UIViewController) {
        let alert = UIAlertController(title: nil,
                                      message: error.errorDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        vc.present(alert, animated: true)
    }

    /// Never shown to the user. Never contains a password or a message body.
    static func log(_ line: String) {
        diagnostics.append("\(Date()) \(line)")
        if diagnostics.count > 500 { diagnostics.removeFirst(diagnostics.count - 500) }
    }
}

#endif
