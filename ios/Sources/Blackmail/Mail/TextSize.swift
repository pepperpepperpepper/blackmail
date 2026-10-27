import Foundation

/// The iPad's text size and Bold Text, which Mail follows (B-166). The app
/// follows Bold Text, and since 2026-10-27 is drawn at Large whatever the
/// size (`drawn(at:bold:)`).
///
/// Mail's list, its Mailboxes, the letter it shows and its composer take
/// the size set in Settings, Display & Brightness, Text Size, or past its
/// seven steps in Accessibility, Display & Text Size, Larger Text; or the
/// one set for the app alone in Accessibility, Per-App Settings, which iOS
/// hands the app the same way, as its `preferredContentSizeCategory`; and
/// Bold Text. Every size the app's type and rows take goes through this
/// size's `scale` (`Theme.textScale`, `Theme.scaled`), which is exactly 1
/// at Large, the size an iPad comes with, so that the app at Large is the
/// app as it was.
///
/// Held at Large since 2026-10-27: the owner, "Let's keep the exact layout
/// for now", so Blackmail is drawn at Large whatever size iOS hands it,
/// as D-007 and B-071 had it (`drawn(at:bold:)`). The sizes and the rows
/// at each stay here, run by the suite, for the day he says otherwise.
///
/// Out of `Theme` and the screens, which are UIKit, so that the suite can
/// run it: the sizes iOS has, by the body text Apple sets at each, and
/// where a row of the list puts its lines at each (`RowLines`). The
/// screens turn UIKit's name for a size into a `Step` (`Step(_:)`).
struct TextSize: Equatable, Sendable {

    /// The twelve sizes iOS offers, smallest first: the seven of Text Size,
    /// Large the factory one, then the five that Larger Accessibility
    /// Sizes adds. UIKit's `UIContentSizeCategory`, in the order it has
    /// them.
    enum Step: Int, CaseIterable, Comparable, Sendable {
        case extraSmall, small, medium, large, extraLarge, extraExtraLarge, extraExtraExtraLarge
        case accessibilityMedium, accessibilityLarge, accessibilityExtraLarge
        case accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge

        /// The body text at this size, in points: Apple's table for the
        /// text style Mail's letters are set in (Human Interface
        /// Guidelines, Typography, Dynamic Type sizes), 17 at Large. Mail's
        /// names and folders are 17 at Large as well, and its subjects,
        /// previews and dates 15, and the app's are too; each goes up and
        /// down by the body's share.
        var body: Int {
            switch self {
            case .extraSmall: return 14
            case .small: return 15
            case .medium: return 16
            case .large: return 17
            case .extraLarge: return 19
            case .extraExtraLarge: return 21
            case .extraExtraExtraLarge: return 23
            case .accessibilityMedium: return 28
            case .accessibilityLarge: return 33
            case .accessibilityExtraLarge: return 40
            case .accessibilityExtraExtraLarge: return 47
            case .accessibilityExtraExtraExtraLarge: return 53
            }
        }

        /// One of the five Larger Accessibility Sizes adds.
        var isAccessibility: Bool { self >= .accessibilityMedium }

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    var step: Step
    /// Bold Text. Nothing here is drawn differently for it: the system's
    /// font is made bolder by iOS itself while it is on, as Mail's is, and
    /// the app's fonts are the system's (`Theme`). What it changes is
    /// whether the type the screens hold is the type to draw, so a switch
    /// of it draws them again, as a change of size does.
    var bold: Bool

    /// The iPad as it comes: Large, Bold Text off.
    static let factory = TextSize(step: .large, bold: false)

    /// The size the app is drawn at when iOS hands it `step`: Large,
    /// whatever `step` is, so that every screen keeps its exact layout at
    /// every text size (the owner, 2026-10-27: "Let's keep the exact layout
    /// for now"; B-166, Changed). Bold Text is followed: it was before
    /// B-166, the app's fonts being the system's, made as they are drawn,
    /// and held off they would mix weights, the fonts made before a switch
    /// beside those made after it. It sets no size and no row's height,
    /// but its glyphs are wider, so a line that only just fit may be cut
    /// sooner or wrap: a long name cut with "…" a little sooner, the two
    /// preview lines broken elsewhere, and the header's subject, on as
    /// many lines as it takes, a line longer, the letter under it lower.
    static func drawn(at step: Step, bold: Bool) -> TextSize {
        TextSize(step: .large, bold: bold)
    }

    /// What the app's sizes are multiplied by: this size's body over
    /// Large's, so exactly 1 at Large.
    var scale: CGFloat { CGFloat(step.body) / CGFloat(Step.large.body) }

    /// `points` at this size, to the whole point, as `Theme.scaled` has
    /// always rounded them.
    func scaled(_ points: CGFloat) -> CGFloat { (points * scale).rounded() }

    /// A height a finger has to hit, at this size: `points` scaled, and
    /// never under `floor`, the 44 points every tappable control is given
    /// (D-007), however small the size.
    func tappable(_ points: CGFloat, floor: CGFloat) -> CGFloat { max(floor, scaled(points)) }

