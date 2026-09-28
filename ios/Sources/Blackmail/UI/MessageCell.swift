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
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        // Full-bleed selection with black text, the pre-iOS-13 treatment. The
        // modern default insets the highlight and greys the text, both of which
        // make "which message am I looking at" harder to answer at a glance.
        let selected = UIView()
        selected.backgroundColor = Theme.selection
        selectedBackgroundView = selected

        unreadDot.backgroundColor = Theme.tintBlue
        unreadDot.layer.cornerRadius = Theme.unreadDotDiameter / 2

        senderLabel.font = Theme.fontListSender
        senderLabel.textColor = Theme.primaryText
        timestampLabel.font = Theme.fontListTimestamp
        timestampLabel.textColor = Theme.secondaryText
        timestampLabel.textAlignment = .right
        subjectLabel.font = Theme.fontListSubject
        subjectLabel.textColor = Theme.primaryText
        previewLabel.font = Theme.fontListPreview
        previewLabel.textColor = Theme.secondaryText
        previewLabel.numberOfLines = 2

        attachmentIcon.image = UIImage(systemName: "paperclip")
        attachmentIcon.tintColor = Theme.secondaryText
        attachmentIcon.contentMode = .scaleAspectFit
        flagIcon.image = UIImage(systemName: "flag.fill")
        flagIcon.tintColor = Theme.flagTint
        flagIcon.contentMode = .scaleAspectFit

        spinner.color = Theme.secondaryText
        spinner.hidesWhenStopped = true

        for v in [unreadDot, senderLabel, timestampLabel, subjectLabel,
                  previewLabel, attachmentIcon, flagIcon, spinner] {
            contentView.addSubview(v)
        }
    }

    /// A spinner in the leading gutter, over the unread dot and the
    /// paperclip, which it hides while it turns: this row's letter is on its
    /// way, as a draft is to the composer. The gutter because it is the one
    /// place in a measured row that nothing else needs while it turns, so
    /// the text does not move.
    var isBusy = false {
        didSet {
            guard isBusy != oldValue else { return }
            if isBusy { spinner.startAnimating() } else { spinner.stopAnimating() }
            setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(with m: MessageSummary) {
        senderLabel.text = MailFormat.displayName(m.sender)
        timestampLabel.text = MailFormat.listTimestamp(m.date)
        subjectLabel.text = m.subject.isEmpty ? "(no subject)" : m.subject

        // Forced line height, so the two preview lines keep the row's own 20 pt
        // rhythm instead of the font's natural 18.
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = (Theme.previewLine2Baseline - Theme.previewLine1Baseline)
            * Theme.textScale
        ps.maximumLineHeight = ps.minimumLineHeight
        ps.lineBreakMode = .byTruncatingTail
        previewLabel.attributedText = NSAttributedString(string: m.preview, attributes: [
            .font: Theme.fontListPreview,
            .foregroundColor: Theme.secondaryText,
            .paragraphStyle: ps,
        ])
        unreadDot.isHidden = m.isRead
        attachmentIcon.isHidden = !m.hasAttachment
        flagIcon.isHidden = !m.isFlagged
        setNeedsLayout()
    }

    /// Places a label so its *baseline* lands at `baseline` points from the top
    /// of the row. Laying out by baseline rather than by frame top is what
    /// keeps the vertical rhythm identical when the type scale changes.
    /// The origin is snapped to the device pixel grid. Without it, `baseline -
    /// ascender` is a fractional y that differs per font (11.35 for 17 pt
    /// semibold, 13.25 for 15 pt), so two labels asked for the SAME baseline
    /// rasterised a pixel apart — the sender and the timestamp sat half a point
    /// out of line on every row.
    private func place(_ label: UILabel, baseline: CGFloat, left: CGFloat, width: CGFloat) {
        let scale = UIScreen.main.scale
        let y = (((baseline * Theme.textScale) - label.font.ascender) * scale).rounded() / scale
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
        let w = contentView.bounds.width
        let left = Theme.messageTextLeft + indent
        let gutterX = Theme.unreadDotCenterX + indent
        let right = w - Theme.rowTextRightInset
        let textWidth = right - left

        unreadDot.frame = CGRect(
            x: gutterX - Theme.unreadDotDiameter / 2,
            y: (Theme.unreadDotCenterY * Theme.textScale) - Theme.unreadDotDiameter / 2,
            width: Theme.unreadDotDiameter, height: Theme.unreadDotDiameter)
        spinner.center = CGPoint(x: gutterX, y: Theme.unreadDotCenterY * Theme.textScale)

        // The timestamp takes what it needs from the right; the sender gets the
        // rest, so a long name truncates instead of colliding with the date.
        let stampWidth = min(110, textWidth * 0.45)
        place(timestampLabel, baseline: Theme.senderBaseline,
              left: right - stampWidth, width: stampWidth)
        place(senderLabel, baseline: Theme.senderBaseline,
              left: left, width: textWidth - stampWidth - 8)

        // The paperclip belongs in the LEADING gutter on the sender line — the
        // same column the unread dot uses — not hung off the trailing end of
        // the subject. All three reference passes found it there and found
        // nothing trailing. UNMEASURED and decided here: the reference has no
        // row that is both unread AND has an attachment, so the dot wins the
        // gutter and the clip falls back to trailing when they collide.
        let clipInGutter = attachmentIcon.isHidden == false && unreadDot.isHidden
        // Faded rather than hidden under the spinner, so that nothing the
        // layout decides from what is hidden changes while it turns.
        unreadDot.alpha = isBusy ? 0 : 1
        attachmentIcon.alpha = isBusy && clipInGutter ? 0 : 1
        var subjectWidth = textWidth
        if clipInGutter {
            let size: CGFloat = 16
            attachmentIcon.frame = CGRect(
                x: gutterX - size / 2,
                y: (Theme.unreadDotCenterY * Theme.textScale) - size / 2,
                width: size, height: size)
        } else if !attachmentIcon.isHidden {
            attachmentIcon.frame = CGRect(x: right - 18,
                                          y: (Theme.subjectBaseline * Theme.textScale) - 13,
                                          width: 14, height: 14)
            subjectWidth -= 22
        }
        // The flag has no reference support in either position, so it keeps its
        // trailing place — but anchored to the same right edge as the timestamp
        // so the column's right edge stops being ragged between the two lines.
        if !flagIcon.isHidden {
            let x = right - 14 - (clipInGutter || attachmentIcon.isHidden ? 0 : 22)
            flagIcon.frame = CGRect(x: x, y: (Theme.subjectBaseline * Theme.textScale) - 13,
                                    width: 14, height: 14)
            subjectWidth -= 22
        }
        place(subjectLabel, baseline: Theme.subjectBaseline, left: left, width: subjectWidth)

        // Explicit leading. A 2-line label left to SF's natural 15 pt metrics
        // puts line 2 eighteen points below line 1, so `previewLine2Baseline`
        // was a constant the layout never consulted — it is set in configure().
        let pitch = (Theme.previewLine2Baseline - Theme.previewLine1Baseline) * Theme.textScale
        let firstBaseline = Theme.previewLine1Baseline * Theme.textScale
        let lineHeight = previewLabel.font.lineHeight
        previewLabel.frame = CGRect(
            x: left,
            y: firstBaseline - previewLabel.font.ascender - (pitch - lineHeight),
            width: textWidth, height: pitch * 2)
    }
}

#endif
