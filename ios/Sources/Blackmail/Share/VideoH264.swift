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
    /// (`ShareItems.needsH264`); then an `AVAssetExportSession` at
    /// `AVAssetExportPresetHighestQuality`, which the 16.5 SDK's header
    /// says compresses the video as H.264 and the sound as AAC, at the
    /// video's own size, never larger: the most compatible copy at its
    /// best, as Photos' was. Written as the file type asked
    /// (`ShareItems.exportType`), or QuickTime where the session cannot,
    /// for a network: what a reader's mail program needs first comes
    /// first. Its metadata goes with it, as AVFoundation carries it over
    /// when it is given none, as it went in Photos' copy (B-070).
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
    static let h264 = ShareItems.VideoConversion { from, to, fileType, done in
        let export = H264Export()
        let asset = AVURLAsset(url: from)
        asset.loadTracks(withMediaType: .video) { tracks, error in
            guard let tracks, error == nil else {
                return done(.failed(code: (error as NSError?)?.code))
            }
            Task {
                var codecs: [String] = []
                for track in tracks {
                    guard let formats = try? await track.load(.formatDescriptions) else {
                        return done(.failed(code: nil))
                    }
                    codecs += formats.map { ShareItems.fourCC(CMFormatDescriptionGetMediaSubType($0)) }
                }
                guard ShareItems.needsH264(codecs: codecs) else { return done(.notNeeded) }
                export.begin(asset, to: to, fileType: fileType, done: done)
            }
        }
        return { export.cancel() }
    }
}

/// One video's conversion: its `AVAssetExportSession`, kept so that the
/// read's call-off reaches it. Called off before the session is begun, it
/// is never begun. Any thread.
private final class H264Export: @unchecked Sendable {
    private let lock = NSLock()
    private var session: AVAssetExportSession?
    private var cancelled = false

    /// The session made and begun, writing `asset` to `to`, unless it has
    /// been called off; `done` once, as it ends.
    func begin(_ asset: AVAsset, to: URL, fileType: String,
               done: @escaping (ShareItems.Converted) -> Void) {
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
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
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return done(.cancelled) }
        self.session = session
        // Begun under the lock, so a call-off cannot fall between the
        // session kept and the session begun.
        session.exportAsynchronously {
            switch session.status {
            case .completed:
                done(.made)
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
