// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// The search control, built from a plain view and a plain text field.
///
/// NOT a `UISearchBar`, for exactly the reason `RootViewController` is not a
/// `UISplitViewController`: this app's whole premise is that positions are
/// fixed and predictable, and UISearchBar will not be told. Four rounds of
/// measured attempts on device, each of which failed differently:
///
/// 1. `barTintColor = 201` renders 249, leaving 6 levels of field/band
///    contrast where the reference has 42.
/// 2. A height constraint on `searchTextField` is silently overridden — the
///    bar lays its field out by frame, so the constraint never participates.
/// 3. `setSearchFieldBackgroundImage` paints onto the BAR's own background
///    view, not the text field, so the visible white box is not the thing a
///    frame change moves. It stretched to 35 pt regardless.
/// 4. Blanking that image and placing the field by hand in a `layoutSubviews`
///    override collapsed it to a 3 pt sliver, because the bar re-derives the
///    field's height from the (now 1×1) background image on the next pass.
///
/// Forty lines of view code do what the framework would not, and every number
/// in them comes from `Theme`.
///
/// ## The scope bar, and a rule it breaks on purpose
///
/// Cancel and the two scope buttons appear when the field is focused and go
/// away when it is not. That is contextual chrome, which `UI_SPEC.md:46` and
/// `BRIEF.md:14` forbid outright — "controls never move based on
/// context" is one of this project's stated non-negotiables, and it is a
/// good rule, written to stop a 90-year-old having to hunt for a button that
/// wandered.
///
/// It loses here to a better one. The requirement is that the app work
/// exactly like Apple Mail, so that it is something he knows, and
/// the man has used Mail for years. Mail reveals Cancel and the scope bar on
/// focus. Matching a habit he already has beats obeying a rule we invented to
/// protect him from habits he does not have — and the rule's own purpose,
/// that nothing he relies on moves, is met: the search FIELD never moves, and
/// nothing above or beside it does either. What appears, appears below.
///
/// Recorded as D-012 rather than slipped in.
///
/// ## Mail's recent searches (B-105)
///
/// Under the scope bar, while the field is focused and still empty, Mail's
/// "Recent Searches": the last three, newest first (`RecentSearches`). The
/// first letter typed takes them away, and the band shrinks back to the
/// field and the scope bar. A tap on one puts its words in the field, the
/// keyboard goes, and the list searches at once. They appear below, as the
/// scope bar does, and nothing above or beside the field moves.
final class SearchHeaderView: UIView, UITextFieldDelegate {

    var onQueryChanged: ((String) -> Void)?
    /// Fired when the scope buttons change what "search" means. Separate
    /// from `onQueryChanged` so the list can re-run a search it already has
    /// text for without pretending the text changed.
    var onScopeChanged: ((MailSearchScope) -> Void)?
    /// Cancel: leave search entirely and put the folder back.
    var onCancel: (() -> Void)?
    /// The band has grown or shrunk. A `tableHeaderView`'s height is read
    /// when it is ASSIGNED and never again, so the host has to re-assign it
    /// — the classic silent no-op in this file's neighbourhood.
    var onHeightChanged: (() -> Void)?
    /// His recent searches, newest first, asked for as the field is focused
    /// empty, and again whenever it is emptied (B-105).
    var recentSearches: (() -> [String])?
    /// One of them tapped: its words are in the field and the keyboard has
    /// gone. The list searches for them at once.
    var onRecentChosen: ((String) -> Void)?
    /// Search on the keyboard, with what is in the field.
    var onSearchKey: ((String) -> Void)?

    private let field = SearchField()
    private let placeholderStack = UIStackView()
    private let cancelButton = UIButton(type: .system)
    private let scopeControl = UISegmentedControl(
        items: MailSearchScope.allCases.map(\.title))
    private let recentHeading = UILabel()
    private let recentRows = (0..<RecentSearches.most).map { _ in RecentSearchRow() }

    /// Where search is looking. Mail's default is everywhere, and so is
    /// ours: the commonest search is "find that letter", and the folder he
    /// happens to be standing in has nothing to do with where it is filed.
    private(set) var scope: MailSearchScope = .allMailboxes

    /// True while the extra controls are on show.
    /// Whether the scope bar and Cancel are showing.
    ///
    /// Readable from outside because the table asks how tall its pinned
    /// header should be, and it must NOT be answered from this view's own
    /// frame: the table resets that frame during the same layout pass, so
    /// reading it back gives the height the band had a moment ago and the
    /// scope bar ends up drawn over the first message.
    private(set) var isExpanded = false

    /// The recent searches on show, newest first: none unless the field is
    /// focused and empty and there are some.
    private(set) var shownRecents: [String] = []

    /// How tall the band wants to be, from `Theme` rather than from its
    /// current frame.
    var wantedHeight: CGFloat {
        Theme.searchBarHeight + (isExpanded ? Theme.searchScopeBarHeight : 0) + recentsHeight
    }

    /// The "Recent Searches" line and a row for each on show, or nothing.
    private var recentsHeight: CGFloat {
        guard !shownRecents.isEmpty else { return 0 }
        return Theme.scaled(Theme.searchRecentHeadingHeight)
            + CGFloat(shownRecents.count) * Theme.scaled(Theme.searchRecentRowHeight)
    }

