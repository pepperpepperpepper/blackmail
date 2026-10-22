import Foundation

extension MIMEDecoder {

    /// The header lines of a letter forwarded inline as message/rfc822,
    /// drawn above its words when there are words outside it, as Mail
    /// draws the forwarded letter under the note (B-114). Before, a note
    /// and a letter forwarded after it showed the note alone: the letter's
    /// words, its From and its Subject were nowhere, with no row to open.
    ///
    /// Mail's form, as this app's own Forward writes it (`Draft.forwarding`,
    /// B-050): "Begin forwarded message:", a blank line, then From, Date,
    /// To, Cc when there is one, and Subject, a blank line after them; in
    /// HTML each label bold, and the subject's value bold too
    /// (`AppleMailHTML`). A field the letter has nothing in is left out,
    /// where a Forward of his has every one.
    struct ForwardedFields: Equatable {
        /// Each address as its header gives it, name and all.
        var from: [String] = []
        var date: Date?
        var to: [String] = []
        var cc: [String] = []
        var subject: String?

        /// Each line's label and value, in Mail's order.
        var lines: [(label: String, value: String)] {
            func names(_ list: [String]) -> String {
                list.map(MailFormat.addressForQuoting).joined(separator: ", ")
            }
            var out: [(label: String, value: String)] = []
            if !from.isEmpty { out.append(("From:", names(from))) }
            if let date { out.append(("Date:", MailFormat.forwardedDate(date))) }
            if !to.isEmpty { out.append(("To:", names(to))) }
            if !cc.isEmpty { out.append(("Cc:", names(cc))) }
            if let subject, !subject.isEmpty { out.append(("Subject:", subject)) }
            return out
        }

        /// As plain words, ending in a blank line.
        var text: String {
            "Begin forwarded message:\n\n"
                + lines.map { $0.label + " " + $0.value + "\n" }.joined() + "\n"
        }

        /// As HTML, a blank line above and below.
        var html: String {
            "<div dir=\"ltr\"><br>Begin forwarded message:<br><br></div><div dir=\"ltr\">"
                + lines.map { line in
                    let value = QuotedMarkup.escaped(line.value)
                    return "<b>" + line.label + "</b> "
                        + (line.label == "Subject:" ? "<b>" + value + "</b>" : value) + "<br>"
                }.joined()
                + "<br></div>"
        }
    }
}
