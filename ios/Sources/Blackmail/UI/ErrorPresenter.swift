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

    /// Alerts asked for while a sheet is sliding away, which UIKit would
    /// drop. Each says whether it was put up. See `AlertHold`.
    private static var hold = AlertHold<() -> Bool>()

    static func show(_ error: MailError, on vc: UIViewController) {
        let present = { [weak vc] () -> Bool in
            // Gone from the screen while the alert was held, as a list is
            // when the folder changes: there is nothing to put it over.
            guard let vc, vc.viewIfLoaded?.window != nil else { return false }
            let alert = UIAlertController(title: nil,
                                          message: error.errorDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            vc.present(alert, animated: true)
            return true
        }
        showFirst(hold.show(present, at: Date()))
    }

    /// A sheet he chose from has started to slide away, and what he chose
    /// is already on its way: any alert it brings waits for the sheet to
    /// go. Returns what to call from the dismissal's completion. A sheet
    /// that never reports back is waited for only as long as
    /// `AlertHold.bound`.
    static func sheetLeaving() -> () -> Void {
        let id = hold.sheetLeaving(at: Date())
        DispatchQueue.main.asyncAfter(deadline: .now() + AlertHold<() -> Bool>.bound + 0.05) {
            showFirst(hold.due(at: Date()))
        }
        return { showFirst(hold.sheetGone(id, at: Date())) }
    }

    /// The first of `alerts` that can still be put up, and no more: UIKit
    /// shows one at a time.
    private static func showFirst(_ alerts: [() -> Bool]) {
        for present in alerts where present() { return }
    }

    /// Never shown to the user. Never contains a password or a message body.
    static func log(_ line: String) {
        diagnostics.append("\(Date()) \(line)")
        if diagnostics.count > 500 { diagnostics.removeFirst(diagnostics.count - 500) }
    }
}

#endif
