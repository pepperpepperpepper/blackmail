import Foundation

/// A picture shared into the extension (B-036), and what is decided about it
/// before ImageIO touches it: here, where the suite runs it. The reading and
/// the encoding are `ShareItems.picture`, beside the sheet, since ImageIO is
/// on the iPad only.
///
/// Why it is shrunk at all. A share extension is killed past a limit that
/// is the iPad's: 180 MB on the test iPad (its jetsam properties), about
/// 120 MB on others. A photo decoded whole to be made a JPEG is its width times its height
/// times four bytes: 49 MB for a 12-megapixel one, 195 MB for 48 megapixels,
/// more for a panorama. Killed, the sheet simply vanishes, with nothing
/// said. So a photo is read from its file and made a JPEG of at most 4096
/// px on its longest side by ImageIO, one photo at a time.
///
/// How much of it is decoded is the decoder's, not the size asked for. A
/// JPEG or a HEIC is decoded whole, or at a half, a quarter or an eighth,
/// and at nothing in between: by the look of it the smallest of those
/// still no smaller than what is asked; the header documents only the
/// factor itself. Asked for 4096 px of a photo 8064 wide,
/// whose half is 4032, it decodes the whole, 195 MB, and the sheet went
/// (B-036, seen on the iPad 2026-10-04). So it is asked for what it
/// reaches by halving (`size`): 8064 goes at 4032, decoded at 49 MB.
///
/// What ImageIO holds while it does so is more than the decoded picture:
/// measured on the test iPad, a JPEG peaks at about three times it, 148 MB
/// for 12 megapixels read whole and for 48 read at a half, and a HEIC from
/// his camera at about once, 51 MB (B-036).
///
/// 4096 px is a 16-megapixel picture at 4:3, more than any screen it will be
/// read on, and a photo from his iPad's camera, 4032 px, is not made smaller.
enum SharedPhoto {

    /// The longest side a JPEG made here has, in pixels.
    static let longestSide = 4096

    /// The JPEG's quality, as the composer's (`ComposeViewController`).
    static let quality = 0.85

    /// The largest GIF or PNG that goes as the file it is (`way`): the
    /// share's room shared out among the five pictures the sheet allows
    /// (ShareInfo.plist), so five that go whole always fit together.
    static let wholeAtMost: Int64 = ShareItems.Staging.budget / 5

    // MARK: - Which of what is offered

    /// Still pictures ImageIO reads, by the identifiers an item provider
    /// offers them under. A RAW photo is not among them, nor a Live
    /// Photo's bundle, nor the Photos app's own private thumbnails.
    static let stills: Set<String> = [
        "public.heic", "public.heif", "public.jpeg", "public.png", "com.compuserve.gif",
        "public.tiff", "org.webmproject.webp", "public.avif", "com.microsoft.bmp",
        "public.jpeg-2000",
    ]

    /// A camera's RAW photo: taken only when nothing else is offered.
    static let raws: Set<String> = [
        "com.adobe.raw-image", "public.camera-raw-image", "com.apple.raw-image",
    ]

    /// The type to read a picture as, from what the provider offers, in the
    /// provider's order, which is best first: the first still picture, so
    /// the original (HEIC from the camera) rather than a copy made for
    /// sharing; then a RAW photo, the camera's data undeveloped, whose
    /// developing asks far more of the extension than a finished picture
    /// and looks flat without Photos' own; then any picture at all. Nil
    /// for what is not a picture: a page, words, a PDF, a video.
    static func fileType(offered: [String]) -> String? {
        offered.first(where: stills.contains)
            ?? offered.first(where: raws.contains)
            ?? offered.first { $0 == "public.image" }
    }

    // MARK: - Whole or a JPEG

    /// How a picture goes into the letter.
    enum Way: Equatable {
        /// As the file it is, with this extension and this type.
        case whole(filenameExtension: String, mimeType: String)
        /// As a JPEG made here, of at most `longestSide`.
        case jpeg
    }

    /// The pictures that may go as the files they are: a GIF, since an
    /// animated one is what people share and a JPEG of it is one still
    /// frame of the joke; a PNG, since that is a screenshot, mostly words,
    /// which JPEG blurs at the edges of every letter, and which may be a
    /// picture with a clear background, which JPEG has not got. Every mail
    /// program shows both.
    static let keptWhole: [String: (filenameExtension: String, mimeType: String)] = [
        "com.compuserve.gif": ("gif", "image/gif"),
        "public.png": ("png", "image/png"),
    ]

    /// Whole, for a GIF or a PNG of at most `wholeAtMost` that fits in the
    /// `room` left in the letter and carries no location. A JPEG for every
    /// other picture, a JPEG from the camera included: re-made, it loses its
    /// location (`kept`). A GIF made a JPEG is its first frame.
    ///
    /// A GIF or PNG kept whole is copied, never read, so its size costs the
    /// extension nothing; the bound is for the letter, which a large one
    /// would crowd the other pictures out of.
    static func way(type: String, size: Int64, room: Int64, carriesLocation: Bool) -> Way {
        guard let whole = keptWhole[type], size > 0, size <= wholeAtMost, size <= room,
              !carriesLocation else { return .jpeg }
        return .whole(filenameExtension: whole.filenameExtension, mimeType: whole.mimeType)
    }

    // MARK: - Its size

    /// A picture's size in pixels.
    struct Size: Equatable {
        var width: Int
        var height: Int
        var longest: Int { max(width, height) }
    }

    /// What a decoder can divide a picture's sides by as it reads it:
    /// nothing, a half, a quarter, an eighth. CGImageSource.h, at
    /// `kCGImageSourceSubsampleFactor`, allows 2, 4 and 8, for JPEG, HEIF,
    /// TIFF and PNG.
    static let factors = [1, 2, 4, 8]

