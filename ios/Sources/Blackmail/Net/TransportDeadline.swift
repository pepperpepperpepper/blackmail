import Foundation

/// The one way a transport gives up on the network: a deadline that only the
/// deadline can trip, and that the caller's cancellation cannot.
///
/// Reads used to race the receive against `Task.sleep` in a task group, and
/// that shape got both halves wrong. A task group does not return until every
/// child has finished, and neither `NWConnection.receive` nor the scripted
/// transport's receive answers cancellation, so:
///
/// - the deadline threw on time and then waited for the receive anyway, which
///   on a peer that had gone quiet was a read with no end;
/// - a cancelled caller's sleep child threw at once, the group waited for the
///   chunk it was reading and then dropped it. That reply was gone from the
///   stream, so `IMAPClient` had to tear the connection down, and every search
///   cancelled by the next keystroke cost a reconnect.
///
/// Here the operation runs in an unstructured task, which does not inherit the
/// caller's cancellation, and the deadline is a dispatch timer. Whichever ends
/// first resumes the caller and the other finds it already resumed. The
/// caller's cancellation is not consulted at all: a read or a write that has
/// started runs to completion, so the reply it belongs to is read whole and
/// the stream stays in step. A cancelled caller hears about it before its
/// next command, from the exchange gate in `IMAPClient`.
///
/// When the deadline wins, `onExpiry` runs BEFORE the caller is told.
/// `LinkTransport` passes it a close of the transport, which lets go of the
/// link and so ends the operation left behind with an error, and closes the
/// transport again itself as the caller hears `.timedOut`, so nothing reads
/// a late reply from it.
enum TransportDeadline {

    /// How much of a write is handed to the stack at a time.
    ///
    /// Each piece gets the whole deadline to itself, and that is what makes a
    /// write's deadline measure progress rather than size. `send` completes
    /// once the stack has taken the bytes, and once its buffers are full it
    /// takes more only as the far end acknowledges what went before, so a
    /// piece that has not gone in 30 seconds means under about 2 KB/s: a line
    /// that has stopped, not a slow one. A flat bound on the whole write
    /// could not tell those apart, and a five-photo letter is 20 MB after
    /// base64, which is minutes on a poor uplink.
    static let writeChunkBytes = 64 * 1024

    /// `operation`, or `MailTransportError.timedOut` once `seconds` have
    /// passed without it finishing, whichever comes first.
    static func race<T: Sendable>(within seconds: TimeInterval,
                                  onExpiry expire: @escaping @Sendable () -> Void,
                                  _ operation: @escaping @Sendable () async throws -> T)
        async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = ResumeOnce(continuation)
            let deadline = DispatchWorkItem {
                guard let caller = once.take() else { return }
                expire()
                caller.resume(throwing: MailTransportError.timedOut)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: deadline)
            Task {
                let result: Result<T, Error>
                do {
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                deadline.cancel()
                once.take()?.resume(with: result)
            }
        }
    }

    /// Writes `data` through `send` a piece at a time, each piece raced
    /// against `seconds` on its own. See `writeChunkBytes`.
    ///
    /// The pieces are slices of `data`, not copies, and go one after another:
    /// the stack buffers well past one piece, so waiting for each completion
    /// before handing over the next costs nothing in throughput.
    ///
    /// `progress` hears the running total after each piece has been taken,
    /// and nothing for a piece that failed.
    static func write(_ data: Data, within seconds: TimeInterval,
                      onExpiry expire: @escaping @Sendable () -> Void,
                      progress: UploadProgress? = nil,
                      through send: @escaping @Sendable (Data) async throws -> Void) async throws {
        var start = data.startIndex
        repeat {
            let end = data.index(start, offsetBy: writeChunkBytes, limitedBy: data.endIndex)
                ?? data.endIndex
            let piece = data[start..<end]
            try await race(within: seconds, onExpiry: expire) { try await send(piece) }
            start = end
            progress?(start - data.startIndex, data.count)
        } while start < data.endIndex
    }
}

/// A continuation that the first of two racers takes and the second finds
/// gone. Resuming a checked continuation twice is a crash, not an error, and
/// the receive finishing and the deadline firing can happen in the same
/// instant on two threads.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func take() -> CheckedContinuation<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let taken = continuation
        continuation = nil
        return taken
    }
}
