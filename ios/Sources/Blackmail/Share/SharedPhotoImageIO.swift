// Guarded so this file compiles away on a host without UIKit or ImageIO.
// What is decided about a shared picture is `SharedPhoto`, which the host
// suite runs; this is ImageIO doing it, and its wiring is read from this
// source by `SharedPhotoTests`.
#if canImport(UIKit) && canImport(ImageIO)

import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

extension ShareItems {

    /// A picture (B-036): its file, as Apple Mail sends it (2026-10-05).
    /// A JPEG that fits goes as its own image data, never decoded, its
    /// metadata replaced and what was written read back, under its file's
    /// name; a GIF or PNG that fits and says nothing of where it was is
    /// copied as it is (`SharedPhoto.way`). Fits: in what is left of the
    /// letter's 25 MB.
    /// Any other is read by ImageIO and made a JPEG of at most 4096 px,
    /// decoded at a half, a quarter or an eighth where it is larger
    /// (`SharedPhoto.size`) or where the memory left asks it, and left out,
    /// and said, where even an eighth would not fit. Never `UIImage`, which
    /// decodes every pixel: 195 MB for a 48-megapixel photo, in an
    /// extension killed at about 120 MB, and the sheet gone with nothing
    /// said. A `UIImage` only as the last resort, bounded (`object`).
    ///
    /// The copy iOS hands over lasts only as long as the callback, so it is
    /// read, written and staged in there, its name taken there too, and the
    /// next picture is not begun until it has been (`oneAtATime`). Each in
    /// its own autorelease pool, so what ImageIO made for one has gone
    /// before the next.
    ///
    /// Failing the file, none given, none ImageIO can open or one it finds
    /// no picture in (`read`), its bytes, the same way. A file with a
    /// picture in it that ImageIO then cannot make a picture of is not
    /// read again as its bytes: they are the same bytes, and would only be
    /// held in memory to fail the same way. Left out, as a file that does
    /// not fit is, the sheet says so (`ShareItems.leftOut`).
    ///
    /// Failing both, the next type the provider offers that is a picture,
    /// in its own order, the same way, file then bytes
    /// (`SharedPhoto.typesToRead`); and with none left, the `UIImage` the
    /// provider gives (`object`). The screenshot editor's share, by the
    /// look of it, gives nothing under the type it offers: three times of
    /// three on the test iPad the sheet said "The photo could not be
    /// attached." (B-090).
    /// Only a picture not opened goes on to the next, one with no picture
    /// in it among them: one with a picture in it not made a picture of,
    /// or left out for the room or the memory, is the same picture
    /// whatever type it is read as.
    ///
    /// One line in the log for each, whichever way it went
    /// (`SharedPhoto.Report`): it is what an iPad check reads.
    ///
    /// Each load is the one `loading` calls off (B-142); called off, no
    /// other way is begun, and the line says so (`calledOff`).
    static func picture(_ provider: NSItemProvider, type: String, staging: Staging,
                        loading: Loading, done: @escaping (SharedItem?) -> Void) {
        let types = SharedPhoto.typesToRead(first: type, offered: provider.registeredTypeIdentifiers,
                                            isImage: { UTType($0)?.conforms(to: .image) == true })
        picture(provider, as: types[...], unopened: [], staging: staging, loading: loading, done: done)
    }

