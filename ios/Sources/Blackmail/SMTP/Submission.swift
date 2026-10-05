import Foundation

/// One letter handed to the submission server: who it goes to, the message
/// made from it, and the SMTP conversation that delivers it.
///
/// The app's repository sends through this, and so does the share
/// extension. A link shared from Safari is most of what he sends (B-036),
/// and it has to leave made and delivered by exactly the code a letter
/// written in the app is, not by a second copy of it that drifts.
///
/// What differs between the two stays with the caller: where the files'
/// bytes come from (a forward's parts are on the server, a shared photo is
/// on disk), and the HTML twin, which a shared link needs with the link in
/// it (`ShareLetter.html`).
///
/// The letter is never made whole (B-070). It is planned once for the
/// attempt (`RFC5322Builder.plan`), its files opened and held
/// (`LetterFiles`), and rehearsed: every byte made and counted before the
/// server is reached, so a file that cannot go fails here, with nothing on
/// the wire. Then it is made again as it goes, a piece at a time, and its
/// terminating dot made only once each file has read the same again
/// (`DataStream`). What Send holds is the letter's text and a few hundred
/// kilobytes, whatever its files weigh, and nothing is written to the disk.
///
/// Called `Outbox` until the app had an Outbox of its own (B-052), which is
/// what he sees under that name; this is only the handing over.
enum Submission {

    typealias File = (filename: String, mimeType: String, source: LetterSource)
    typealias InlineImage = (contentID: String, filename: String, mimeType: String, data: Data)

    /// Everyone the letter is addressed to, To, Cc and Bcc, with blanks
    /// dropped.
    static func recipients(of draft: Draft) -> [String] {
        (draft.to + draft.cc + draft.bcc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Makes the letter and sends it. Returns at the server's 250 for it.
    ///
    /// A letter addressed to nobody is refused here, before `attachments`
    /// is asked for anything: fetching a forward's files for a letter that
    /// cannot go would cost a download for nothing.
    ///
    /// A file that cannot be opened, is not a file, is not the size it was
    /// attached at, or cannot be read whole, is refused here, before the
    /// server is reached, as `MailError.notSent`, and the log says which
    /// and why (`LETTER-FILE`). A file whose size when attached is not
    /// known goes unchecked, and its line says so. `rehearsed` hears what
    /// the rehearsal found, before the server is reached.
    ///
    /// `messageID`, for a letter in the Outbox, is the one it goes under at
    /// every attempt, so an attempt cut off after the server had it can be
    /// found by it (`LocalDrafts.send`); nil makes a new one. `beforeData`
    /// is called once the server has taken the envelope and nothing is left
    /// but the letter itself (`SMTPClient.send`).
    ///
    /// `date`, `boundaryToken` and `opening` are for a test, to make the
    /// letter reproducible and its files' reads its own.
    static func send(_ draft: Draft, from account: MailAccount, password: String,
                     through smtp: SMTPClient,
                     threadHeaders: (messageID: String, references: String?)?,
                     attachments: () async throws -> [File],
                     htmlBody: String?,
                     inlineImages: [InlineImage],
                     messageID: String? = nil,
                     rehearsed: (@Sendable (DataStream.Rehearsal) -> Void)? = nil,
                     beforeData: (@Sendable () async throws -> Void)? = nil,
                     progress: UploadProgress?,
                     date: Date = Date(),
                     boundaryToken: () -> String = RFC5322Builder.randomToken,
                     opening: ([LetterSource]) throws -> LetterFiles = { try LetterFiles(opening: $0) })
        async throws {
        let recipients = recipients(of: draft)
        guard !recipients.isEmpty else { throw MailError.notSent }
        let files = try await attachments()
        let opened: LetterFiles
        do {
            opened = try opening(files.map(\.source))
        } catch let failure as LetterSourceFailure {
            throw refused(failure)
        }
        // Every way out, the letter sent, refused or cut off. `deinit` would
        // too, later.
        defer { opened.close() }
        // The one plan of this attempt: its Date, Message-ID and boundaries
        // are the letter's on the wire, which the rehearsal and the wire
        // pass both make.
        let plan = RFC5322Builder.plan(draft: draft, from: account,
                                       date: date,
                                       messageID: messageID,
                                       inReplyToHeaders: threadHeaders,
                                       files: files.map { ($0.filename, $0.mimeType) },
                                       htmlBody: htmlBody,
                                       inlineImages: inlineImages,
                                       boundaryToken: boundaryToken)
        let letter: DataStream
        do {
            letter = try DataStream(plan: plan, files: opened)
        } catch let failure as LetterSourceFailure {
            throw refused(failure)
        }
        let rehearsal = letter.rehearsal
        Diagnostics.log(.note,
            "LETTER-PLAN files=\(rehearsal.files.count) "
            + "file-bytes=\(rehearsal.files.reduce(0) { $0 + $1.bytes }) "
            + "raw=\(rehearsal.rawCount) payload=\(rehearsal.payloadCount) ms=\(rehearsal.ms)")
        for (index, file) in rehearsal.files.enumerated() {
            var line = "LETTER-FILE \(index + 1) bytes=\(file.bytes) crc=\(CRC32.hex(file.crc))"
            // A file on the disk with no size when attached: its size was
            // not checked (`LetterFiles`), and the log says so.
            if case .disk(_, attachedSize: nil) = files[index].source {
                line += " attached=- not checked"
            }
            Diagnostics.log(.note, line)
        }
        rehearsed?(rehearsal)
        try await smtp.send(letter, from: account.address, to: recipients, password: password,
                            progress: progress, beforeData: beforeData)
    }

    /// A file that could not go, before the server was reached: logged,
    /// numbers only, and said as "Message was not sent.".
    private static func refused(_ failure: LetterSourceFailure) -> MailError {
        if failure.file == nil {
            Diagnostics.log(.note, "LETTER-PLAN refused \(failure.words)")
        } else {
            Diagnostics.log(.note, "LETTER-FILE \(failure.fileNumber) refused \(failure.words)")
        }
        return .notSent
    }
}