    /// At the accessibility sizes a row of the list puts its date on a line
    /// of its own under the names, and the rest of the row a line lower.
    /// Beside the names, the date at these sizes took up to the whole line
    /// and left the names nothing; a list of UIKit's own puts two things
    /// that no longer fit side by side one under the other in the same
    /// way. How Mail's list is laid out at these sizes was not seen.
    var stacksRowDate: Bool { step.isAccessibility }
}

/// Where a row of the message list puts its lines at a text size: the
/// baselines of the names, the date, the subject and the first of the two
/// preview lines, from the top of the row, the pitch between the preview
/// lines, and the row's height (B-166). The gutter's dot, arrow and
/// paperclip ride with the names, on the first line, as at Large.
///
/// The row's numbers in `Theme` are the row at Large, and one rigid block:
/// at any size each is scaled by the size's `scale`, the row's height
/// with them, so the rhythm holds. At the accessibility sizes the date
/// has a line of its own under the names (`TextSize.stacksRowDate`), as
/// far below them as the subject is, and everything under it, and the
/// row, are that much lower. At Large these are the row's own numbers,
/// unchanged.
struct RowLines: Equatable, Sendable {
    let names: CGFloat
    let date: CGFloat
    let subject: CGFloat
    let preview: CGFloat
    let pitch: CGFloat
    /// To the whole point, as `Theme.messageRowHeightScaled` always was.
    let height: CGFloat
    /// Whether the date is on a line of its own.
    let stacked: Bool

    /// `names`, `subject`, `preview1` and `preview2` are the row's
    /// baselines at Large, from its top, and `height` its height there.
    init(_ size: TextSize, names: CGFloat, subject: CGFloat, preview1: CGFloat, preview2: CGFloat,
         height: CGFloat) {
        let scale = size.scale
        stacked = size.stacksRowDate
        // The date's own line: one more line of the row's pitch.
        let lower = stacked ? subject - names : 0
        self.names = names * scale
        date = (stacked ? subject : names) * scale
        self.subject = (subject + lower) * scale
        preview = (preview1 + lower) * scale
        pitch = (preview2 - preview1) * scale
        self.height = ((height + lower) * scale).rounded()
    }

    /// The square a mark in the row's gutter is drawn in, the reply or
    /// forward arrow, `points` wide at Large and centred `centre` points
    /// from the row's left, where the dot is, with the names beginning at
    /// `textLeft`: scaled with the type, and never wider than the gutter
    /// holds, so that it neither runs off the row's left edge nor comes
    /// within a point of the names. The gutter stays as at Large at every
    /// size, and the arrow scaled alone outgrew it at the two largest
    /// sizes: 33 and 37 points about a centre 14 from the edge. At Large,
    /// and up to the third accessibility size, the scaled width (B-166).
    static func gutterBox(_ points: CGFloat, at size: TextSize, centre: CGFloat,
                          textLeft: CGFloat) -> CGFloat {
        min(size.scaled(points), 2 * min(centre, textLeft - centre - 1))
    }
}

/// The app's text size, read when iOS says it may have changed, put where
/// the type reads it, and said on the main queue once it has (B-166).
///
/// As `DisplayDates` is for the clock: the screens listen for `didChange`,
/// never for iOS's own words, so the size they read when they draw again
/// is the new one. Read and said on the main queue, after iOS's own call
/// has returned and UIKit has done with the change itself (its circles in
/// Edit mode, its drags' buttons), and only when the size or Bold Text did
/// change, so a word iOS says twice draws the screens once.
final class TextSizes {

    /// Said on the main queue, in the centre given, once the new size is
    /// where the type reads it: the screens set their type and rows again.
    /// Since 2026-10-27 only for Bold Text, the size read being Large
    /// whatever the iPad's (`TextSize.drawn`).
    static let didChange = Notification.Name("BlackmailTextSizeDidChange")

    private let notifications: NotificationCenter
    private let read: () -> TextSize
    private let apply: (TextSize) -> Void
    private var observers: [NSObjectProtocol] = []
    private let lock = NSLock()
    /// A look is on its way to the main queue and has not run yet.
    private var looking = false

    /// The size as last read and applied.
    private(set) var current: TextSize

    /// `read` gives the size iOS hands the app now, and Bold Text; `apply`
    /// puts it where the type reads it (`Theme.textSize`), at once, here,
    /// before any screen is made, and again at each change. `names` are
    /// iOS's words that either may have changed, heard in `notifications`,
    /// where `didChange` is said too; a test hands in a centre of its own.
    init(notifications: NotificationCenter = .default, names: [Notification.Name],
         read: @escaping () -> TextSize, apply: @escaping (TextSize) -> Void) {
        self.notifications = notifications
        self.read = read
        self.apply = apply
        current = read()
        apply(current)
        for name in names {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: nil) {
                [weak self] _ in self?.look()
            })
        }
    }

    deinit {
        for observer in observers { notifications.removeObserver(observer) }
    }

    /// Reads the size again, on the main queue, after what is running there
    /// now, unless a look is already on its way: that one reads it. When it
    /// has changed, applies it and then says `didChange`. The share sheet
    /// calls this itself, as its traits change (`ShareViewController`).
    func look() {
        lock.lock()
        let go = !looking
        looking = true
        lock.unlock()
        guard go else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.looking = false
            self.lock.unlock()
            let now = self.read()
            guard now != self.current else { return }
            self.current = now
            self.apply(now)
            self.notifications.post(name: Self.didChange, object: self)
        }
    }
}

/// What a screen set from the text size, kept to be set again when it
/// changes (B-166): each step is run once as it is kept, and all of them
/// again, in the order kept, at `again`. A screen made once and kept open,
/// the composer or the share sheet, keeps a step for each label, field and
/// line it sizes, and runs them at `TextSizes.didChange`.
final class Restyles {
    private var steps: [() -> Void] = []

    /// Runs `step` now, and at every `again`.
    func keep(_ step: @escaping () -> Void) {
        step()
        steps.append(step)
    }

    func again() {
        for step in steps { step() }
    }
}
