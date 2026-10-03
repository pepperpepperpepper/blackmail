// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// Puts `EraseQuestion` in front of him before a Delete inside Trash
/// (B-062): the reading pane's and Edit mode's.
///
/// An alert rather than an action sheet. On the iPad an action sheet is a
/// popover, and UIKit leaves a popover's Cancel out, to be answered by a
/// tap somewhere else on the screen; a question that cannot be taken back
/// keeps its Cancel on the screen, where he can read it. Cancel on the
/// left and Delete in red on the right, as UIKit lays out a cancel and a
/// destructive action.
enum EraseConfirmation {

    /// Asks `question` over `vc`, and calls `delete` only if he taps
    /// Delete. Cancel does nothing at all.
    static func ask(_ question: EraseQuestion, on vc: UIViewController,
                    delete: @escaping () -> Void) {
        let alert = UIAlertController(title: question.title, message: question.message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: EraseQuestion.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: EraseQuestion.delete, style: .destructive) { _ in
            delete()
        })
        vc.present(alert, animated: true)
    }
}

#endif
