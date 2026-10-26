import Foundation

/// The folders the Mailboxes pane draws, in order, with each one's name and
/// indent, from one LIST (B-116).
///
/// Three runs, one after the other:
///
/// 1. *The Inbox, then the folders with a role*, in a fixed order: Drafts,
///    Sent Mail, Spam, Trash, All Mail (the server's names; Sent and Junk
///    on screen, B-144). Each is named by the last part of its name and
///    indented by how deep the name is, as it always was: Gmail's sit one
///    step in, inside "[Gmail]", which is not drawn.
/// 2. *The server's other folders inside that same container*, Gmail's
///    Important and Starred and a label made inside "[Gmail]", by name, at
///    the same step in. They used to be sorted by name among the labels,
///    one step in among labels at the left edge, so that each read as a
///    folder inside the label above it: Important under House, Starred
///    under Recipes.
/// 3. *The labels, as a tree*: a label, then the labels inside it one step
///    further in, each level by name. A label inside folders that are not
///    drawn, a `\Noselect` one or one LIST does not name, is named by its
///    path from the nearest folder that is: "Unopened 4/17/17" at the left
///    edge, not "17" two steps in under nothing. A folder inside the Inbox,
///    on a server that keeps folders there, is one of these tops too, by
///    its own name, with its own folders under it. They used to be sorted
///    by the last part of the name alone, so a label inside another was
///    drawn under whichever label came before it by name.
///
/// A role comes only from LIST's flags, or from INBOX's name
/// (`IMAPMailboxListing.specialUse`): a label called "Drafts", "Junk
/// E-mail" or "Deleted Messages" is a label, drawn and opened as one.
///
/// Mail's own order, read from iOS 18.6's Message framework
/// (`-[MFMailboxUid sortChildren]`, `MFCompareMailboxUids`): each folder's
/// children by name, case-insensitive with numbers compared as numbers, in
/// the iPad's language; the same with case counted for a tie. Here a tie
/// left after that goes by the server's name, so the order is the same at
/// every launch.
enum FolderTree {

    /// The folders of `listings` that can be opened, in the pane's order.
    /// A folder with no count in `unread` reads 0. `locale` is the iPad's
    /// language, for the order of the names; tests pass one.
    static func mailboxes(from listings: [IMAPMailboxListing], unread: [String: Int],
                          locale: Locale = .current) -> [Mailbox] {
        // Drawn: what can be opened, the first of a name LIST gives twice.
        var drawn: [String: Folder] = [:]
        var listed: [String] = []
        for l in listings where l.isSelectable && drawn[l.name] == nil {
            drawn[l.name] = Folder(l)
            listed.append(l.name)
        }

        // The containers: a folder that is not drawn and holds one of the
        // server's own. "[Gmail]" on Gmail, by what is in it and not by its
        // name, so the name Gmail gives it in some countries is one too, and
        // "Unopened 4/17", which holds only a label, is not.
        var containers: Set<String> = []
        for l in listings where l.isServersOwn || l.specialUse != nil {
            if let parent = Folder(l).ancestors.first, drawn[parent.name] == nil {
                containers.insert(parent.name)
            }
        }

        // What each folder is drawn under: the nearest folder above it that
        // is drawn or is a container.
        var anchors: [String: Anchor] = [:]
        for name in listed {
            let folder = drawn[name]!
            var found = Anchor.none
            for above in folder.ancestors {
                if drawn[above.name] != nil {
                    found = .folder(above.name, parts: above.parts)
                    break
                }
                if containers.contains(above.name) {
                    found = .container(parts: above.parts)
                    break
                }
            }
            anchors[name] = found
        }

        // Names and depths. A folder's anchor has a shorter name than its
        // own, so taking them shortest first has every anchor's depth to
        // hand when it is wanted.
        var names: [String: String] = [:]
        var depths: [String: Int] = [:]
        for name in listed.sorted(by: { $0.count < $1.count }) {
            let folder = drawn[name]!
            if folder.role != nil {
                // As before: the last part of the name, and its depth.
                names[name] = folder.name(under: folder.parts.count - 1)
                depths[name] = max(0, folder.parts.count - 1)
                continue
            }
            switch anchors[name] ?? .none {
            case .none:
                names[name] = name
                depths[name] = 0
            case .container(let parts):
                names[name] = folder.name(under: parts)
                depths[name] = parts
            case .folder(let above, let parts) where drawn[above]?.role == .inbox:
                // Inside the Inbox: at the left edge, by its own name, as
                // the label it reads as. The Inbox's block is the Inbox
                // alone (`FolderCounts`), so the folder cannot be drawn
                // under it, and one step in among the labels it read as a
                // folder inside the label above it.
                names[name] = folder.name(under: parts)
                depths[name] = 0
            case .folder(let above, let parts):
                names[name] = folder.name(under: parts)
                depths[name] = (depths[above] ?? 0) + 1
            }
        }

        // Where each goes: the roles, the container's others, the labels'
        // tops, and every other folder under the one it is drawn under.
        // The Inbox's own folders are drawn among the labels' tops, at the
        // left edge, each with its own folders under it.
        var roles: [String] = []
        var others: [String] = []
        var tops: [String] = []
        var children: [String: [String]] = [:]
        for name in listed {
            if drawn[name]!.role != nil {
                roles.append(name)
                continue
            }
            switch anchors[name] ?? .none {
            case .none:
                tops.append(name)
            case .container:
                others.append(name)
            case .folder(let above, _) where drawn[above]?.role == .inbox:
                tops.append(name)
            case .folder(let above, _):
                // Written back whole, not appended in place: a change made
                // in place inside a Dictionary can compile to a coroutine
                // that needs `swift_coroFrameAlloc`, which the iOS 16
                // runtime does not have (B-013).
                var under = children[above] ?? []
                under.append(name)
                children[above] = under
            }
        }

        let byName = { (a: String, b: String) -> Bool in
            precedes(names[a] ?? a, a, names[b] ?? b, b, locale: locale)
        }
        let byRole = { (a: String, b: String) -> Bool in
            let ra = drawn[a]!.role.flatMap { rank[$0] } ?? rank.count
            let rb = drawn[b]!.role.flatMap { rank[$0] } ?? rank.count
            return ra != rb ? ra < rb : byName(a, b)
        }

        // Each run in order, every folder followed by its own, depth first.
        // A stack rather than recursion, so that a name nested a thousand
        // deep costs a longer list and not the thread's stack.
        var out: [Mailbox] = []
        let runs = roles.sorted(by: byRole) + others.sorted(by: byName) + tops.sorted(by: byName)
        var stack = Array(runs.reversed())
        while let name = stack.popLast() {
            let folder = drawn[name]!
            out.append(Mailbox(id: name, name: names[name] ?? name,
                               unreadCount: unread[name] ?? 0, role: folder.role,
                               depth: depths[name] ?? 0))
            stack.append(contentsOf: (children[name] ?? []).sorted(by: byName).reversed())
        }
        return out
    }

