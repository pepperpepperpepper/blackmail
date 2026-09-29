// The pane widths come first and are plain arithmetic, so the host builds
// them and `PaneArrangementTests` checks them: which arrangement gets which
// width is the logic the view button switches (D-015). Everything after
// them is UIColor and UIFont, and is guarded to compile away on a host
// without UIKit.
import Foundation

/// Every layout number in the app. Nothing else may hard-code one.
///
/// These come from measuring the iOS 10 iPad Mail reference pixel by pixel; the
/// derivation of each is in `docs/LAYOUT_CONSTANTS.md`. They are split the way
/// D-007 splits them:
///
/// - **Binding** — positions, row heights, insets, control order, hit targets.
///   This is the product. A 90-year-old man's hands know where things are, and
///   these are what keep them there.
/// - **Advisory** — greys, fills, hairlines. Match where free, never fight the
///   OS for them. Layout was always the requirement; appearance became one
///   too with D-010, which made the dark look the shipped default, so the
///   palette below is now specified rather than inherited.
///
/// Phase 10 of `IMPLEMENTATION_PLAN.md` freezes this file. After that, changing a number here
/// needs the same approval as changing a feature.
enum Theme {

    // MARK: - Panes (binding)

    /// THREE panes: Mailboxes | message list | message. This reverses D-003,
    /// deliberately — the two-pane build was itself a correction to an earlier
    /// three-pane attempt, so the history here is not a drift but a decision
    /// taken twice. What changed is the arrival of the iOS 10 12.9-inch
    /// reference showing all three. Two panes came back beside them as his
    /// choice (D-015); see `twoPaneLeftColumnWidth`.
    ///
    /// FRACTIONS, not copied absolutes — the lesson from the two-pane list,
    /// where 320 pt was right only on the 1024 pt screen it came off and read
    /// as 27% instead of 31% on an 1194 pt iPad.
    ///
    /// Measured off the primary iOS 10 12.9-inch reference listed in
    /// `spec/references/REFERENCE_SCREENSHOTS.md` (kept locally and never
    /// committed — it is Macworld's image), which unlike
    /// the owner's photo IS a raw screenshot (580x435, aspect exactly 1.3333,
    /// no bezel) at 2.3552 pt/px. The two dividers are the only full-height
    /// low-variance dark columns in the image, at x=121 and x=281:
    ///
    ///     mailboxes  285 pt of 1366 = 20.9%
    ///     list       377 pt         = 27.6%
    ///     message    704 pt         = 51.5%
    static let mailboxColumnFraction: CGFloat = 0.209
    static let listColumnFraction: CGFloat = 0.276

    /// Clamps, so the proportions cannot produce something unusable at the
    /// extremes: the mailbox pane must still fit an indented subfolder name,
    /// and the list must not truncate a sender on sight.
    static let mailboxColumnMin: CGFloat = 220
    static let mailboxColumnMax: CGFloat = 320
    static let listColumnMin: CGFloat = 300
    static let listColumnMax: CGFloat = 420

    /// 1194 pt (11-inch) -> 250 / 330, leaving 614 for the message.
    /// 1366 pt (13-inch) -> 285 / 377, leaving 704 — the reference exactly.
    static func mailboxColumnWidth(forScreenWidth w: CGFloat) -> CGFloat {
        min(max((w * mailboxColumnFraction).rounded(), mailboxColumnMin), mailboxColumnMax)
    }
    static func listColumnWidth(forScreenWidth w: CGFloat) -> CGFloat {
        min(max((w * listColumnFraction).rounded(), listColumnMin), listColumnMax)
    }

    static let paneDividerWidth: CGFloat = 0.5

    /// TWO panes, D-015's other arrangement and his choice: the left column
    /// holds the Mailboxes or a folder's list in turn, and the message takes
    /// the rest. Three stay the default.
    ///
    /// 375, D-003's figure, and fixed rather than a fraction. It is the
    /// list's width on the 12.9-inch reference (377 measured), so on that
    /// iPad the list keeps its width across the switch, to 2 pt, and only
    /// the Mailboxes column comes and goes, which is what iOS 10's button
    /// did. The owner's own photo, a two-pane iPad at 1024 pt, puts the
    /// divider at 31%, which is 370 on the 11-inch: within 5 pt. Not the
    /// fraction, because what the column has to hold does not grow with the
    /// screen: with a folder open its bar carries the view button,
    /// "< Mailboxes", the calendar, the folder's name and Edit, and 31% of
    /// a 1024 pt iPad is 317.
    ///
    ///     1194 pt (11-inch)    375 | 818.5 for the message
    ///     1366 pt (12.9-inch)  375 | 990.5
    static let twoPaneLeftColumnWidth: CGFloat = 375
}

#if canImport(UIKit)

import UIKit

extension Theme {

    // MARK: - Chrome (binding)

