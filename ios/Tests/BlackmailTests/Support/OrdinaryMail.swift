import Foundation
@testable import Blackmail

/// Ordinary mail, made the same way on every run from a seed: the shapes
/// senders write, at the sizes letters come in. What the linear passes over
/// a stranger's letter are held to, byte for byte, against what they gave
/// before (`BoundedLetterTests`), and what the fuzz starts from
/// (`HostileLetterFuzzTests`).
///
/// Nothing here is hostile. Markup is well formed but for what real mail
/// leaves open (a paragraph, a cell, a list item); a letter's MIME is what
/// Gmail hands over from Mail, Outlook, Gmail and a newsletter's sender.
enum OrdinaryMail {

    /// SplitMix64: the same numbers from the same seed on every host.
    struct Numbers {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
        mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
        mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }
    }

    // MARK: - Words

    private static let words = [
        "the", "garden", "show", "is", "on", "Saturday", "at", "ten", "and", "we", "hope",
        "you", "can", "come", "tickets", "café", "crème", "naïve", "Zürich", "déjà", "vu",
        "roses", "photos", "attached", "from", "Jane", "Sam", "Carlo", "Grüße", "日本",
        "письмо", "🌹", "👍", "—", "“quoted”", "it’s", "5%", "£5", "€10", "10:30", "(maybe)",
        "https://example.com/show?day=sat&n=2", "www.example.org/roses", "a.b@example.com",
    ]

    private static let entities = ["&amp;", "&nbsp;", "&#8217;", "&lt;", "&gt;", "&quot;",
                                   "&mdash;", "&eacute;", "&#x2019;", "&copy;"]

    static func sentence(_ n: inout Numbers, words count: Int) -> String {
        (0..<count).map { _ in n.pick(words) }.joined(separator: " ")
    }

    // MARK: - HTML bodies

    /// Content-IDs the documents show pictures by, and a letter's parts
    /// carry.
    static let pictures = ["ii_garden01", "image001.png@01D9F0A2.1B2C3D40", "logo@example.com",
                           "photo 2", "sig-logo"]

    /// HTML bodies: the shapes other suites pin, a newsletter at two sizes,
    /// and `generated` more from the seed.
    static func documents(generated: Int = 40, seed: UInt64 = 0x6C65_7474_6572_7331) -> [String] {
        var out = [
            """
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
            <html xmlns="http://www.w3.org/1999/xhtml" lang="en">
            <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
            <title>Garden club news</title>
            <style type="text/css">body { margin: 0; padding: 0 } .wrap { width: 600px }</style>
            </head>
            <body style="margin:0; padding:0;" bgcolor="#ffffff">
            <table class="wrap"><tr><td><p>The spring show is on the 12th.</p></td></tr></table>
            </body>
            </html>
            """,
            "<HTML xmlns:o=\"urn:schemas-microsoft-com:office:office\"><HEAD>\r\n"
                + "<META http-equiv=Content-Type content=\"text/html; charset=windows-1252\">\r\n"
                + "<STYLE>P.MsoNormal { MARGIN: 0cm }</STYLE></HEAD>\r\n"
                + "<BODY lang=EN-GB link=blue vLink=purple>\r\n"
                + "<DIV class=WordSection1><P class=MsoNormal>Dear Sam,<o:p></o:p></P></DIV>"
                + "</BODY></HTML>",
            "<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\">"
                + "</head><body style=\"overflow-wrap: break-word; -webkit-nbsp-mode: space;\">"
                + "<div dir=\"ltr\">See you on Sunday.<br><br><div>Carlo</div></div></body></html>",
            "<div dir=\"ltr\">Thanks for the photos.<div><br></div><div>Sam</div></div>",
            "<html>\n<head\n  lang=\"en\"\t>\n<title>x</title></head>\n<body>\n<p>one</p>\n</body></html>",
            "<html><head></head><body></body></html>",
            "<head/><p>After a self-closing head.</p>",
            "",
            "<html><head><title>1</title></head><body><p>Look at this.</p><blockquote>"
                + "<html><head><title>2</title><style>p{}</style></head><body><p>Quoted.</p>"
                + "</body></html></blockquote></body></html>",
            "<html><head><title>News</title></head><body><header class=\"masthead\">"
                + "<h1>Garden club</h1></header><p>The show.</p><header><h2>Tickets</h2>"
                + "</header><p>Five pounds.</p></body></html>",
            "<p>Logo: <img src=\"cid:logo@example.com\"> and <img src='CID:gone'></p>",
            "<html><head><title>Receipt</title><body><p>Thanks for your order.</p></body></html>",
            PanePageTests.newsletter(kilobytes: 16),
            PanePageTests.newsletter(kilobytes: 96),
        ]
        var n = Numbers(seed: seed)
        for _ in 0..<generated { out.append(document(&n)) }
        return out
    }

    /// One HTML body from `n`.
    static func document(_ n: inout Numbers) -> String {
        var out = ""
        let wrapper = n.below(6)
        switch wrapper {
        case 0:
            out += "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
                + "<title>\(sentence(&n, words: 3))</title>\n<style type=\"text/css\">"
                + "body { margin: 0 } .x { color: #333333 } td { padding: 8px }</style></head>\n"
                + "<body style=\"margin:0; padding:0;\" bgcolor=\"#ffffff\">\n"
        case 1:
            out += "<html><head><meta http-equiv=\"content-type\" content=\"text/html; "
                + "charset=utf-8\"></head><body style=\"overflow-wrap: break-word; "
                + "-webkit-nbsp-mode: space; line-break: after-white-space;\">"
        case 2:
            out += "<HTML xmlns:o=\"urn:schemas-microsoft-com:office:office\"><HEAD>\r\n"
                + "<META http-equiv=Content-Type content=\"text/html; charset=utf-8\">\r\n"
                + "<!--[if gte mso 9]><xml><o:OfficeDocumentSettings></o:OfficeDocumentSettings>"
                + "</xml><![endif]-->\r\n<STYLE>P.MsoNormal { MARGIN: 0cm }</STYLE></HEAD>\r\n"
                + "<BODY lang=EN-GB link=blue vLink=purple>\r\n<DIV class=WordSection1>"
        case 3:
            out += "<div dir=\"ltr\">"
        case 4:
            out += "<html><body>"
        default:
            break
        }
        let count = 1 + n.below(n.chance(15) ? 60 : 8)
        for _ in 0..<count { out += block(&n, depth: 0) }
        switch wrapper {
        case 0, 4: out += "\n</body></html>"
        case 1: out += "</body></html>"
        case 2: out += "</DIV></BODY></HTML>"
        case 3: out += "</div>"
        default: break
        }
        return out
    }

    private static func block(_ n: inout Numbers, depth: Int) -> String {
        let nested = depth < 5
        switch n.below(nested ? 14 : 6) {
        case 0, 1:
            return "<p>" + inline(&n) + (n.chance(80) ? "</p>" : "") + "\n"
        case 2:
            return "<br>"
        case 3:
            let id = n.chance(70) ? n.pick(pictures) : "gone\(n.below(9))"
            return "<img src=\"cid:\(id)\" alt=\"\(n.pick(words))\" width=\"\(100 + n.below(500))\">"
        case 4:
            return "<!-- \(sentence(&n, words: 2)) -->"
        case 5:
            return "<img src=\"https://example.com/p\(n.below(99)).png\" style=\"display:block\">"
        case 6, 7:
            let style = n.pick(["", " style=\"color:#333333; font-size:15px;\"",
                                " style=\"background:url(cid:\(n.pick(pictures)))\"",
                                " style=\"background-image:url('https://example.com/bg.png')\"",
                                " class=\"x\" dir=\"ltr\""])
            return "<div\(style)>" + (0..<(1 + n.below(3))).map { _ in block(&n, depth: depth + 1) }
                .joined() + "</div>"
        case 8:
            return "<table width=\"600\" cellpadding=\"0\" style=\"border-collapse: collapse;\">"
                + "<tr><td style=\"color:#333333;\">" + block(&n, depth: depth + 1)
                + "</td><td>" + inline(&n) + (n.chance(50) ? "</td></tr>" : "") + "</table>\n"
        case 9:
            return "<ul>" + (0..<(1 + n.below(4))).map { _ in "<li>" + inline(&n) }.joined()
                + "</ul>"
        case 10:
            return "<blockquote type=\"cite\">" + block(&n, depth: depth + 1) + "</blockquote>"
        case 11:
            return "<header><h2>" + inline(&n) + "</h2></header>"
        case 12:
            return "<!--[if mso]><table><tr><td><![endif]-->" + block(&n, depth: depth + 1)
                + "<!--[if mso]></td></tr></table><![endif]-->"
        default:
            return "<center><font face=\"Arial\" color=\"#333\">" + inline(&n) + "</font></center>"
        }
    }

    private static func inline(_ n: inout Numbers) -> String {
        var out = ""
        for _ in 0..<(1 + n.below(6)) {
            switch n.below(9) {
            case 0: out += "<b>" + sentence(&n, words: 2) + "</b> "
            case 1: out += "<i>" + sentence(&n, words: 1) + "</i> "
            case 2: out += "<a href=\"https://example.com/x?a=\(n.below(9))&amp;b=2\" "
                + "target=\"_blank\">" + sentence(&n, words: 2) + "</a> "
            case 3: out += "<span style=\"font-weight:bold\">" + n.pick(words) + "</span>"
            case 4: out += n.pick(entities) + " "
            case 5: out += "<br>"
            default: out += sentence(&n, words: 1 + n.below(12)) + " "
            }
        }
        return out
    }

    // MARK: - Whole letters

    /// Whole letters as Gmail hands them over, CRLF throughout.
    static func letters(count: Int = 30, seed: UInt64 = 0x6C65_7474_6572_7332) -> [Data] {
        var n = Numbers(seed: seed)
        return (0..<count).map { _ in letter(&n) }
    }

    /// One letter from `n`; `depth` letters forwarded inside it at most.
    static func letter(_ n: inout Numbers, depth: Int = 2) -> Data {
        var header = "Return-Path: <jane@example.com>\r\n"
            + "Received: from mail.example.com (mail.example.com [192.0.2.1])\r\n"
            + "        by mx.google.com with ESMTPS id x\(n.below(999))\r\n"
            + "        for <owner@example.com>;\r\n"
        header += "From: " + n.pick(["\"Jane Example\" <jane@example.com>", "sam@example.com",
                                     "=?UTF-8?Q?Ren=C3=A9e_Example?= <renee@example.com>",
                                     "Carlo <carlo@example.org>"]) + "\r\n"
        header += "To: owner@example.com" + (n.chance(40) ? ",\r\n\tJane <jane@example.com>" : "")
            + "\r\n"
        if n.chance(30) { header += "Cc: Sam Example <sam@example.com>\r\n" }
        header += "Subject: " + n.pick([
            sentence(&n, words: 4),
            "=?UTF-8?Q?Caf=C3=A9_on_Saturday?=",
            "=?utf-8?B?" + Data(sentence(&n, words: 5).utf8).base64EncodedString() + "?=",
            "Re: " + sentence(&n, words: 3) + "\r\n =?UTF-8?Q?=E2=80=94_and_more?=",
        ]) + "\r\n"
        header += "Date: Mon, 20 Sep 2026 10:\(10 + n.below(49)):00 +0100\r\n"
        header += "Message-ID: <\(n.next())@example.com>\r\n"
        if n.chance(40) {
            header += "References: <a\(n.below(99))@example.com>\r\n <b\(n.below(99))@example.com>"
                + "\r\n\t<c\(n.below(99))@example.com>\r\n"
        }
        header += "MIME-Version: 1.0\r\n"

        let text = (0..<(1 + n.below(8))).map { _ in sentence(&n, words: 3 + n.below(14)) }
            .joined(separator: "\n")
        let html = document(&n)
        let body: (headers: String, content: String)
        switch n.below(depth > 0 ? 6 : 5) {
        case 0:
            body = plainPart(text, &n)
        case 1:
            body = htmlPart(html, &n)
        case 2:
            body = multipart("alternative", [plainPart(text, &n), htmlPart(html, &n)], &n)
        case 3:
            body = multipart("related", [htmlPart(html, &n), picture(&n)], &n)
        case 4:
            body = multipart("mixed", [multipart("alternative", [plainPart(text, &n),
                                                                  htmlPart(html, &n)], &n),
                                       file(&n), picture(&n)], &n)
        default:
            let forwarded = letter(&n, depth: depth - 1)
            body = multipart("mixed", [plainPart(text, &n),
                                       ("Content-Type: message/rfc822\r\n"
                                            + "Content-Disposition: inline\r\n",
                                        String(decoding: forwarded, as: UTF8.self))], &n)
        }
        return Data((header + body.headers + "\r\n" + body.content).utf8)
    }

    private static func crlf(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\r\n")
    }

    private static func plainPart(_ text: String, _ n: inout Numbers) -> (headers: String,
                                                                           content: String) {
        if n.chance(50) {
            return ("Content-Type: text/plain; charset=\"UTF-8\"\r\n"
                        + "Content-Transfer-Encoding: quoted-printable\r\n",
                    quotedPrintable(text))
        }
        return ("Content-Type: text/plain; charset=utf-8; format=flowed\r\n"
                    + "Content-Transfer-Encoding: 8bit\r\n", crlf(text) + "\r\n")
    }

    private static func htmlPart(_ html: String, _ n: inout Numbers) -> (headers: String,
                                                                          content: String) {
        if n.chance(50) {
            return ("Content-Type: text/html; charset=\"utf-8\"\r\n"
                        + "Content-Transfer-Encoding: base64\r\n",
                    Data(html.utf8).base64EncodedString(
                        options: [.lineLength76Characters, .endLineWithCarriageReturn,
                                  .endLineWithLineFeed]) + "\r\n")
        }
        return ("Content-Type: text/html; charset=UTF-8\r\n"
                    + "Content-Transfer-Encoding: quoted-printable\r\n", quotedPrintable(html))
    }

    private static func picture(_ n: inout Numbers) -> (headers: String, content: String) {
        let bytes = Data((0..<(200 + n.below(900))).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let id = n.pick(pictures)
        return ("Content-Type: image/png; name=\"photo.png\"\r\n"
                    + "Content-Disposition: inline; filename=\"photo.png\"\r\n"
                    + "Content-Transfer-Encoding: base64\r\nContent-ID: <\(id)>\r\n",
                bytes.base64EncodedString(options: [.lineLength76Characters,
                                                    .endLineWithCarriageReturn,
                                                    .endLineWithLineFeed]) + "\r\n")
    }

    private static func file(_ n: inout Numbers) -> (headers: String, content: String) {
        let bytes = Data("%PDF-1.4 the programme \(n.next())".utf8)
        let name = n.pick(["Programme.pdf", "résumé.pdf"])
        let disposition = name == "Programme.pdf"
            ? "attachment; filename=\"Programme.pdf\""
            : "attachment;\r\n filename*=utf-8''r%C3%A9sum%C3%A9.pdf"
        return ("Content-Type: application/pdf; name=\"\(name)\"\r\n"
                    + "Content-Disposition: \(disposition)\r\n"
                    + "Content-Transfer-Encoding: base64\r\n",
                bytes.base64EncodedString() + "\r\n")
    }

    private static func multipart(_ subtype: String,
                                  _ parts: [(headers: String, content: String)],
                                  _ n: inout Numbers) -> (headers: String, content: String) {
        let boundary = "=_\(subtype)_\(n.next() % 1_000_000)"
        var content = n.chance(30) ? "This is a multi-part message in MIME format.\r\n\r\n" : ""
        for part in parts {
            content += "--\(boundary)\r\n" + part.headers + "\r\n" + part.content
            if !part.content.hasSuffix("\r\n") { content += "\r\n" }
        }
        content += "--\(boundary)--\r\n"
        return ("Content-Type: multipart/\(subtype);\r\n\tboundary=\"\(boundary)\"\r\n", content)
    }

    /// Quoted-printable as mailers write it: 76 columns with soft breaks,
    /// `=` and every byte outside printable ASCII escaped, CRLF line ends,
    /// and trailing white space escaped.
    static func quotedPrintable(_ text: String) -> String {
        var out = ""
        for line in text.components(separatedBy: "\n") {
            var column = 0
            let bytes = Array(line.utf8)
            for (i, byte) in bytes.enumerated() {
                let last = i == bytes.count - 1
                let piece: String
                if byte == 0x3D || byte >= 0x7F || byte < 0x20
                    || (last && (byte == 0x20 || byte == 0x09)) {
                    piece = String(format: "=%02X", byte)
                } else {
                    piece = String(UnicodeScalar(byte))
                }
                if column + piece.count > 75 {
                    out += "=\r\n"
                    column = 0
                }
                out += piece
                column += piece.count
            }
            out += "\r\n"
        }
        return out
    }

    // MARK: - What the passes make of it

    /// The new ids a quote gives `pictures`.
    static let quotePictures = Dictionary(uniqueKeysWithValues: pictures.enumerated().map {
        ($1, "bmquote\($0 + 1).5eedc0ffee00")
    })

    /// `QuotedMarkup.made` of each of `documents`, what it shows included.
    static func quotedFingerprints() -> [String] {
        documents().map { html in
            let made = QuotedMarkup.made(html, pictures: quotePictures)
            return fingerprint(made.html + "\u{0}" + made.shown.sorted().joined(separator: ","))
        }
    }

    /// The reading pane's page, and a conversation's body, for each of
    /// `documents` as a letter carrying `pictures`.
    static func pageFingerprints() -> [String] {
        let style = PanePage.Style(inset: 26, bodyPointSize: 17, lineHeight: 1.41)
        let parts = pictures.enumerated().map { i, id in
            Attachment(id: "\(i + 2)", filename: "p\(i).png", mimeType: "image/png", size: 100,
                       contentID: id, isInline: true)
        }
        return documents().map { html in
            let m = Message(id: "600001/2", mailboxID: "INBOX", sender: "Jane <jane@example.com>",
                            senderAddress: "jane@example.com", to: ["owner@example.com"], cc: [],
                            subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                            textBody: nil, htmlBody: html, attachments: parts)
            return fingerprint((PanePage.letter(m, style: style) ?? "\u{1}") + "\u{0}"
                               + PanePage.stackBody(m).html)
        }
    }

    /// `MIMEDecoder.decodeMessage` and `parseHeaders` of each of `letters`:
    /// the text, the HTML, every file and every header.
    static func decodedFingerprints() -> [String] {
        letters().map { raw in
            let body = MIMEDecoder.decodeMessage(raw)
            var text = (body.text ?? "\u{1}") + "\u{0}" + (body.html ?? "\u{1}")
            for a in body.attachments {
                text += "\u{0}\(a.id)|\(a.filename)|\(a.mimeType)|\(a.size ?? -1)|"
                    + "\(a.contentID ?? "-")|\(a.isInline)"
            }
            for header in MIMEDecoder.parseHeaders(raw) {
                text += "\u{0}\(header.name): \(header.value)"
            }
            return fingerprint(text)
        }
    }

    // MARK: - Fingerprints

    /// 64-bit FNV-1a of `bytes`, in hex: what a byte-for-byte comparison
    /// against a recorded output compares.
    static func fingerprint<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    static func fingerprint(_ text: String) -> String { fingerprint(text.utf8) }
}
