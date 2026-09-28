// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// Sender, recipient, subject and date above the message body.
///
/// The order here is taken from the supplied reference, and it is
/// **not** the order the 12.9-inch measurements implied:
///
///     Sarah Castelblanco      <- sender, blue, semibold
///     To: Eden Sears          <- grey
///     ------------------------
///     Not the same without you <- subject, black, bold, roughly sender-sized
///     Today at 9:14 AM        <- grey
///     ------------------------
///     body
///
/// The earlier build had the subject first at 22 pt, which came from measuring
/// the 12.9-inch iPad Pro shot where the subject really is that large. On the
/// iPad he actually used, the subject sits third and is close to body size.
/// The supplied screenshot wins: it is the layout his hands know.
///
/// No avatar. The reference has one at the right of the sender line; `BRIEF.md`
/// bans sender photographs and that ban still holds. It costs horizontal room
/// and tells him nothing the name beside it does not.
final class MessageHeaderView: UIView {

    private let senderLabel = UILabel()
    private let toLabel = UILabel()
    private let subjectLabel = UILabel()
    private let dateLabel = UILabel()
    /// One tappable row per file, not one blue label listing them all.
    ///
    /// The label was styled like a link and was not one — the single worst
    /// state for a control to be in, and for a reader who cannot tell
    /// "nothing happened" from "I missed" it is actively cruel. A row each
    /// also gives every file its own `minHitTarget`-sized target instead of
    /// one line of 13 pt text shared between them.
    private let attachmentStack = UIStackView()
    private var attachmentButtons: [String: UIButton] = [:]

    /// Fired when a file is tapped. The header does not know how to open
    /// one; it only knows which was chosen.
    ///
    /// The rows are greyed while there is none: the header lists a letter's
    /// files from the tap, from its list row, and they can be opened once
    /// the letter has come. Greyed rather than live and ignoring the tap,
    /// which reads as a tap that missed.
    var onSelectAttachment: ((Attachment) -> Void)? {
        didSet {
            for button in attachmentButtons.values { button.isEnabled = onSelectAttachment != nil }
        }
    }
    private let topRule = UIView()
    private let bottomRule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.canvas

        senderLabel.font = Theme.fontDetailSender
        senderLabel.textColor = Theme.tintBlue          // blue, per the reference
        toLabel.font = Theme.fontDetailMeta
        toLabel.textColor = Theme.secondaryText
        subjectLabel.font = Theme.fontDetailSubject     // bold, sender-sized
        subjectLabel.textColor = Theme.primaryText
        subjectLabel.numberOfLines = 0
        dateLabel.font = Theme.fontDetailMeta
        dateLabel.textColor = Theme.secondaryText
        attachmentStack.axis = .vertical
        attachmentStack.spacing = 0
        attachmentStack.alignment = .fill

        topRule.backgroundColor = Theme.detailRule
        bottomRule.backgroundColor = Theme.detailRule

        for v in [senderLabel, toLabel, topRule, subjectLabel, dateLabel,
                  attachmentStack, bottomRule] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        let left = Theme.detailContentInsetLeft

        // The rules start 5 pt LEFT of the text and bleed off the right edge.
        // An earlier comment here claimed they "run the full width of the pane,
        // as in the reference" — that was false, and pinning them to the
        // leading edge put two long lines 22 pt adrift of the text they
        // separate. Two passes independently located the left end at 22-23 pt,
        // and a solid line localises far better than a glyph does.
        let rule = Theme.detailRuleInsetLeft

        // An empty `UIStackView` has no intrinsic height, and it sits in the
        // middle of the chain that gives this header its own height — so
        // with no files on the message, nothing decides how tall the header
        // is and the layout is AMBIGUOUS. Auto Layout is then free to pick
        // any value, and it picks a different one depending on what else is
        // being laid out at the time: in a message with no attachments it
        // settled on 0, and in the conversation pane it settled on 760 of
        // an 834 pt pane, which left the web view pinned under it exactly 0
        // points tall. The stack was fine, the letters were fine, the
        // document was fine — there was simply nowhere to draw it.
        //
        // A zero-height preference at low priority resolves it: with files,
        // the arranged subviews' own required constraints win and this
        // breaks harmlessly; with none, the header collapses to its text
        // the way it always appeared to.
        let flat = attachmentStack.heightAnchor.constraint(equalToConstant: 0)
        flat.priority = .defaultLow
        flat.isActive = true