    /// `navBarHeight 44` and `bottomToolbarHeight 44` used to sit here. Both
    /// were fiction twice over: nothing read them, and UIKit gives a
    /// regular-width iPad bar 50 pt regardless of what this file says. The
    /// device facts they were pretending to control — a 24 pt safe-area status
    /// bar against the reference's 20, a 50 pt nav bar against 44, and a ~21 pt
    /// home indicator — cost about 25 pt of list budget, a quarter of a row,
    /// before the app draws anything. That is recorded in
    /// `docs/LAYOUT_CONSTANTS.md` where a fact belongs, not as a constant
    /// asserting control it does not have.
    static let searchBarHeight: CGFloat = 44.5
    static let searchFieldHeight: CGFloat = 28
    static let searchFieldSideInset: CGFloat = 8

    /// How far a letter inside an opened conversation is set in from the
    /// edge.
    ///
    /// Colour alone was doing this job and it was not enough: a tinted
    /// row still begins at the same left edge as a top-level one, so the
    /// eye reads a list of equals in two shades rather than a group and
    /// its contents. The indent is what says "these belong to the line
    /// above".
    static let threadChildIndent: CGFloat = 20

    /// A row in the composer's address-suggestion list.
    ///
    /// Taller than `minHitTarget` because the row carries TWO lines: the
    /// name he recognises and, under it, the address it actually resolves
    /// to. At 44 the second line was clipped away entirely, which left
    /// "Carlo" standing for an address he could not see — and two people
    /// can share a name.
    static let suggestionRowHeight: CGFloat = 60

    /// The Current Mailbox / All Mailboxes strip, which exists only while
    /// search is active and so costs the list nothing the rest of the time.
    ///
    /// Not in the 2016 reference, which has no scope bar at all — this is
    /// Mail's own control, added because the requirement is that the
    /// app work as Mail does (D-012). Mail's strip of this era is about
    /// 29 pt; this is taller so the two buttons clear a 34 pt tap target,
    /// which is the same trade `minHitTarget` records everywhere else.
    static let searchScopeBarHeight: CGFloat = 40

    /// Every tappable control gets at least this, whatever the glyph measures.
    /// From the accessibility requirement, not from the reference — you cannot
    /// recover a hit area from pixels.
    static let minHitTarget: CGFloat = 44

    /// Width reserved for the list toolbar's leading button, and mirrored as
    /// dead space on the trailing side. Without the mirror, "Updated Just Now"
    /// centres in what is LEFT of the toolbar rather than in the pane, which
    /// measured 20 pt off-centre — the reference centres it in the pane.
    static let toolbarLeadingSlot: CGFloat = 72

    // MARK: - Mailbox rows (binding)

    /// The break between the Inbox block and the folders block.
    ///
    /// Classic Mail separates the two, and `sectionGapHeight` and
    /// `sectionGapFill` used to sit in this file for it — declared,
    /// never read, and deleted for being a number describing a build that
    /// did not exist (B-004). The gap exists now, so the number comes back
    /// with a reader this time.
    static let mailboxSectionGap: CGFloat = 28

    static let mailboxRowHeight: CGFloat = 44
    static let mailboxSeparatorInset: CGFloat = 55
    /// One step per level of nesting, rather than a separate constant per
    /// level. `mailboxSubfolderSeparatorInset 86` and `mailboxIconCenterXIndented
    /// 65` used to sit here and were never read — the list computes
    /// `mailboxIconCenterX + depth * mailboxIndentStep` instead, which handles
    /// depth 2 as well as depth 1.
    static let mailboxIndentStep: CGFloat = 31
    static let mailboxIconCenterX: CGFloat = 29.25

    // MARK: - Message rows (binding)

    /// 96, not the 104 the 12.9-inch reference gave. Measured off the owner's
    /// own iPad: seven sender lines fit a straight line at 41.50 px pitch with
    /// every residual under 0.6 px, and the row separators land on exactly that
    /// grid (90.5, 132, 173.5, 215, 256.5, 298, 339.5). 41.5 px / 0.4326 px-per-pt
    /// = 95.9 pt. See `spec/references/OWNER_SCREENSHOT_GEOMETRY.md` for the
    /// screen rect that scale depends on — the reference is a photo of a whole
    /// iPad, so the screen is a sub-rectangle and measuring the image bounds
    /// inflates everything by 31%.
    static let messageRowHeight: CGFloat = 96
    /// Both KEPT at 29 on purpose, and not because they were confirmed. The
    /// reference's screen origin is unresolvable to better than 1.5 px (67.14
    /// px if you force the rect to exact 4:3, 68.6 px if you pin it with the
    /// nav/search 8 pt insets), which is ±3.5 pt on every "distance from the
    /// pane's left edge" in the image. The three passes read the separator at
    /// 22.6 / 26.1 / 29.9 — a 7 pt spread — so there is no number in there to
    /// move to. Two of the three did put the separator's left end on the same
    /// pixel column as the text's first ink, which is why these stay equal.
    static let messageSeparatorInset: CGFloat = 29
    static let messageTextLeft: CGFloat = 29
    /// 15, not 16: three passes read 15.0 / 14.6 / 13.5. The delta is inside a
    /// single pass's error but the bias is consistent across all three.
    static let rowTextRightInset: CGFloat = 15