    /// The picture read as the first of `types`, its file and then its
    /// bytes; neither opened, the rest of `types`; none left, the object.
    /// `unopened`: the types tried before, for its line in the log.
    private static func picture(_ provider: NSItemProvider, as types: ArraySlice<String>,
                                unopened: [String], staging: Staging, loading: Loading,
                                done: @escaping (SharedItem?) -> Void) {
        let suggested = provider.suggestedName
        let offered = provider.registeredTypeIdentifiers
        guard !loading.isCancelled else {
            return calledOff(offered: offered, read: types.first ?? "object", unopened: unopened,
                             suggested: suggested, done: done)
        }
        guard let type = types.first else {
            return object(provider, unopened: unopened, staging: staging, loading: loading, done: done)
        }
        let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            // The file's own name, taken while there is a file: Photos'
            // library name, "IMG_0776.JPG", which it gives no other way.
            let named = SharedPhoto.named(suggested: suggested, file: url?.lastPathComponent)
            var report = SharedPhoto.Report(offered: offered, read: type, named: named)
            report.unopened = unopened
            let fromFile = read(file: url, type: type, named: named, staging: staging,
                                report: &report)
            switch fromFile {
            case .staged(let item): return finish(item, report, done)
            case .undecodable: return finish(nil, report, done)
            case .unopened: break
            }
            // No file, it may be, because the read was called off.
            guard !loading.isCancelled else {
                report.went = .leftOut("called off")
                return finish(nil, report, done)
            }
            let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                var fromItsBytes = report
                let fromBytes = read(bytes: data, type: type, named: named, staging: staging,
                                     report: &fromItsBytes)
                switch fromBytes {
                case .staged(let item): finish(item, fromItsBytes, done)
                case .undecodable: finish(nil, fromItsBytes, done)
                case .unopened:
                    // Nothing ImageIO opens under this type: the next.
                    picture(provider, as: types.dropFirst(), unopened: unopened + [type],
                            staging: staging, loading: loading, done: done)
                }
            }
            loading.track(progress)
        }
        loading.track(progress)
    }

    /// A picture whose read was called off before its next way was begun
    /// (`Loading`, B-142): nothing staged, and its line saying so,
    /// "left out, called off", though it is only set aside, to be read
    /// again.
    static func calledOff(offered: [String], read: String, unopened: [String],
                          suggested: String?, done: (SharedItem?) -> Void) {
        var report = SharedPhoto.Report(offered: offered, read: read,
                                        named: SharedPhoto.named(suggested: suggested, file: nil))
        report.unopened = unopened
        report.went = .leftOut("called off")
        finish(nil, report, done)
    }

    /// `url`, a picture's file, opened by ImageIO and staged (`stage`), in
    /// its own autorelease pool, inside the callback that is all the file
    /// lasts. Not opened where there is no file, ImageIO does not open it,
    /// or it opens with no picture in it: ImageIO opens what is no picture
    /// at all, a keyed archive or words, and finds nothing in it, with no
    /// type and a count of nought (on a Mac, 2026-10-20), so a file is
    /// opened only when there is a picture in it to read.
    private static func read(file url: URL?, type: String, named: SharedPhoto.Named,
                             staging: Staging, report: inout SharedPhoto.Report) -> Picture {
        autoreleasepool { () -> Picture in
            guard let url,
                  let source = CGImageSourceCreateWithURL(url as CFURL, SharedPhoto.reading),
                  CGImageSourceGetCount(source) > 0
            else { return .unopened }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            return stage(source, type: type, size: size, named: named, staging: staging,
                         report: &report) { name, mimeType in
                staging.file(at: url, size: size, named: name, mimeType: mimeType,
                             unnamed: named == .none)
            }
        }
    }

    /// `data`, a picture's bytes, the same way as its file (`read(file:)`),
    /// and not opened the same way.
    private static func read(bytes data: Data?, type: String, named: SharedPhoto.Named,
                             staging: Staging, report: inout SharedPhoto.Report) -> Picture {
        autoreleasepool { () -> Picture in
            guard let data,
                  let source = CGImageSourceCreateWithData(data as CFData, SharedPhoto.reading),
                  CGImageSourceGetCount(source) > 0
            else { return .unopened }
            return stage(source, type: type, size: Int64(data.count), named: named,
                         staging: staging, report: &report) { name, mimeType in
                staging.photo(data, named: name, mimeType: mimeType, unnamed: named == .none)
            }
        }
    }

    /// The provider's own item where it is not a `UIImage` (B-090,
    /// `ShareItems.item`): a picture's file on this iPad, or its bytes,
    /// which `loadItem` may hand over where neither
    /// `loadFileRepresentation` nor `loadDataRepresentation` gave them.
    /// Read as either of those is (`read`), by the same rules and the same
    /// bounds; a file named by its own name, as a file handed over any
    /// other way is (`SharedPhoto.named`). Nil for anything else, or what
    /// ImageIO does not open, the line saying why (`report`).
    static func picture(item: NSSecureCoding?, type: String, suggested: String?,
                        staging: Staging, report: inout SharedPhoto.Report) -> SharedItem? {
        let fromItem: Picture
        if let url = item as? URL, url.isFileURL {
            let named = SharedPhoto.named(suggested: suggested, file: url.lastPathComponent)
            report.named = named
            fromItem = read(file: url, type: type, named: named, staging: staging,
                            report: &report)
        } else if let data = item as? Data {
            fromItem = read(bytes: data, type: type, named: report.named, staging: staging,
                            report: &report)
        } else {
            return nil
        }
        guard case .staged(let staged) = fromItem else { return nil }
        return staged
    }

    /// The picture's line in the log, with the bytes it staged, and then
    /// `done`.
    static func finish(_ item: SharedItem?, _ report: SharedPhoto.Report,
                       _ done: (SharedItem?) -> Void) {
        var report = report
        if case .file(_, _, _, let size) = item { report.bytes = size }
        Diagnostics.log(.note, report.line)
        done(item)
    }

    /// What became of a picture read one way.
    private enum Picture {
        /// Staged, or left out for want of room, of a disk to write it to,
        /// or of memory to make a JPEG of it in.
        case staged(SharedItem?)
        /// Not opened: no file given, none ImageIO knows, or one with no
        /// picture in it (`read`). Its bytes may open where the file did
        /// not, and another type where neither did.
        case unopened
        /// Opened, a picture in it, and no picture made of it: none at its
        /// index, or none ImageIO could decode or encode. Its bytes would
        /// fail the same.
        case undecodable
    }

    /// One picture ImageIO has open, staged as `SharedPhoto.way` says, by
    /// the type the file itself says it is: as its own bytes, written
    /// straight onto the disk; whole through `whole`, given its name and
    /// type; or as a JPEG, which is also what becomes of one whose own
    /// bytes could not be written.
    private static func stage(_ source: CGImageSource, type: String, size: Int64,
                              named: SharedPhoto.Named, staging: Staging,
                              report: inout SharedPhoto.Report,
                              whole: (String, String) -> SharedItem?) -> Picture {
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard index < CGImageSourceGetCount(source) else {
            report.went = .leftOut("no picture at its index")
            return .undecodable
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [String: Any] ?? [:]
        let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil)
        let located = SharedPhoto.carriesLocation(properties)
            || properties[kCGImagePropertyGPSDictionary as String] != nil
            || SharedPhoto.locationPaths.contains { path in
                metadata.flatMap { CGImageMetadataCopyTagWithPath($0, nil, path as CFString) } != nil
            }
        let kind = CGImageSourceGetType(source).map { $0 as String } ?? type
        report.inside = kind
        // The letter's room alone: Send makes the letter from its files as
        // it goes, in memory that does not grow with them (B-070).
        let way = SharedPhoto.way(type: kind, size: size, room: staging.room, carriesLocation: located)
        report.fellBack = SharedPhoto.notItself(type: kind, size: size, room: staging.room,
                                                carriesLocation: located)
        switch way {
        case .whole(_, let mimeType):
            let name = SharedPhoto.name(named, way: way, number: staging.unnamed)
            report.name = name
            let item = whole(name, mimeType)
            report.went = item == nil ? .leftOut("not copied") : .whole
            return .staged(item)
        case .own:
            let name = SharedPhoto.name(named, way: way, number: staging.unnamed)
            var copied: Bool?
            var still: String?
            if let item = staging.written(named: name, mimeType: "image/jpeg", expected: size,
                                          unnamed: named == .none, { url in
                copied = SharedPhoto.copy(source, type: kind, properties: properties, to: url)
                guard copied == true else { return false }
                // What was written, read back before it may go: one that
                // still says more than was kept is thrown away here.
                still = SharedPhoto.readBack(url)
                return still == nil
            }) {
                report.name = name
                report.went = .own
                return .staged(item)
            }
            report.fellBack = copied == nil ? "no place on the disk"
                : copied == false ? "CopyImageSource failed"
                : still.map { "the file written \($0)" } ?? "too large for the room as written"
        case .jpeg:
            break
        }

        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let available = SharedPhoto.availableMemory()
        guard let factor = SharedPhoto.factor(width: width, height: height, type: kind,
                                              available: available ?? SharedPhoto.assumedAvailable)
        else {
            report.went = .tooLargeForMemory(
                needs: SharedPhoto.leastPeak(width: width, height: height, type: kind),
                available: available)
            return .staged(nil)
        }
        report.went = .jpeg(factor: factor, available: available)
        guard let jpeg = SharedPhoto.jpeg(from: source, at: index, properties: properties,
                                          factor: factor)
        else {
            report.went = .leftOut("not made a JPEG")
            return .undecodable
        }
        let name = SharedPhoto.name(named, way: .jpeg, number: staging.unnamed)
        report.name = name
        let item = staging.photo(jpeg, named: name, unnamed: named == .none)
        if item == nil {
            report.went = .leftOut(Int64(jpeg.count) > staging.room ? "no room" : "not written")
        }
        return .staged(item)
    }
}

