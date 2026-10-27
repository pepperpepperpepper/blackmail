// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// Puts `DiscardQuestion` in front of him before a Trash or an Archive
/// under Ask Before Deleting (B-168): the reading pane's Delete, the Edit
/// bar's Trash, a drag's button tapped and More's.
///
/// An action sheet, as Mail's is, from the button tapped or over the row:
/// on the iPad a popover, whose Cancel UIKit leaves out, to be answered by
/// a tap anywhere else, as the Flag button's sheet and Reply's are. Unlike
/// `EraseConfirmation`'s alert, which asks before what cannot be taken
/// back: a letter trashed or archived can be, by Undo or from the Trash.
enum DiscardConfirmation {

    /// Asks `question` over `vc`, from `item`, and calls `go` only if he
    /// taps its red button. Cancel does nothing at all.
    static func ask(_ question: DiscardQuestion, on vc: UIViewController,
                    from item: UIBarButtonItem?, go: @escaping () -> Void) {
        let sheet = self.sheet(question, go: go)
        sheet.popoverPresentationController?.barButtonItem = item
        vc.present(sheet, animated: true)
    }

    /// The same, over `place`, a row's part in its table.
    static func ask(_ question: DiscardQuestion, on vc: UIViewController,
                    over place: (view: UIView, rect: CGRect), go: @escaping () -> Void) {
        let sheet = self.sheet(question, go: go)
        sheet.popoverPresentationController?.sourceView = place.view
        sheet.popoverPresentationController?.sourceRect = place.rect
        vc.present(sheet, animated: true)
    }

    private static func sheet(_ question: DiscardQuestion,
                              go: @escaping () -> Void) -> UIAlertController {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: question.button, style: .destructive) { _ in go() })
        sheet.addAction(UIAlertAction(title: DiscardQuestion.cancel, style: .cancel))
        return sheet
    }
}

#endif