    var currentQuery: String { field.text ?? "" }

    /// He is typing in the field: VoiceOver is not taken off it, or off the
    /// keys, when the list's rows are drawn again (B-079).
    var isTyping: Bool { field.isEditing }

    init(width: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: Theme.searchBarHeight))
        backgroundColor = Theme.searchBarFill

        field.backgroundColor = Theme.searchFieldFill
        field.font = Theme.fontListSubject
        field.textColor = Theme.primaryText
        field.layer.cornerRadius = Theme.searchFieldCornerRadius
        field.layer.masksToBounds = true
        field.delegate = self
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        // A text inset, so typed text does not touch the rounded corner.
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        field.leftViewMode = .always
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        // What VoiceOver calls the field, as Mail's is called (B-071). The
        // word "Search" in the field is a label of its own beside it, so the
        // field itself had no name.
        field.accessibilityLabel = "Search"
        addSubview(field)

        // Magnifier + "Search", centred as a unit. The reference centres them
        // (ink centre 160.6 pt against a 160.5 pt half-width), and a
        // UITextField's own placeholder cannot carry an icon beside it.
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit
        let label = UILabel()
        label.text = "Search"
        label.font = Theme.fontListSubject
        label.textColor = Theme.secondaryText
        // Drawn, not read (B-071). The field is called "Search" itself, and
        // VoiceOver read the magnifier and the word as two more things
        // called "Search".
        icon.isAccessibilityElement = false
        label.isAccessibilityElement = false
        placeholderStack.axis = .horizontal
        placeholderStack.spacing = 5
        placeholderStack.alignment = .center
        placeholderStack.isUserInteractionEnabled = false
        placeholderStack.addArrangedSubview(icon)
        placeholderStack.addArrangedSubview(label)
        addSubview(placeholderStack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
        ])

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = Theme.fontBarButton
        cancelButton.setTitleColor(Theme.tintBlue, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.isHidden = true
        addSubview(cancelButton)

        scopeControl.selectedSegmentIndex =
            MailSearchScope.allCases.firstIndex(of: scope) ?? 0
        scopeControl.selectedSegmentTintColor = Theme.tintBlue
        scopeControl.setTitleTextAttributes(
            [.foregroundColor: Theme.secondaryText, .font: Theme.fontDetailMeta], for: .normal)
        scopeControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: Theme.fontDetailMeta], for: .selected)
        scopeControl.addTarget(self, action: #selector(scopeTapped), for: .valueChanged)
        scopeControl.isHidden = true
        addSubview(scopeControl)

        recentHeading.text = RecentSearches.heading
        recentHeading.font = Theme.fontListSender
        recentHeading.textColor = Theme.primaryText
        recentHeading.accessibilityTraits = .header
        recentHeading.isHidden = true
        addSubview(recentHeading)
        for row in recentRows {
            row.addTarget(self, action: #selector(recentTapped(_:)), for: .touchUpInside)
            row.isHidden = true
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Theme.searchFieldSideInset
        // Cancel is laid out first because the field's width depends on it.
        // `reserved` is the button plus the gap in front of it; the button
        // itself gets the full band height so the tap target is not the
        // 17 pt of ink.
        let textWidth = isExpanded ? cancelButton.sizeThatFits(bounds.size).width : 0
        let reserved = isExpanded ? textWidth + inset : 0
        cancelButton.frame = CGRect(x: bounds.width - inset - textWidth, y: 0,
                                    width: textWidth, height: Theme.searchBarHeight)

        field.frame = CGRect(x: inset,
                             y: ((Theme.searchBarHeight - Theme.searchFieldHeight) / 2).rounded(),
                             width: bounds.width - 2 * inset - reserved,
                             height: Theme.searchFieldHeight)

        placeholderStack.sizeToFit()
        let size = placeholderStack.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize)
        placeholderStack.frame = CGRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((Theme.searchBarHeight - size.height) / 2).rounded(),
            width: size.width, height: size.height)

        scopeControl.frame = CGRect(x: inset, y: Theme.searchBarHeight,
                                    width: bounds.width - 2 * inset,
                                    height: Theme.searchScopeBarHeight - 6)

        // The recent searches under the scope bar, from the same numbers
        // as `recentsHeight`.
        let heading = Theme.scaled(Theme.searchRecentHeadingHeight)
        let row = Theme.scaled(Theme.searchRecentRowHeight)
        var y = Theme.searchBarHeight + Theme.searchScopeBarHeight
        recentHeading.frame = CGRect(x: 2 * inset, y: y,
                                     width: bounds.width - 4 * inset, height: heading)
        y += heading
        for recent in recentRows {
            recent.frame = CGRect(x: 0, y: y, width: bounds.width, height: row)
            y += row
        }
    }

    /// Hidden the moment there is anything to read instead, so the field never
    /// shows a placeholder and a query at the same time.
    private func updatePlaceholder() {
        placeholderStack.isHidden = field.isEditing || !(field.text ?? "").isEmpty
    }

    /// Grows the band to hold Cancel and the scope buttons, and the recent
    /// searches under them, or shrinks it back.
    ///
    /// Stays expanded while there is a query even after the keyboard goes,
    /// because results are still on screen and taking the scope buttons away
    /// while he is looking at what they chose would strand him.
    ///
    /// The recent searches show only while the field is focused AND empty,
    /// and there are some: before he types, as Mail's do (B-105).
    private func refreshExpansion() {
        let empty = (field.text ?? "").isEmpty
        let expanded = field.isEditing || !empty
        let recents = field.isEditing && empty
            ? Array((recentSearches?() ?? []).prefix(recentRows.count)) : []
        guard expanded != isExpanded || recents != shownRecents else { return }
        isExpanded = expanded
        shownRecents = recents
        cancelButton.isHidden = !expanded
        scopeControl.isHidden = !expanded
        recentHeading.isHidden = recents.isEmpty
        for (index, row) in recentRows.enumerated() {
            row.isHidden = index >= recents.count
            row.text = index < recents.count ? recents[index] : ""
        }
        frame.size.height = wantedHeight
        setNeedsLayout()
        onHeightChanged?()
    }

    @objc private func editingChanged() {
        updatePlaceholder()
        refreshExpansion()
        onQueryChanged?(field.text ?? "")
    }

    @objc private func scopeTapped() {
        let chosen = MailSearchScope.allCases[scopeControl.selectedSegmentIndex]
        guard chosen != scope else { return }
        scope = chosen
        onScopeChanged?(chosen)
    }

    /// A recent search tapped: its words in the field, the keyboard down so
    /// the results can be seen, and the list told, which searches at once.
    ///
    /// The row goes as its words go into the field, and with VoiceOver on
    /// its cursor was on that row: it is put on the field, which now holds
    /// the words, and not left on a row that is hidden for VoiceOver to
    /// choose where to go (B-079). The field does not move, and the list's
    /// rows under it do not take VoiceOver from it as the results come.
    @objc private func recentTapped(_ row: RecentSearchRow) {
        let text = row.text
        guard !text.isEmpty else { return }
        field.text = text
        field.resignFirstResponder()
        updatePlaceholder()
        refreshExpansion()
        onRecentChosen?(text)
        UIAccessibility.post(notification: .layoutChanged, argument: field)
    }

    @objc private func cancelTapped() {
        field.text = nil
        field.resignFirstResponder()
        updatePlaceholder()
        refreshExpansion()
        onCancel?()
    }

    func clear() {
        field.text = nil
        field.resignFirstResponder()
        updatePlaceholder()
        refreshExpansion()
    }

    func textFieldDidBeginEditing(_ t: UITextField) {
        updatePlaceholder()
        refreshExpansion()
    }

    func textFieldDidEndEditing(_ t: UITextField) {
        updatePlaceholder()
        refreshExpansion()
    }

    /// Search on the keyboard: the keyboard goes, and the list keeps what
    /// is in the field among his recent searches (B-105).
    func textFieldShouldReturn(_ t: UITextField) -> Bool {
        t.resignFirstResponder()
        onSearchKey?(t.text ?? "")
        return true
    }

    func textFieldShouldClear(_ t: UITextField) -> Bool {
        onQueryChanged?("")
        DispatchQueue.main.async {
            self.updatePlaceholder()
            self.refreshExpansion()
        }
        return true
    }
}