extension SharedPhoto {

    /// How a picture is opened: nothing of it decoded and kept beyond what
    /// one call asks for.
    static let reading = [kCGImageSourceShouldCache: false] as CFDictionary

    /// The picture `source` as its own image data, as Mail sends a photo
    /// at Actual Size: copied into a file at `url` of the same `type`, the
    /// camera's pixels as they were, never decoded. True when it was
    /// written.
    ///
    /// Its metadata is replaced on the way. `kCGImageDestinationMetadata`,
    /// given alone, replaces every EXIF, IPTC and XMP tag the file has
    /// with what it holds (CGImageDestination.h), and it holds only what
    /// `keptOwn` keeps: the moment it was taken, its offset from UTC, and
    /// the orientation, as a tag, since these pixels are not turned. So
    /// the location does not go, nor the camera, nor Apple's own notes.
    /// Never with `kCGImageDestinationMergeMetadata`, which would keep the
    /// rest, nor `kCGImageMetadataShouldExcludeGPS`, which the header says
    /// cannot reach a location kept in a maker's note or in XMP of its
    /// own; never `CGImageDestinationAddImageFromSource`, which copies the
    /// file's metadata across. `kCGImageDestinationOrientation` cannot be
    /// given with the metadata; the orientation is in it.
    ///
    /// The colour profile is not EXIF, IPTC or XMP, and the header says
    /// the image data is not modified, so it should stay; that is for the
    /// iPad to show.
    ///
    /// That the location is gone rests on ImageIO doing as its header says,
    /// on an iPadOS that is never updated; so the file is read back before
    /// it may go (`readBack`), and one that still says where is thrown away
    /// and the photo made a JPEG here instead.
    static func copy(_ source: CGImageSource, type: String, properties: [String: Any],
                     to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString,
                                                                1, nil) else { return false }
        let metadata = CGImageMetadataCreateMutable()
        for (dictionary, values) in keptOwn(properties) {
            for (name, value) in values {
                CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary as CFString,
                                                             name as CFString, value as CFTypeRef)
            }
        }
        let replaced = [kCGImageDestinationMetadata: metadata] as CFDictionary
        return CGImageDestinationCopyImageSource(destination, source, replaced, nil)
    }

    /// The file `copy` wrote at `url`, opened again as ImageIO reads any
    /// picture, and what it still says that it should not, for the log; nil
    /// when nothing. More than one picture in it, which may carry metadata
    /// of its own; where it was, by `SharedPhoto.keepsMoreThanReplaced`,
    /// by ImageIO's own names for GPS, IPTC and Apple's notes, and in the
    /// XMP (`locationPaths`); or a maker's note. What ImageIO does not read
    /// back, a segment of a maker's own or bytes after the picture's end,
    /// this cannot see (B-036, Not covered).
    static func readBack(_ url: URL) -> String? {
        guard let written = CGImageSourceCreateWithURL(url as CFURL, reading) else {
            return "could not be read back"
        }
        let count = CGImageSourceGetCount(written)
        guard count == 1 else { return "holds \(count) pictures" }
        let properties = CGImageSourceCopyPropertiesAtIndex(written, 0, nil)
            as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let metadata = CGImageSourceCopyMetadataAtIndex(written, 0, nil)
        let says = keepsMoreThanReplaced(properties)
            || properties[kCGImagePropertyGPSDictionary as String] != nil
            || properties[kCGImagePropertyIPTCDictionary as String] != nil
            || properties[kCGImagePropertyMakerAppleDictionary as String] != nil
            || exif?[kCGImagePropertyExifMakerNote as String] != nil
            || locationPaths.contains { path in
                metadata.flatMap { CGImageMetadataCopyTagWithPath($0, nil, path as CFString) } != nil
            }
        return says ? "still says more than was kept" : nil
    }

    /// The memory left to the extension before iOS kills it, in bytes, read
    /// right before each picture is decoded: `os_proc_available_memory`,
    /// which says nought when it does not know; then the same figure from
    /// `task_info`, `limit_bytes_remaining`, which is nought with no limit.
    /// Nil when neither knows, and `SharedPhoto.assumedAvailable` is taken
    /// instead.
    static func availableMemory() -> Int64? {
        let available = os_proc_available_memory()
        if available > 0 { return Int64(available) }
        guard let info = limited() else { return nil }
        return Int64(clamping: info.limit_bytes_remaining)
    }

    /// The memory at Send, for its lines in the log (`ShareSheet`): what is
    /// left now (`availableMemory`), and the least there has been since the
    /// extension started: its limit, the footprint now and what is left,
    /// less the footprint at its highest. Nil where `task_info` does not
    /// say.
    static func memory() -> Memory {
        let least = limited().map { info in
            Int64(clamping: info.phys_footprint) + Int64(clamping: info.limit_bytes_remaining)
                - info.ledger_phys_footprint_peak
        }
        return Memory(available: availableMemory(), least: least)
    }

    /// `task_info`'s account of the extension's memory, where it has the
    /// limit in it, and one: nil otherwise.
    private static func limited() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                           / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        // An older kernel fills less of it; the limit is in it only from
        // its fourth revision on, after the footprint and its peak.
        guard let offset = MemoryLayout<task_vm_info_data_t>.offset(of: \.limit_bytes_remaining)
        else { return nil }
        let filled = Int(count) * MemoryLayout<natural_t>.size
        guard result == KERN_SUCCESS, filled >= offset + MemoryLayout<UInt64>.size,
              info.limit_bytes_remaining > 0 else { return nil }
        return info
    }

    /// The picture at `index` of `source` as a JPEG, read at `factor`: at
    /// most `longestSide` px, never made larger (`size`), turned upright,
    /// the colour profile it has, `quality`, and of its metadata only what
    /// `kept` keeps. Nil when ImageIO cannot make one.
    ///
    /// Made as a thumbnail, which is ImageIO's way of letting the decoder
    /// read a picture at a half, a quarter or an eighth of its size: always
    /// from the picture itself, never from a small thumbnail a file may
    /// carry, and decoded at once, here, rather than later at the encoding.
    ///
    /// The size asked for is the one `size` gives for the factor, which the
    /// decoder reaches by halving, and the bound. The factor itself is
    /// passed as well, where it is one: CGImageSource.h documents
    /// `kCGImageSourceSubsampleFactor`, and says nothing of how a
    /// thumbnail's size picks a factor: that the size picks one, and how a
    /// size exactly at a half counts, is inferred from the sheet vanishing
    /// at 4096, which fits either way. So both are given, and neither is
    /// relied on alone. A format the header does not name for it, a GIF, a
    /// WebP, a BMP, is decoded whole whatever is asked, and then made
    /// smaller.
    static func jpeg(from source: CGImageSource, at index: Int,
                     properties: [String: Any], factor halving: Int) -> Data? {
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let longest = size(width: width, height: height, factor: halving)?.longest ?? longestSide
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
