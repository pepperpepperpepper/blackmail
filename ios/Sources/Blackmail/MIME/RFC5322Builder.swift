import Foundation

/// Turns a `Draft` into the exact bytes that follow SMTP's `DATA`.
///
/// Pure data: no I/O, no actor, no state. The SMTP client owns the envelope
/// (MAIL FROM / RCPT TO), the dot-stuffing and the terminating `.`; this owns
/// everything between them. Keeping the split there is what makes the whole
/// message format testable on Linux without a server.
///
/// It plans a letter rather than making it (`plan`, B-070): every header,
/// boundary and line of text, and a place for each file's base64. Reading
/// the files and making their base64 belong to `LetterBytes`, so Send can
/// make the letter as it goes, from the files on the disk, without ever
/// holding it whole. `build` is the plan made whole, for a draft.
///
/// Three rules drive almost every decision below, and all three are the kind
/// of thing that only bites in production:
///
/// 1. **Bcc never appears in the message.** It goes in RCPT TO and nowhere
///    else. A Bcc header that survives into the bytes shows every blind
///    recipient to every other one, which is a privacy breach rather than a
///    formatting slip, so there is deliberately no code path here that can
///    emit one — `draft.bcc` is not read at all.
/// 2. **Everything is CRLF.** Mixed endings get a message rejected, silently
///    truncated, or re-wrapped by a strict relay. The body is normalised
///    before it is encoded, and every join in here uses `crlf`.
/// 3. **Nothing user-typed reaches a header raw.** A recipient field
///    containing a newline would otherwise inject arbitrary headers (a Bcc,
///    another To). `headerSafe` folds CR, LF and NUL to a space before any
///    value is used.
enum RFC5322Builder {

    private static let crlf = "\r\n"

    /// RFC 5322 caps a line at 998 characters and says it SHOULD be under 78.
    /// We hold to 78 because RFC 5322 recommends it and because some ancient
    /// relays still wrap at 80 themselves, which corrupts a longer line.
    private static let headerLineLimit = 78

    // MARK: - Entry point

    /// Builds one complete message: `plan` made whole, from the files'
    /// bytes. What a draft's APPEND sends, byte for byte what it always
    /// was; Send makes the same plan as it goes instead (`Submission`).
    ///
    /// - Parameters:
    ///   - attachments: already-loaded bytes. Reading files is the caller's
    ///     job, so this stays synchronous and pure.
    ///   - bodyPictures: his photos in the letter, already loaded, as
    ///     `plan`'s `inlineFiles` with their bytes (B-109).
    ///   - the rest: as `plan`'s.
    static func build(draft: Draft,
                      from: MailAccount,
                      date: Date = Date(),
                      messageID: String? = nil,
                      inReplyToHeaders: (messageID: String, references: String?)? = nil,
                      attachments: [(filename: String, mimeType: String, data: Data)] = [],
                      includeBcc: Bool = false,
                      htmlBody: String? = nil,
                      inlineImages: [(contentID: String, filename: String,
                                      mimeType: String, data: Data)] = [],
                      bodyPictures: [(contentID: String, filename: String,
                                      mimeType: String, data: Data)] = [],
                      boundaryToken: () -> String = randomToken) -> Data {
        plan(draft: draft, from: from, date: date, messageID: messageID,
             inReplyToHeaders: inReplyToHeaders,
             files: attachments.map { ($0.filename, $0.mimeType) },
             includeBcc: includeBcc, htmlBody: htmlBody, inlineImages: inlineImages,
             inlineFiles: bodyPictures.map { ($0.contentID, $0.filename, $0.mimeType) },
             boundaryToken: boundaryToken)
            // The plan's places: the photos first, then the files.
            .rendered(from: bodyPictures.map(\.data) + attachments.map(\.data))
    }

