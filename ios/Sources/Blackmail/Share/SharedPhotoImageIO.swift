// Guarded so this file compiles away on a host without UIKit or ImageIO.
// What is decided about a shared picture is `SharedPhoto`, which the host
// suite runs; this is ImageIO doing it, and its wiring is read from this
// source by `SharedPhotoTests`.
#if canImport(UIKit) && canImport(ImageIO)

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ShareItems {

    /// A picture (B-036, 2026-10-04): its file, read by ImageIO and made a
    /// JPEG of at most 4096 px, decoded at a half, a quarter or an eighth
    /// where it is larger (`SharedPhoto.size`), or copied as it is where
    /// `SharedPhoto.way` says. Never `UIImage`, which decodes every pixel:
    /// 195 MB for a 48-megapixel photo, in an extension killed at about
    /// 120 MB, and the sheet gone with nothing said.
    ///
    /// The copy iOS hands over lasts only as long as the callback, so it is
    /// read, made a JPEG and staged in there, and the next picture is not
    /// begun until it has been (`oneAtATime`). Each in its own autorelease
    /// pool, so what ImageIO made for one has gone before the next.
    ///
    /// Failing the file, none given or none ImageIO can open, its bytes,
    /// the same way. A file ImageIO opens and then cannot make a picture
    /// of is not read again as its bytes: they are the same bytes, and
    /// would only be held in memory to fail the same way. Left out, as a
    /// file that does not fit is, the sheet says so (`ShareItems.leftOut`).
    static func picture(_ provider: NSItemProvider, type: String, staging: Staging,
                        done: @escaping (SharedItem?) -> Void) {
        let suggested = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            let fromFile = autoreleasepool { () -> Picture in
                guard let url,
                      let source = CGImageSourceCreateWithURL(url as CFURL, SharedPhoto.reading)
                else { return .unopened }
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                return stage(source, type: type, size: size, suggested: suggested,
                             staging: staging) { name, mimeType in
                    staging.file(at: url, size: size, named: name, mimeType: mimeType)
                }
            }
            switch fromFile {
            case .staged(let item): return done(item)
            case .undecodable: return done(nil)
            case .unopened: break
            }
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                let fromBytes = autoreleasepool { () -> Picture in
                    guard let data,
                          let source = CGImageSourceCreateWithData(data as CFData,
                                                                   SharedPhoto.reading)
                    else { return .unopened }
                    return stage(source, type: type, size: Int64(data.count),
                                 suggested: suggested, staging: staging) { name, mimeType in
                        staging.photo(data, named: name, mimeType: mimeType)
                    }
                }
                if case .staged(let item) = fromBytes { done(item) } else { done(nil) }
            }
        }
    }

    /// What became of a picture read one way.
    private enum Picture {
        /// Staged, or left out for want of room or of a disk to write it to.
        case staged(SharedItem?)
        /// Not opened: no file given, or none ImageIO knows. Its bytes may
        /// open where the file did not.
        case unopened
        /// Opened, and no picture made of it: no image in it, or none
        /// ImageIO could decode or encode. Its bytes would fail the same.
        case undecodable
    }

    /// One picture ImageIO has open, staged as `SharedPhoto.way` says:
    /// whole through `whole`, given its name and type, or as a JPEG.
    private static func stage(_ source: CGImageSource, type: String, size: Int64,
                              suggested: String?, staging: Staging,
                              whole: (String, String) -> SharedItem?) -> Picture {
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard index < CGImageSourceGetCount(source) else { return .undecodable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [String: Any] ?? [:]
        let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil)
        let located = SharedPhoto.carriesLocation(properties)
            || properties[kCGImagePropertyGPSDictionary as String] != nil
            || SharedPhoto.locationPaths.contains { path in
                metadata.flatMap { CGImageMetadataCopyTagWithPath($0, nil, path as CFString) } != nil
            }
        let way = SharedPhoto.way(type: type, size: size, room: staging.room,
                                  carriesLocation: located)
        if case .whole(_, let mimeType) = way {
            return .staged(whole(SharedPhoto.name(suggested: suggested, way: way), mimeType))
        }
        guard let jpeg = SharedPhoto.jpeg(from: source, at: index, properties: properties)
        else { return .undecodable }
        return .staged(staging.photo(jpeg, named: SharedPhoto.name(suggested: suggested,
                                                                   way: .jpeg)))
    }
}

extension SharedPhoto {

    /// How a picture is opened: nothing of it decoded and kept beyond what
    /// one call asks for.
    static let reading = [kCGImageSourceShouldCache: false] as CFDictionary

    /// The picture at `index` of `source` as a JPEG: at most `longestSide`
    /// px, never made larger (`size`), turned upright, the colour profile
    /// it has, `quality`, and of its metadata only what `kept` keeps. Nil
    /// when ImageIO cannot make one.
    ///
    /// Made as a thumbnail, which is ImageIO's way of letting the decoder
    /// read a picture at a half, a quarter or an eighth of its size: always
    /// from the picture itself, never from a small thumbnail a file may
    /// carry, and decoded at once, here, rather than later at the encoding.
    ///
    /// The size asked for is one the decoder reaches by halving (`size`),
    /// and the bound. The factor itself is passed as well, where it is one:
    /// CGImageSource.h documents `kCGImageSourceSubsampleFactor`, and says
    /// nothing of how a thumbnail's size picks a factor: that the size
    /// picks one, and how a size exactly at a half counts, is inferred
    /// from the sheet vanishing at 4096, which fits either way. So both
    /// are given, and neither is relied on alone. A format the header does not name for it, a GIF, a WebP,
    /// a BMP, is decoded whole whatever is asked, and then made smaller.
    static func jpeg(from source: CGImageSource, at index: Int,
                     properties: [String: Any]) -> Data? {
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let longest = size(width: width, height: height)?.longest ?? longestSide
        let halving = factor(longest: max(width, height))
        var thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if halving > 1 { thumbnail[kCGImageSourceSubsampleFactor] = halving }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index,
                                                              thumbnail as CFDictionary)
        else { return nil }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            jpeg as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var written = kept(properties)
        written[kCGImageDestinationLossyCompressionQuality as String] = quality
        CGImageDestinationAddImage(destination, image, written as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return jpeg as Data
    }
}

#endif
