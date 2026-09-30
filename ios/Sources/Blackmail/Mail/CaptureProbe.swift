import Foundation

/// Writes the protocol transcript of a send to a FILE, instead of leaving it
/// in a ring buffer to be read off the screen.
///
/// This began as B-034 instrumentation and earned a permanent place. The whole
/// B-033/B-034 investigation drew its conclusions from a 500-line in-memory
/// buffer photographed through a five-tap debug screen, and misread that
/// screen eight times: a STARTTLS exchange that could not exist, a sender name
/// that said something else, three different byte counts. Every one of those
/// cost a cycle. A file costs nothing and cannot be misread.
///
/// It also closed B-034. Two sends captured this way produced a complete,
/// machine-recorded Gmail session — `235`, `SIZE=17953`, `354`,
/// `WIRE-ACK err=none`, `250` with a queue id — and both letters arrived. The
/// hypothesis that the transport was lying about what it transmitted died on
/// the `WIRE-ACK` line.
///
/// **What this may never write.**
///
/// - **No credentials.** `Diagnostics.transcript()` is already redacted, and
///   the transport's write probe (`LinkTransport.writeThroughLink`) logs a
///   LENGTH and only above 1 KB, because the `AUTH PLAIN` line goes through
///   that same function and the length of that line is the length of the
///   password.
/// - **No message content.** An earlier revision of this file dumped the
///   built letter and the dot-stuffed wire payload to disk, which is how
///   B-034 was settled. That is a debugging tool, not a shipping one: it
///   writes his correspondence to the container in plaintext, on a device
///   that is going to a ninety-year-old. It was removed once it had done its
///   job. Anyone re-adding it for a recurrence should remove it again after,
///   and should not gate it on a marker file — a code path that changes
///   behaviour because a file exists is exactly what `AppDelegate` deleted
///   the bootstrap import for.
///
///   That covers the letter as built and sent, not the transcript. The
///   transcript holds the wire as it went (`Diagnostics`, rule 2), and the
///   wire carries his correspondence: the subjects, names and addresses in
///   a FETCH's ENVELOPE, the addresses on RCPT TO, the words of a search.
///   Whether to take those out of the log, and so out of these files, is
///   an open question in D-016.
enum CaptureProbe {

    /// Groups the files from one send under a common token.
    private(set) static var session = "0"

    private static let lock = NSLock()

    /// Files land at the ROOT of the container's tmp, not under
    /// `tmp/Attachments` — `AttachmentStore.purge()` clears that subdirectory
    /// at launch and would take the evidence with it.
    private static var directory: String { NSTemporaryDirectory() }

    /// `token` is the time in seconds unless a test names one, to tell two
    /// sessions apart that begin within the same second.
    static func beginSession(_ token: String = String(Int(Date().timeIntervalSince1970))) {
        lock.lock()
        defer { lock.unlock() }
        session = token
    }

    /// The redacted transcript. Called at BOTH exits of a send, because the
    /// failing case is the one worth having and it is the one that throws.
    ///
    /// `session` is the send's own, taken when it ended: the file is written
    /// after `send` has returned, and a letter sent straight after would
    /// otherwise have its token put on this one's transcript.
    static func dumpTranscript(_ tag: String, session: String = CaptureProbe.session) {
        let text = Diagnostics.transcript()
        write(Data(text.utf8), name: "blackmail-send-\(session)-\(tag).txt")
    }

    private static func write(_ data: Data, name: String) {
        let path = (directory as NSString).appendingPathComponent(name)
        // `try?` throughout: a diagnostic that can break a send is worse than
        // no diagnostic. A missing file is legible; a letter that failed to go
        // out because the probe threw is not.
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
