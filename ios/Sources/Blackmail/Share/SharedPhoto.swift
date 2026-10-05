import Foundation

/// A picture shared into the extension (B-036), and what is decided about it
/// before ImageIO touches it: here, where the suite runs it. The reading and
/// the writing are `ShareItems.picture`, beside the sheet, since ImageIO is
/// on the iPad only.
///
/// As Apple Mail does it (2026-10-05, the owner's ruling). Mail sends a
/// photo shared from Photos as the very file Photos hands over: its own
/// image data, never decoded, under its library name, "IMG_0776.JPG", its
/// orientation a tag. So does this, with one difference: its metadata is
/// replaced, and only the moment it was taken and its orientation go with
/// it, so the location does not (`keptOwn`). Mail sends the location.
///
/// Shrunk only where Mail would leave him stuck. A photo too large for
/// what is left of the letter Mail would offer to send by Mail Drop, which
/// this cannot do; one that would make the letter too large to build at
/// Send in the memory the extension has, which Mail, an app, never meets
/// (`sendRoom`); and some pictures cannot go as their own bytes: a HEIC
/// with no JPEG offered beside it, a TIFF, a WebP, a GIF or a PNG that says
/// where it was. Those are made a JPEG here (`way`).
///
/// Why shrinking is careful. A share extension is killed past a limit that
/// is the iPad's: 180 MB on the test iPad (its jetsam properties), about
/// 120 MB on others. A photo decoded whole to be made a JPEG is its width
/// times its height times four bytes: 49 MB for a 12-megapixel one, 195 MB
/// for 48 megapixels, more for a panorama. Killed, the sheet simply
/// vanishes, with nothing said. So a photo is read from its file and made a
/// JPEG of at most 4096 px on its longest side by ImageIO, one photo at a
/// time.
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
/// his camera at about once, 51 MB (B-036). So the memory left is read
/// before each one, and a picture is read at a larger factor where its
/// peak would not fit, or left out, and said, where none fits
/// (`factor(width:height:type:available:)`).
///
/// 4096 px is a 16-megapixel picture at 4:3, more than any screen it will be
/// read on. A photo from his iPad's camera, 4032 px, goes at its own size
/// as its own bytes; made a JPEG, at its own size where the memory allows
/// it and at a half where it does not.
enum SharedPhoto {

    /// The longest side a JPEG made here has, in pixels.
    static let longestSide = 4096

    /// The JPEG's quality, as the composer's (`ComposeViewController`).
    static let quality = 0.85

    /// A JPEG, by the identifier an item provider offers it under.
    static let jpegType = "public.jpeg"

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

    /// The type to read a picture as, from what the provider offers.
    ///
    /// A JPEG, whenever one is offered (2026-10-05). It is what Photos
    /// hands Mail: a camera's JPEG as it is, and a HEIC made a JPEG in
    /// Photos' own process, not in this extension's memory. So it goes
    /// ahead of the HEIC and of any other still. Not ahead of a GIF or a
    /// PNG offered before it: that is the picture as it is, and Mail sends
    /// a screenshot as the PNG it is; a GIF made a JPEG is one still frame.
    ///
    /// Otherwise the provider's order, which is best first: the first still
    /// picture; then a RAW photo, the camera's data undeveloped, whose
    /// developing asks far more of the extension than a finished picture
    /// and looks flat without Photos' own; then any picture at all. Nil
    /// for what is not a picture: a page, words, a PDF, a video.
    static func fileType(offered: [String]) -> String? {
        let still = offered.first(where: stills.contains)
        if let still, keptWhole[still] == nil, offered.contains(jpegType) { return jpegType }
        return still
            ?? offered.first(where: raws.contains)
            ?? offered.first { $0 == "public.image" }
    }

    // MARK: - Its own bytes, whole, or a JPEG

    /// How a picture goes into the letter.
    enum Way: Equatable {
        /// As its own image data, never decoded, its metadata replaced
        /// (`keptOwn`): a JPEG, as Mail sends it at Actual Size.
        case own
        /// As the file it is, copied, with this extension and this type.
        case whole(filenameExtension: String, mimeType: String)
        /// As a JPEG made here, of at most `longestSide`: shrunk.
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