    /// What a picture whose longest side is `longest` is read at: the
    /// smallest factor that brings it to `longestSide` or less. Past an
    /// eighth, over 32768 px, an eighth all the same, the most there is.
    static func factor(longest: Int) -> Int {
        factors.first { longest / $0 <= longestSide } ?? 8
    }

    /// The size a picture `width` by `height` goes at as a JPEG. Its own
    /// when its longest side is no more than `longestSide`: never made
    /// bigger. Larger, its longest side at the factor it is read at
    /// (`factor`): 8064 goes at 4032, 5712 at 2856, a 16000 px panorama at
    /// 4000. Those the decoder reaches by halving, so it decodes no more
    /// than them. A half is in whole pixels, rounded down: a decoder rounds
    /// an odd side's half up, so it is never short of what is asked, which
    /// would have it decode at the factor below, twice the size each way.
    ///
    /// What that costs: a picture a little over 4096 px goes at half its
    /// size, 4097 at 2048. And past an eighth, over 32768 px, it goes at
    /// `longestSide`: the decoder reads the eighth, more than 4096 px, and
    /// makes a second picture of 4096 from it, holding both for a moment.
    /// A panorama 40000 by 10000 is 25 MB at an eighth and 17 MB at 4096.
    ///
    /// The other side in proportion, to the nearest pixel and never less
    /// than one. Nil when the picture does not say its size. ImageIO is told
    /// only the longest side (`ShareItems.picture`) and works out the other
    /// itself, which is this to within a pixel.
    static func size(width: Int, height: Int) -> Size? {
        guard width > 0, height > 0 else { return nil }
        let longest = max(width, height)
        let halving = factor(longest: longest)
        guard halving > 1 else { return Size(width: width, height: height) }
        let asked = min(longest / halving, longestSide)
        let scale = Double(asked) / Double(longest)
        func fitted(_ side: Int) -> Int {
            side == longest ? asked : max(1, Int((Double(side) * scale).rounded()))
        }
        return Size(width: fitted(width), height: fitted(height))
    }

    // MARK: - Its name

    /// The extensions a picture's suggested name may come with, which a
    /// JPEG made of it does not keep: "IMG_0412.HEIC" goes as
    /// "IMG_0412.jpg", not "IMG_0412.HEIC.jpg".
    static let pictureExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "gif", "tif", "tiff", "webp", "avif", "bmp",
        "dng", "jp2",
    ]

    /// The name a picture goes by: the sharing app's suggestion, or "Photo"
    /// when it offers none, as the composer names one, without the
    /// extension it came with, and with the one it goes with.
    static func name(suggested: String?, way: Way) -> String {
        var base = (suggested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = base.lastIndex(of: "."),
           pictureExtensions.contains(base[base.index(after: dot)...].lowercased()) {
            base = String(base[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if base.isEmpty { base = "Photo" }
        switch way {
        case .jpeg: return base + ".jpg"
        case .whole(let ext, _): return base + "." + ext
        }
    }

    // MARK: - What goes with it

    /// What is written into a JPEG made here, out of everything the
    /// picture's own file says (`CGImageSourceCopyPropertiesAtIndex`): only
    /// the moment it was taken, and its offset from UTC, so that a
    /// recipient's Photos files it under that day. A list of what may go,
    /// not of what may not, so whatever else a photo carries, named here
    /// or not, stays behind.
    ///
    /// So the location does not go: not the GPS, nor a place's name. Mail
    /// sends it unless "Location" is switched off in the share sheet's
    /// Options; he would not know it was there, and in a photo taken at
    /// home it is his address, to whoever the letter is forwarded to. Nor
    /// the orientation: the picture is turned upright as it is made
    /// (`kCGImageSourceCreateThumbnailWithTransform`), and a tag left
    /// saying to turn it would turn it again. Nor the camera, lens,
    /// exposure, or Apple's own notes.
    ///
    /// The colour profile is not in this at all: it rides with the picture
    /// itself, so a photo in Display P3 is written in Display P3, at no cost.
    ///
    /// The keys are ImageIO's, written out, since ImageIO is not on this
    /// host: `kCGImagePropertyExifDictionary`, `…ExifDateTimeOriginal`,
    /// `…ExifOffsetTimeOriginal`. Were one ever misspelt, the date would
    /// not go; nothing else would.
    static let keptExif: Set<String> = ["DateTimeOriginal", "OffsetTimeOriginal"]

    static func kept(_ properties: [String: Any]) -> [String: Any] {
        guard let exif = properties["{Exif}"] as? [String: Any] else { return [:] }
        let taken = exif.filter { keptExif.contains($0.key) }
        return taken.isEmpty ? [:] : ["{Exif}": taken]
    }

    /// Whether a picture's own file says where it was: GPS, or the place
    /// names IPTC has room for. A GIF or PNG that does is made a JPEG, which
    /// carries neither (`way`). `kCGImagePropertyGPSDictionary` and
    /// `kCGImagePropertyIPTCDictionary`, written out; on the iPad the GPS is
    /// looked for by ImageIO's own name as well, and in the XMP
    /// (`locationPaths`), so a misspelling here cannot let one go whole.
    static func carriesLocation(_ properties: [String: Any]) -> Bool {
        properties["{GPS}"] != nil || properties["{IPTC}"] != nil
    }

    /// Where XMP keeps a location, which a PNG may carry instead of EXIF.
    static let locationPaths = ["exif:GPSLatitude", "exif:GPSLongitude"]
}