    /// Plans one complete message (B-070): its text as bytes, and each of
    /// `files` as a place for that file's base64, by its index.
    ///
    /// - Parameters:
    ///   - messageID: pass one only to make a build reproducible (tests, or a
    ///     resend that must keep its identity). Left nil, a fresh UUID-based
    ///     id is minted against the sender's domain.
    ///   - inReplyToHeaders: the parent's Message-ID, plus the parent's own
    ///     References header if it had one; for a reply reopened from
    ///     Drafts, the draft's own In-Reply-To and References, the parent
    ///     already last in them. Supplying this is the entire
    ///     difference between a reply that threads and a reply that starts a
    ///     new conversation in the recipient's client. Only the ids in them
    ///     are written (`messageIDs`).
    ///   - files: each file's name and type. Its bytes are not needed: the
    ///     boundaries are never looked for in base64, which cannot hold
    ///     one (below).
    ///   - htmlBody: the same letter as markup, when it has one. Passing it
    ///     turns the body into `multipart/alternative` with the plain text
    ///     first and the markup second — RFC 2046 says the last alternative
    ///     is the richest and clients render the last one they understand,
    ///     so the order is not cosmetic. Left nil, nothing about the output
    ///     changes, which is what keeps the quarter of his mail that has
    ///     nothing rich in it going out as plain text the way Mail sends it.
    ///   - inlineFiles: his photos the markup shows under his words, each by
    ///     its Content-ID (B-109): parts inside the related set beside
    ///     `inlineImages`, before them, each with `Content-ID` and
    ///     `Content-Disposition: inline` and its file's name as a file's is
    ///     written (`partName`), but each a place for its file's base64 as a
    ///     file is, never its bytes. The plan numbers them first, from 0,
    ///     and `files` after them, so the places come in the order of their
    ///     numbers. With no `htmlBody` there is nothing to show them in, and
    ///     each goes as a file, under the letter, rather than not at all.
    ///   - boundaryToken: where the boundaries' randomness comes from. Pass
    ///     one only to make a build reproducible; see `uniqueBoundary`.
    static func plan(draft: Draft,
                     from: MailAccount,
                     date: Date = Date(),
                     messageID: String? = nil,
                     inReplyToHeaders: (messageID: String, references: String?)? = nil,
                     files: [(filename: String, mimeType: String)] = [],
                     includeBcc: Bool = false,
                     htmlBody: String? = nil,
                     inlineImages: [(contentID: String, filename: String,
                                     mimeType: String, data: Data)] = [],
                     inlineFiles: [(contentID: String, filename: String,
                                    mimeType: String)] = [],
                     boundaryToken: () -> String = randomToken) -> LetterPlan {
        // Inline images are the HTML twin's companions — a `cid:` reference
        // only means anything inside markup — so without an `htmlBody` there
        // is nowhere for them to be referred from and they are dropped
        // rather than sent as orphan parts. His photos are not: they are his
        // files, and a photo he attached never stays behind (above).
        let inline = htmlBody == nil ? [] : inlineImages

        // MARK: Body and attachment payloads first
        //
        // They are encoded before the headers are written because the
        // multipart boundary has to be checked against the finished payloads,
        // not against the raw input: quoted-printable and base64 both invent
        // characters that were not in the source.
        let encodedBody = quotedPrintable(draft.body)
        // Quoted-printable for the markup too, not 8bit: its attribution
        // line carries U+202F before AM or PM, as the iPad's formatter
        // writes it from iPadOS 17 on (B-119), and a single `<div>` holding
        // a long paragraph runs well past RFC 5322's 998-octet ceiling, which a
        // strict relay is entitled to wrap wherever it likes — through the
        // middle of a tag.
        let encodedHTML = htmlBody.map(quotedPrintable)
        // A file's name and type only. Its base64 is made where the letter
        // is made, a block at a time, from the file itself (`LetterBytes`):
        // never every file encoded at once, nor one file whole. A letter of
        // 25 MB of photos built whole in the share extension was about
        // seven times that at its peak, in an extension allowed about
        // 120 MB (B-036), and five times once each file's base64 was made
        // only as it was written. Since B-070 it is never held whole.
        let encodedAttachments: [(filename: String, mimeType: String)] =
            files.map { att in
                (filename: partName(att.filename), mimeType: partType(att.mimeType))
            }
        // His photos in the body: named and typed as his files are, since
        // that is what they are, and each under the Content-ID the markup
        // shows it by, which `AppleMailHTML` made (B-109).
        let encodedInlineFiles: [(contentID: String, filename: String, mimeType: String)] =
            inlineFiles.map { file in
                (contentID: contentIDValue(file.contentID), filename: partName(file.filename),
                 mimeType: partType(file.mimeType))
            }
        // With no markup to show them in, they go as files (above): every
        // one of them, numbered first all the same.
        let shownInline = htmlBody == nil ? [] : encodedInlineFiles
        let underLetter = htmlBody == nil ? encodedInlineFiles : []

        let encodedInline: [(contentID: String, filename: String,
                             mimeType: String, base64: String)] = inline.map { img in
            let id = contentIDValue(img.contentID)
            let name = headerSafe(img.filename).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "")
            let mime = headerSafe(img.mimeType).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
            return (contentID: id,
                    filename: name.isEmpty ? "inline.png" : name,
                    mimeType: mime.isEmpty ? "application/octet-stream" : mime,
                    base64: base64Wrapped(img.data))
        }

        // Every payload the boundaries have to avoid, in one place, so a
        // boundary can never collide with content in a part that was added
        // after the check was written.
        //
        // Except the base64 payloads, and only because a boundary provably
        // cannot occur in one: every boundary has `_` in it, and base64 is
        // letters, digits, `+`, `/` and `=`, wrapped with CRLF
        // (`base64Wrapped`, the standard alphabet, never base64url). Scanning
        // them anyway was most of the time a photo letter took to build, a
        // pass over every byte of every picture for each boundary, and it
        // could never find anything. The text parts, and the names and types
        // that go into the part headers, are still scanned: they hold what he
        // typed or what a file was called, and either can hold anything.
        var candidates = [encodedBody]
        if let encodedHTML { candidates.append(encodedHTML) }
        for att in encodedAttachments {
            candidates.append(att.filename)
            candidates.append(att.mimeType)
        }
        for img in encodedInline {
            candidates.append(img.contentID)
            candidates.append(img.filename)
            candidates.append(img.mimeType)
        }
        for file in encodedInlineFiles {
            candidates.append(file.contentID)
            candidates.append(file.filename)
            candidates.append(file.mimeType)
        }