    /// How a picture of `type`, `size` bytes, goes, with `room` left in the
    /// letter: the letter's own, or less where the memory at Send asks it
    /// (`sendRoom`).
    ///
    /// A JPEG that fits goes as its own bytes, its location or not: its
    /// metadata is replaced on the way (`keptOwn`). A GIF or a PNG that
    /// fits goes whole, copied and never read, when it says nothing of
    /// where it was; one that does is made a JPEG, which carries no place.
    /// There is no bound on a size but the room: Mail has none at Actual
    /// Size, and the extension none but its memory at Send.
    ///
    /// A JPEG made here for every other picture: one that does not fit,
    /// which Mail would send by Mail Drop, a HEIC, a TIFF, a WebP, a RAW
    /// photo. A GIF made a JPEG is its first frame.
    static func way(type: String, size: Int64, room: Int64, carriesLocation: Bool) -> Way {
        guard size > 0, size <= room else { return .jpeg }
        if type == jpegType { return .own }
        guard let whole = keptWhole[type], !carriesLocation else { return .jpeg }
        return .whole(filenameExtension: whole.filenameExtension, mimeType: whole.mimeType)
    }

    // MARK: - The memory Send takes

    /// What the letter holds at its peak while Send builds it, in times
    /// the files in it. The extension builds the whole letter in memory at
    /// Send, as the app does: every file read back, its base64, the letter,
    /// and the letter again as it goes (`Submission`). Measured on the host
    /// on 2026-10-05, the files read, the letter built and made ready for
    /// the wire, the peak against the files: 5.4 to 6.9 times as it was,
    /// by how the allocator gave memory back; 4.1 to 5.1 times once
    /// `RFC5322Builder` made each file's base64 only as it wrote it into
    /// the letter, and asked for the letter's room at once. Taken at five:
    /// the host is not the iPad, nor its allocator Apple's.
    static let sendPeak = 5.0

    /// The room a picture has to go as its own bytes or whole: what is
    /// left of the letter's 25 MB, `room`, or less, so that the letter as
    /// Send will build it, `staged` bytes already and this, takes no more
    /// than `memoryShare` of the `available` bytes of memory left now
    /// (`sendPeak`). Nought when there is none. Past it, a picture goes as
    /// a JPEG made here, as on 2026-10-04, rather than the extension killed
    /// at "Sending…" and the letter not sent.
    ///
    /// With 80 MB left, all that is assumed when the iPad says nothing, a
    /// letter of about 9.6 MB; with 150 MB, about 18 MB. Read as each
    /// picture is staged, before the sheet is up; what the sheet takes
    /// after is for the two fifths not counted on.
    static func sendRoom(room: Int64, staged: Int64, available: Int64) -> Int64 {
        let letter = Int64(Double(max(0, available)) * memoryShare / sendPeak)
        return max(0, min(room, letter - staged))
    }

    /// Why a picture that may go as itself, a JPEG, a GIF or a PNG, goes
    /// as a JPEG made here instead, for the log: it says where it was, it
    /// is larger than what is left of the letter (`room`), or larger than
    /// the room Send has memory for (`sendRoom`). Nil when it goes as
    /// itself, or could never have.
    static func notItself(type: String, size: Int64, room: Int64, sendRoom: Int64,
                          carriesLocation: Bool) -> String? {
        guard type == jpegType || keptWhole[type] != nil else { return nil }
        if size <= 0 { return "its size not known" }
        if type != jpegType, carriesLocation { return "it says where it was" }
        if size > room { return "more than the letter's room, \(room / 1_000_000) MB left" }
        if size > sendRoom {
            return "more than Send could build, room for \(sendRoom / 1_000_000) MB"
        }
        return nil
    }

    // MARK: - Its size, made a JPEG

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
    /// The least it is read at: the memory may ask for more
    /// (`factor(width:height:type:available:)`).
    static func factor(longest: Int) -> Int {
        factors.first { longest / $0 <= longestSide } ?? 8
    }

    /// The size a picture `width` by `height` goes at as a JPEG, read at
    /// the least factor (`factor(longest:)`).
    static func size(width: Int, height: Int) -> Size? {
        size(width: width, height: height, factor: factor(longest: max(width, height)))
    }

