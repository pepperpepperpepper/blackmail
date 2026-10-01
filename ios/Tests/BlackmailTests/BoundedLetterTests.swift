import XCTest
@testable import Blackmail

/// A stranger's letter costs time and memory in proportion to its size.
///
/// Every pass over a received letter's content that grew with the square
/// of it is one pass now: taking off the sender's document wrapper for the
/// reading pane (`DocumentWrapper`), pointing its pictures at the loader
/// (`InlineImageRewriter`), making its markup safe to quote
/// (`QuotedMarkup`), and reading its header and its parts
/// (`MIMEDecoder`). Two things are held here for each.
///
/// What they make of ordinary mail has not changed by a byte. The wrapper,
/// the pictures and the line breaks are held against the code they replace,
/// kept here as the reference; the quote, the pane's page and the decoded
/// letter against fingerprints of what the code before them made of the
/// same letters (`OrdinaryMail`).
///
/// And the letters built to make them slow are not. Each is timed against a
/// bound at least ten times what it takes here, in the debug build the
/// suite runs, on a host that may be running several suites at once, and
/// sized so that the old way goes well past the bound: a quadratic pass
/// fails, a linear one has room to spare. Where the old way is too close to
/// the new in this build to be told from it by time, what it does is held
/// instead. Memory is measured where it was memory that blew up
/// (`PeakMemory`).
final class BoundedLetterTests: XCTestCase {

    // MARK: - The code replaced, kept as the reference