        // Up to three nested multiparts. With everything present the tree is
        //
        //   mixed > related > alternative > {plain, html} + inline + files
        //
        // The alternatives have to be siblings of each other and not of the
        // files, or a reader picks the photograph as an alternative
        // rendering of the letter and shows only that. And the `cid:`
        // images have to live INSIDE the related set with the markup that
        // references them — that is what "related" means, and it is why a
        // client is entitled to treat the pair as one displayable unit
        // rather than a letter with a stray picture stapled to it.
        let alternativeBoundary = encodedHTML == nil
            ? nil : uniqueBoundary(avoiding: candidates, token: boundaryToken)
        if let alternativeBoundary { candidates.append(alternativeBoundary) }
        let relatedBoundary = (encodedHTML == nil || (encodedInline.isEmpty && shownInline.isEmpty))
            ? nil : uniqueBoundary(avoiding: candidates, token: boundaryToken)
        if let relatedBoundary { candidates.append(relatedBoundary) }
        let boundary = (encodedAttachments.isEmpty && underLetter.isEmpty)
            ? nil : uniqueBoundary(avoiding: candidates, token: boundaryToken)

        // MARK: Headers

        var headers = ""

        let senderAddress: String = {
            let a = headerSafe(from.address).trimmingCharacters(in: .whitespaces)
            return a.isEmpty ? headerSafe(from.username).trimmingCharacters(in: .whitespaces) : a
        }()
        let senderName = headerSafe(from.displayName).trimmingCharacters(in: .whitespaces)
        headers += headerLine("From", addressValue(name: senderName.isEmpty ? nil : senderName,
                                                   address: senderAddress))

        let to = addressListValue(draft.to)
        if !to.isEmpty { headers += headerLine("To", to) }

        let cc = addressListValue(draft.cc)
        if !cc.isEmpty { headers += headerLine("Cc", cc) }

        // Bcc is emitted ONLY when saving to Drafts, never when sending.
        //
        // Those are opposite requirements and both are real. On the wire a
        // surviving Bcc header shows every blind recipient to everyone, so
        // `send` must not carry one. But a DRAFT is not delivered — it is
        // stored for him to come back to — and omitting it there silently
        // drops a recipient he deliberately chose: he Bccs someone, is
        // interrupted, reopens the letter, and the person is simply gone
        // with nothing to say so. Storing it is what Mail does too.
        if includeBcc {
            let bcc = addressListValue(draft.bcc)
            if !bcc.isEmpty { headers += headerLine("Bcc", bcc) }
        }

        // On the SEND path draft.bcc is still intentionally unread; see
        // `includeBcc` above and the type comment.

        let subject = headerSafe(draft.subject).trimmingCharacters(in: .whitespaces)
        if !subject.isEmpty {
            headers += headerLine("Subject", encodeIfNeeded(subject))
        }

        headers += headerLine("Date", rfc5322Date(date))
        headers += headerLine("Message-ID", angled(messageID ?? freshMessageID(for: senderAddress)))

        if let reply = inReplyToHeaders {
            // The ids alone, each `<…>`, from whatever the header held: a
            // reply's parent is a Message-ID as the parent wrote it, and a
            // reply reopened from Drafts brings the draft's own In-Reply-To
            // and References, which another client may have written with a
            // comment, several ids, or a line break in them (B-064).
            let parents = messageIDs(in: reply.messageID)
            if !parents.isEmpty {
                headers += headerLine("In-Reply-To", parents.joined(separator: " "))
                // References is the whole ancestry, oldest first, with the
                // immediate parent last. Threading in Gmail and Apple Mail
                // walks this chain; In-Reply-To alone only links one hop and
                // loses the thread as soon as a middle message is missing.
                // A reply reopened from Drafts has its parent in References
                // already, and it is not added again; one another client
                // listed earlier in it is moved to the end, where readers
                // look for it.
                let parentSet = Set(parents)
                let references = messageIDs(in: reply.references ?? "")
                    .filter { !parentSet.contains($0) } + parents
                headers += headerLine("References", references.joined(separator: " "))
            }
        }

        headers += headerLine("MIME-Version", "1.0")

        if let boundary {
            headers += headerLine("Content-Type", "multipart/mixed; boundary=\"\(boundary)\"")
        } else if let relatedBoundary {
            // `type=` names the root part's kind, so a reader knows the
            // alternatives — not a stray image — are the letter.
            headers += headerLine("Content-Type",
                                  "multipart/related; boundary=\"\(relatedBoundary)\"; "
                                  + "type=\"multipart/alternative\"")
        } else if let alternativeBoundary {
            headers += headerLine("Content-Type",
                                  "multipart/alternative; boundary=\"\(alternativeBoundary)\"")
        } else {
            headers += headerLine("Content-Type", "text/plain; charset=utf-8")
            headers += headerLine("Content-Transfer-Encoding", "quoted-printable")
        }

        // MARK: Body

        /// The two renderings of the letter, alternatives in their own
        /// multipart. Plain first, markup second — RFC 2046 §5.1.4 puts the
        /// best rendering last, and a client shows the last alternative it
        /// can handle. The wrong order sends everyone the plain text.
        ///
        /// With no markup, the plain text alone under a part's header, for
        /// the multipart/mixed of a plain letter with files. A letter of one
        /// part does not use it (below).
        func alternativeParts() -> String {
            guard let alternativeBoundary, let encodedHTML else {
                var out = headerLine("Content-Type", "text/plain; charset=utf-8")
                out += headerLine("Content-Transfer-Encoding", "quoted-printable")
                out += crlf
                return out + terminated(encodedBody)
            }
            var out = "--" + alternativeBoundary + crlf
            out += headerLine("Content-Type", "text/plain; charset=utf-8")
            out += headerLine("Content-Transfer-Encoding", "quoted-printable")
            out += crlf
            out += terminated(encodedBody)

            out += "--" + alternativeBoundary + crlf
            out += headerLine("Content-Type", "text/html; charset=utf-8")
            out += headerLine("Content-Transfer-Encoding", "quoted-printable")
            out += crlf
            out += terminated(encodedHTML)
            out += "--" + alternativeBoundary + "--" + crlf
            return out
        }

