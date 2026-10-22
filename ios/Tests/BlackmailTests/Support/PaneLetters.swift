import Foundation
@testable import Blackmail

/// The letters the reading pane's page is checked against
/// (`PanePageTests`), and a printed letter's page with it
/// (`PrintPageTests`, B-110): shapes of real mail, pictures known and not,
/// letters with nothing in them, plain text with markup's characters in
/// it, a newsletter, and replies with quotes.
enum PaneLetters {

    static func letter(text: String? = nil, html: String? = nil,
                        pictures: [String] = []) -> Message {
        let attachments = pictures.enumerated().map { i, cid in
            Attachment(id: "\(i + 2)", filename: "image\(i).png", mimeType: "image/png",
                       size: 2_000, contentID: cid)
        }
        return Message(id: "7/3", mailboxID: "INBOX", sender: "Sam Example <sam@example.com>",
                       senderAddress: "sam@example.com", to: ["me@example.com"], cc: [],
                       subject: "The garden", date: Date(timeIntervalSince1970: 1_790_000_000),
                       textBody: text, htmlBody: html, attachments: attachments)
    }

    static var all: [Message] {
        let pictures = ["logo@example.com"] + (0..<7).map { "photo\($0)@example.com" }
        return [
            // Shapes of real mail, as `DocumentWrapperTests` has them.
            letter(html: """
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "x">
            <html lang="en"><head><title>Garden club news</title>
            <style type="text/css">body { margin: 0 }</style></head>
            <body style="margin:0; padding:0;"><table class="wrap"><tr><td><p>The spring show
            is on the 12th.</p></td></tr></table></body></html>
            """),
            letter(html: "<HTML><HEAD>\r\n<META http-equiv=Content-Type content=\"text/html\">\r\n"
                   + "<STYLE>P.MsoNormal { MARGIN: 0cm }</STYLE></HEAD>\r\n<BODY lang=EN-GB>\r\n"
                   + "<DIV class=WordSection1><P class=MsoNormal>Dear Sam,</P></DIV></BODY></HTML>"),
            letter(text: "See you on Sunday.\n\nCarlo",
                   html: "<html><head></head><body style=\"overflow-wrap: break-word;\">"
                   + "<div dir=\"ltr\">See you on Sunday.<br><br><div>Carlo</div></div></body></html>"),
            letter(html: "<div dir=\"ltr\">Thanks for the photos.<div><br></div><div>Sam</div></div>"),
            letter(html: "<html><head><title>News</title></head><body><header><h1>Garden club</h1>"
                   + "</header><p>Look.</p></body></html>"),
            // Pictures: known, unknown, and a letter that is only a picture.
            letter(html: "<p>Logo: <img src=\"cid:logo@example.com\"> and <img src='CID:gone'></p>",
                   pictures: ["logo@example.com"]),
            letter(html: "<img src=\"cid:photo0@example.com\">", pictures: ["photo0@example.com"]),
            // Nothing in them, which the pane says in words.
            letter(html: "<html><body>  <br> </body></html>"),
            letter(text: " \n\n \t"),
            letter(),
            // Plain text: this app's own replies open with blank lines, and
            // text carries everything markup would take for its own.
            letter(text: "\n\nDear Sam,\n\nIt's <b>not</b> bold & it's \"quoted\" > here.\n"
                   + "\u{2028}é \u{1F4EE}\n\n> On Monday, Carlo wrote:\n> The roses?"),
            // The one with a link written in it (`linked`).
            letter(text: "\n\nhttps://example.com/a?b=1&c=2 </script>"),
            // A newsletter big enough to matter, in a debug build.
            letter(html: PanePageTests.newsletter(kilobytes: 48), pictures: pictures),
            letter(text: String(repeating: "A line of a long plain letter, <with> & more.\n", count: 800)),
            // A CRLF is one Character to Swift, so the trim never took it;
            // the decoder has made every line end LF by the time it gets here.
            letter(text: "\r\n\nDear Sam,"),
            // Replies, with quotes Mail draws a bar beside (B-101).
            letter(text: "Yes, Sunday.", html: PanePageTests.appleMailReply),
            letter(text: "Thanks!", html: PanePageTests.gmailReply),
        ]
    }
}
