// Guarded so this file compiles away on a host without AVFoundation. What
// is decided about a video is `ShareItems.compatible`, which the host suite
// runs; this is AVFoundation doing it, and its wiring is read from this
// source by `VideoCompatibleTests`.
#if canImport(UIKit) && canImport(AVFoundation)

import AVFoundation
import CoreMedia

extension ShareItems.VideoConversion {

    /// AVFoundation's (B-142): the composer's Photo Library hands over the
    /// video Photos keeps (`.current`), and a video whose pictures are not
    /// H.264 already, the HEVC an iPad films in, is made H.264 here, as
    /// Photos' compatible copy made it before (B-108).
    ///
    /// Its video tracks' codecs first, by their formats
    /// (`ShareItems.needsH264`); then an `AVAssetExportSession` at the
    /// preset the copy asks: `AVAssetExportPresetHighestQuality` for the
    /// copy at its own size, `AVAssetExportPreset1280x720` for the 720p one.
    /// The 16.5 SDK's header says of both that they compress the video as
    /// H.264 and the sound as AAC, and never scale a video up: the most
    /// compatible copy, as Photos' was. Written as the file type asked
    /// (`ShareItems.exportType`), or QuickTime where the session cannot,
    /// for a network: what a reader's mail program needs first comes
    /// first. Its metadata goes with it, as AVFoundation carries it over
    /// when it is given none, as it went in Photos' copy (B-070). Stopped
    /// once it is past `limit` bytes (`fileLengthLimit`), the room and
    /// `ShareItems.copyMargin`: a copy that cannot fit is not written to
    /// its end. Written, its length and its codecs are read back from the
    /// file (`readBack`).
    ///
    /// The session is kept where the call-off reaches it, which the read
    /// keeps (`ShareItems.Loading.track(conversion:)`): called off before
    /// it begins, it never begins; after, `cancelExport`. Inside the app,
    /// it holds no file coordination claim. In the background an app gives
    /// up its encoder, and the export fails as `operationInterrupted`
    /// (Apple, of `AVAssetWriter`: it "must give up encoding resources when
    /// your app goes into the background"); the composer calls it off as
    /// the app goes, and with a Send waiting its 20 seconds' grace hold
    /// nothing past that (`ComposeIntake.away`).
    static let h264 = ShareItems.VideoConversion { from, to, fileType, copy, limit, done in
        let export = H264Export()
        let asset = AVURLAsset(url: from)
        asset.loadTracks(withMediaType: .video) { tracks, error in
            guard let tracks, error == nil else {
                return done(.failed(code: (error as NSError?)?.code))
            }
            Task {
                guard let found = await ShareItems.VideoConversion.codecs(of: tracks) else {
                    return done(.failed(code: nil))
                }
                guard ShareItems.needsH264(codecs: found) else { return done(.notNeeded) }
                let preset = copy == .ownSize ? AVAssetExportPresetHighestQuality
                    : AVAssetExportPreset1280x720
                export.begin(asset, preset: preset, to: to, fileType: fileType, limit: limit,
                             done: done)
            }
        }
        return { export.cancel() }
    }

    /// The codecs of `tracks`' formats, by their four letters; nil where
    /// a track's formats could not be read.
    fileprivate static func codecs(of tracks: [AVAssetTrack]) async -> [String]? {
        var codecs: [String] = []
        for track in tracks {
            guard let formats = try? await track.load(.formatDescriptions) else { return nil }
            codecs += formats.map { ShareItems.fourCC(CMFormatDescriptionGetMediaSubType($0)) }
        }
        return codecs
    }

    /// A copy written (`H264Export`): its length beside its video's, and
    /// its video tracks' codecs, read back from the file at `url`, for the
    /// routing to check and the log to say (`SHARE-VIDEO ... codec=avc1`).
    /// Shorter than the video by more than `ShareItems.cutShortBy`, it was
    /// stopped at its limit: `cutShort`. Otherwise `made`, with its codecs,
    /// none where they could not be read. A length that could not be read
    /// is not taken as short: the bytes decide (`ShareItems.compatible`).
    fileprivate static func readBack(_ asset: AVAsset, _ url: URL,
                                     done: @escaping (ShareItems.Converted) -> Void) {
        let copy = AVURLAsset(url: url)
        Task {
            if let whole = try? await asset.load(.duration),
               let written = try? await copy.load(.duration),
               whole.isNumeric, written.isNumeric,
               CMTimeGetSeconds(written) < CMTimeGetSeconds(whole) - ShareItems.cutShortBy {
                return done(.cutShort)
            }
            let tracks = (try? await copy.loadTracks(withMediaType: .video)) ?? []
            let found = await ShareItems.VideoConversion.codecs(of: tracks) ?? []
            done(.made(codecs: found))
        }
    }
}

/// One video's conversion: its `AVAssetExportSession`, kept so that the
/// read's call-off reaches it. Called off before the session is begun, it
/// is never begun. Any thread.
private final class H264Export: @unchecked Sendable {
    private let lock = NSLock()
    private var session: AVAssetExportSession?
    private var cancelled = false

    /// The session made at `preset` and begun, writing `asset` to `to`,
    /// stopped past `limit` bytes, unless it has been called off; `done`
    /// once, as it ends.
    func begin(_ asset: AVAsset, preset: String, to: URL, fileType: String, limit: Int64,
               done: @escaping (ShareItems.Converted) -> Void) {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            return done(.failed(code: nil))
        }
        let asked = AVFileType(rawValue: fileType)
        let types = session.supportedFileTypes
        guard let type = types.contains(asked) ? asked : types.contains(.mov) ? .mov : nil else {
            return done(.failed(code: nil))
        }
        session.outputURL = to
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        session.fileLengthLimit = limit
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return done(.cancelled) }
        self.session = session
        // Begun under the lock, so a call-off cannot fall between the
        // session kept and the session begun.
        session.exportAsynchronously {
            switch session.status {
            case .completed:
                ShareItems.VideoConversion.readBack(asset, to, done: done)
            case .cancelled:
                done(.cancelled)
            default:
                let error = session.error as NSError?
                let interrupted = error?.domain == AVFoundationErrorDomain
                    && error?.code == AVError.Code.operationInterrupted.rawValue
                done(interrupted ? .interrupted : .failed(code: error?.code))
            }
        }
    }

    /// Called off: the session cancelled where it has begun, and never
    /// begun where it has not.
    func cancel() {
        lock.lock()
        cancelled = true
        let session = self.session
        lock.unlock()
        session?.cancelExport()
    }
}

#endif