        /// The headers of one part the markup shows by `cid:`, inside the
        /// related set: a picture of the signature's or the quote's, or one
        /// of his photos (B-109).
        ///
        /// `Content-Disposition: inline`, because that is what tells the
        /// READING side this picture belongs in the body flow rather than
        /// stapled underneath it — Mail's signature images and Apple Mail's
        /// inserted photographs both arrive exactly this shape.
        func inlineHeaders(_ contentID: String, _ filename: String, _ mimeType: String) -> String {
            var out = headerLine("Content-Type", "\(mimeType); name=\"\(filename)\"")
            out += headerLine("Content-Transfer-Encoding", "base64")
            out += headerLine("Content-ID", "<\(contentID)>")
            out += headerLine("Content-Disposition", "inline; filename=\"\(filename)\"")
            return out
        }

        /// One `cid:` image, as a part inside the related set.
        func inlinePart(_ img: (contentID: String, filename: String,
                                mimeType: String, base64: String),
                        within rel: String) -> String {
            var out = "--" + rel + crlf
            out += inlineHeaders(img.contentID, img.filename, img.mimeType)
            out += crlf
            return out + terminated(img.base64)
        }

        /// The headers of a file's part under the letter.
        func fileHeaders(_ filename: String, _ mimeType: String) -> String {
            let name = encodeIfNeeded(filename)
            // `name=` on the Content-Type is obsolete but harmless, and old
            // clients that ignore Content-Disposition entirely still find a
            // filename there.
            var out = headerLine("Content-Type", "\(mimeType); name=\"\(name)\"")
            out += headerLine("Content-Transfer-Encoding", "base64")
            out += headerLine("Content-Disposition", "attachment; filename=\"\(name)\"")
            return out
        }

        // The letter, as text, and a place for each file's base64 where its
        // part's headers end, which never ends in CRLF; the CRLF after it
        // begins the next delimiter, as `terminated` ends an inline
        // image's. `text` is what is not yet a piece.
        var pieces: [LetterPlan.Piece] = []
        var text = headers + crlf     // the blank line that ends the header block
        func place(_ index: Int) {
            pieces.append(.text(Data(text.utf8)))
            pieces.append(.file(index))
            text = crlf
        }

        // `containerHeaders` are the letter's own headers as a part, when
        // it is nested inside the multipart/mixed, and empty when it IS
        // the message.
        var containerHeaders = ""
        if let relatedBoundary, alternativeBoundary != nil {
            containerHeaders = headerLine(
                "Content-Type",
                "multipart/related; boundary=\"\(relatedBoundary)\"; "
                + "type=\"multipart/alternative\"")
        } else if let alternativeBoundary {
            // A multipart nested inside another multipart must declare its
            // own Content-Type. An earlier cut of this built the tree but
            // left the alternative's header off, which reads as a part with
            // no headers — the sub-parts' headers then belong to its BODY,
            // and a strict reader shows the letter's own Content-Type lines
            // as text. Caught by a test that greps for exactly this header.
            containerHeaders = headerLine(
                "Content-Type",
                "multipart/alternative; boundary=\"\(alternativeBoundary)\"")
        }

        if let boundary {
            text += "--" + boundary + crlf
            if !containerHeaders.isEmpty {
                text += containerHeaders     // ends in its own CRLF
                text += crlf                 // part headers ↵ body separator
            }
        }

        // The letter as it sits inside the message: either the alternatives
        // alone, or the alternatives AND their `cid:` images inside a
        // related set — the markup and the pictures it names travel as one
        // unit, which is what makes a client resolve them for the reader
        // instead of showing a box. His photos come first among them, as
        // they come first in the markup, each read from its file as it
        // goes (B-109).
        if let relatedBoundary, let alternativeBoundary {
            text += "--" + relatedBoundary + crlf
            text += headerLine("Content-Type",
                               "multipart/alternative; boundary=\"\(alternativeBoundary)\"")
            text += crlf
            text += alternativeParts()
            for (index, file) in shownInline.enumerated() {
                text += "--" + relatedBoundary + crlf
                text += inlineHeaders(file.contentID, encodeIfNeeded(file.filename), file.mimeType)
                text += crlf
                place(index)
            }
            for img in encodedInline {
                text += inlinePart(img, within: relatedBoundary)
            }
            text += "--" + relatedBoundary + "--" + crlf
        } else if alternativeBoundary == nil, boundary == nil {
            // A letter of one part, plain text alone, is its encoded text
            // and nothing more. Its Content-Type and transfer encoding are
            // the message's own header lines, above. `alternativeParts` is
            // the text as a part of a multipart/mixed, with those two lines
            // as the part's header. Written here, they were the first two
            // lines of the letter, in the list, in the pane and in every
            // reader's client, and a draft reopened took them up as words
            // and wrapped them again at each save (B-068). Nothing follows
            // the last line, so a draft comes back as he left it; SMTP ends
            // the line itself (`DataStuffer.finish`).
            text += encodedBody
        } else {
            text += alternativeParts()
        }

        guard let boundary else {
            pieces.append(.text(Data(text.utf8)))
            return LetterPlan(pieces: pieces)
        }