    /// UNVERIFIABLE against the reference, and flagged as such rather than
    /// quietly presented as measured: every row in the owner's screenshot is
    /// read, so there is no dot anywhere in it (the gutter's maximum chroma is
    /// 2/255). Diameter and centre are inherited assumptions. The only evidence
    /// the gutter column exists at this size is the paperclip that sits in it,
    /// whose centre three passes put at x 14-16, y 18-21.
    static let unreadDotDiameter: CGFloat = 12
    static let unreadDotCenterX: CGFloat = 14
    /// Rides with the sender baseline, 5.5 pt above it, or the dot drifts off
    /// the name it belongs to.
    static let unreadDotCenterY: CGFloat = 18.5

    /// Baselines from the top of the row. Measured, not derived from line
    /// heights — the reference does not use the font's natural leading.
    ///
    /// The 20 pt pitch was always right: the reference's four text lines span
    /// 60.1 pt first baseline to last and these span 60.0. What was wrong was
    /// where the block SAT — and then, briefly, wrong in the other direction.
    /// An earlier change moved it up 7 pt off a single-pass reading of ~20.5 pt;
    /// three independent passes put the sender baseline at 23.8 / 25.4 / 22.9,
    /// mean 24 ±1.5, so that overshot by 3.5 pt and crowded the separator.
    ///
    /// COUPLING: these four are one rigid block. `MessageCell.place()` scales
    /// each by `textScale` while `messageRowHeightScaled` scales the row by the
    /// same factor, so the block stays proportional at any type size
    /// (24/96 = 25%, 84/96 = 87.5%). If `messageRowHeight` ever moves again,
    /// all four move by the same ratio IN THE SAME COMMIT.
    static let senderBaseline: CGFloat = 24
    static let subjectBaseline: CGFloat = 44
    static let previewLine1Baseline: CGFloat = 64
    static let previewLine2Baseline: CGFloat = 84

    // MARK: - Message detail (binding)

    /// 26, the best-supported absolute inset in the whole reference: five
    /// separate elements (sender, To:, subject, date, and the body's first
    /// line) share one ink column, read as 26.0 / 26.2 / 24-26. It feeds both
    /// the header's constraints and the web wrapper's padding, so the letter
    /// lines up with the name of whoever sent it.
    static let detailContentInsetLeft: CGFloat = 26
    /// Deliberately 5 pt LEFT of the text, not equal to it. The reference's
    /// rules start at 22-23 pt, and a solid line localises to ±1.2 pt — far
    /// better than any glyph in this image — so the offset is real.
    static let detailRuleInsetLeft: CGFloat = 21

    /// Vertical rhythm of the detail header, from the nav bar's bottom edge.
    /// Previously seven bare numbers inside `MessageHeaderView`'s constraints,
    /// which broke this file's own "nothing else may hard-code one" rule.
    static let detailSenderTopPadding: CGFloat = 8
    static let detailSenderToGap: CGFloat = 2
    static let detailToRuleGap: CGFloat = 17
    static let detailRuleSubjectGap: CGFloat = 6
    static let detailSubjectDateGap: CGFloat = 3
    static let detailDateAttachmentGap: CGFloat = 3
    static let detailAttachmentRuleGap: CGFloat = 14

    // MARK: - Type (binding in size, see D-007's open question)

    /// The reference's scale, drawn for 2016 eyesight. For a 90-year-old this
    /// is the floor, not the target — `textScale` exists so it can be raised
    /// without the row rhythm falling apart, because row heights scale with it.
    static var textScale: CGFloat = 1.0

    static func scaled(_ points: CGFloat) -> CGFloat { (points * textScale).rounded() }

