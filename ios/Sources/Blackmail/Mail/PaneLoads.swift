import Foundation

/// The reading pane's downloads: what goes on screen before a letter's body
/// is fetched, which fetches are called off when he moves on, and which
/// answers may still be drawn.
///
/// Out of `MessageDetailViewController` for the reason `SearchAnswer` is:
/// the controller is UIKit and does not exist on the machine the suite runs
/// on, so an order that lived there could be reverted with every test green.
///
/// Two things used to go wrong here. The pane drew a letter only once its
/// body had come, so for the whole fetch it held the previous letter, header
/// and all, beside a selection that had already moved: a plausible letter
/// that was not the one he tapped. And nothing kept the fetch, so tapping
/// through four letters downloaded all four, whole, one after another, and
/// the one he stopped on came last.
///
/// Now `show` draws the stand-in first, from what the list already knows,
/// and only then asks for the body; and every fetch for what was on screen
/// before is cancelled. Cancelling is safe on the one connection: a fetch
/// already on the wire finishes its exchange, so the stream stays in step,
/// and one still waiting for the connection leaves the line without sending
/// anything (`IMAPClient.beginExchange`). Whichever way a cancelled fetch
/// ends, it draws nothing.
@MainActor
final class PaneLoads {

    /// Bumped each time the pane is given something else to show.
    private var generation = 0
    private var running: [Int: Task<Void, Never>] = [:]
    private var lastID = 0

    /// Puts something new in the pane: calls off every fetch for what was
    /// there, draws `standIn` at once, and then fetches. `settle` gets the
    /// answer, or the failure, unless the pane has moved on by then.
    ///
    /// The stand-in is drawn before the fetch is so much as asked for. That
    /// is the point of it: from the tap onwards the pane says which letter
    /// it is about, and nothing left over from the one before is on screen.
    func show<Value>(standIn: () -> Void,
                     fetch: @escaping () async throws -> Value,
                     settle: @escaping @MainActor (Result<Value, Error>) -> Void) {
        supersede()
        standIn()
        start(fetch, settle: settle)
    }

    /// Fetches for what is on screen now without replacing it: another
    /// letter opened inside the conversation already showing. A fetch
    /// started here is called off with the rest when the pane moves on.
    func start<Value>(_ fetch: @escaping () async throws -> Value,
                      settle: @escaping @MainActor (Result<Value, Error>) -> Void) {
        let asked = generation
        lastID += 1
        let id = lastID
        running[id] = Task { @MainActor [weak self] in
            let outcome: Result<Value, Error>
            do {
                outcome = .success(try await fetch())
            } catch {
                outcome = .failure(error)
            }
            guard let self else { return }
            self.running.removeValue(forKey: id)
            guard Self.draws(outcome, cancelled: Task.isCancelled,
                             current: asked == self.generation) else { return }
            settle(outcome)
        }
    }

    /// The pane has been given something else, or emptied: every fetch for
    /// what it showed is called off, and none of their answers is drawn.
    func supersede() {
        generation += 1
        let called = running.values
        running = [:]
        for task in called { task.cancel() }
    }

    /// How many fetches are still running. How a test knows the pane has
    /// stopped waiting without sleeping on it.
    var inFlight: Int { running.count }

    /// Whether a fetch's answer goes on screen. The rule `SearchAnswer`
    /// applies to a search, for the same reasons: a fetch that has been
    /// called off, or whose pane has moved on, draws nothing whichever way
    /// it ended, and a `CancellationError` can only mean it was called off,
    /// never that the letter could not be downloaded. So a letter he tapped
    /// past never says "could not be downloaded" over the one he stopped
    /// on, and never replaces it either.
    nonisolated static func draws<Value>(_ outcome: Result<Value, Error>,
                                         cancelled: Bool, current: Bool) -> Bool {
        guard !cancelled, current else { return false }
        if case .failure(let error) = outcome, error is CancellationError { return false }
        return true
    }
}

/// What the reading pane shows in place of a letter: the grey words for a
/// letter still on its way, one that could not be downloaded, or one with
/// nothing in it, and the empty page left behind when the pane is emptied.
///
/// Deliberately one presentation for all of them, because the difference
/// that matters is in the WORDS, and the words are the whole point.
enum PaneNotice {

    /// What a letter says while its body is on its way.
    static let loading = "Loading…"

    /// A dark page carrying `lines`, each its own paragraph. With no lines,
    /// the page the pane is emptied to, so that nothing a letter drew is
    /// left in the web view for the next letter to reveal.
    static func html(_ lines: [String]) -> String {
        let paragraphs = lines
            .map { "<p style=\"font-size:17px;\">\(ConversationDocument.escape($0))</p>" }
            .joined()
        return """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#000;">
        <div style="font:-apple-system-body;color:#8e8e8e;padding:24px;">
        \(paragraphs)
        </div></body></html>
        """
    }
}

extension Message {

    /// What the reading pane's header can say about a letter before its
    /// body has come: sender, subject and date, and the files it carries,
    /// all of which the list row already has.
    ///
    /// No recipients, because the row has none, so the header reads "To: me"
    /// until the letter lands; one line either way, so nothing moves when it
    /// does. The files are the row's, from the letter's structure, and they
    /// are the ones the landed letter lists: a row each, at least 44 pt
    /// tall, which the header used to gain only when the body came, pushing
    /// the letter or a conversation's stack down under him. `subject` is the
    /// thread's when the pane is showing a conversation.
    static func heading(for row: MessageSummary, subject: String? = nil) -> Message {
        Message(id: row.id, mailboxID: row.mailboxID,
                sender: row.sender, senderAddress: MailFormat.bareAddress(row.sender),
                to: [], cc: [], subject: subject ?? row.subject, date: row.date,
                textBody: nil, htmlBody: nil, attachments: row.attachments)
    }
}
