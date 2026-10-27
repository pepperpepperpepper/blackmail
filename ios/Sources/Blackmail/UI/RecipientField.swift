// Guarded so this file compiles away on a host without UIKit. What the
// field holds and does is `RecipientBubbles`, which the host suite runs.
#if canImport(UIKit)

import UIKit

/// To, Cc or Bcc in the composer and in the share sheet, as Mail's: each
/// recipient a bubble with the person's name on it, then the line he types
/// on (B-076). What it holds is `RecipientBubbles`, which the sheets read a
/// recipient at a time (`recipients`): a bubble is one recipient, whatever
/// is in it.
///
/// Built from a plain text field and plain buttons rather than
/// `UISearchTextField`'s tokens, which iOS has had since 13, because the
/// app is installed once and never updated. Every part of this is UIKit
/// that has behaved the same for a decade: a text field, its
/// `deleteBackward`, buttons laid out by hand, and an action sheet. What a
/// search field's tokens do is the system's: how backspace takes one off,
/// what a tap on one does, whether its text holds them, and its search
/// look, which is a magnifier and a grey well to be undone. They also keep
/// to one line and slide out of sight as more are added, so a Reply All's
/// tenth person in Cc would be under the first. Here every recipient is in
/// sight, a line at a time as Mail's field grows, and what each key and tap
/// does is in this file and in the suite.
///
/// Sends `.editingDidBegin` and `.editingDidEnd` as the line he types on
/// does, and `.editingChanged` whenever what it holds changes under his
/// hand: a
/// letter typed or taken out, a bubble made with a comma, a ";" or Return,
/// one taken off by backspace or Remove, or by letters typed in its place.
/// Not for `show` or `pick`, which the sheet calls itself. Sends
/// `.valueChanged` when a bubble is tapped, before its menu goes up, for
/// the sheet to close the list and take the caret there (B-134).
final class RecipientField: UIControl, UITextFieldDelegate, UIGestureRecognizerDelegate {

    /// What the field holds.
    private(set) var bubbles = RecipientBubbles()
    /// The line he types on, after the bubbles.
    let input = TypingLine()
    private var buttons: [UIButton] = []
    /// One line of `lineHeight` for each line of bubbles: `minHitTarget`
    /// at Large, the size the app is drawn at whatever the iPad's (B-166,
    /// `TextSize.drawn`).
    private lazy var height = heightAnchor.constraint(equalToConstant: Theme.lineHeight)

    var font: UIFont = .systemFont(ofSize: Theme.scaled(17)) {
        didSet {
            input.font = font
            rebuild()
        }
    }

    var textColor: UIColor? {
        get { input.textColor }
        set { input.textColor = newValue }
    }

    /// Whom the field sends to: each bubble's entry, as it is, then what he
    /// is typing after them (`RecipientBubbles.recipients`). Send, Cancel,
    /// a draft and the letter read this, so the letter goes to the people
    /// the bubbles show. They read the field written out as text before,
    /// split again at its commas, and one bubble with a stray quote in it
    /// split them all.
    var recipients: [String] { bubbles.recipients }

    var isEditing: Bool { input.isEditing }

    /// VoiceOver's name for the field, "To", on the line he types on.
    override var accessibilityLabel: String? {
        get { input.accessibilityLabel }
        set { input.accessibilityLabel = newValue }
    }

    override var isFirstResponder: Bool { input.isFirstResponder }

    @discardableResult
    override func becomeFirstResponder() -> Bool { input.becomeFirstResponder() }

    @discardableResult
    override func resignFirstResponder() -> Bool { input.resignFirstResponder() }

