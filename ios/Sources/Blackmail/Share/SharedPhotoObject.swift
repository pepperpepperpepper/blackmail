// Guarded so this file compiles away on a host without UIKit or ImageIO.
// What is decided about a picture handed over as an object is `SharedPhoto`
// (`objectRefused`, `objectWay`, `objectFile`, `objectLeftOut`,
// `exifOrientation`), which the host suite runs; this is UIKit and ImageIO
// doing it, and its wiring is read from this source by
// `SharePictureFallbackTests` and `SharedPhotoTests`.
#if canImport(UIKit) && canImport(ImageIO)

import UIKit
import ImageIO
import UniformTypeIdentifiers

extension ShareItems {

    /// A picture's last resort (B-090): no type the provider offers gave a
    /// file or bytes ImageIO opens (`picture`). The screenshot editor's
    /// share is one, by the look of it: a picture of the screen, marked up
    /// or not, handed over as a `UIImage` and not as a file. So the
    /// provider is asked for one, as `UIImage` reads it (`loadObject`);
    /// failing that, for its own item, which is the `UIImage` itself where
    /// the sharing app shared one (`item`). Either is made a file here
    /// (`made`), bounded by the memory, and named as a picture with no
    /// name is: "image0.png", "image0.jpeg". An item that is a file or
    /// bytes is read by ImageIO, as any other is.
    ///
    /// The only `UIImage` in the extension, and only here: everything a
    /// provider hands over as a file or as bytes is read by ImageIO, which
    /// can decode at a half, a quarter or an eighth (`SharedPhoto`).
    ///
    /// `unopened`: the types tried before, for its line in the log.
    /// `loading` calls off the load under way (B-142), and neither way is
    /// begun once it has.
    static func object(_ provider: NSItemProvider, unopened: [String], staging: Staging,
                       loading: Loading, done: @escaping (SharedItem?) -> Void) {
        let offered = provider.registeredTypeIdentifiers
        let named = SharedPhoto.named(suggested: provider.suggestedName, file: nil)
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            return item(provider, unopened: unopened, staging: staging, loading: loading, done: done)
        }
        let progress = provider.loadObject(ofClass: UIImage.self) { object, _ in
            guard let image = object as? UIImage else {
                return item(provider, unopened: unopened + ["object"], staging: staging,
                            loading: loading, done: done)
            }
            var report = SharedPhoto.Report(offered: offered, read: "object", named: named)
            report.unopened = unopened
            let staged = autoreleasepool {
                made(image, named: named, offered: offered, staging: staging, report: &report)
            }
            finish(staged, report, done)
        }
        loading.track(progress)
    }

    /// The provider's own item, asked for under the first type tried: the
    /// `UIImage` a sharing app put there as it is, where `loadObject` made
    /// none. Or a file or bytes, which a sharing app may hand over this way
    /// and no other: read by ImageIO as a file or bytes given under a type
    /// are (`picture(item:)`), never as a `UIImage`. Anything else is left
    /// out, not opened.
    private static func item(_ provider: NSItemProvider, unopened: [String], staging: Staging,
                             loading: Loading, done: @escaping (SharedItem?) -> Void) {
        let offered = provider.registeredTypeIdentifiers
        let suggested = provider.suggestedName
        let named = SharedPhoto.named(suggested: suggested, file: nil)
        let type = unopened.first ?? UTType.image.identifier
        // `loadItem` gives no `Progress`: called off, it is not begun.
        guard !loading.isCancelled else {
            return calledOff(offered: offered, read: "item", unopened: unopened,
                             suggested: suggested, done: done)
        }
        provider.loadItem(forTypeIdentifier: type, options: nil) { object, _ in
            var report = SharedPhoto.Report(offered: offered, read: "item", named: named)
            report.unopened = unopened
            guard let image = object as? UIImage else {
                let staged = picture(item: object, type: type, suggested: suggested,
                                     staging: staging, report: &report)
                return finish(staged, report, done)
            }
            let staged = autoreleasepool {
                made(image, named: named, offered: offered, staging: staging, report: &report)
            }
            finish(staged, report, done)
        }
    }

    /// `image` made a file, written by ImageIO straight onto the disk where
    /// it is staged (`Staging.written`): a PNG or a JPEG as
    /// `SharedPhoto.objectWay` says, its bytes and its MIME type from that
    /// one way (`SharedPhoto.objectFile`), at its own size, named as
    /// `SharedPhoto.name` names it. Left out, and said, where
    /// `SharedPhoto.objectRefused` says, with the memory read right before:
    /// its size is the `CGImage`'s, read before a pixel of it is decoded.
    /// Written and too large for what is left of the letter's room, it is
    /// taken away again and said to be (`SharedPhoto.objectLeftOut`).
    ///
    /// Nothing of where it was can go with it: a `UIImage` carries no
    /// metadata at all, no GPS, no EXIF, only its pixels, their colour
    /// profile and its orientation, and nothing but the orientation is
    /// written into the file (`SharedPhoto.write`).
    private static func made(_ image: UIImage, named: SharedPhoto.Named, offered: [String],
                             staging: Staging, report: inout SharedPhoto.Report) -> SharedItem? {
        guard let picture = image.cgImage else {
            report.went = .leftOut("no picture in the object")
            return nil
        }
        let available = SharedPhoto.availableMemory()
        if let refused = SharedPhoto.objectRefused(width: picture.width, height: picture.height,
                                                   available: available) {
            report.went = refused
            return nil
        }
        let hasAlpha: Bool
        switch picture.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let way = SharedPhoto.objectWay(offered: offered, hasAlpha: hasAlpha)
        let file = SharedPhoto.objectFile(way)
        let name = SharedPhoto.name(named, way: way, number: staging.unnamed)
        report.name = name
        report.went = .object(png: file.png, available: available)
        let orientation = SharedPhoto.exifOrientation(imageOrientation: image.imageOrientation.rawValue)
        // Its size is not known until it is written: the room is weighed
        // on what was written, which is measured.
        let item = staging.written(named: name, mimeType: file.mimeType, expected: 0,
                                   unnamed: named == .none) { url in
            SharedPhoto.write(picture, png: file.png, orientation: orientation, to: url)
        }
        if item == nil {
            report.went = SharedPhoto.objectLeftOut(measured: staging.lastMeasured,
                                                    room: staging.room)
        }
        return item
    }
}

extension SharedPhoto {

    /// `picture` written at `url` by ImageIO, as a PNG or as a JPEG at the
    /// JPEG's quality, as it is: never turned, never made smaller, its
    /// colour profile with it. Of properties only the orientation, where it
    /// is not upright (`exifOrientation`), and for a JPEG the quality.
    /// True when it was written.
    static func write(_ picture: CGImage, png: Bool, orientation: Int, to url: URL) -> Bool {
        let type = png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString,
                                                                1, nil) else { return false }
        var written: [CFString: Any] = [:]
        if orientation != 1 { written[kCGImagePropertyOrientation] = orientation }
        if !png { written[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, picture, written as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

#endif