/// The search field, which VoiceOver calls a search field, as it does
/// Mail's (B-071). Added to the traits UIKit gives a text field, which
/// change as it is edited, and not put in their place.
///
/// It is read as a heading too, and that stays: the band is the list's
/// section header, and UIKit reads whatever is in one as a heading, a
/// trait taken off here or not.
private final class SearchField: UITextField {
    override var accessibilityTraits: UIAccessibilityTraits {
        get { super.accessibilityTraits.union(.searchField) }
        set { super.accessibilityTraits = newValue }
    }
}

/// One recent search under the field (B-105): a clock and its words, on
/// one line, lit while a finger is on it, as a row is. To VoiceOver, a
/// button: "Recent search, margaret".
private final class RecentSearchRow: UIControl {

    private let icon = UIImageView(
        image: UIImage(systemName: "clock",
                       withConfiguration: UIImage.SymbolConfiguration(font: Theme.fontListSubject)))
    private let label = UILabel()

    var text = "" {
        didSet {
            label.text = text
            accessibilityLabel = RecentSearches.spoken(text)
        }
    }

    init() {
        super.init(frame: .zero)
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        label.font = Theme.fontListSubject
        label.textColor = Theme.primaryText
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        addSubview(icon)
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Theme.selection : .clear }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = 2 * Theme.searchFieldSideInset
        let iconWidth = Theme.scaled(Theme.searchRecentRowHeight / 2)
        icon.frame = CGRect(x: inset, y: 0, width: iconWidth, height: bounds.height)
        let textX = icon.frame.maxX + Theme.searchFieldSideInset
        label.frame = CGRect(x: textX, y: 0, width: max(0, bounds.width - textX - inset),
                             height: bounds.height)
    }
}

#endif