    init() {
        super.init(frame: .zero)
        input.font = font
        input.delegate = self
        input.borderStyle = .none
        // The EMAIL keyboard, which is the difference between "@" being on
        // the main layer and being hidden two taps deep behind .?123. Found
        // by typing a real address into the composer: the key in that
        // position on the default keyboard is a COMMA, so the address came
        // out as "someone,example.org" and would have been rejected as
        // unparseable. A 90-year-old hunting for an @ sign is a reason not
        // to send the letter at all. And nothing changed behind his back.
        input.keyboardType = .emailAddress
        input.autocapitalizationType = .none
        input.autocorrectionType = .no
        input.smartDashesType = .no
        input.smartQuotesType = .no
        input.addTarget(self, action: #selector(began), for: .editingDidBegin)
        input.addTarget(self, action: #selector(changed), for: .editingChanged)
        input.addTarget(self, action: #selector(ended), for: .editingDidEnd)
        input.backspaceToBubbles = { [weak self] in self?.backspace() ?? false }
        // A tap on the line puts back a bubble a backspace picked out
        // (`lineTapped`). Seen beside the line's own taps, which still put
        // the caret where he tapped, and taking nothing from them.
        let tap = UITapGestureRecognizer(target: self, action: #selector(lineTapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        input.addGestureRecognizer(tap)
        addSubview(input)
        height.isActive = true
        // A tap beside the bubbles is a tap on the line he types on.
        addTarget(self, action: #selector(tappedBeside), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - What the sheet does

    /// The field as a letter has it: a bubble for each entry.
    func show(_ entries: [String]) {
        bubbles = RecipientBubbles(entries: entries)
        input.text = ""
        rebuild()
    }

    /// A suggestion picked: a bubble in place of what he typed.
    func pick(_ entry: String) {
        bubbles.pick(entry)
        input.text = ""
        rebuild()
    }

    // MARK: - What he does

    @objc private func began() {
        sendActions(for: .editingDidBegin)
    }

    /// A letter typed or taken out. A recipient he has ended with a comma
    /// or a ";" becomes a bubble, and the line holds what is left. Typed
    /// over a bubble picked out, the letters take its place, as in Mail,
    /// and its menu goes with it (B-134).
    @objc private func changed() {
        // Not while a keyboard is still composing a character.
        guard input.markedTextRange == nil else { return }
        let had = bubbles
        let now = input.text ?? ""
        if bubbles.typingTakesThePicked(now) { closeMenu() }
        bubbles.type(now)
        keepMenu()
        if input.text != bubbles.typed { input.text = bubbles.typed }
        if had.entries != bubbles.entries || had.selected != bubbles.selected { rebuild() }
        sendActions(for: .editingChanged)
    }

    /// Leaving the field: what he typed becomes a bubble. A bubble whose
    /// menu is up stays picked out (`keepMenu`).
    @objc private func ended() {
        let had = bubbles
        bubbles.finish(leaving: true)
        keepMenu()
        input.text = ""
        if had != bubbles { rebuild() }
        sendActions(for: .editingDidEnd)
    }

    /// The bubble whose menu is up, if one is, the entry it was put up
    /// for, and the menu.
    private var menuFor: Int?
    private var menuEntry: String?
    private weak var menu: UIAlertController?

    /// While a bubble's menu is up, that bubble stays picked out through a
    /// comma, a ";", Return or leaving the field under it: the keyboard
    /// stays live under the menu. Taken off under it, by a backspace, or by
    /// letters typed in its place (`changed`, B-134), it takes its menu
    /// with it.
    private func keepMenu() {
        guard let i = menuFor else { return }
        if bubbles.entries.indices.contains(i), bubbles.entries[i] == menuEntry {
            bubbles.select(i)
        } else {
            closeMenu()
        }
    }

    /// The bubble's menu put away, as its bubble goes.
    private func closeMenu() {
        menuFor = nil
        menuEntry = nil
        if let menu, menu.presentingViewController != nil { menu.dismiss(animated: true) }
    }

    /// Return: what he typed becomes a bubble, and he stays in the field.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let before = (bubbles.entries, bubbles.typed)
        bubbles.finish()
        keepMenu()
        input.text = ""
        rebuild()
        if (bubbles.entries, bubbles.typed) != before { sendActions(for: .editingChanged) }
        return false
    }

    /// A backspace, asked before the line takes a letter off. With nothing
    /// typed, the last bubble picked out, then taken off
    /// (`RecipientBubbles.backspace`); with a bubble picked out, that one
    /// taken off, letters on the line or not, as Mail's field deletes the
    /// recipient it has selected (B-134). True when it was the bubbles'.
    private func backspace() -> Bool {
        guard bubbles.backspaceIsTheBubbles(lineEmpty: (input.text ?? "").isEmpty) else { return false }
        let before = bubbles.entries
        guard bubbles.backspace() else { return true }
        keepMenu()
        rebuild()
        if bubbles.entries != before { sendActions(for: .editingChanged) }
        return true
    }

    @objc private func tappedBeside() {
        lineTapped()
        input.becomeFirstResponder()
    }

    /// A tap on the line he types on, or beside the bubbles, with no
    /// bubble's menu up: a bubble a backspace picked out is put back, as a
    /// tap that puts Mail's caret on its line ends the selection that was
    /// its recipient, so the next letter goes after it (B-134). It stayed
    /// picked out, and the next letter took it off. With a menu up a tap
    /// there is a tap outside the menu, whose Cancel puts the bubble back.
    @objc private func lineTapped() {
        guard menuFor == nil, bubbles.lineTapped() else { return }
        rebuild()
    }

    /// The tap on the line is seen with the line's own, never instead.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// A bubble tapped: picked out, with its address and Remove under it.
    /// The sheet is told first (`.valueChanged`): it closes the list, so
    /// the menu never stands over it, and takes the caret into this field,
    /// where Mail's tap puts it, so letters typed next take this bubble's
    /// place (B-134).
    @objc private func bubbleTapped(_ sender: UIButton) {
        guard let index = buttons.firstIndex(of: sender),
              bubbles.entries.indices.contains(index) else { return }
        bubbles.select(index)
        rebuild()
        sendActions(for: .valueChanged)
        guard bubbles.entries.indices.contains(index), bubbles.selected == index,
              let owner = presenter, owner.presentedViewController == nil else { return }
        let entry = bubbles.entries[index]
        let words = RecipientBubbles.words(for: entry)
        let address = RecipientBubbles.address(for: entry)
        let menu = UIAlertController(title: words,
                                     message: address == words ? nil : address,
                                     preferredStyle: .actionSheet)
        // Dark, as the sheets are (D-010), whatever is under them.
        menu.overrideUserInterfaceStyle = .dark
        // Its arrow on the bubble as drawn, not on the line it takes taps on.
        menu.popoverPresentationController?.sourceView = sender
        menu.popoverPresentationController?.sourceRect = sender.bounds
        // Under the bubble, or over it, never beside it. Beside it the menu
        // covers the rest of the line: what he types next and every bubble
        // after this one. With the on-screen keyboard up, on the iPad's
        // 16.5.1, UIKit put it to the right of the bubble, its arrow at the
        // title bar's line, well above the bubble (B-078). Where UIKit
        // already chose up, as with the keyboard down, nothing changes.
        menu.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        menu.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.menuFor = nil
            self?.menuEntry = nil
            self?.remove(entry, at: index)
        })
        // On the iPad a popover's Cancel is a tap outside it.
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.menuFor = nil
            self?.menuEntry = nil
            self?.bubbles.select(nil)
            self?.rebuild()
        })
        menuFor = index
        menuEntry = entry
        self.menu = menu
        owner.present(menu, animated: true)
    }

    /// The bubble's Remove, if it is still the one tapped.
    private func remove(_ entry: String, at index: Int) {
        guard bubbles.entries.indices.contains(index), bubbles.entries[index] == entry else { return }
        bubbles.remove(at: index)
        rebuild()
        sendActions(for: .editingChanged)
    }

    /// The sheet the field is on, which puts up a bubble's menu.
    private var presenter: UIViewController? {
        var next: UIResponder? = self
        while let r = next {
            if let vc = r as? UIViewController { return vc }
            next = r.next
        }
        return nil
    }

    // MARK: - The bubbles

    /// The bubbles drawn again from `bubbles`. The same people keep their
    /// buttons, only their look changing, so the one a menu hangs from is
    /// not taken away under it: those before the first change and after
    /// the last keep theirs (`RecipientBubbles.unchanged`), and only the
    /// bubbles between are made again. A bubble made with a comma, a ";" or
    /// Return while a menu is up is one more at the end. Every button used to be
    /// made again at any change, and the menu was left pointing where its
    /// bubble had been.
    private func rebuild() {
        if shown != bubbles.entries {
            let now = bubbles.entries
            let (head, tail) = RecipientBubbles.unchanged(from: shown, to: now)
            for b in buttons[head ..< buttons.count - tail] { b.removeFromSuperview() }
            let made: [UIButton] = (head ..< now.count - tail).map { _ in
                let b = BubbleButton(type: .system)
                b.addTarget(self, action: #selector(bubbleTapped(_:)), for: .touchUpInside)
                addSubview(b)
                return b
            }
            buttons = Array(buttons[..<head]) + made + Array(buttons[(buttons.count - tail)...])
            shown = now
        }
        for (index, entry) in bubbles.entries.enumerated() {
            dress(buttons[index], RecipientBubbles.words(for: entry),
                  address: RecipientBubbles.address(for: entry),
                  selected: bubbles.selected == index)
        }
        setNeedsLayout()
    }

    /// The entries the buttons were made for.
    private var shown: [String] = []

    private func dress(_ button: UIButton, _ words: String, address: String?, selected: Bool) {
        var look = UIButton.Configuration.plain()
        var title = AttributedString(words)
        title.font = font
        title.foregroundColor = Theme.primaryText
        look.attributedTitle = title
        look.titleLineBreakMode = .byTruncatingTail
        look.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: Theme.recipientBubblePadding,
                                                     bottom: 0, trailing: Theme.recipientBubblePadding)
        look.background.backgroundColor = selected ? Theme.tintBlue : Theme.recipientBubbleFill
        look.background.cornerRadius = Theme.scaled(Theme.recipientBubbleHeight) / 2
        button.configuration = look
        button.accessibilityLabel = words
        button.accessibilityValue = address == words ? nil : address
        if selected {
            button.accessibilityTraits.insert(.selected)
        } else {
            button.accessibilityTraits.remove(.selected)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lines = place(in: bounds.width)
        let tall = CGFloat(lines) * Theme.lineHeight
        if height.constant != tall { height.constant = tall }
    }

    /// The bubbles in lines of `lineHeight`, as many to a line as fit,
    /// and the line he types on after the last of them, on a line of its
    /// own when what is left is too short to type in. The number of lines.
    /// At Large a line is `minHitTarget` and a bubble 30 points; at another
    /// text size both are scaled with the names in them (B-166).
    ///
    /// A bubble is drawn `recipientBubbleHeight` tall, and at least
    /// `minHitTarget` wide, a short name centred in it; it takes a tap on
    /// the whole height of its line (`BubbleButton`). So every bubble is a
    /// target of 44 by 44 points or more, as D-007 binds every tappable
    /// control. A bubble was a 30-point pill, as narrow as its name, and a
    /// tap a few points above or below it raised the keyboard instead.
    private func place(in width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let line = Theme.lineHeight
        let tall = Theme.scaled(Theme.recipientBubbleHeight)
        var x: CGFloat = 0
        var row = 0
        for b in buttons {
            let w = min(max(ceil(b.intrinsicContentSize.width), Theme.minHitTarget), width)
            if x > 0, x + w > width {
                row += 1
                x = 0
            }
            b.frame = CGRect(x: x, y: CGFloat(row) * line + (line - tall) / 2, width: w, height: tall)
            x += w + Theme.recipientBubbleGap
        }
        if x > 0, width - x < min(width, 120) {
            row += 1
            x = 0
        }
        input.frame = CGRect(x: x, y: CGFloat(row) * line, width: width - x, height: line)
        return row + 1
    }
}

/// A bubble in a `RecipientField`: drawn as a pill shorter than its line,
/// it takes a tap anywhere on the line's height, `minHitTarget`
/// (`RecipientBubbles.touchArea`), so a tap just above or below the pill is
/// a tap on it (D-007). No two bubbles take the same tap: the lines above
/// and below begin where this one ends, and every bubble is drawn at least
/// `minHitTarget` wide, so none grows sideways.
final class BubbleButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        RecipientBubbles.touchArea(of: bounds, atLeast: Theme.minHitTarget).contains(point)
    }
}

/// The line he types on in a `RecipientField`, which asks the field first
/// at each backspace: with nothing on the line the bubble before it is
/// picked out, then taken off, and a bubble picked out is taken off even
/// with letters on the line (B-134). Otherwise the backspace takes a
/// letter off the line.
final class TypingLine: UITextField {
    /// True when the field has taken the backspace.
    var backspaceToBubbles: (() -> Bool)?

    override func deleteBackward() {
        if markedTextRange == nil, let backspaceToBubbles, backspaceToBubbles() {
            return
        }
        super.deleteBackward()
    }
}

#endif