    /// The size a picture `width` by `height` goes at as a JPEG, read at
    /// `factor`, or at the least factor where that is more. Its own when it
    /// is read at 1: never made bigger. Otherwise its longest side at the
    /// factor, and never more than `longestSide`: 8064 goes at 4032, 5712
    /// at 2856, a 16000 px panorama at 4000, and a 4032 px photo the memory
    /// has read at a half at 2016. Those the decoder reaches by halving, so
    /// it decodes no more than them, and the size asked for and the factor
    /// agree. A half is in whole pixels, rounded down: a decoder rounds an
    /// odd side's half up, so it is never short of what is asked, which
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
    static func size(width: Int, height: Int, factor: Int) -> Size? {
        guard width > 0, height > 0 else { return nil }
        let longest = max(width, height)
        let halving = max(factor, self.factor(longest: longest))
        guard halving > 1 else { return Size(width: width, height: height) }
        let asked = max(1, min(longest / halving, longestSide))
        let scale = Double(asked) / Double(longest)
        func fitted(_ side: Int) -> Int {
            side == longest ? asked : max(1, Int((Double(side) * scale).rounded()))
        }
        return Size(width: fitted(width), height: fitted(height))
    }

    // MARK: - The memory it takes

    /// How a decoder holds a picture while ImageIO makes a JPEG of it.
    struct Decoding: Equatable {
        /// What it holds at its peak, in times the picture it decodes, at
        /// four bytes a pixel.
        var peak: Double
        /// Whether it reads at a half, a quarter or an eighth. One that
        /// does not decodes the whole, whatever is asked.
        var halves: Bool
    }

    /// The decoder for `type`, the type the file says it is. A JPEG peaks
    /// at three times its decoded picture and a HEIC at about once, both
    /// measured on the test iPad (B-036); the HEIC is taken at 1.2 for what
    /// one measure may have missed. A PNG and a TIFF are read at a factor
    /// too (CGImageSource.h) and were not measured: taken as a JPEG, the
    /// larger. Any other, a GIF, a WebP, an AVIF, a BMP, a RAW photo, is
    /// decoded whole whatever is asked, and taken at three times as well.
    static func decoding(type: String) -> Decoding {
        switch type {
        case "public.jpeg", "public.png", "public.tiff": return Decoding(peak: 3, halves: true)
        case "public.heic", "public.heif": return Decoding(peak: 1.2, halves: true)
        default: return Decoding(peak: 3, halves: false)
        }
    }

    /// What a decode may take of the memory left: three fifths. The rest
    /// is for what the estimate leaves out: the extension's own memory
    /// growing while it decodes, a measure taken outside an extension on
    /// one iPad, and the formats nobody measured. At three fifths the
    /// estimate may be short by two thirds of itself before the extension
    /// is killed.
    static let memoryShare = 0.6

    /// The memory taken to be left when the iPad says nothing of it
    /// (`ShareItems.picture`): 80 MB, two thirds of the 120 MB an iPad is
    /// thought to allow a share extension, the rest being the extension's
    /// own before a picture is read. Neither figure is measured.
    static let assumedAvailable: Int64 = 80_000_000

    /// What making a JPEG of a picture `width` by `height` of `type`, read
    /// at `factor`, is expected to hold at its peak, in bytes: the decoder's
    /// share (`decoding`) of the picture it decodes, at four bytes a pixel,
    /// and the JPEG made, at most a byte a pixel of the size it goes at.
    static func peak(width: Int, height: Int, type: String, factor: Int) -> Int64 {
        let decoder = decoding(type: type)
        let halving = max(factor, self.factor(longest: max(width, height)))
        func part(_ side: Int) -> Double {
            decoder.halves ? Double((side + halving - 1) / halving) : Double(side)
        }
        let decoded = part(width) * part(height) * 4 * decoder.peak
        let made = size(width: width, height: height, factor: halving)
            .map { Double($0.width) * Double($0.height) } ?? 0
        return Int64(decoded + made)
    }

