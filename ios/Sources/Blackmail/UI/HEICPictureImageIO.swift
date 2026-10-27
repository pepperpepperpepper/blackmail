// Guarded so this file compiles away on a host without UIKit or ImageIO.
// What is decided about a HEIC among a letter's words is `HEICPicture`,
// which the host suite runs; this is ImageIO doing it.
#if canImport(UIKit) && canImport(ImageIO)

import Foundation
import ImageIO

extension HEICPicture {

    /// Whether this system's WebKit draws HEIC: from iOS 17. Read by
    /// `ProcessInfo`, as `#available` does not link with this toolchain
    /// (`LetterPrint`'s note on printing backgrounds).
    static let systemDrawsHEIC = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0))

    /// A JPEG of the picture in `data`, upright, drawn at most `maxPixels`
    /// on its longer side by ImageIO's thumbnail, at the quality a shared
    /// photo is made at (`SharedPhoto.quality`); nil where ImageIO opens no
    /// picture in it. How much of the photo ImageIO holds while it draws
    /// it was not measured. Off the main thread, one at a time
    /// (`HEICPicture.turns`): it takes a moment for a photo.
    static func jpeg(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: SharedPhoto.quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

#endif
