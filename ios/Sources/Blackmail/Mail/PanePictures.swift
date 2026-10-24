import Foundation

/// A picture in a letter, tapped (B-122): what the pane opens for it, out
/// of `MessageDetailViewController` for the reason `PaneNavigation` is, so
/// the suite can test it.
///
/// Mail opens a picture the letter carries, one its HTML shows by `cid:`,
/// full screen in Quick Look when he taps it, with the share button that
/// gives Save Image and Save to Files. It does not for a picture from the
/// web. So the pane opens a picture of the letter's own parts the way a
/// tap on a file's row in the header opens the file (`openAttachment`),
/// and nothing else: a picture from the web stays as it was.
///
/// What says a picture was tapped is the stack's script, in the app's
/// content world (`ConversationDocument.script`), which wires each `<img>`
/// whose `src` is the address the loader answers (`InlineImageRewriter`)
/// and posts a tap on it to `handler`, registered in that world alone. A
/// letter's own markup has no handler to post to, and its script never
/// runs. What the script posts is only where to look: the picture opened is
/// the part, by its `Content-ID`, of the letter whose section the picture
/// is in, the one the pane shows on its own or one of the conversation's;
/// a letter can name none but its own.
///
/// Not a picture inside a link, an image map or a button: the link goes
/// where a tapped link goes (`PaneNavigation`), and nothing more. Mail, by
/// developers' reports of 2023 and 2025, opens the picture as well as the
/// link's page, which they take for a fault. And not a small one: a
/// spacer, an icon, a logo in a signature (`Tap.opens`).
enum PanePictures {

    /// The name the stack's script posts a tap under, in the app's content
    /// world.
    static let handler = "bmPicture"

    /// The least a picture is, each way, for a tap to open it: in points as
    /// the letter draws it, and in pixels in itself. Mail has no such
    /// bound that is known; it opens every picture the letter carries.
    /// Here a spacer or a tracking pixel drawn large, an icon, and a logo
    /// drawn small whatever its own size, such as his own signature's,
    /// 210 by 156 drawn at 35 by 25, are left as they were. A photo is
    /// hundreds of pixels each way and drawn as wide as the pane allows.
    static let least: Double = 100

    /// A tap on a picture, as the script posts it.
    struct Tap: Equatable {
        /// The `Content-ID` the picture's address names, as the loader
        /// reads it.
        let contentID: String
        /// The section of the stack the picture is in, its letter's; "" on
        /// a letter's own page.
        let section: String
        /// The picture's own size, in pixels: 0 by 0 until it has come.
        let width: Double
        let height: Double
        /// Its size as the letter draws it, in points.
        let drawnWidth: Double
        let drawnHeight: Double

        init(contentID: String, section: String, width: Double, height: Double,
             drawnWidth: Double, drawnHeight: Double) {
            self.contentID = contentID
            self.section = section
            self.width = width
            self.height = height
            self.drawnWidth = drawnWidth
            self.drawnHeight = drawnHeight
        }

        /// What the script posted, nil for anything else: a `src` that is
        /// not the loader's address, or a field missing or of another kind.
        init?(_ body: Any) {
            guard let fields = body as? [String: Any],
                  let src = fields["src"] as? String,
                  let url = URL(string: src),
                  url.scheme?.lowercased() == InlineImageRewriter.scheme,
                  let contentID = InlineImageRewriter.contentID(of: url),
                  let section = fields["section"] as? String,
                  let width = Self.number(fields["width"]),
                  let height = Self.number(fields["height"]),
                  let drawnWidth = Self.number(fields["drawnWidth"]),
                  let drawnHeight = Self.number(fields["drawnHeight"])
            else { return nil }
            self.init(contentID: contentID, section: section, width: width, height: height,
                      drawnWidth: drawnWidth, drawnHeight: drawnHeight)
        }

        /// A number as WebKit hands one over, an `NSNumber`, or as Swift
        /// holds one.
        private static func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            return nil
        }

        /// Whether the picture is large enough to open (`least`): drawn at
        /// least that each way, and at least that in itself, which a
        /// picture that has not come, or never will, is not.
        var opens: Bool {
            [width, height, drawnWidth, drawnHeight].allSatisfy { $0.isFinite && $0 >= PanePictures.least }
        }
    }

    /// The letter whose section the tap was in and its part the picture
    /// is, for the pane to open as a file's row opens a file; nil for a
    /// picture too small (`Tap.opens`), one the letter has no part for, or
    /// a section of no letter the pane holds.
    ///
    /// `inStack` is whether the pane shows a conversation's stack. On a
    /// letter's own page the letter is `alone`, whatever section the tap
    /// names, since that page has only the one. In a stack, the letter of
    /// the section: one of the conversation's that has come (`stack`, by
    /// their ids), or one of his own from Sent Mail that has (`his`, by the
    /// section, B-104); one whose body has not come has no picture.
    static func opening(_ tap: Tap, inStack: Bool, alone: Message?, stack: [String: Message],
                        his: (String) -> Message?) -> (letter: Message, part: Attachment)? {
        guard tap.opens else { return nil }
        let letter: Message?
        if inStack {
            letter = stack.first(where: { ConversationDocument.sectionID(for: $0.key) == tap.section })?.value
                ?? his(tap.section)
        } else {
            letter = alone
        }
        guard let m = letter, let part = part(tap.contentID, of: m) else { return nil }
        return (m, part)
    }

    /// The part of `m` with the `Content-ID` `contentID`: the last of them
    /// where it has two, the one the loader drew (`PanePage.pictures`).
    static func part(_ contentID: String, of m: Message) -> Attachment? {
        m.attachments.last(where: { $0.contentID == contentID })
    }
}
