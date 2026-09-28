import XCTest
@testable import Blackmail

/// Taking a sender's `<html>`/`<head>`/`<body>` off before the reading pane
/// puts the letter inside its own document.
///
/// Two properties matter and they pull in different directions. On the
/// mail that was already handled right, the output must not change by a
/// byte: the pane's CSS and the inline-image rewrite both run on it, and
/// "equivalent" HTML is not something anyone here can vouch for without
/// the iPad. And a body with HTML5 `<header>` elements, which the old head
/// pattern mistook for `<head>`, must keep them.
final class DocumentWrapperTests: XCTestCase {

    /// The stripping exactly as the reading pane did it before it moved,
    /// kept as the reference the new one has to agree with.
    private func previousStrip(_ html: String) -> String {
        var s = html
        for pattern in ["<!DOCTYPE[^>]*>", "</?html[^>]*>", "<head[^>]*>[\\s\\S]*?</head>",
                        "</?body[^>]*>"] {
            s = s.replacingOccurrences(of: pattern, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    /// Shapes of real mail, none of which contains a `<header>`.
    private let ordinaryDocuments = [
        // A template newsletter: doctype, meta, title, a stylesheet, and the
        // styled body that made the wrapper worth removing in the first place.
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
        // Outlook: upper case, attributes on every tag, Office namespaces.
        "<HTML xmlns:o=\"urn:schemas-microsoft-com:office:office\"><HEAD>\r\n"
            + "<META http-equiv=Content-Type content=\"text/html; charset=windows-1252\">\r\n"
            + "<STYLE>P.MsoNormal { MARGIN: 0cm }</STYLE></HEAD>\r\n"
            + "<BODY lang=EN-GB link=blue vLink=purple>\r\n"
            + "<DIV class=WordSection1><P class=MsoNormal>Dear Sam,</P></DIV></BODY></HTML>",
        // Apple Mail.
        "<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"></head>"
            + "<body style=\"overflow-wrap: break-word; -webkit-nbsp-mode: space;\">"
            + "<div dir=\"ltr\">See you on Sunday.<br><br><div>Carlo</div></div></body></html>",
        // Gmail sends a bare fragment with no wrapper at all.
        "<div dir=\"ltr\">Thanks for the photos.<div><br></div><div>Sam</div></div>",
        // A head tag with attributes over several lines, and a tab before `>`.
        "<html>\n<head\n  lang=\"en\"\t>\n<title>x</title></head>\n<body>\n<p>one</p>\n</body></html>",
        // Empty head, empty body, a self-closing head, and nothing at all.
        "<html><head></head><body></body></html>",
        "<head/><p>After a self-closing head.</p>",
        "",
        // A forwarded letter quoting a whole document of its own.
        "<html><head><title>1</title></head><body><p>Look at this.</p><blockquote>"
            + "<html><head><title>2</title><style>p{}</style></head><body><p>Quoted.</p></body></html>"
            + "</blockquote></body></html>",
    ]

    func testOrdinaryMailComesOutByteForByteAsItDidBefore() {
        for document in ordinaryDocuments {
            XCTAssertEqual(DocumentWrapper.stripped(from: document), previousStrip(document),
                           document)
        }
    }

    func testTheWrapperIsWhatComesOff() {
        let stripped = DocumentWrapper.stripped(from: ordinaryDocuments[0])
        XCTAssertFalse(stripped.contains("<!DOCTYPE"))
        XCTAssertFalse(stripped.lowercased().contains("<html"))
        XCTAssertFalse(stripped.contains("<body"))
        XCTAssertFalse(stripped.contains("<title>"))
        XCTAssertFalse(stripped.contains(".wrap"))
        XCTAssertTrue(stripped.contains("<table class=\"wrap\"><tr><td><p>The spring show is on the 12th.</p>"))
    }

    func testHeaderElementsAreNotMistakenForTheHead() {
        let html = "<html><head><title>News</title></head><body>"
            + "<header class=\"masthead\"><h1>Garden club</h1></header>"
            + "<p>The spring show is on the 12th.</p>"
            + "<header><h2>Tickets</h2></header><p>Five pounds.</p>"
            + "</body></html>"
        XCTAssertEqual(DocumentWrapper.stripped(from: html),
                       "<header class=\"masthead\"><h1>Garden club</h1></header>"
                       + "<p>The spring show is on the 12th.</p>"
                       + "<header><h2>Tickets</h2></header><p>Five pounds.</p>")
    }

    func testAHeaderBeforeAQuotedDocumentNoLongerTakesTheLetterWithIt() {
        // The old pattern read `<header>` as a head and found a `</head>` to
        // end it at: the quoted document's. Everything between went.
        let html = "<html><head><title>1</title></head><body>"
            + "<header><h1>Garden club</h1></header><p>Look at this.</p><blockquote>"
            + "<html><head><title>2</title></head><body><p>Quoted.</p></body></html>"
            + "</blockquote></body></html>"
        XCTAssertEqual(previousStrip(html), "<p>Quoted.</p></blockquote>")
        XCTAssertEqual(DocumentWrapper.stripped(from: html),
                       "<header><h1>Garden club</h1></header><p>Look at this.</p>"
                       + "<blockquote><p>Quoted.</p></blockquote>")
    }

    func testOnlyAWholeTagNameCounts() {
        // A tag name ends at white space, `/` or `>`. Custom elements are
        // allowed hyphens, so `<head-line>` is somebody's element, not a head.
        for html in ["<head-line>Big news</head-line><p>x</p></head>",
                     "<headline>Big news</headline><p>x</p></head>"] {
            XCTAssertEqual(DocumentWrapper.stripped(from: html), html)
        }
    }
}