        // Each file is its part's headers, as text, and then a place for
        // its base64: his photos first when there is no markup to show them
        // in, numbered first as they are, then the files.
        for (index, file) in underLetter.enumerated() {
            text += "--" + boundary + crlf
            text += fileHeaders(file.filename, file.mimeType)
            text += crlf
            place(index)
        }
        for (index, att) in encodedAttachments.enumerated() {
            text += "--" + boundary + crlf
            text += fileHeaders(att.filename, att.mimeType)
            text += crlf
            place(encodedInlineFiles.count + index)
        }

        text += "--" + boundary + "--" + crlf
        pieces.append(.text(Data(text.utf8)))
        return LetterPlan(pieces: pieces)
    }

    // MARK: - Dates

    /// `Thu, 18 Sep 2026 14:03:11 +0100`.
    ///
    /// `en_US_POSIX` is not decoration. With the device locale, a phone set to
    /// French emits `jeu., 18 sept. 2026` and a strict server answers 550 — and
    /// the bug only ever reproduces on that one user's phone.
    static func rfc5322Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return f.string(from: date)
    }

    // MARK: - Identity

    static func freshMessageID(for address: String) -> String {
        // The domain half should be one we "own", and the sender's domain is
        // the closest thing to that. Gmail rewrites the id on submission
        // anyway, so this matters mainly for the copy we keep and for the
        // In-Reply-To of a reply that comes straight back.
        let domain = address.split(separator: "@").last.map(String.init) ?? "localhost"
        return "<\(UUID().uuidString.lowercased())@\(domain.isEmpty ? "localhost" : domain)>"
    }

    /// Wraps a bare id in angle brackets, tolerating one that already has them.
    /// Callers hand us Message-IDs copied out of other people's headers, and
    /// roughly half of the sources in the wild include the brackets.
    static func angled(_ id: String) -> String {
        var t = headerSafe(id).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "" }
        if !t.hasPrefix("<") { t = "<" + t }
        if !t.hasSuffix(">") { t += ">" }
        return t
    }

    /// The message ids in an In-Reply-To or a References, each `<…>`, once
    /// each, in the order written.
    ///
    /// What a reply's threading headers are made of (B-064). A fresh reply
    /// hands over its parent's Message-ID and References as the parent
    /// wrote them; a reply reopened from Drafts, the draft's own
    /// In-Reply-To and References, which another client may have written
    /// in any of the shapes mail has used:
    ///
    /// - several ids, a letter answering more than one: each is kept;
    /// - a comment or a phrase beside the id, `<id> (Jane's letter of
    ///   Monday)`, as older clients wrote: left out;
    /// - an id folded over two lines: its white space is taken out;
    /// - an id without its brackets, as some senders write a Message-ID:
    ///   bracketed, when it is the whole value, one word with an `@` in it;
    /// - nothing like an id, `Your letter of Monday`: no id at all, and the
    ///   reply then claims no parent.
    ///
    /// White space, control characters and line breaks inside an id, U+0085,
    /// U+2028 and U+2029 among them, are taken out, and outside one they
    /// only separate. So whatever line break the header held, each id is
    /// one word on one line, and nothing after it can become a header of
    /// its own.
    static func messageIDs(in raw: String) -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []
        func add(_ id: String) {
            guard id.count > 2, seen.insert(id).inserted else { return }
            ids.append(id)
        }
        func separates(_ s: Unicode.Scalar) -> Bool {
            s.properties.isWhitespace || s.properties.generalCategory == .control
        }

        // The id being read, after its `<`; nil outside one.
        var id: String.UnicodeScalarView?
        var bracketed = false
        // Outside an id: inside a comment, how deep, or a quoted phrase,
        // and whether the last character there was a backslash.
        var depth = 0
        var quoted = false
        var escaped = false
        for s in raw.unicodeScalars {
            if var current = id {
                switch s {
                case ">":
                    add("<" + String(current) + ">")
                    id = nil
                case "<":
                    // The one before was never closed: read from here.
                    id = String.UnicodeScalarView()
                default:
                    if !separates(s) {
                        current.append(s)
                        id = current
                    }
                }
            } else if escaped {
                escaped = false
            } else if quoted {
                if s == "\\" { escaped = true } else if s == "\"" { quoted = false }
            } else if depth > 0 {
                switch s {
                case "\\": escaped = true
                case "(": depth += 1
                case ")": depth -= 1
                default: break
                }
            } else {
                switch s {
                case "<":
                    id = String.UnicodeScalarView()
                    bracketed = true
                case "(": depth = 1
                case "\"": quoted = true
                default: break
                }
            }
        }
        guard !bracketed else { return ids }
        let words = raw.unicodeScalars.split(whereSeparator: separates).map(String.init)
        if words.count == 1, let word = words.first, word.contains("@"),
           !word.contains(where: { "<>()\"".contains($0) }) {
            add("<" + word + ">")
        }
        return ids
    }

    // MARK: - Addresses

    /// A To, Cc or Bcc: each entry split as the composer's field is split,
    /// at a comma or a ";" between addresses (`MailFormat.addresses(in:)`),
    /// as `Submission.recipients` splits it for the envelope, so the header
    /// names exactly whom the letter goes to, joined by commas. An entry
    /// kept with a ";" after it, "jane@example.com;", went into the header
    /// as written, with a ";" that ends a group and no group begun (B-081).
    private static func addressListValue(_ raw: [String]) -> String {
        raw.flatMap(MailFormat.addresses(in:)).compactMap(recipient).joined(separator: ", ")
    }

    /// Accepts whatever the compose field contains: `jane@x.com`,
    /// `Jane Smith <jane@x.com>`, `"Smith, Jane" <jane@x.com>`. Anything it
    /// cannot make sense of is passed through as a bare address rather than
    /// dropped — a message that goes to a slightly odd address beats one that
    /// silently loses a recipient.
    ///
    /// Read from the entry's first line (`recipientLine`), as the envelope
    /// reads it, so that the header names whom the letter goes to.
    private static func recipient(_ raw: String) -> String? {
        let t = headerSafe(recipientLine(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        guard let open = t.lastIndex(of: "<"),
              let close = t.lastIndex(of: ">"),
              open < close else {
            return addressValue(name: nil, address: t)
        }

        let address = String(t[t.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return addressValue(name: nil, address: t) }

        var name = String(t[t.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") {
            // The name inside the quotes, a quoted pair as the character it
            // stands for, before `addressValue` quotes it again. Left as it
            // was, `"Sam \"The Gardener\""` went out with its backslashes
            // doubled, and the name arrived with them in it. A reply keeps
            // its recipients' names since B-061, so such a name now comes
            // from the letter replied to as well as from his typing.
            var unescaped = ""
            var escaped = false
            for c in name.dropFirst().dropLast() {
                if escaped || c != "\\" {
                    unescaped.append(c)
                    escaped = false
                } else {
                    escaped = true
                }
            }
            name = unescaped
        }
        // A name that is only the address again, in any letter case, goes
        // out as the bare address, as Mail sends it (B-076): `"jane@example.com"
        // <jane@example.com>` is `jane@example.com`.
        let named = !name.isEmpty
            && name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(address) != .orderedSame
        // An address alone, out of its brackets, that would read as more
        // than one, `a;b@example.com` from `<a;b@example.com>`, keeps them,
        // so the header names the one address the envelope goes to, and is
        // not read back as "a" and "b@example.com" (B-081).
        if !named, MailFormat.addresses(in: address).count > 1 { return "<\(address)>" }
        return addressValue(name: named ? name : nil, address: address)
    }

    /// The part of a recipient entry the letter is addressed by: the entry
    /// up to its first line break (`Character.isNewline`), blanks around it
    /// left out. The header's To and Cc are read from this, and so is the
    /// envelope's RCPT TO (`SMTPClient.envelopeAddress`), which is why it is
    /// one function: the two once read an entry broken over lines
    /// differently, the envelope its first line and the header all of it,
    /// so that `sam@example.org<LF><other@example.net>` went to Sam with
    /// other@example.net in its header, and a name broken by U+2028 or
    /// U+0085, which a reply copied from the letter it answered, went to
    /// the name's first word with the right address in the header. A
    /// reply's entries are on one line since (`MailFormat.recipient(name:
    /// address:)`); this is for whatever else puts a line break in a field,
    /// a `mailto:` link's `%0A` among them.
    static func recipientLine(_ entry: String) -> String {
        String(entry.trimmingCharacters(in: .whitespacesAndNewlines).prefix { !$0.isNewline })
    }

    /// One `name-addr`, with the display name quoted or RFC 2047 encoded as
    /// needed.
    private static func addressValue(name: String?, address: String) -> String {
        guard let name, !name.isEmpty else { return address }

        if needsEncoding(name) {
            // An encoded word may not live inside a quoted string (RFC 2047
            // §5), so a non-ASCII display name is emitted unquoted. That is
            // correct: the encoded word is an atom as far as the parser is
            // concerned, even though it contains `?` and `=`.
            return encodedWords(name) + " <\(address)>"
        }

        let specials = "()<>@,;:\\\".[]"
        if name.contains(where: { specials.contains($0) }) {
            let quoted = name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(quoted)\" <\(address)>"
        }
        return "\(name) <\(address)>"
    }

    // MARK: - RFC 2047

    static func needsEncoding(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value > 126 || $0.value < 32 }
    }

    /// Leaves plain ASCII alone (readable in a raw dump, and no decoder to go
    /// wrong) and base64-encodes anything else.
    static func encodeIfNeeded(_ text: String) -> String {
        needsEncoding(text) ? encodedWords(text) : text
    }

    /// `=?UTF-8?B?…?=`, split into as many words as it takes.
    ///
    /// An encoded word may not exceed 75 characters, so a long subject becomes
    /// several of them separated by a space; a decoder joins adjacent encoded
    /// words and drops the whitespace between them, and the header folder
    /// below is free to break the line at those same spaces. Chunking is by
    /// `Character`, never by byte: splitting a multi-byte scalar (or a
    /// combining sequence) across two words produces a replacement character
    /// in every client that decodes each word on its own.
    static func encodedWords(_ text: String) -> String {
        // 42 source bytes -> 56 base64 characters -> 68 once wrapped in
        // `=?UTF-8?B?` and `?=`. That is the number that keeps the header
        // inside 78 without the folder having to break anything: `Subject: `
        // plus 68 is 77, and a continuation line is a space plus 68.
        let maxBytesPerWord = 42
        var chunks: [Data] = []
        var current = Data()

        for character in text {
            let bytes = Data(String(character).utf8)
            if !current.isEmpty, current.count + bytes.count > maxBytesPerWord {
                chunks.append(current)
                current = Data()
            }
            current.append(bytes)
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks
            .map { "=?UTF-8?B?" + $0.base64EncodedString() + "?=" }
            .joined(separator: " ")
    }

    // MARK: - Header assembly

    /// `Name: value`, folded so no line exceeds 78 characters, terminated with
    /// CRLF.
    ///
    /// Folding only ever happens at existing whitespace and the original
    /// whitespace is carried onto the continuation line, so unfolding (delete
    /// the CRLF, keep the WSP) reproduces the value byte for byte. A single
    /// word longer than the limit — a monstrous URL, a 200-character
    /// Message-ID — is left to overflow: breaking it would change its meaning,
    /// and an over-long line is the lesser sin.
    static func headerLine(_ name: String, _ value: String) -> String {
        let tokens = foldTokens(value)
        guard !tokens.isEmpty else { return name + ":" + crlf }

        var lines: [String] = []
        var current = name + ":"
        var currentHasWord = false

        for (index, token) in tokens.enumerated() {
            // Exactly one space after the colon; inside the value, the
            // author's own spacing.
            let space = index == 0 ? " " : token.space
            if currentHasWord && current.count + space.count + token.word.count > headerLineLimit {
                lines.append(current)
                current = space + token.word
            } else {
                current += space + token.word
                currentHasWord = true
            }
        }
        lines.append(current)
        return lines.joined(separator: crlf) + crlf
    }

    private static func foldTokens(_ value: String) -> [(space: String, word: String)] {
        var tokens: [(space: String, word: String)] = []
        var space = ""
        var word = ""

        for ch in value {
            if ch == " " || ch == "\t" {
                if !word.isEmpty {
                    tokens.append((space.isEmpty ? " " : space, word))
                    word = ""
                    space = ""
                }
                space.append(ch)
            } else {
                word.append(ch)
            }
        }
        if !word.isEmpty { tokens.append((space.isEmpty ? " " : space, word)) }
        return tokens
    }

    // MARK: - Bodies

    /// CRLF everywhere, from whatever mixture a text view produced.
    static func normalisedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }

    /// RFC 2045 quoted-printable.
    ///
    /// Encodes `=`, every byte above 126, the control characters, and any
    /// space or tab that would otherwise sit at the end of a line — trailing
    /// whitespace is the classic loss, because relays are entitled to strip it
    /// and then the decoded text no longer matches what was typed.
    ///
    /// Line breaks are CRLF, LF or a lone CR on the way in, as
    /// `normalisedLineEndings` reads them, and CRLF on the way out.
    ///
    /// Written into bytes rather than built up a `String` at a time. It was
    /// the latter, which is nothing for a letter he types and a third of a
    /// second, in a release build on this host, for the megabyte of markup a
    /// forwarded newsletter carries; this takes about 0.02 s for the same
    /// megabyte and writes the same bytes, which `QuotedPrintableTests`
    /// holds it to against the old encoder.
    static func quotedPrintable(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 8 + 16)
        var start = 0
        var k = 0
        while k < bytes.count {
            let c = bytes[k]
            guard c == 0x0D || c == 0x0A else { k += 1; continue }
            quotedPrintableLine(bytes, start..<k, into: &out)
            out.append(0x0D)
            out.append(0x0A)
            k += c == 0x0D && k + 1 < bytes.count && bytes[k + 1] == 0x0A ? 2 : 1
            start = k
        }
        quotedPrintableLine(bytes, start..<bytes.count, into: &out)
        return String(decoding: out, as: UTF8.self)
    }

    /// The soft-wrap budget for one encoded line's content. 73 leaves room for
    /// the worst case in the fix-up below (a trailing space promoted to `=20`,
    /// then the `=` soft break) to land on exactly 76, which is the hard limit.
    private static let qpLineBudget = 73

    private static func quotedPrintableLine(_ bytes: [UInt8], _ line: Range<Int>,
                                            into out: inout [UInt8]) {
        var length = 0
        for index in line {
            let byte = bytes[index]
            let isBlank = byte == 0x20 || byte == 0x09
            var escape = byte == 0x3D || byte > 126 || (byte < 32 && !isBlank)
                || (isBlank && index == line.upperBound - 1)

            if length + (escape ? 3 : 1) > qpLineBudget {
                // A soft break must not be preceded by whitespace: the space
                // would be at the end of a transmitted line in all but name,
                // and decoders disagree about whether to keep it. (`length`
                // is above zero here, so the last byte written is this
                // line's.)
                if let last = out.last, last == 0x20 || last == 0x09 {
                    out.removeLast()
                    appendEscaped(last, to: &out)
                    length += 2
                }
                out.append(0x3D)
                out.append(0x0D)
                out.append(0x0A)
                length = 0
            }

            // A line beginning with `.` is SMTP's terminator once it stands
            // alone, and must be dot-stuffed even when it does not. The SMTP
            // client stuffs too; escaping here as well costs two bytes,
            // decodes back to `.` regardless, and means no line this builder
            // emits can ever be mistaken for the end of DATA by anything in
            // between. Note this has to happen after the soft wrap, because
            // the wrap is what decides where a line begins.
            if length == 0 && byte == 0x2E { escape = true }

            if escape {
                appendEscaped(byte, to: &out)
                length += 3
            } else {
                out.append(byte)
                length += 1
            }
        }
    }

    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)

    private static func appendEscaped(_ byte: UInt8, to out: inout [UInt8]) {
        // Uppercase, because RFC 2045 says so and a few decoders are literal
        // about it.
        out.append(0x3D)
        out.append(hexDigits[Int(byte >> 4)])
        out.append(hexDigits[Int(byte & 0x0F)])
    }

    /// Base64 in 76-character lines. Wrapped by hand rather than with
    /// `Data.Base64EncodingOptions`, whose line-ending flags have a history of
    /// behaving differently between Apple Foundation and swift-corelibs — and
    /// this code is written on Linux and run on iOS, so it has to agree with
    /// itself across both.
    ///
    /// Written once into a string of its final size, from the encoded bytes,
    /// rather than as an array of 76-character lines joined: those lines
    /// alone were more than twice the file, the largest single cost of
    /// building a letter of photos in the share extension (B-036). The
    /// same characters either way. Never ends in CRLF.
    ///
    /// For inline images, which are small, and as what `LetterBytes`, which
    /// makes a file's base64 a block at a time, is held to.
    static func base64Wrapped(_ data: Data) -> String {
        let encoded = data.base64EncodedData()
        guard !encoded.isEmpty else { return "" }
        let length = base64WrappedLength(data.count)
        return encoded.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let source = raw.bindMemory(to: UInt8.self)
            return String(unsafeUninitializedCapacity: length) { target in
                var read = 0
                var written = 0
                while read < source.count {
                    if read > 0 {
                        target[written] = 0x0D
                        target[written + 1] = 0x0A
                        written += 2
                    }
                    let line = min(76, source.count - read)
                    (target.baseAddress! + written).initialize(from: source.baseAddress! + read,
                                                               count: line)
                    read += line
                    written += line
                }
                return written
            }
        }
    }

    /// How many characters `base64Wrapped` makes of `count` bytes: a
    /// file's place in a letter (`LetterPlan.length`).
    static func base64WrappedLength(_ count: Int) -> Int {
        let encoded = (count + 2) / 3 * 4
        guard encoded > 0 else { return 0 }
        return encoded + 2 * ((encoded + 75) / 76 - 1)
    }

    /// Guarantees the chunk ends with exactly one CRLF, so the next boundary
    /// line starts where it should. The CRLF in front of a `--boundary`
    /// belongs to the delimiter, not to the part, so a part whose content
    /// already ends in a newline must not gain a second one.
    private static func terminated(_ chunk: String) -> String {
        chunk.hasSuffix(crlf) ? chunk : chunk + crlf
    }

    // MARK: - Boundaries

    /// A multipart boundary that provably does not occur in any part.
    ///
    /// A collision is not a cosmetic problem: the first occurrence inside a
    /// part is read as the start of the next part, so the mail silently
    /// truncates and the attachment turns into garbage. The candidate is
    /// therefore checked against the *encoded* payloads, and on a collision it
    /// grows by another 32 random hex characters. Growth is what makes the
    /// loop terminate rather than merely being unlikely to spin: a string
    /// longer than the longest content cannot be a substring of it.
    ///
    /// The `_` is load-bearing as well as traditional: it is what keeps a
    /// boundary out of base64, which is why `build` does not scan base64
    /// payloads. A boundary without one would have to scan them again.
    static func uniqueBoundary(avoiding contents: [String],
                               token: () -> String = randomToken) -> String {
        var extra = 0
        while true {
            var candidate = "=_Blackmail_"
            for _ in 0...extra {
                candidate += token()
            }
            candidate += "_="
            if !contents.contains(where: { $0.contains(candidate) }) { return candidate }
            extra += 1
        }
    }

    /// 32 random hex digits: a UUID without its hyphens.
    static func randomToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    // MARK: - Sanitising

    /// A file's name as its part's headers carry it, before `encodeIfNeeded`:
    /// on one line, without blanks at its ends, and "attachment" when
    /// nothing is left.
    ///
    /// A quote or backslash in a filename would end the quoted string early
    /// and shove the rest of the name into the parameter list; they are
    /// stripped rather than escaped, because a 90-year-old does not need to
    /// know why his file is called `re\"port.pdf`. His photos in the letter
    /// are named so too, and the markup's `alt` is the same name
    /// (`AppleMailHTML.pictureMarkup`, B-109).
    static func partName(_ raw: String) -> String {
        let name = headerSafe(raw)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "")
        return name.isEmpty ? "attachment" : name
    }

    /// A part's type as its Content-Type carries it, octet-stream when
    /// there is none.
    private static func partType(_ raw: String) -> String {
        let mime = headerSafe(raw)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
        return mime.isEmpty ? "application/octet-stream" : mime
    }

    /// A Content-ID as the header carries it, inside its angle brackets:
    /// on one line, with no bracket of its own, and a fresh one when
    /// nothing is left.
    private static func contentIDValue(_ raw: String) -> String {
        let id = headerSafe(raw).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        return id.isEmpty ? UUID().uuidString : id
    }

    /// Removes the three characters that can break out of a header value.
    ///
    /// CR and LF would start a new header line: a recipient typed as
    /// `x@y.com\r\nBcc: someone@else` becomes a real Bcc without this. NUL is
    /// stripped for the same reason `IMAPResponseLine` uses it as a marker —
    /// it has no business in text and some servers choke on it.
    static func headerSafe(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.value {
            case 0x0A, 0x0D, 0x00: scalars.append(" ")
            default:               scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
