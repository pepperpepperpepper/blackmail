import Foundation

/// One letter handed to the submission server: who it goes to, the message
/// built from it, and the SMTP conversation that delivers it.
///
/// The app's repository sends through this, and so does the share
/// extension. A link shared from Safari is most of what he sends (B-036),
/// and it has to leave built and delivered by exactly the code a letter
/// written in the app is, not by a second copy of it that drifts.
///
/// What differs between the two stays with the caller: where the files'
/// bytes come from (a forward's parts are on the server, a shared photo is
/// on disk), and the HTML twin, which a shared link needs with the link in
/// it (`ShareLetter.html`).
///
/// Called `Outbox` until the app had an Outbox of its own (B-052), which is
/// what he sees under that name; this is only the handing over.
enum Submission {

    typealias File = (filename: String, mimeType: String, data: Data)
    typealias InlineImage = (contentID: String, filename: String, mimeType: String, data: Data)

    /// Everyone the letter is addressed to, To, Cc and Bcc, with blanks
    /// dropped.
    static func recipients(of draft: Draft) -> [String] {
        (draft.to + draft.cc + draft.bcc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Builds the letter and sends it. Returns at the server's 250 for it.
    ///
    /// A letter addressed to nobody is refused here, before `attachments`
    /// is asked for anything: fetching a forward's files for a letter that
    /// cannot go would cost a download for nothing.
    ///
    /// `messageID`, for a letter in the Outbox, is the one it goes under at
    /// every attempt, so an attempt cut off after the server had it can be
    /// found by it (`LocalDrafts.send`); nil makes a new one. `beforeData`
    /// is called once the server has taken the envelope and nothing is left
    /// but the letter itself (`SMTPClient.send`).
    static func send(_ draft: Draft, from account: MailAccount, password: String,
                     through smtp: SMTPClient,
                     threadHeaders: (messageID: String, references: String?)?,
                     attachments: () async throws -> [File],
                     htmlBody: String?,
                     inlineImages: [InlineImage],
                     messageID: String? = nil,
                     beforeData: (@Sendable () async throws -> Void)? = nil,
                     progress: UploadProgress?) async throws {
        let recipients = recipients(of: draft)
        guard !recipients.isEmpty else { throw MailError.notSent }
        let raw = RFC5322Builder.build(draft: draft, from: account,
                                       messageID: messageID,
                                       inReplyToHeaders: threadHeaders,
                                       attachments: try await attachments(),
                                       htmlBody: htmlBody,
                                       inlineImages: inlineImages)
        try await smtp.send(raw, from: account.address, to: recipients, password: password,
                            progress: progress, beforeData: beforeData)
    }
}
