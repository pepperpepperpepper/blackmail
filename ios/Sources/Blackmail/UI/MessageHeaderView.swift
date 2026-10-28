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
///     Cc: Sam Example         <- grey, only when the letter has a Cc; not
///                                in the reference, which has none
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
///
/// No files. Mail's header has no list of them: each is drawn in the
/// letter's body, where it sits, a picture at its size and any other file
/// as Mail's tile (`BodyFiles`, B-170). The header had a row per file under
/// the date from B-101 until then, the files of a letter's row from the tap
/// (B-042) and, from B-148, all but a file drawn among the words.
final class MessageHeaderView: UIView {

    private let senderLabel = UILabel()
    private let toLabel = UILabel()
    /// Under To, as Mail puts it, and only when there is a Cc: a label with
    /// no text has no height, and its gap goes with it (`ccGap`), so a
    /// letter without one lays out exactly as before.
    private let ccLabel = UILabel()
    private var ccGap: NSLayoutConstraint!
    private let subjectLabel = UILabel()
    private let dateLabel = UILabel()
    /// The letter's date, and what VoiceOver reads before it, kept so the
    /// date can be written again where it is (`drawDate`).
    private var date: Date?
    private var spoken = ""
    private let topRule = UIView()
    private let bottomRule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.canvas

        senderLabel.font = Theme.fontDetailSender
        senderLabel.textColor = Theme.tintBlue          // blue, per the reference
        toLabel.font = Theme.fontDetailMeta
        toLabel.textColor = Theme.secondaryText
        ccLabel.font = Theme.fontDetailMeta
        ccLabel.textColor = Theme.secondaryText
        subjectLabel.font = Theme.fontDetailSubject     // bold, sender-sized
        subjectLabel.textColor = Theme.primaryText
        subjectLabel.numberOfLines = 0
        dateLabel.font = Theme.fontDetailMeta
        dateLabel.textColor = Theme.secondaryText

        topRule.backgroundColor = Theme.detailRule
        bottomRule.backgroundColor = Theme.detailRule

        for v in [senderLabel, toLabel, ccLabel, topRule, subjectLabel, dateLabel,
                  bottomRule] as [UIView] {
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

        ccGap = ccLabel.topAnchor.constraint(equalTo: toLabel.bottomAnchor, constant: 0)

        NSLayoutConstraint.activate([
            senderLabel.topAnchor.constraint(equalTo: topAnchor,
                                             constant: Theme.detailSenderTopPadding),
            senderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            senderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -left),

            toLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor,
                                         constant: Theme.detailSenderToGap),
            toLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            toLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),

            ccGap,
            ccLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            ccLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -left),

            topRule.topAnchor.constraint(equalTo: ccLabel.bottomAnchor,
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

            // The two gaps the files' rows sat between, which a letter with
            // no file had with nothing between them (B-170): the header is
            // the height a letter with no file always had.
            bottomRule.topAnchor.constraint(equalTo: dateLabel.bottomAnchor,
                                            constant: Theme.detailDateAttachmentGap
                                                + Theme.detailAttachmentRuleGap),
            bottomRule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: rule),
            bottomRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomRule.heightAnchor.constraint(equalToConstant: 0.5),
            bottomRule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(with m: Message) {
        senderLabel.text = MailFormat.displayName(m.sender)
        // Names, and the address where there is no name, as Mail writes
        // them (`MailFormat.recipientName`).
        toLabel.text = MailFormat.recipientsLine("To", m.to) ?? "To: me"
        let cc = MailFormat.recipientsLine("Cc", m.cc)
        ccLabel.text = cc
        ccLabel.isHidden = cc == nil
        ccGap.constant = cc == nil ? 0 : Theme.detailToCcGap
        subjectLabel.text = m.subject.isEmpty ? "(no subject)" : m.subject
        // When it arrived, as Mail's header shows it (B-178), its Date
        // where that is not known.
        date = m.headerDate
        spoken = "From \(MailFormat.displayName(m.sender)), \(m.subject)"
        drawDate()
    }

    /// The header's type at the text size now, which has changed (B-166;
    /// since 2026-10-27 only Bold Text, the size being Large whatever the
    /// iPad's, `TextSize.drawn`): the names, the subject and the date. Its
    /// lines are laid out by Auto Layout and grow or shrink with their
    /// words, and the letter under the header moves with its foot, as when
    /// it was drawn. A file has no row
    /// here since B-170: it is drawn in the letter, its tile at the pane's
    /// scale (`BodyFiles.sizeRule`; int19).
    func restyle() {
        senderLabel.font = Theme.fontDetailSender
        toLabel.font = Theme.fontDetailMeta
        ccLabel.font = Theme.fontDetailMeta
        subjectLabel.font = Theme.fontDetailSubject
        dateLabel.font = Theme.fontDetailMeta
        setNeedsLayout()
    }

    /// The date under the subject written from the letter's own, as the
    /// iPad writes it now: as the letter is shown, and again where it is
    /// when the 24-Hour Time switch, the time zone or the region has
    /// changed, or the day has turned over, so "Today at 11:50 PM" reads
    /// "Yesterday at 11:50 PM" once midnight has passed (B-139). Nothing
    /// else in the header is touched, and it keeps its height: the date is
    /// one line.
    func drawDate() {
        guard let date else { return }
        let when = MailFormat.detailTimestamp(date)
        dateLabel.text = when
        accessibilityLabel = "\(spoken), \(when)"
    }
}

#endif
