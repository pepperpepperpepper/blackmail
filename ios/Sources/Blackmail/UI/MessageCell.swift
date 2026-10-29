// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// A message-list row, laid out by hand.
///
/// This has to be a custom cell rather than a `UIListContentConfiguration`, and
/// the reason is structural: the timestamp sits at the *top right*, on the
/// sender's baseline, and no content configuration can place it there. The
/// starter code's `defaultContentConfiguration()` approach cannot produce this
/// row at all — which is why its 74 pt guess was never going to match the
/// measured 104.
///
/// Every number comes from `Theme`. Baselines are measured from the top of the
/// row, not derived from font leading, because the reference does not use the
/// font's natural line spacing.
final class MessageCell: UITableViewCell {

    static let reuseID = "MessageCell"

    private let unreadDot = UIView()
    private let senderLabel = UILabel()
    private let timestampLabel = UILabel()
    private let subjectLabel = UILabel()
    private let previewLabel = UILabel()
    private let attachmentIcon = UIImageView()
    private let flagIcon = UIImageView()
    /// Mail's grey arrow in the gutter, for a letter answered or forwarded
    /// (`RowArrow`, B-102). Hidden on a row with no arrow, an unread one
    /// among them.
    private let statusIcon = UIImageView()
    /// Its two images, made once: the reply arrow and the forward arrow,
    /// each at a size of its own (B-071).
    private let repliedArrow = UIImage(systemName: RowArrow.replied.symbolName,
                                       withConfiguration: Theme.rowArrowSymbol)
    private let forwardedArrow = UIImage(systemName: RowArrow.forwarded.symbolName,
                                         withConfiguration: Theme.rowArrowSymbol)
    /// Mail's mark of a conversation, a blue chevron in a circle after the
    /// date, on a row of more than one letter, in every folder: the names
    /// have no count after them (B-075, B-080). A mark alone: tapping the
    /// row opens the conversation, as anywhere else.
    private let conversationMark = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// The row's date, kept to be written again where it is (`drawDate`).
    private var date: Date?
    /// The text size the row's type was last set for (`restyle`).
    private var styled: TextSize?
    /// The preview's words, drawn in the grey the row's state calls for
    /// (`drawPreview`).
    private var previewText = ""
    /// The letter has no subject: the subject line says Mail's "No
    /// Subject" in the row's grey (`drawSubject`, `RowPreview`, B-182).
    private var subjectIsGrey = false
    /// The ground of a selected or pressed row: Mail's blue for the letter
    /// in the pane and for a tick in Edit mode, the grey of a press
    /// otherwise (`colour`, `RowShade`, B-174, B-181).
    private let selectedGround = UIView()

    /// The list is in Edit mode, where a selected row is a tick, drawn as
    /// Mail draws one (r6 comparison C-03): the row its blue,
    /// rgb(10,132,255), the tick a white disc, the names and the subject
    /// white as always, and the grey lines in Mail's see-through grey,
    /// which reads (145,194,249) on the blue. It was the letter-in-the-pane
    /// grey with a blue tick. Colours only: nothing moves (B-174). Since
    /// B-181 the letter in the pane is drawn in the same colours out of
    /// Edit mode, as Mail's is (`RowShade`); this says only whether a press
    /// is blue and whether the row's own tick shows.
    var ticks = false {
        didSet {
            guard ticks != oldValue else { return }
            colour()
        }
    }