    /// The wrapper as four regular expressions took it off.
    private func expressionsStripped(_ html: String) -> String {
        var s = html
        for pattern in ["<!DOCTYPE[^>]*>", "</?html[^>]*>", "<head(?=[\\s/>])[^>]*>[\\s\\S]*?</head>",
                        "</?body[^>]*>"] {
            s = s.replacingOccurrences(of: pattern, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    /// The pictures as Foundation's search on the rest of the body found
    /// them.
    private func searchedRewrite(_ html: String, known: Set<String>) -> String {
        guard html.range(of: "cid:", options: .caseInsensitive) != nil else { return html }
        var out = ""
        var rest = Substring(html)
        while let found = rest.range(of: "cid:", options: .caseInsensitive) {
            out += rest[..<found.lowerBound]
            let after = rest[found.upperBound...]
            let id = after.prefix { ch in
                !(ch == "\"" || ch == "'" || ch == " " || ch == ">" || ch == ")"
                  || ch == "\n" || ch == "\r" || ch == "\t")
            }
            if known.contains(String(id)) {
                out += InlineImageRewriter.scheme + "://" + InlineImageRewriter.escapedHost(String(id))
            } else {
                out += "cid:" + id
            }
            rest = after[id.endIndex...]
        }
        return out + rest
    }

    /// Line breaks as Foundation's two replacements made them.
    private func replacedNewlines(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - Ordinary mail, byte for byte

    func testTheWrapperComesOffByteForByteAsTheExpressionsTookIt() {
        var documents = OrdinaryMail.documents()
        // The corners of what the expressions matched: every case, a head
        // ended by each kind of white space they allowed and by `/` and
        // `>`, and not by what they did not allow; pieces never closed;
        // HTML5's header; a head holding the other pieces.
        documents += [
            "<!doctype html><HtMl><HEAD><title>x</title></HEAD><BoDy>y</bOdY></hTmL>",
            "<head\t>a</head>b<head\n>c</head>d<head\r>e</head>f<head\u{0C}>g</head>h",
            "<head\u{00A0}>a</head>b<head\u{2028}>c</head>d<head\u{3000}>e</head>f",
            "<head\u{0B}>a</head>b<head\u{85}>c</head>d<headx>e</head>f",
            "<head/>a</head>b<head>c</head>d",
            "a<!DOCTYPE never closed <p>b</p>",
            "a<html never closed",
            "<head><title>no end</title><p>a</p>",
            "<body class=\"x\"><header><h1>a</h1></header><head>b</head>c",
            "<head><!DOCTYPE x><html><body></head>after",
            "</HTML></BODY></head><html/><body/>",
            "caf\u{E9} <html lang=\"fr\">d\u{E9}j\u{E0} \u{1F339}</html>",
        ]
        for (i, html) in documents.enumerated() {
            XCTAssertEqual(Array(DocumentWrapper.stripped(from: html).utf8),
                           Array(expressionsStripped(html).utf8), "document \(i)")
        }
    }

    func testPicturesArePointedAtTheLoaderByteForByteAsBefore() {
        let known = Set(OrdinaryMail.pictures)
        var documents = OrdinaryMail.documents()
        documents += [
            "<img src=\"CID:ii_garden01\"><img src='Cid:photo 2'><img src=cid:sig-logo>",
            "url(cid:logo@example.com) cid: cid:\tcid:gone\ncid:ii_garden01)",
            "the acid test, and cid: with nothing after it; cid:ii_garden01",
        ]
        for (i, html) in documents.enumerated() {
            XCTAssertEqual(Array(InlineImageRewriter.rewrite(html, known: known).utf8),
                           Array(searchedRewrite(html, known: known).utf8), "document \(i)")
            XCTAssertEqual(InlineImageRewriter.rewrite(html, known: []),
                           searchedRewrite(html, known: []), "document \(i)")
        }
    }

    func testLineBreaksComeOutByteForByteAsTheReplacementsMadeThem() {
        var n = OrdinaryMail.Numbers(seed: 0x6272_6561_6B73)
        var texts = ["", "no breaks", "\r\n", "\r", "\n", "a\r\n\r\nb", "a\r\rb", "a\n\rb",
                     "\r\r\n\n\r", "caf\u{E9}\r\n\u{1F339}\r\u{65E5}\u{672C}\n"]
        for _ in 0..<40 {
            let lines = (0..<(1 + n.below(30))).map { _ in
                OrdinaryMail.sentence(&n, words: n.below(12))
            }
            texts.append(lines.joined(separator: n.pick(["\r\n", "\n", "\r", "\r\n\r\n"])))
        }
        for (i, text) in texts.enumerated() {
            let decoded = MIMEDecoder.decodeText(Data(text.utf8), encoding: "8bit",
                                                 charset: "utf-8")
            XCTAssertEqual(Array(decoded.utf8), Array(replacedNewlines(text).utf8), "text \(i)")
        }
    }

    func testOrdinaryMarkupIsQuotedByteForByteAsBefore() {
        XCTAssertEqual(OrdinaryMail.quotedFingerprints(), Self.quoted)
    }

    func testOrdinaryLettersPagesAreByteForByteAsBefore() {
        XCTAssertEqual(OrdinaryMail.pageFingerprints(), Self.pages)
    }

    func testOrdinaryLettersAreDecodedByteForByteAsBefore() {
        XCTAssertEqual(OrdinaryMail.decodedFingerprints(), Self.decoded)
    }

    // MARK: - Letters made to be slow

    /// Seconds for `work`, and the bound it is held to.
    private func assertQuick(_ label: String, within bound: TimeInterval = 1,
                             file: StaticString = #filePath, line: UInt = #line,
                             _ work: () -> Void) {
        let started = Date()
        work()
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, bound, "\(label): \(elapsed) s", file: file, line: line)
    }

    /// 48 KB of each piece of the wrapper, never closed. Each opening made
    /// its expression read to the end of the letter: `<head>` took 6.4 s
    /// here, and the others 1.9 to 3.4 s. About 10 ms each now.
    func testAWrapperNeverClosedIsReadOnce() {
        for piece in ["<head>", "<html", "<!DOCTYPE", "<body"] {
            let html = String(repeating: piece, count: 48 * 1_024 / piece.utf8.count)
            assertQuick(piece) { _ = DocumentWrapper.stripped(from: html) }
        }
    }

    /// Twenty thousand pictures, 400 bytes apart: 8 MB. Each was found by
    /// searching a copy of the rest of the body, 7.5 s here, and 1.5 s at
    /// half the size. 0.1 s now.
    func testManyPicturesAreFoundInOnePass() {
        let text = String(repeating: "Here is the garden in June, and the roses. ", count: 9)
        let html = String(repeating: "<img src=\"cid:ii_garden01\">" + text, count: 20_000)
        var out = ""
        assertQuick("pictures", within: 2) {
            out = InlineImageRewriter.rewrite(html, known: ["ii_garden01"])
        }
        // Each `cid:` became the four bytes longer `bmcid://`.
        XCTAssertEqual(out.utf8.count, html.utf8.count + 4 * 20_000)
        XCTAssertTrue(out.hasPrefix("<img src=\"bmcid://ii_garden01\">Here is"))
    }

    /// `<div>` opened nine thousand times, then `</x>` as often, 83 KB:
    /// each `</x>` read the whole list of what was open, 5 s here. 45 ms
    /// now.
    func testAClosingTagForNothingOpenIsRefusedAtOnce() {
        let n = 9 * 1_024
        let html = String(repeating: "<div>", count: n) + String(repeating: "</x>", count: n)
        assertQuick("stack") { _ = QuotedMarkup.safe(html) }
    }

    /// As many elements open as the pass keeps, then `</x>` fifty thousand
    /// times: with only the limit, each `</x>` still looked through all 512
    /// of them. Timed against the same closing tags with nothing open, the
    /// fastest of three runs of each, so that what is compared is the work
    /// and not the load on the host: about the same time now, 19 times as
    /// long before.
    func testAClosingTagForNothingOpenIsRefusedWithoutLookingAtWhatIs() {
        let closes = String(repeating: "</x>", count: 50_000)
        let full = String(repeating: "<div>", count: QuotedMarkup.OpenElements.limit) + closes
        func fastest(_ html: String) -> TimeInterval {
            (0..<3).map { _ -> TimeInterval in
                let started = Date()
                _ = QuotedMarkup.safe(html)
                return Date().timeIntervalSince(started)
            }.min() ?? 0
        }
        let nothingOpen = fastest(closes)
        let limitOpen = fastest(full)
        XCTAssertLessThan(limitOpen, 4 * nothingOpen + 0.05,
                          "\(limitOpen) s with \(QuotedMarkup.OpenElements.limit) open, "
                          + "\(nothingOpen) s with none")
    }

    /// `<head>x` over and over, 24 KB: each head was read to the end of the
    /// markup for its `</head>`, 4.1 s here, and 48 KB took 16 s. 14 ms now.
    func testAHeadNeverClosedIsReadToTheEndOnce() {
        let html = String(repeating: "<head>x", count: 24 * 1_024 / 7)
        var out = ""
        assertQuick("heads") { out = QuotedMarkup.safe(html) }
        XCTAssertEqual(out, String(repeating: "x", count: 24 * 1_024 / 7))
    }

    /// One tag of eight thousand attributes: each was looked for among the
    /// ones before it, 2.8 s here. 45 ms now.
    func testATagOfThousandsOfAttributesIsReadOnce() {
        let html = "<div " + (0..<8_000).map { "a\($0)=\"1\"" }.joined(separator: " ") + ">x</div>"
        var out = ""
        assertQuick("attributes") { out = QuotedMarkup.safe(html) }
        XCTAssertTrue(out.hasPrefix("<div a0=\"1\" a1=\"1\""))
        XCTAssertTrue(out.hasSuffix(" a7999=\"1\">x</div>"))
    }

    /// A style whose `cid:` reference is made of `cid:` over and over, after
    /// twelve thousand more of them: the reference was looked for afresh
    /// from each place it might start, 2 s here, and 3.6 s at a third as
    /// much again. 70 ms now.
    func testAReferenceInAStyleIsFoundInOnePass() {
        let m = 12_000
        let style = String(repeating: "cid:", count: m) + " url(" + String(repeating: "cid:", count: m / 2)
            + "X)"
        assertQuick("reference") {
            _ = QuotedMarkup.safe("<div style=\"\(style)\">x</div>", pictures: ["p": "bmquote1.x"])
        }
        // What the pass decides is unchanged: an id the letter does not
        // carry takes the style with it.
        XCTAssertEqual(QuotedMarkup.safe("<div style=\"\(style)\">x</div>"), "<div>x</div>")
    }

    /// A style of 4 MB with 180,000 references to a picture a forward
    /// carries, each renamed to the longer id it travels under: put in one
    /// at a time as each was found, each moved the rest of the style along,
    /// 8 s in a release build and 7.7 s here. Now every id is read where
    /// the sender wrote it, in the style as it came, and all are put in
    /// together once they are found. That nothing moves meanwhile is what
    /// is held here, place by place: timed, the quadratic way is only about
    /// seven times the linear one at 4 MB in this build, too close to a
    /// bound to tell them apart without flaking. The pass over 30,000
    /// references takes 0.2 s here, and is timed against 2 s for anything
    /// else that might grow with the square of it.
    func testAStylesPicturesAreRenamedInOneCopy() {
        let unit = "background:url(cid:p);"
        let count = 30_000
        let style = Array(String(repeating: unit, count: count).utf8)
        let compact = QuotedMarkup.compactCSS(style)
        let new = Array("bmquote1.5eedc0ffee00".utf8)
        var places: [Int] = []
        var out: [UInt8]?
        assertQuick("renaming", within: 2) {
            out = QuotedMarkup.picturesRenamed(in: style, compact: compact) { id in
                places.append(id.startIndex)
                return id.elementsEqual("p".utf8) ? new : nil
            }
        }
        // Each id where it stands in the style as written: `cid:` is 19
        // bytes into each unit.
        let written = (0..<count).map { $0 * unit.utf8.count + 19 }
        XCTAssertEqual(places.count, count)
        let moved = zip(places, written).enumerated().first { $0.element.0 != $0.element.1 }
        XCTAssertNil(moved, "reference \(moved?.offset ?? 0) read at \(moved?.element.0 ?? 0), "
                     + "written at \(moved?.element.1 ?? 0)")
        XCTAssertEqual(out?.count, style.count + count * (new.count - 1))
        let first: [UInt8] = Array("background:url(cid:bmquote1.5eedc0ffee00);".utf8)
        XCTAssertEqual(out.map { Array($0.prefix(first.count)) }, first)
        XCTAssertEqual(out.map { Array($0.suffix(first.count)) }, first)
        // And through the pass, with a style that shows it twice.
        let quoted = QuotedMarkup.safe(
            "<div style=\"background:url(cid:p); border-image:url('cid:p')\">x</div>",
            pictures: ["p": "bmquote1.5eedc0ffee00"])
        XCTAssertEqual(quoted, "<div style=\"background:url(cid:bmquote1.5eedc0ffee00); "
                       + "border-image:url('cid:bmquote1.5eedc0ffee00')\">x</div>")
    }

    /// A forward of a letter whose picture references are written in
    /// another case than their Content-IDs: each was compared with every
    /// picture the forward carries, and with 500 of them 1.1 MB took 7.3 s
    /// in a release build, 14 times the same references in their own case
    /// here. Looked up in a table of the ids in one case now, made once:
    /// about one and a half times. Timed with 2,000 pictures, where the
    /// comparing way is fifty times, well past a bound ten times what the
    /// lookup takes; the fastest of three runs of each, so that what is
    /// compared is the work and not the load on the host.
    func testAReferenceInAnotherCaseIsLookedUpNotComparedWithEveryPicture() {
        let pictures = Dictionary(uniqueKeysWithValues: (0..<2_000).map {
            ("photo\($0)@example.com", "bmquote1.\($0)")
        })
        func letter(_ id: (Int) -> String) -> String {
            (0..<2_000).map { "<img src=\"cid:\(id($0))\">" }.joined()
        }
        let own = letter { "photo\($0)@example.com" }
        let other = letter { "PHOTO\($0)@EXAMPLE.COM" }
        func fastest(_ html: String) -> TimeInterval {
            (0..<3).map { _ -> TimeInterval in
                let started = Date()
                _ = QuotedMarkup.safe(html, pictures: pictures)
                return Date().timeIntervalSince(started)
            }.min() ?? 0
        }
        let ownCase = fastest(own)
        let otherCase = fastest(other)
        XCTAssertLessThan(otherCase, 16 * ownCase + 0.05,
                          "\(otherCase) s in another case, \(ownCase) s in their own")
        XCTAssertEqual(QuotedMarkup.safe(other, pictures: pictures),
                       QuotedMarkup.safe(own, pictures: pictures))

        // What it finds is what the comparison found, ß and SS as one; and
        // of two ids that differ only in case, the first in order, every
        // time.
        XCTAssertEqual(QuotedMarkup.safe("<img src=\"cid:STRASSE@EXAMPLE.COM\">",
                                         pictures: ["straße@example.com": "bmquote1.1"]),
                       "<img src=\"cid:bmquote1.1\">")
        XCTAssertEqual(QuotedMarkup.safe("<img src=\"cid:PHOTO@EXAMPLE.COM\">",
                                         pictures: ["photo@example.com": "bmquote1.2",
                                                    "Photo@example.com": "bmquote1.3"]),
                       "<img src=\"cid:bmquote1.3\">")
        // One it carries in no case goes, as it went.
        XCTAssertEqual(QuotedMarkup.safe("<img src=\"cid:GONE@EXAMPLE.COM\">x",
                                         pictures: pictures), "x")
    }

    /// A header folded onto twenty thousand lines of a hundred bytes, 2 MB:
    /// the value was copied whole for every line put on it, 4.7 s here.
    /// 80 ms now.
    func testAHeaderFoldedThousandsOfTimesIsUnfoldedOnce() {
        let line = " " + String(repeating: "x", count: 97) + "\r\n"
        let raw = Data(("Subject: start\r\n" + String(repeating: line, count: 20_000)
                        + "From: a@example.com\r\n\r\nbody").utf8)
        var headers: [(name: String, value: String)] = []
        assertQuick("folding") { headers = MIMEDecoder.parseHeaders(raw) }
        XCTAssertEqual(MIMEDecoder.headerValue("Subject", in: headers)?.utf8.count,
                       5 + 20_000 * 98)
        XCTAssertEqual(MIMEDecoder.headerValue("From", in: headers), "a@example.com")
    }

    // MARK: - Memory

    /// 4 MB of bare line breaks in a multipart: the list of every line made
    /// first came to 102 MB. 9 MB now, the copies of the letter itself.
    func testAPartOfLineBreaksIsWalkedInPlace() throws {
        var raw = Data("Content-Type: multipart/mixed; boundary=\"B\"\r\n\r\n--B\r\n".utf8)
        raw.append(Data("Content-Type: text/plain\r\n\r\n".utf8))
        raw.append(Data(repeating: 0x0A, count: 4 << 20))
        raw.append(Data("\r\n--B--\r\n".utf8))
        var parsed: (structure: MIMEPart, bodies: [String: Data])?
        let growth = PeakMemory.growth { parsed = MIMEDecoder.parse(raw) }
        XCTAssertEqual(parsed?.bodies["1"]?.count, 4 << 20)
        guard let growth else { throw XCTSkip(Self.unmeasured) }
        XCTAssertLessThan(growth, 48 << 20, "\(growth >> 20) MB")
    }

    /// 4 MB of CRLF: the two replacements came to 151 MB, and took 2.3 s.
    /// 2 MB now, and 0.2 s.
    func testLineBreaksAreMadeLineFeedsInOneCopy() throws {
        let breaks = Data(String(repeating: "\r\n", count: 2 << 20).utf8)
        var text = ""
        let growth = PeakMemory.growth {
            text = MIMEDecoder.decodeText(breaks, encoding: "7bit", charset: "utf-8")
        }
        XCTAssertEqual(text.utf8.count, 2 << 20)
        guard let growth else { throw XCTSkip(Self.unmeasured) }
        XCTAssertLessThan(growth, 32 << 20, "\(growth >> 20) MB")
    }

    /// The header of a 48 MB letter: the whole letter was copied to read
    /// it, 47 MB. Nothing to speak of now.
    func testOnlyAHeaderIsCopiedToReadIt() throws {
        var raw = Data("From: Jane <jane@example.com>\r\nSubject: Photographs\r\n\r\n".utf8)
        raw.append(Data(repeating: 0x41, count: 48 << 20))
        var headers: [(name: String, value: String)] = []
        let growth = PeakMemory.growth { headers = MIMEDecoder.parseHeaders(raw) }
        XCTAssertEqual(MIMEDecoder.headerValue("Subject", in: headers), "Photographs")
        guard let growth else { throw XCTSkip(Self.unmeasured) }
        XCTAssertLessThan(growth, 16 << 20, "\(growth >> 20) MB")
    }

    static let unmeasured = "no high-water mark to measure memory by on this host"

    // MARK: - Bounds

    /// Nested past `OpenElements.limit`, an element loses its tag and keeps
    /// what is inside it, and what is kept still closes in order.
    func testQuotedMarkupNestsNoDeeperThanTheLimit() {
        let limit = QuotedMarkup.OpenElements.limit
        let deep = String(repeating: "<div>", count: limit + 100) + "x"
            + String(repeating: "</div>", count: limit + 100) + "<p>after</p>"
        let out = QuotedMarkup.safe(deep)
        XCTAssertEqual(out, String(repeating: "<div>", count: limit) + "x"
                       + String(repeating: "</div>", count: limit) + "<p>after</p>")
        // Left open, they are closed at the end, innermost first.
        XCTAssertEqual(QuotedMarkup.safe(String(repeating: "<b>", count: limit + 1) + "y"),
                       String(repeating: "<b>", count: limit) + "y"
                       + String(repeating: "</b>", count: limit))
    }

    /// A letter of six hundred files in nested multiparts lists five
    /// hundred: each is a row in the pane's header and on the kept page.
    func testNoMoreThanFiveHundredFilesAreListed() {
        var body = ""
        for outer in 0..<3 {
            body += "--O\r\nContent-Type: multipart/mixed; boundary=\"I\(outer)\"\r\n\r\n"
            for inner in 0..<200 {
                body += "--I\(outer)\r\nContent-Type: application/pdf; name=\"f\(outer)-\(inner).pdf\"\r\n"
                    + "Content-Disposition: attachment\r\n\r\nx\r\n"
            }
            body += "--I\(outer)--\r\n"
        }
        let raw = Data(("Content-Type: multipart/mixed; boundary=\"O\"\r\n\r\n" + body + "--O--\r\n")
            .utf8)
        let files = MIMEDecoder.decodeMessage(raw).attachments
        XCTAssertEqual(files.count, MIMEDecoder.maxAttachments)
        XCTAssertEqual(files.first?.filename, "f0-0.pdf")
        XCTAssertEqual(files.last?.filename, "f2-99.pdf")
        XCTAssertEqual(MIMEDecoder.listedAttachments(in: MIMEDecoder.parseStructure(raw)).count,
                       MIMEDecoder.maxAttachments)
    }

    // MARK: - Fingerprints of what the code before made of `OrdinaryMail`

    private static let quoted = [
        "7fa3c4232321b956", "5722377f85102a6a", "c1212a4be9b951c7", "0cd21ca077556c8b",
        "2088ee58b8f010c2", "af63bd4c8601b7df", "ab9c183ccc778e03", "af63bd4c8601b7df",
        "a902167fa96d01d2", "55bf643998ae0c5c", "ef41e68cb50d5674", "195a79958ae616bd",
        "51d8c7c58810bb85", "fe84b4da2f13ca7b", "4e60b4b714002da2", "9f62834bab3853ae",
        "c752b2de9c52cbe2", "2812aa876866774a", "cdd7b502491c8631", "e6a5cf498d22308b",
        "e927ce768b81358d", "076360888899fd6c", "e458b625c300594e", "95b5f4060f2804b4",
        "3e14e29ae8d55672", "b4e7c4f91a0dce5b", "911a9de7681169dc", "8114908cdc608911",
        "d00a053b2c38bacf", "69e362c72eaf243b", "2dbbfe6534126e3d", "ce19b045ec42708b",
        "835624bb50f82163", "75e12738bb2a6145", "5ac5088983395e96", "d062437c86189f81",
        "7a65763dc47db1df", "de4b4b89d2e88b4b", "08548407b5084f87", "3fe2b91cdfcf1ca4",
        "2527f9c693107bd6", "3b475f29d9fa3f1e", "1d1e70e732f3bdb1", "b9635a823c38574c",
        "262a132ad14125b0", "948b033b859650e7", "f162f649feeef66b", "3aec6e753c1a0954",
        "acf13037903198df", "f8a8fbb7f0a31bc4", "415bd516f238086e", "4bdbfb747622fd16",
        "3fa578335518adad", "d5382b84fc3b9e76",
    ]

    /// The pane's page as B-055 left it (links in the text, the pane's own
    /// script out of the page), which the code before B-054 made of the
    /// same letters byte for byte once B-055 was in.
    private static let pages = [
        "8ed1fd729c463093", "001452042feeb48b", "bffd162866db60c7", "70ae21e172cb2f59",
        "6929055f3ae96a9b", "355790a2dd2326b6", "355790a2dd2326b6", "355790a2dd2326b6",
        "1e54000f6f73684b", "903cc1a690b06407", "087fffa6deefd08d", "355790a2dd2326b6",
        "1ffb99359a4d0d37", "9b254dbd3de0d9a3", "d2b792ec1c12b87f", "7fd79aa689386437",
        "007b6384be4357ab", "474956b595d529b1", "59a44d067094aee9", "1d7e377417a38fcf",
        "112e9b050bda7bd1", "355790a2dd2326b6", "442972f1ed521dd3", "28d77903f8d41641",
        "0a7d557b77bc594f", "c613b75cb6fc43e3", "24ad962b246fbfe3", "aa0ddde42f754451",
        "e2b2797593f4f17f", "525b10cee522f2bb", "1b66fc6f9b877c71", "5d1b0cbd92fe6503",
        "bd4eea0fa8b52b49", "8167e3b55e46bafd", "324f6a19622021cb", "5fa515a696a39bbd",
        "1de2954065047979", "38e4d32e0aa27a2b", "355790a2dd2326b6", "035ce5164e15c94b",
        "8b77dde964ca3f71", "bb42129aa27ad7db", "e9f0f8c0f233f33b", "d8178ab60cad20ab",
        "0b9fe1ffbe110d0b", "6c4bdae5d0e6c8cf", "7c2159ea9bec613d", "89f34672c6b6ebcb",
        "615bd78df00c4995", "1354a845a1f28309", "65aff0f215b42851", "181308f186571713",
        "b1a74e2b45e329b3", "bc91ca5ffa349b33",
    ]

    private static let decoded = [
        "73994bb71b0dc36c", "93a105f48f730967", "865fcbd7abe81223", "884bc9e1e09eeea9",
        "281614d264936717", "f757152f8db25213", "a5ffc51eecadfedf", "411e68f1df5124cc",
        "fa63ea4f4fde0319", "e19b3494ac92ceac", "1957ea5390396471", "dd2608e102948857",
        "8f706c917b23a629", "a6938c2f3227f89a", "370486990df6e704", "01e8b57895b8c184",
        "9267637a69b7cb06", "26ca6e77c7ddeacd", "b8c28a2aac29f940", "325f26c02c38ef5f",
        "43eed83397125d61", "e5e9538085fd22ed", "9b7baeaa1bf3dedd", "7577a19b161e1dcc",
        "a30f27d04ee880c6", "94a76e2c39fa7cb5", "06f1e3935bd47ba1", "85dd636fbe8f7716",
        "8e5b81b18adc9874", "6fed3899fbcb0e99",
    ]
}
