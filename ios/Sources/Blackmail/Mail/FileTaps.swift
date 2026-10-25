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
/// Now each tap takes a number, and a file that lands opens only if the
/// last tap was on it: one tapped before another file, or before another
/// letter's line, is let go as it lands, not shown, and no failure said
/// for it, as a body he has tapped past is not (`PaneLoads.draws`). A
/// letter opened by its line, which moves the header and the toolbar to it
/// (`StackFocus.opened`), takes a number, so a file of the letter he left
/// is let go as it lands, as `openAttachment` has said it would be since
/// B-122. Its download is not called off; it ends, and is let go.
///
/// A file tapped again while its download is still running is not fetched
/// a second time: the tap is the download's own again, which opens it as
/// it lands (`tapped`). A row among a letter's words and a picture have no
/// spinner and are never held, and he taps again when nothing seems to
/// happen; a second download behind the first, on the one connection, made
/// him wait for both. And a file tapped, then another, then the first
/// again: the first's download, still running, is the one that opens.
///
/// Neither a line closed nor the line of the letter the header is on
/// already, closed and opened again, takes a number: the header stays
/// where it was, and so does what he tapped.
///
/// Out of the controller, which is UIKit and does not build on the host,
/// for the reason `StackFocus` is.
struct FileTaps: Equatable {

    /// A file or a picture of a letter, as the pane asks for it: the letter
    /// by its id, the part by its section, and what the pane showed at the
    /// tap (`PaneLoads.shown`). The pane given something else since, the
    /// same file tapped there again is another download.
    struct File: Hashable {
        let letter: String
        let part: String
        let shown: Int
    }

    /// The number the last tap took, a file's or a line's; nought before
    /// any.
    private(set) var lastFileTapped = 0

    /// The downloads running, each with the number of the last tap on its
    /// file.
    private var running: [File: Int] = [:]

    /// `file` tapped: true when its download is to start; false when it is
    /// running already, and opens it as it lands now that this tap is the
    /// last.
    mutating func tapped(_ file: File) -> Bool {
        lastFileTapped += 1
        let starts = running[file] == nil
        running[file] = lastFileTapped
        return starts
    }

    /// The letter `id` opened by its line, the header on `headerWasOn`
    /// until then: when that is another letter, every file tapped before
    /// it is let go as it lands. The letter the header is on already,
    /// closed and opened again, lets nothing go.
    mutating func lineOpened(_ id: String, headerWasOn: String?) {
        guard id != headerWasOn else { return }
        lastFileTapped += 1
    }

    /// Whether `file`, landing, is opened, or its failure said: the last
    /// tap was on it, and no other letter has been opened by its line
    /// since.
    func opens(_ file: File) -> Bool {
        running[file] == lastFileTapped
    }

    /// `file`'s download has ended, however: a tap on it after this
    /// fetches it again.
    mutating func ended(_ file: File) {
        running[file] = nil
    }
}