    /// The factor a picture is read at to be made a JPEG, with `available`
    /// bytes of memory left: the least that brings it to `longestSide`
    /// (`factor(longest:)`), or a larger one where the peak of that would
    /// take more than `memoryShare` of what is left (`peak`). Nil when even
    /// an eighth would: the picture is left out, and the sheet says so,
    /// rather than the extension killed and the sheet gone. A picture that
    /// is decoded whole whatever is asked gains nothing from a factor, and
    /// is left out when it does not fit as it is.
    ///
    /// A picture that does not say its size is read as before, at 1:
    /// there is nothing to weigh, and ImageIO is asked for no more than
    /// `longestSide`.
    static func factor(width: Int, height: Int, type: String, available: Int64) -> Int? {
        guard width > 0, height > 0 else { return 1 }
        let allowed = Double(available) * memoryShare
        return tried(width: width, height: height, type: type).first { factor in
            Double(peak(width: width, height: height, type: type, factor: factor)) <= allowed
        }
    }

    /// The factors a picture is tried at, the least first: from the least
    /// that brings it to `longestSide` to an eighth, or that least alone
    /// for one decoded whole whatever is asked.
    private static func tried(width: Int, height: Int, type: String) -> [Int] {
        let least = factor(longest: max(width, height))
        return decoding(type: type).halves ? factors.filter { $0 >= least } : [least]
    }

    /// What the last factor tried holds at its peak (`peak`): the least a
    /// picture can be made a JPEG in, which the log gives for one left out.
    static func leastPeak(width: Int, height: Int, type: String) -> Int64 {
        let last = tried(width: width, height: height, type: type).last ?? 8
        return peak(width: width, height: height, type: type, factor: last)
    }

    // MARK: - Its name

    /// Where a picture's name came from.
    enum Named: Equatable {
        /// The sharing app's suggestion (`NSItemProvider.suggestedName`).
        case suggested(String)
        /// The name of the file the sharing app handed over: Photos', its
        /// library name, "IMG_0776.JPG".
        case file(String)
        /// None at all.
        case none
    }

    /// The extensions a picture's name may come with, which a JPEG made of
    /// it does not keep: "IMG_0412.HEIC" goes as "IMG_0412.jpg", not
    /// "IMG_0412.HEIC.jpg".
    static let pictureExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "gif", "tif", "tiff", "webp", "avif", "bmp",
        "dng", "jp2",
    ]

