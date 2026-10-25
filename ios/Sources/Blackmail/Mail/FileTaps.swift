import Foundation

/// Which file or picture tapped in the reading pane is opened when its
/// download ends (B-141): the one tapped last, and only while he has not
/// opened another letter of the conversation by its line since.
///
/// A file waits for its bytes before Quick Look can show it, seconds for a
/// large PDF, and the pane is his meanwhile. In a conversation on the test
/// iPad, A's PDF of 14.7 MB was tapped, then B's line, which takes the
/// header to B (B-129), then B's own file. A's PDF opened in Quick Look as
/// it landed, over B's header, and B's file, landing under Quick Look, was
/// let go without a word, its spinner cleared: UIKit presents nothing over
/// a controller already presenting. The pane asked only whether it still
/// showed what the file was tapped in (`PaneLoads.stillShows`), and another
/// letter of the same conversation is the same conversation shown.
///
/// Now each tap takes a number, the last one tapped holds the last number,
/// and a file that lands holding an earlier one is let go: not shown, and
/// no failure said for it, as a body he has tapped past is not
/// (`PaneLoads.draws`). A letter opened by its line, which moves the header
/// and the toolbar to it (`StackFocus.opened`), takes a number too, so a
/// file of the letter he left is let go as it lands, as `openAttachment`
/// has said it would be since B-122. Its download is not called off; it
/// ends, and is let go. A line closed takes none: the header stays where
/// it was, and so does what he tapped.
///
/// Out of the controller, which is UIKit and does not build on the host,
/// for the reason `StackFocus` is.
struct FileTaps: Equatable {

    /// The number the last tap took, a file's or a line's; nought before
    /// any.
    private(set) var lastFileTapped = 0

    /// A file or a picture tapped: the number it is opened by.
    mutating func tapped() -> Int {
        lastFileTapped += 1
        return lastFileTapped
    }

    /// A letter of the conversation opened by its line: every file tapped
    /// before it is let go as it lands.
    mutating func lineOpened() {
        lastFileTapped += 1
    }

    /// Whether the file tapped as `tap` is opened as it lands, or its
    /// failure said: nothing tapped since, and no letter opened by its line.
    func opens(_ tap: Int) -> Bool {
        tap == lastFileTapped
    }
}