    /// Inbox first, then the other roles in a fixed order. A folder list
    /// whose order changes between launches is exactly what this product
    /// exists to prevent.
    private static let rank: [Mailbox.Role: Int] = [.inbox: 0, .drafts: 1, .sent: 2,
                                                     .junk: 3, .trash: 4, .archive: 5]

    /// Mail's order of two names (`MFCompareMailboxUids`): case-insensitive
    /// with numbers as numbers, then with case counted; then the server's
    /// name, which no two folders share.
    static func precedes(_ a: String, _ aID: String, _ b: String, _ bID: String,
                         locale: Locale) -> Bool {
        let folded = a.compare(b, options: [.caseInsensitive, .numeric], range: nil, locale: locale)
        if folded != .orderedSame { return folded == .orderedAscending }
        let cased = a.compare(b, options: [.numeric], range: nil, locale: locale)
        if cased != .orderedSame { return cased == .orderedAscending }
        return aID < bID
    }

    /// What a folder is drawn under.
    private enum Anchor {
        /// Nothing: a folder at the top, or inside folders none of which
        /// is drawn or a container.
        case none
        /// A drawn folder, whose name has `parts` parts.
        case folder(String, parts: Int)
        /// A container that is not drawn, whose name has `parts` parts.
        case container(parts: Int)
    }

    /// One LIST row, its name in parts.
    private struct Folder {
        let listing: IMAPMailboxListing
        let delimiter: String
        let parts: [String]
        let role: Mailbox.Role?

        init(_ listing: IMAPMailboxListing) {
            self.listing = listing
            delimiter = listing.delimiter ?? "/"
            parts = delimiter.isEmpty ? [listing.name]
                                      : listing.name.components(separatedBy: delimiter)
            role = listing.specialUse
        }

        /// The names of the folders this one is inside, the nearest first,
        /// each with how many parts it has.
        var ancestors: [(name: String, parts: Int)] {
            guard parts.count > 1 else { return [] }
            return (1..<parts.count).reversed().map {
                (name: parts[0..<$0].joined(separator: delimiter), parts: $0)
            }
        }

        /// The name past its first `count` parts, or the whole name when
        /// nothing is left of it.
        func name(under count: Int) -> String {
            let rest = parts.dropFirst(max(0, count)).joined(separator: delimiter)
            return rest.isEmpty ? listing.name : rest
        }
    }
}