    /// Where the name comes from: the sharing app's suggestion; failing
    /// that, the name of the file it handed over, which is how Photos names
    /// a photo, giving an extension no suggestion; failing that, none. A
    /// name of nothing but an extension, ".jpg", is no name.
    static func named(suggested: String?, file: String?) -> Named {
        let suggestion = (suggested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !withoutPictureExtension(suggestion).isEmpty { return .suggested(suggestion) }
        let file = (file ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = file.lastIndex(of: ".") {
            if !file[..<dot].trimmingCharacters(in: .whitespaces).isEmpty { return .file(file) }
        } else if !file.isEmpty {
            return .file(file)
        }
        return .none
    }

    /// The name a picture goes by, as Mail names it.
    ///
    /// The file's own name, as it is, for a picture that goes as its own
    /// bytes or whole: "IMG_0776.JPG" stays "IMG_0776.JPG", case and all,
    /// as in his Sent mail. A JPEG made here keeps the file's name and ends
    /// ".jpg": "IMG_0412.HEIC" goes as "IMG_0412.jpg". A suggestion loses
    /// the extension it came with and takes the one it goes with. A file
    /// whose extension says another type than it goes as is treated so too.
    ///
    /// With no name, "image" and `number`: "image0.jpeg", then
    /// "image1.png", as Mail names a picture that has none, counted from
    /// nought in each letter, one count for every type, ".jpeg" for a JPEG.
    /// Two of the same name are not told apart: Mail does not.
    static func name(_ named: Named, way: Way, number: Int) -> String {
        let goesAs: (ext: String, accepted: Set<String>)
        switch way {
        case .own: goesAs = ("jpg", ["jpg", "jpeg", "jpe"])
        case .jpeg: goesAs = ("jpg", [])
        case .whole(let ext, _): goesAs = (ext, [ext])
        }
        switch named {
        case .none:
            return "image\(number)." + (goesAs.ext == "jpg" ? "jpeg" : goesAs.ext)
        case .file(let file):
            if let dot = file.lastIndex(of: "."),
               goesAs.accepted.contains(file[file.index(after: dot)...].lowercased()) {
                return file
            }
            return withoutPictureExtension(file) + "." + goesAs.ext
        case .suggested(let suggestion):
            return withoutPictureExtension(suggestion) + "." + goesAs.ext
        }
    }

    /// `name` without a picture's extension at its end, where it has one.
    private static func withoutPictureExtension(_ name: String) -> String {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = base.lastIndex(of: "."),
           pictureExtensions.contains(base[base.index(after: dot)...].lowercased()) {
            base = String(base[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return base
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
    /// home it is his address, to whoever the letter is forwarded to. Kept
    /// out pending the owner's word (B-036, 2026-10-05); this list and
    /// `keptOwn` are where that is decided. Nor the orientation: the
    /// picture is turned upright as it is made
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

    /// What goes with a photo sent as its own bytes (`Way.own`): what
    /// `kept` keeps, and its orientation, by ImageIO's dictionaries and
    /// names. Written as the file's whole metadata, which replaces every
    /// EXIF, IPTC and XMP tag it had (`ShareItems.picture`), so nothing
    /// else goes: not the location, not the camera.
    ///
    /// The orientation must go here, where `kept` leaves it out: these
    /// pixels are the camera's, not turned, and the tag is what turns
    /// them. The TIFF dictionary's, or failing that ImageIO's own reading
    /// of it, from 1 to 8; none when the file says none. Misspelt, the
    /// picture would arrive on its side; nothing else would go.
    static func keptOwn(_ properties: [String: Any]) -> [String: [String: Any]] {
        var own: [String: [String: Any]] = [:]
        if let exif = kept(properties)["{Exif}"] as? [String: Any] { own["{Exif}"] = exif }
        let tiff = properties["{TIFF}"] as? [String: Any]
        if let turn = (tiff?["Orientation"] ?? properties["Orientation"]) as? Int,
           (1...8).contains(turn) {
            own["{TIFF}"] = ["Orientation": turn]
        }
        return own
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

    /// Whether a photo written as its own bytes, read back from the disk,
    /// still says more than `keptOwn` put in it: where it was, by GPS or
    /// IPTC (`carriesLocation`), Apple's own notes, or a maker's note, any
    /// of which may hold a place. Then the file is thrown away and the
    /// photo made a JPEG here, which can carry none of them
    /// (`ShareItems.picture`).
    ///
    /// The replacing is ImageIO's, by its header's word, and nothing here
    /// can watch it work on his iPad, whose iPadOS is never updated; so
    /// what it wrote is looked at before it goes. What ImageIO adds of its
    /// own, the picture's size or its colour space, is not counted: a list
    /// of what may not stay, unlike `kept`, since what ImageIO writes is
    /// not known in advance. On the iPad the GPS and IPTC are looked for
    /// by ImageIO's own names as well, and in the XMP (`locationPaths`).
    static func keepsMoreThanReplaced(_ properties: [String: Any]) -> Bool {
        let exif = properties["{Exif}"] as? [String: Any]
        return carriesLocation(properties) || properties["{MakerApple}"] != nil
            || exif?["MakerNote"] != nil
    }

    // MARK: - The log

    /// What became of a picture, for the log.
    enum Went: Equatable {
        /// Its file not opened, nor its bytes.
        case notOpened
        /// As its own bytes, its metadata replaced.
        case own
        /// Copied whole.
        case whole
        /// Made a JPEG, read at `factor`, with `available` bytes of memory
        /// left, nil when the iPad did not say.
        case jpeg(factor: Int, available: Int64?)
        /// Left out: even the last factor tried, an eighth or for a picture
        /// decoded whole its least, would hold `needs` bytes at its peak
        /// (`leastPeak`), more than `memoryShare` of what is left.
        case tooLargeForMemory(needs: Int64, available: Int64?)
        /// Left out, for the reason given.
        case leftOut(String)
    }

    /// The line the log gets for each picture shared (B-036), which is what
    /// an iPad check reads: the types the provider offered, in its order;
    /// the one read, and what the file turned out to be when that is
    /// another; where the name came from and the name; how it went; and the
    /// bytes staged. Nothing of the metadata: no GPS, no place.
    ///
    /// The name as it is only when a device made it: Photos' "IMG_0776.JPG",
    /// or "image0.jpeg" made here. Any other is a title someone gave it,
    /// "Sam's lab results.png", and goes in the log by its length and its
    /// extension alone, "{17 chars}.png" (`logged`): the log is made to be
    /// sent to whoever helps, and says what happened in numbers and ids,
    /// never who or what about (Diagnostics, D-016).
    struct Report {
        var offered: [String]
        var read: String
        var inside: String?
        var named: Named = .none
        var name = ""
        var went: Went = .notOpened
        /// Why it was not sent as its own bytes, when it was meant to be.
        var fellBack: String?
        var bytes: Int64 = 0

        init(offered: [String], read: String, named: Named) {
            self.offered = offered
            self.read = read
            self.named = named
        }

        var line: String {
            let source: String
            switch named {
            case .suggested: source = "suggested"
            case .file: source = "file"
            case .none: source = "none"
            }
            let file = inside.map { $0 == read ? "" : " (\($0) inside)" } ?? ""
            let back = fellBack.map { " (not as its own bytes: \($0))" } ?? ""
            return "SHARE-PICTURE offered=\(offered.joined(separator: ",")) read=\(read)\(file)"
                + " name=\(source) \"\(Self.logged(name))\" way=\(Self.words(went))\(back)"
                + " bytes=\(bytes)"
        }

        /// `name` as the log has it: as it is when it is "IMG_" or "image"
        /// and digits, a dot, and letters and digits after it; otherwise
        /// its length in characters before the extension, and the
        /// extension when it is plain and short, "{6 chars}.jpg".
        static func logged(_ name: String) -> String {
            func plain(_ text: Substring) -> Bool {
                !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            }
            guard let dot = name.lastIndex(of: ".") else { return "{\(name.count) chars}" }
            let base = name[..<dot]
            let ext = name[name.index(after: dot)...]
            let number = base.hasPrefix("IMG_") ? base.dropFirst(4)
                : base.hasPrefix("image") ? base.dropFirst(5) : nil
            if let number, !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }),
               plain(ext) {
                return name
            }
            return "{\(base.count) chars}" + (plain(ext) && ext.count <= 5 ? "." + ext : "")
        }

        private static func megabytes(_ bytes: Int64?) -> String {
            guard let bytes else { return "memory unknown, \(assumedAvailable / 1_000_000) MB assumed" }
            return "\(bytes / 1_000_000) MB available"
        }

        private static func words(_ went: Went) -> String {
            switch went {
            case .notOpened: return "left out, not opened"
            case .own: return "own bytes, metadata replaced"
            case .whole: return "copied whole"
            case .jpeg(let factor, let available):
                return "JPEG at factor \(factor), \(megabytes(available))"
            case .tooLargeForMemory(let needs, let available):
                // What would have had to be left, not the peak itself: a
                // decode may take `memoryShare` of what is left. Rounded
                // up, as what is left is rounded down, so the one is
                // always more than the other.
                let needed = (Int64((Double(needs) / memoryShare).rounded(.up)) + 999_999)
                    / 1_000_000
                return "left out, \(needed) MB needed at the least, \(megabytes(available))"
            case .leftOut(let why): return "left out, \(why)"
            }
        }
    }

    // MARK: - The memory at Send

    /// The memory left to the extension, as the iPad tells it: now, and
    /// the least there has been since it started, which is how near its
    /// highest moment came to the limit. Nil where the iPad does not say.
    struct Memory: Equatable {
        var available: Int64?
        var least: Int64?

        init(available: Int64? = nil, least: Int64? = nil) {
            self.available = available
            self.least = least
        }
    }

    /// A line for the log at a step of Send in the share extension
    /// (`ShareSheet`): the step, the files read and their bytes where that
    /// is the step, and the memory. The building of the letter is the
    /// extension's highest moment and is over before the next line, so the
    /// least since it started is what says how near it came. Numbers only.
    static func sendNote(_ step: String, files: [Int64]? = nil, memory: Memory) -> String {
        var line = "SHARE-SEND \(step)"
        if let files {
            line += ", \(files.count) files \(files.reduce(0, +)) bytes"
        }
        line += memory.available.map { ", \($0 / 1_000_000) MB available" } ?? ", memory unknown"
        if let least = memory.least { line += ", \(least / 1_000_000) MB at the least" }
        return line
    }
}
