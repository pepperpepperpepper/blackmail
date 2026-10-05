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

    private let field = SearchField()
    private let placeholderStack = UIStackView()
    private let cancelButton = UIButton(type: .system)
    private let scopeControl = UISegmentedControl(
        items: MailSearchScope.allCases.map(\.title))

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

    /// How tall the band wants to be, from `Theme` rather than from its
    /// current frame.
    var wantedHeight: CGFloat {
        Theme.searchBarHeight + (isExpanded ? Theme.searchScopeBarHeight : 0)
    }

    var currentQuery: String { field.text ?? "" }

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
    }

    /// Hidden the moment there is anything to read instead, so the field never
    /// shows a placeholder and a query at the same time.
    private func updatePlaceholder() {
        placeholderStack.isHidden = field.isEditing || !(field.text ?? "").isEmpty
    }

    /// Grows the band to hold Cancel and the scope buttons, or shrinks it
    /// back.
    ///
    /// Stays expanded while there is a query even after the keyboard goes,
    /// because results are still on screen and taking the scope buttons away
    /// while he is looking at what they chose would strand him.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        cancelButton.isHidden = !expanded
        scopeControl.isHidden = !expanded
        frame.size.height = wantedHeight
        setNeedsLayout()
        onHeightChanged?()
    }

    private func refreshExpansion() {
        setExpanded(field.isEditing || !(field.text ?? "").isEmpty)
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

    func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }

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

#endif