    /// Mail's grey for the second lines (`secondaryLabel` in the dark),
    /// through which a ticked row's blue shows.
    private static let tickedGrey = UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255,
                                            alpha: 0.6)

    /// The tick's colours, [check, disc]: the row's blue on white, as
    /// Mail's is.
    private static let tickPalette = UIImage.SymbolConfiguration(paletteColors: [Theme.tintBlue, .white])
    /// The row's own tick (`placeTick`), over UIKit's in UIKit's edit
    /// control, on every iOS the app runs on. In the white tint of a
    /// ticked row UIKit's own tick is lost: from 17 its white check on a
    /// white disc, seen on the iOS 17.5 and 18.6 simulators, and on 16 a
    /// plain white disc with no check, seen on the test iPad in round
    /// r6-m-fix (KNOWN_ISSUES B-174), where Mail draws its blue check on
    /// the white disc. Made the first time it is asked for.
    private lazy var tickMark: UIImageView = {
        let mark = UIImageView()
        mark.isUserInteractionEnabled = false
        mark.isHidden = true
        return mark
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        // Full-bleed selection, the pre-iOS-13 treatment. The modern default
        // insets the highlight and greys the text, both of which make "which
        // message am I looking at" harder to answer at a glance. Its colour
        // as the row is selected or pressed (`colour`, `RowShade`).
        selectedGround.backgroundColor = Theme.selection
        selectedBackgroundView = selectedGround

        unreadDot.backgroundColor = Theme.tintBlue
        unreadDot.layer.cornerRadius = Theme.unreadDotDiameter / 2

        senderLabel.textColor = Theme.primaryText
        timestampLabel.textColor = Theme.secondaryText
        timestampLabel.textAlignment = .right
        subjectLabel.textColor = Theme.primaryText
        previewLabel.textColor = Theme.secondaryText
        previewLabel.numberOfLines = 2

        attachmentIcon.image = UIImage(systemName: "paperclip")
        attachmentIcon.tintColor = Theme.secondaryText
        attachmentIcon.contentMode = .scaleAspectFit
        flagIcon.image = UIImage(systemName: "flag.fill")
        flagIcon.tintColor = Theme.flagTint
        flagIcon.contentMode = .scaleAspectFit
        // The preview's grey. Mail's arrow is its lighter tertiary grey,
        // whose inversion, about 59 on black, would be too dim (D-020).
        statusIcon.tintColor = Theme.secondaryText
        statusIcon.contentMode = .scaleAspectFit
        statusIcon.isHidden = true
        conversationMark.tintColor = Theme.tintBlue
        conversationMark.contentMode = .center
        conversationMark.isHidden = true

        spinner.color = Theme.secondaryText
        spinner.hidesWhenStopped = true

        for v in [unreadDot, statusIcon, senderLabel, timestampLabel, subjectLabel,
                  previewLabel, attachmentIcon, flagIcon, conversationMark, spinner] {
            contentView.addSubview(v)
        }
        restyle()
    }

    /// The row's type, and the conversation mark drawn at the date's size,
    /// as the text size is now (`Theme.textSize`, B-166): set as the cell
    /// is made, and again as it is next given a row once the size or Bold
    /// Text has changed, which the list's redraw at that change does for
    /// every row in sight. The arrow needs nothing: its box is the row's,
    /// and it is scaled to fit it.
    private func restyle() {
        guard styled != Theme.textSize else { return }
        styled = Theme.textSize
        senderLabel.font = Theme.fontListSender
        timestampLabel.font = Theme.fontListTimestamp
        subjectLabel.font = Theme.fontListSubject
        previewLabel.font = Theme.fontListPreview
        conversationMark.image = UIImage(systemName: "chevron.forward.circle",
                                         withConfiguration: Theme.conversationMarkSymbol)
        setNeedsLayout()
    }

    /// A spinner in the leading gutter, over the unread dot, the arrow and
    /// the paperclip, which it hides while it turns: this row's letter is
    /// on its way, as a draft is to the composer. The gutter because it is
    /// the one place in a measured row that nothing else needs while it
    /// turns, so the text does not move.
    var isBusy = false {
        didSet {
            guard isBusy != oldValue else { return }
            if isBusy { spinner.startAnimating() } else { spinner.stopAnimating() }
            setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// `marked`: the row ends its top line with the mark of a
    /// conversation (`MessageThread.marksConversation(in:)`).
    func configure(with m: MessageSummary, marked: Bool) {
        restyle()
        // The top line as the row gives it (`MessageThread.displayRow`),
        // which has named each sender already (`participants`). Read again
        // as one sender, a line naming whom was cut at its first "<", and
        // a name that is itself an address lost the real one after it
        // (`RowNames.fullName`, B-075).
        senderLabel.text = m.sender
        // When the letter arrived, the date the list is in order of, as
        // Mail's row shows it; its Date where that is not known
        // (`MessageSummary.listDate`, B-178).
        date = m.listDate
        drawDate()
        // Mail's "No Subject" in the grey where there is none (B-182).
        subjectLabel.text = RowPreview.subject(m.subject)
        subjectIsGrey = RowPreview.subjectIsGrey(m.subject)
        drawSubject()

        previewText = m.preview
        drawPreview()
        unreadDot.isHidden = m.isRead
        // The arrow, where the row has one: never on an unread row, whose
        // dot has the gutter (`RowArrow`).
        let arrow = m.arrow
        statusIcon.image = arrow == .forwarded ? forwardedArrow : repliedArrow
        statusIcon.isHidden = arrow == nil
        attachmentIcon.isHidden = !m.hasAttachment
        flagIcon.isHidden = !m.isFlagged
        conversationMark.isHidden = !marked
        setNeedsLayout()
    }

    /// The preview's two lines in the grey the row's state calls for.
    private func drawPreview() {
        // Forced line height, so the two preview lines keep the row's own 20 pt
        // rhythm instead of the font's natural 18, at any text size.
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = Theme.messageRowLines.pitch
        ps.maximumLineHeight = ps.minimumLineHeight
        ps.lineBreakMode = .byTruncatingTail
        previewLabel.attributedText = NSAttributedString(string: previewText, attributes: [
            .font: Theme.fontListPreview,
            .foregroundColor: grey,
            .paragraphStyle: ps,
        ])
    }

    /// The row's colours as it is now: selected, pressed, in Edit mode
    /// (`RowShade`, B-174, B-181).
    private var shade: RowShade {
        RowShade(selected: isSelected, pressed: isHighlighted, ticks: ticks)
    }

    /// The second lines' grey: Mail's see-through one on a selected row,
    /// the letter in the pane or a tick.
    private var grey: UIColor { shade.onBlue ? Self.tickedGrey : Theme.secondaryText }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        colour()
    }

    /// A press's ground, and the row's own tick, which follows a press as
    /// UIKit's does (`RowShade.tick`).
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        colour()
    }

    /// The row's colours as it is selected, pressed or ticked (`RowShade`,
    /// B-174, B-181): the ground, the tick, and on a selected row, the
    /// letter in the pane as a tick, the grey lines, the paperclip and the
    /// arrow in Mail's see-through grey, and the unread dot and the
    /// conversation's mark white, as they would be lost blue on blue (Mail's
    /// ticked row was seen with neither). The names, the subject and the
    /// flag keep theirs; a missing subject's "No Subject" takes the grey.
    private func colour() {
        let shade = self.shade
        switch shade.ground {
        case .blue?: selectedGround.backgroundColor = Theme.tintBlue
        case .grey?: selectedGround.backgroundColor = Theme.selection
        case nil: break
        }
        // UIKit draws the tick in the cell's tint: on 16 a plain white
        // disc, no check, as round r6-m-fix saw (KNOWN_ISSUES B-174), and
        // from 17 a white check on it. The row draws its own tick over
        // UIKit's on both (`placeTick`). The circle of a row not ticked
        // is UIKit's grey whatever the tint.
        tintColor = ticks ? .white : nil
        tickMark.isHidden = !shade.tick
        setNeedsLayout()
        let grey = self.grey
        guard timestampLabel.textColor != grey else { return }
        timestampLabel.textColor = grey
        attachmentIcon.tintColor = grey
        statusIcon.tintColor = grey
        unreadDot.backgroundColor = shade.onBlue ? .white : Theme.tintBlue
        conversationMark.tintColor = shade.onBlue ? .white : Theme.tintBlue
        drawSubject()
        drawPreview()
    }

    /// The subject line's colour: white, or the row's grey for Mail's "No
    /// Subject" (`subjectIsGrey`, B-182).
    private func drawSubject() {
        subjectLabel.textColor = subjectIsGrey ? grey : Theme.primaryText
    }

    /// The date at the top right written from the row's own, as the iPad
    /// writes it now: as the row is drawn, and again where it is when the
    /// 24-Hour Time switch, the time zone or the region has changed, or the
    /// day has turned over, so a letter of 11:50 PM reads "Yesterday" once
    /// midnight has passed (B-139). Nothing else on the row is touched; the
    /// top line is laid out again, as the date's width decides the names'.
    func drawDate() {
        guard let date else { return }
        timestampLabel.text = MailFormat.listTimestamp(date)
        setNeedsLayout()
    }

    /// Places a label so its *baseline* lands at `baseline` points from the top
    /// of the row, as `RowLines` has it at the text size. Laying out by
    /// baseline rather than by frame top is what keeps the vertical rhythm
    /// identical when the type scale changes.
    /// The origin is snapped to the device pixel grid. Without it, `baseline -
    /// ascender` is a fractional y that differs per font (11.35 for 17 pt
    /// semibold, 13.25 for 15 pt), so two labels asked for the SAME baseline
    /// rasterised a pixel apart — the sender and the timestamp sat half a point
    /// out of line on every row.
    private func place(_ label: UILabel, baseline: CGFloat, left: CGFloat, width: CGFloat) {
        let scale = UIScreen.main.scale
        let y = ((baseline - label.font.ascender) * scale).rounded() / scale
        label.frame = CGRect(x: left, y: y, width: width, height: label.font.lineHeight)
    }

    /// Set in from the leading edge, for a letter shown inside an opened
    /// conversation. Zero for every ordinary row, so the measured layout
    /// is untouched when it is not used.
    ///
    /// Applied to the text column AND the gutter the unread dot and the
    /// paperclip share, so the whole row moves as one piece rather than
    /// the words sliding out from under their own markers. The right edge
    /// does not move: the timestamps stay in one column down the list,
    /// which is what makes a date easy to find.
    var indent: CGFloat = 0 {
        didSet { if indent != oldValue { setNeedsLayout() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeTick()
        let w = contentView.bounds.width
        let left = Theme.messageTextLeft + indent
        let gutterX = Theme.unreadDotCenterX + indent
        let right = w - Theme.rowTextRightInset
        let textWidth = right - left
        // The lines at the text size (B-166), the row at Large's own at
        // Large, and the trailing paperclip and flag with them.
        let lines = Theme.messageRowLines
        let s = Theme.textScale

        unreadDot.frame = CGRect(
            x: gutterX - Theme.unreadDotDiameter / 2,
            y: (Theme.unreadDotCenterY * Theme.textScale) - Theme.unreadDotDiameter / 2,
            width: Theme.unreadDotDiameter, height: Theme.unreadDotDiameter)
        spinner.center = CGPoint(x: gutterX, y: Theme.unreadDotCenterY * Theme.textScale)

        // The timestamp takes what it needs from the right; the sender gets the
        // rest, so a long name truncates instead of colliding with the date.
        // The mark of a conversation, on a row that has one, ends the line
        // at the right edge, as Mail's does, and the date ends before it,
        // inside the room it always had (`RowTopLine`, B-075). Where the
        // date's own text needs more, as "Wednesday" in Edit mode in three
        // panes, the names give it up, never the date (B-080).
        let markSize = conversationMark.isHidden ? nil : conversationMark.image?.size
        // At the accessibility sizes the date and the mark have a line of
        // their own under the names (`RowLines.stacked`).
        let line = RowTopLine(left: left, right: right, mark: markSize?.width,
                              gap: Theme.conversationMarkGap,
                              date: timestampLabel.intrinsicContentSize.width,
                              scale: s, stacked: lines.stacked)
        if let markSize, let markX = line.markX {
            // Centred on the date's figures, as Mail's sits beside its date.
            let scale = UIScreen.main.scale
            let figures = lines.date - timestampLabel.font.capHeight / 2
            conversationMark.frame = CGRect(
                x: (markX * scale).rounded() / scale,
                y: ((figures - markSize.height / 2) * scale).rounded() / scale,
                width: markSize.width, height: markSize.height)
        }
        place(timestampLabel, baseline: lines.date,
              left: line.dateX, width: line.dateWidth)
        place(senderLabel, baseline: lines.names,
              left: line.namesX, width: line.namesWidth)

        // The paperclip belongs in the LEADING gutter on the sender line — the
        // same column the unread dot uses — not hung off the trailing end of
        // the subject. All three reference passes found it there and found
        // nothing trailing. UNMEASURED and decided here: the reference has no
        // row that is both unread AND has an attachment, so the dot wins the
        // gutter and the clip falls back to trailing when they collide.
        //
        // The gutter holds one thing, in this order: the spinner over all,
        // then the dot, then the arrow, then the clip (D-020, B-102). So the
        // clip goes to the end of the subject's line whenever the dot or the
        // arrow has the gutter, as Mail's sits there beside its arrow.
        let clipInGutter = attachmentIcon.isHidden == false && unreadDot.isHidden
            && statusIcon.isHidden
        // Faded rather than hidden under the spinner, so that nothing the
        // layout decides from what is hidden changes while it turns.
        unreadDot.alpha = isBusy ? 0 : 1
        statusIcon.alpha = isBusy ? 0 : 1
        attachmentIcon.alpha = isBusy && clipInGutter ? 0 : 1
        if !statusIcon.isHidden {
            // Centred where the dot is, as wide as the dot, the arrow
            // scaled to fit (`Theme.rowArrowBox`).
            let size = Theme.rowArrowBox
            statusIcon.frame = CGRect(
                x: gutterX - size / 2,
                y: (Theme.unreadDotCenterY * Theme.textScale) - size / 2,
                width: size, height: size)
        }
        var subjectWidth = textWidth
        if clipInGutter {
            let size: CGFloat = 16
            attachmentIcon.frame = CGRect(
                x: gutterX - size / 2,
                y: (Theme.unreadDotCenterY * Theme.textScale) - size / 2,
                width: size, height: size)
        } else if !attachmentIcon.isHidden {
            attachmentIcon.frame = CGRect(x: right - 18 * s,
                                          y: lines.subject - 13 * s,
                                          width: 14 * s, height: 14 * s)
            subjectWidth -= 22 * s
        }
        // The flag has no reference support in either position, so it keeps its
        // trailing place — but anchored to the same right edge as the timestamp
        // so the column's right edge stops being ragged between the two lines.
        if !flagIcon.isHidden {
            let x = right - 14 * s - (clipInGutter || attachmentIcon.isHidden ? 0 : 22 * s)
            flagIcon.frame = CGRect(x: x, y: lines.subject - 13 * s,
                                    width: 14 * s, height: 14 * s)
            subjectWidth -= 22 * s
        }
        place(subjectLabel, baseline: lines.subject, left: left, width: subjectWidth)

        // Explicit leading. A 2-line label left to SF's natural 15 pt metrics
        // puts line 2 eighteen points below line 1, so `previewLine2Baseline`
        // was a constant the layout never consulted — it is set in configure().
        let pitch = lines.pitch
        let firstBaseline = lines.preview
        let lineHeight = previewLabel.font.lineHeight
        previewLabel.frame = CGRect(
            x: left,
            y: firstBaseline - previewLabel.font.ascender - (pitch - lineHeight),
            width: textWidth, height: pitch * 2)
    }

    /// The row's own tick on a ticked row and during a press on one of
    /// Edit mode (`RowShade.tick`), on 16 as from 17 (`tickMark`):
    /// the check in the row's blue on a white disc (`tickPalette`), put
    /// inside UIKit's edit control over UIKit's own tick, at its frame and
    /// at its size at every text size, so it slides in and out with it and
    /// nothing moves. UIKit's edit control is the row's one control: the
    /// content view is none, and the row has no accessory or reorder
    /// control. Hidden otherwise, and wherever the control or an image
    /// view in it is not found, which leaves UIKit's alone. The control,
    /// UIKit's `UITableViewCellEditControl`, a `UIControl` that is the
    /// cell's own subview with its tick the first image view in it, as
    /// read on the 17.5 simulator through the debugger; the same class is
    /// in the iOS 16.5 SDK. Not covered: another image view in the control
    /// ahead of UIKit's tick, as the shadow view (`_shadowView`) an older
    /// UIKit's control had, whose frame and content mode the row's tick
    /// would then take in place of the tick's.
    private func placeTick() {
        guard shade.tick, let control = subviews.first(where: { $0 is UIControl }),
              let drawn = control.subviews.first(where: { $0 is UIImageView && $0 !== tickMark })
                as? UIImageView
        else {
            tickMark.isHidden = true
            return
        }
        if tickMark.superview !== control {
            control.addSubview(tickMark)
        } else {
            control.bringSubviewToFront(tickMark)
        }
        tickMark.preferredSymbolConfiguration = drawn.preferredSymbolConfiguration
        tickMark.contentMode = drawn.contentMode
        tickMark.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: Self.tickPalette)
        tickMark.frame = drawn.frame
        tickMark.isHidden = false
    }
}

#endif
