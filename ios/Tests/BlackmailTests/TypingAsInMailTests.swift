import XCTest
@testable import Blackmail

/// Subject and the body type as Mail's do (B-121): Subject begins with a
/// capital and corrects spelling, and both take the keyboard's Smart
/// Punctuation, so his apostrophes and quotes come out curly and "--" a
/// dash, as his own letters from Mail show. The address rows keep their
/// email keyboard with none of that. The sheets are UIKit and never build
/// on this host, so their settings are read from their source; what he
/// types is sent and read back here, curly quotes and dashes in Subject,
/// in the body and in the HTML twin, by the app's own builder and reader.
@MainActor
final class TypingAsInMailTests: XCTestCase {

    /// As Smart Punctuation types them: ’ (U+2019) for every apostrophe,
    /// “ ” (U+201C, U+201D) and ‘ (U+2018) for quotes, an em dash (U+2014)
    /// for "--", and an en dash (U+2013).
    private let subject = "Don’t miss “Tosca” — Sunday’s at 2"
    private let words = "It’s on at two — don’t be late.\n“Bravo,” he said – ‘encore’."

    private let account = MailAccount(address: "carlo@example.org", username: "carlo@example.org",
                                      displayName: "Carlo", signature: "Sam",
                                      signatureHTML: "<div>Sam</div>")

    // MARK: - The fields

    /// Subject in both sheets: a capital to begin, corrections and Smart
    /// Punctuation, the system's own, which is what Mail's Subject has (its
    /// composer sets none of them). None of the four is off any more.
    func testSubjectTypesAsMailsDoes() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertTrue(code.contains("field.autocapitalizationType = .sentences "
                + "field.autocorrectionType = .default "
                + "field.smartDashesType = .default "
                + "field.smartQuotesType = .default"), file)
            for off in ["field.autocapitalizationType = .none", "field.autocorrectionType = .no",
                        "field.smartDashesType = .no", "field.smartQuotesType = .no"] {
                XCTAssertFalse(code.contains(off), "\(file): \(off)")
            }
        }
    }

    /// The body in both: Smart Punctuation as Settings has it, as Mail's.
    func testTheBodyTakesSmartPunctuation() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertTrue(code.contains("bodyView.smartDashesType = .default "
                + "bodyView.smartQuotesType = .default"), file)
            for off in ["bodyView.smartDashesType = .no", "bodyView.smartQuotesType = .no",
                        "bodyView.autocorrectionType = .no", "bodyView.autocapitalizationType = .none"] {
                XCTAssertFalse(code.contains(off), "\(file): \(off)")
            }
        }
    }

    /// To, Cc and Bcc keep theirs: the email keyboard, no capitals, no
    /// corrections, straight quotes. An address corrected or curled is an
    /// address that bounces.
    func testTheAddressRowsKeepTheirOwn() async throws {
        let field = try source("UI/RecipientField.swift")
        XCTAssertTrue(field.contains("input.keyboardType = .emailAddress "
            + "input.autocapitalizationType = .none "
            + "input.autocorrectionType = .no "
            + "input.smartDashesType = .no "
            + "input.smartQuotesType = .no"))
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertEqual(code.components(separatedBy: "autocapitalizationType =").count - 1, 1,
                           "\(file): Subject's alone")
        }
    }

    // MARK: - On the wire

    /// A letter with them in Subject and the body: every byte of it ASCII,
    /// Subject in UTF-8 encoded words that read back as typed, the text in
    /// quoted-printable UTF-8 and the HTML twin the same, each reading back
    /// with every curly quote and dash where he typed it.
    func testCurlyQuotesAndDashesGoOutAndReadBack() {
        var draft = Draft.blank(signature: account.signature)
        draft.to = ["owner@example.com"]
        draft.subject = subject
        draft.body = words + draft.body
        let html = AppleMailHTML.part(for: draft, account: account)
        XCTAssertNotNil(html, "the signature's markup makes a twin")
        let raw = RFC5322Builder.build(draft: draft, from: account, htmlBody: html)
        check(raw, html: true)
    }

    /// The share sheet's letter, its HTML made by `ShareLetter`, with his
    /// words above the link and the page's title as the subject.
    func testAShareWithThemGoesOutAndReadsBack() {
        let page = URL(string: "https://en.wikipedia.org/wiki/Tosca")!
        var draft = ShareLetter.draft(from: [.link(page, title: subject)],
                                      signature: account.signature)
        XCTAssertEqual(draft.subject, subject)
        draft.body = words + "\n" + draft.body
        let letter = ShareLetter.letter(for: draft, account: account)
        XCTAssertNotNil(letter.html)
        let raw = RFC5322Builder.build(draft: draft, from: account, htmlBody: letter.html)
        check(raw, html: true)
        XCTAssertTrue(MIMEDecoder.decodeMessage(raw).html?.contains(
            "<a href=\"\(page.absoluteString)\">") == true)
    }

    /// Searched for, the curly apostrophe stays in its word and the curly
    /// quotes mark a phrase, as B-105 reads them; the words go to the
    /// server as UTF-8 literals (`SearchLiteralTests`).
    func testASearchForTheSubjectFindsItsWords() {
        XCTAssertEqual(SearchCriteria.words(of: subject), ["Don’t", "miss", "Tosca", "Sunday’s", "at"])
    }

    // MARK: - Helpers

    private func check(_ raw: Data, html: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(raw.first { $0 > 0x7E && $0 != 0x0D && $0 != 0x0A }, "seven-bit on the wire",
                     file: file, line: line)
        let headers = MIMEDecoder.parseHeaders(raw)
        let encoded = MIMEDecoder.headerValue("Subject", in: headers) ?? ""
        XCTAssertTrue(encoded.hasPrefix("=?UTF-8?B?"), encoded, file: file, line: line)
        XCTAssertEqual(MIMEDecoder.decodeWord(encoded), subject, file: file, line: line)

        let decoded = MIMEDecoder.decodeMessage(raw)
        XCTAssertTrue(decoded.text?.hasPrefix(words + "\n") == true, decoded.text ?? "nil",
                      file: file, line: line)
        if html {
            let markup = decoded.html ?? ""
            for typed in ["It’s on at two — don’t be late.", "“Bravo,” he said – ‘encore’."] {
                XCTAssertTrue(markup.contains(typed), "\(typed) in \(markup)", file: file, line: line)
            }
        }
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.contains("text/plain; charset=utf-8"), file: file, line: line)
        if html {
            XCTAssertTrue(text.contains("text/html; charset=utf-8"), "the twin labelled as written",
                          file: file, line: line)
        }
        for straight in ["Don't", "It's", "don't"] {
            XCTAssertFalse(text.contains(straight), straight, file: file, line: line)
        }
    }

    private static let composer = "UI/ComposeViewController.swift"
    private static let share = "Share/ShareViewController.swift"

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