    static var fontListSender: UIFont { .systemFont(ofSize: scaled(17), weight: .semibold) }
    static var fontListSubject: UIFont { .systemFont(ofSize: scaled(15)) }
    static var fontListPreview: UIFont { .systemFont(ofSize: scaled(15)) }
    static var fontListTimestamp: UIFont { .systemFont(ofSize: scaled(15)) }
    static var fontMailboxName: UIFont { .systemFont(ofSize: scaled(17)) }
    static var fontMailboxCount: UIFont { .systemFont(ofSize: scaled(17)) }
    static var fontNavTitle: UIFont { .systemFont(ofSize: scaled(17), weight: .semibold) }
    static var fontBarButton: UIFont { .systemFont(ofSize: scaled(17)) }
    static var fontDetailSender: UIFont { .systemFont(ofSize: scaled(17), weight: .semibold) }
    static var fontDetailMeta: UIFont { .systemFont(ofSize: scaled(15)) }
    /// 17 pt bold, not the 22 pt the 12.9-inch reference measures. The owner's
    /// screenshot is of the iPad he actually used, and there the subject sits
    /// third in the header at roughly sender size. His layout wins over the
    /// bigger screen's.
    static var fontDetailSubject: UIFont { .boldSystemFont(ofSize: scaled(17)) }
    static var fontToolbarStatus: UIFont { .systemFont(ofSize: scaled(11)) }

    /// Body leading in the reading pane, as a multiple of the type size. The
    /// reference's body pitch is 24.0 pt on 17 pt type (23.9 and 24.0 from two
    /// independent passes), so 24/17 = 1.41.
    static let detailBodyLineHeight: CGFloat = 1.41

    /// Row heights move with the type or the rhythm breaks. This is exactly why
    /// free Dynamic Type is not wired up: an accidental swipe in Control Centre
    /// must never rearrange his mail.
    static var messageRowHeightScaled: CGFloat { (messageRowHeight * textScale).rounded() }
    static var mailboxRowHeightScaled: CGFloat { (mailboxRowHeight * textScale).rounded() }

    // MARK: - Colour (advisory)

    // MARK: The app ships DARK.
    //
    // The owner's iPad ran with Smart Invert on (confirmed on device:
    // `InvertColorsEnabled 1`, `AXSClassicInvertColorsPreference 0`), and the
    // requirement is that this look be the shipped default with no
    // accessibility setting required. So every neutral below is the literal
    // 255-x inversion of the light value it replaces, which is what that
    // filter was doing to them.
    //
    // ⚠️ SMART INVERT MUST NOW BE TURNED OFF on any device running this
    // build, or it inverts these back and the app returns to white.
    //
    // Three colours are deliberately NOT inverted — see `tintBlue` below.

    /// NOT inverted. Smart Invert was turning this into orange (#FF8500),
    /// because a display filter cannot know that a hue carries meaning. Blue
    /// on black is what every other app on his iPad uses for "you can tap
    /// this", and that consistency is worth more than matching the filter's
    /// side effect. Same reasoning keeps Delete red and the flag orange:
    /// inverted they read as cyan and blue, and a destructive control that
    /// does not look destructive is a safety regression, not a style choice.
    /// If he wants the literal inversion, these three are the whole change.
    static let tintBlue = UIColor(red: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
    static let destructive = UIColor(red: 255 / 255, green: 69 / 255, blue: 58 / 255, alpha: 1)
    static let flagTint = UIColor(red: 255 / 255, green: 159 / 255, blue: 10 / 255, alpha: 1)

    static let separator = UIColor(white: 55 / 255, alpha: 1)           // was 200
    static let paneDivider = UIColor(red: 113 / 255, green: 113 / 255, blue: 108 / 255, alpha: 1)
    static let detailRule = UIColor(white: 55 / 255, alpha: 1)          // was 200
    static let selection = UIColor(white: 38 / 255, alpha: 1)           // was 217, full bleed
    static let secondaryText = UIColor(white: 142 / 255, alpha: 1)      // self-inverse, stays
    static let mailboxCountText = UIColor(white: 127 / 255, alpha: 1)   // was 128
    /// Everything that was black text is now this.
    static let primaryText = UIColor.white
    // `sectionGapFill` and `sectionGapHeight 28` lived here for a grouped
    // mailbox list (an Inbox block above a folders block) that was never built.
    // Removed rather than left asserting a layout the app does not have; the
    // missing feature is logged in docs/KNOWN_ISSUES.md as B-004.
    static let searchBarFill = UIColor(red: 54 / 255, green: 54 / 255, blue: 49 / 255, alpha: 1)
    /// White on the grey band. This one is advisory-by-category but binding in
    /// effect: the reference separates field from band by 42 levels and the
    /// build managed 9, which is the difference between "a box you type in"
    /// and "a grey slab". Contrast is legibility, not taste.
    static let searchFieldFill = UIColor.black            // was white
    static let searchFieldCornerRadius: CGFloat = 5
    static let barFill = UIColor(white: 6 / 255, alpha: 1)             // was 249
    static let canvas = UIColor.black                                  // was white

    // MARK: - Toolbar order (BINDING — the most load-bearing constant here)

    /// Confirmed against the reference pixels, closing `UI_SPEC.md`'s own hedge.
    /// This order does not change between messages, folders, or orientations.
    /// If anything in this file is sacred, it is this.
    enum ToolbarAction: Int, CaseIterable {
        case flag, move, delete, reply, compose
    }
}

#endif
