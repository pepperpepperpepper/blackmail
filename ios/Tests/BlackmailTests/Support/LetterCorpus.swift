import Foundation
@testable import Blackmail

/// Letters of every shape the builder makes, for holding the planned
/// letter to `ReferenceBuilder` (B-070): plain alone (A), with its HTML
/// twin (B), the twin with a picture (C), and with files (D); bodies with
/// every awkward line; Bcc and threading on and off; awkward file names;
/// and files of every size about a line's, a block's and a piece's edge.
///
/// A fixed date and Message-ID, and boundaries from a counting token, so a
/// letter can be made twice the same.
struct LetterCase {
    var label: String
    var draft: Draft
    var account = LetterCorpus.account
    var html: String?
    var inline: [(contentID: String, filename: String, mimeType: String, data: Data)] = []
    var includeBcc = false
    var thread: (messageID: String, references: String?)?
    var files: [(filename: String, mimeType: String, data: Data)] = []

    /// One part, plain text: no twin and no files.
    var isPlainShape: Bool { html == nil && files.isEmpty }

    func reference(_ token: Counting) -> Data {
        ReferenceBuilder.build(draft: draft, from: account, date: LetterCorpus.date,
                               messageID: LetterCorpus.messageID, inReplyToHeaders: thread,
                               attachments: files, includeBcc: includeBcc, htmlBody: html,
                               inlineImages: inline, boundaryToken: token.next)
    }

    func built(_ token: Counting) -> Data {
        RFC5322Builder.build(draft: draft, from: account, date: LetterCorpus.date,
                             messageID: LetterCorpus.messageID, inReplyToHeaders: thread,
                             attachments: files, includeBcc: includeBcc, htmlBody: html,
                             inlineImages: inline, boundaryToken: token.next)
    }

    func plan(_ token: Counting) -> LetterPlan {
        RFC5322Builder.plan(draft: draft, from: account, date: LetterCorpus.date,
                            messageID: LetterCorpus.messageID, inReplyToHeaders: thread,
                            files: files.map { ($0.filename, $0.mimeType) },
                            includeBcc: includeBcc, htmlBody: html, inlineImages: inline,
                            boundaryToken: token.next)
    }
}

/// A boundary token that counts its draws: 32 hex digits of the count.
final class Counting {
    private(set) var draws = 0
    func next() -> String {
        draws += 1
        let digits = String(draws, radix: 16, uppercase: true)
        return String(repeating: "0", count: 32 - digits.count) + digits
    }
}

enum LetterCorpus {

    static let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                     displayName: "Sam Example")
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let messageID = "<b070-corpus@example.com>"

    /// `count` bytes that are not all alike, from `seed`.
    static func bytes(_ count: Int, seed: Int = 1) -> Data {
        var state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 | 1
        var out = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            out[index] = UInt8(truncatingIfNeeded: state)
        }
        return Data(out)
    }

    static let bodies = [
        "", "a", ".", ".\n.", "one\rtwo\r", "a\r\n.\r\nb", "trailing blanks   \n  \t",
        "Caf\u{E9} \u{FC} \u{2014} \u{1F600} \u{202F}", String(repeating: "word ", count: 60),
        "ends with a break\n", "ends without one",
    ]

    static let logo = (contentID: "sig-logo", filename: "logo.png", mimeType: "image/png",
                       data: bytes(300, seed: 7))
    static let markup = "<div dir=\"ltr\">Dear Carlo,<br><br>See you.</div><img src=\"cid:sig-logo\">"

    /// The sizes a file's base64 is made at: about a line (57), a block
    /// (58,368) and a piece (65,536), two blocks and one, and a megabyte.
    static let sizes = [0, 1, 2, 3, 56, 57, 58, 58_367, 58_368, 58_369, 116_737,
                        65_535, 65_536, 65_537, 1_000_003]

    static func draft(_ body: String) -> Draft {
        var draft = Draft()
        draft.to = ["Carlo <carlo@example.org>"]
        draft.cc = ["owner@example.net"]
        draft.bcc = ["hidden@example.org"]
        draft.subject = "Sunday \u{E0} one"
        draft.body = body
        return draft
    }

    /// Every case: each body in each shape, with Bcc and threading on and
    /// off; then each size, then each awkward name.
    static var cases: [LetterCase] {
        var out: [LetterCase] = []
        let shapes: [(String, String?, Bool, Int)] = [
            ("A", nil, false, 0), ("B", markup, false, 0), ("C", markup, true, 0),
            ("D plain", nil, false, 1), ("D html", markup, false, 1), ("D all", markup, true, 2),
        ]
        for (index, body) in bodies.enumerated() {
            for (shape, html, inline, files) in shapes {
                for bcc in [false, true] {
                    for threaded in [false, true] {
                        var c = LetterCase(label: "\(shape) body \(index) bcc \(bcc) thread \(threaded)",
                                           draft: draft(body))
                        c.html = html
                        c.inline = inline ? [logo] : []
                        c.includeBcc = bcc
                        c.thread = threaded ? ("<parent@example.org>", "<root@example.org>") : nil
                        c.files = (0..<files).map {
                            ("f\($0).bin", "application/octet-stream", bytes(100 + $0, seed: $0))
                        }
                        out.append(c)
                    }
                }
            }
        }
        for size in sizes {
            var c = LetterCase(label: "size \(size)", draft: draft("Attached."))
            c.html = markup
            c.files = [("IMG_0001.MOV", "video/quicktime", bytes(size, seed: size))]
            out.append(c)
        }
        var many = LetterCase(label: "every size at once", draft: draft("All of them."))
        many.files = sizes.map { ("file \($0).bin", "application/octet-stream", bytes($0, seed: $0)) }
        out.append(many)
        // A name holding the boundary the counting token draws next makes
        // the boundary grow, and draw again.
        let next = "=_Blackmail_" + String(repeating: "0", count: 31) + "1_="
        let names: [(String, String)] = [
            ("Caf\u{E9} \u{FC}.pdf", "application/pdf"), ("re\"port\\.pdf", "application/pdf"),
            ("", "application/pdf"), (next, "text/plain"), ("Notes.txt", ""),
        ]
        for (index, name) in names.enumerated() {
            var c = LetterCase(label: "name \(index)", draft: draft("Named."))
            c.files = [(name.0, name.1, bytes(500, seed: index))]
            out.append(c)
            var twin = c
            twin.label += " with html"
            twin.html = markup
            twin.inline = [logo]
            out.append(twin)
        }
        var named = LetterCase(label: "every name at once", draft: draft(".\nNamed."))
        named.html = markup
        named.files = names.enumerated().map { ($1.0, $1.1, bytes(57 * $0, seed: $0)) }
        out.append(named)
        return out
    }
}