        NSLayoutConstraint.activate([
            senderLabel.topAnchor.constraint(equalTo: topAnchor,
                                             constant: Theme.detailSenderTopPadding),
            senderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            senderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -left),

            toLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor,
                                         constant: Theme.detailSenderToGap),
            toLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            toLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),

            topRule.topAnchor.constraint(equalTo: toLabel.bottomAnchor,
                                         constant: Theme.detailToRuleGap),
            topRule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: rule),
            topRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            topRule.heightAnchor.constraint(equalToConstant: 0.5),

            subjectLabel.topAnchor.constraint(equalTo: topRule.bottomAnchor,
                                              constant: Theme.detailRuleSubjectGap),
            subjectLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            subjectLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),

            dateLabel.topAnchor.constraint(equalTo: subjectLabel.bottomAnchor,
                                           constant: Theme.detailSubjectDateGap),
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),

            attachmentStack.topAnchor.constraint(equalTo: dateLabel.bottomAnchor,
                                                 constant: Theme.detailDateAttachmentGap),
            attachmentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            attachmentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),

            bottomRule.topAnchor.constraint(equalTo: attachmentStack.bottomAnchor,
                                            constant: Theme.detailAttachmentRuleGap),
            bottomRule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: rule),
            bottomRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomRule.heightAnchor.constraint(equalToConstant: 0.5),
            bottomRule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(with m: Message) {
        senderLabel.text = MailFormat.displayName(m.sender)
        toLabel.text = "To: " + (m.to.isEmpty ? "me" : m.to.map(MailFormat.displayName).joined(separator: ", "))
        subjectLabel.text = m.subject.isEmpty ? "(no subject)" : m.subject
        dateLabel.text = MailFormat.detailTimestamp(m.date)

        // Inline pictures are not files: they are rendered inside the
        // letter by the `cid:` resolver, and a row for each would list the
        // signature's logo on every message. See Attachment.isInline.
        let listed = m.listedAttachments
        for row in attachmentStack.arrangedSubviews { row.removeFromSuperview() }
        attachmentButtons.removeAll()
        attachmentStack.isHidden = listed.isEmpty
        for attachment in listed {
            let button = makeAttachmentButton(attachment)
            attachmentButtons[attachment.id] = button
            attachmentStack.addArrangedSubview(button)
        }

        accessibilityLabel = "From \(MailFormat.displayName(m.sender)), "
            + "\(m.subject), \(MailFormat.detailTimestamp(m.date))"
    }

    private func makeAttachmentButton(_ attachment: Attachment) -> UIButton {
        let button = UIButton(type: .system)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "paperclip")
        config.imagePadding = 8
        config.baseForegroundColor = Theme.tintBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        // Middle, not tail. The extension lives at the end of the name and is
        // the part that says what the thing IS — "Invoice-QX7T…-0001.pdf"
        // is useful where "Invoice-QX7T2KDA-000…" is not.
        config.titleLineBreakMode = .byTruncatingMiddle

        let size = attachment.size.map {
            " (" + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + ")"
        } ?? ""
        var title = AttributedString(attachment.filename + size)
        title.font = Theme.fontDetailMeta
        config.attributedTitle = title
        button.configuration = config

        button.contentHorizontalAlignment = .leading
        button.isEnabled = onSelectAttachment != nil
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minHitTarget).isActive = true
        button.accessibilityLabel = "Attachment, \(attachment.filename)\(size)"
        button.addAction(UIAction { [weak self] _ in
            self?.onSelectAttachment?(attachment)
        }, for: .touchUpInside)
        return button
    }

    /// Shows that a particular file is being fetched.
    ///
    /// Per row rather than one spinner somewhere on the screen, so the
    /// feedback lands on the thing that was touched. A download of a few
    /// megabytes is several seconds of nothing otherwise, which reads as a
    /// tap that missed — and the response to that is to tap again.
    ///
    /// Not busy is live only if a file can be opened: a row listed from the
    /// list's row before the letter has come stays grey.
    func setAttachment(_ id: String, busy: Bool) {
        guard let button = attachmentButtons[id] else { return }
        button.isEnabled = !busy && onSelectAttachment != nil
        button.configuration?.showsActivityIndicator = busy
    }
}

#endif
