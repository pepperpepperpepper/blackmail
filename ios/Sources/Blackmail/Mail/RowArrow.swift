import Foundation

/// Mail's grey arrow in a row's leading gutter, on the sender's line: the
/// left-turning arrow for a letter answered, the right-turning one for a
/// letter forwarded (B-102). It says "did I answer this?" at a glance,
/// which the list could not say before.
///
/// Out of `MessageCell` for the reason `RowTopLine` is: the cell is UIKit
/// and does not exist on the machine the suite runs on. What the row shows
/// and what VoiceOver reads for it come from here, so the two cannot
/// disagree.
///
/// The gutter is the unread dot's, and holds one thing at a time, in this
/// order (D-019): the spinner over everything while a draft is on its way,
/// then the unread dot, then the arrow, then the paperclip, which goes to
/// the end of the subject's line whenever the gutter is taken. So an
/// unread letter shows its dot and no arrow, and its arrow once it is read.
/// A letter both answered and forwarded shows the reply arrow. Mail's own
/// choice for either is not known; this is the one made here.
enum RowArrow: Equatable {
    case replied
    case forwarded

    /// The arrow a row shows, or none: none for an unread row, whose dot
    /// has the gutter, nor for a letter neither answered nor forwarded.
    init?(read: Bool, answered: Bool, forwarded: Bool) {
        guard read else { return nil }
        if answered {
            self = .replied
        } else if forwarded {
            self = .forwarded
        } else {
            return nil
        }
    }

    /// The SF Symbol: Mail's filled arrow, turning up and back for a reply
    /// and up and on for a forward. Both in iOS since 13.
    var symbolName: String {
        switch self {
        case .replied:   return "arrowshape.turn.up.left.fill"
        case .forwarded: return "arrowshape.turn.up.right.fill"
        }
    }

    /// What VoiceOver reads for it, where it reads "Unread" for the dot.
    var spoken: String {
        switch self {
        case .replied:   return "Replied"
        case .forwarded: return "Forwarded"
        }
    }
}

extension MessageSummary {
    /// The arrow this row shows in its gutter, from its read mark and its
    /// two flags (`RowArrow`).
    var arrow: RowArrow? {
        RowArrow(read: isRead, answered: isAnswered, forwarded: isForwarded)
    }
}
