// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// Mail's options in Blackmail's Settings (B-167): the parts of
/// `MailOptions.page`, each under its heading in capitals with Mail's line
/// under it, its rows in Mail's order and words, as Settings > Apps > Mail
/// draws them on his iPad. A switch beside its title; a choice with its
/// value after its title, opening a page of its values, the chosen one
/// ticked; one of Mail's pages, Swipe Options or Privacy Protection, opening
/// it. Pushed on the navigation controller Settings is in, as Mail's
/// Settings pushes its pages.
///
/// Each acts at once, as Mail's do, and as Organize by Thread always did
/// here: written to `MailOptions`, told to `onChange`, and posted
/// (`MailOptions.changed`). Settings' Cancel does not undo them.
///
/// A row Blackmail does not have every value of (`MailOptions.built`) is
/// drawn greyed at its value, takes no tap, and has what Blackmail does in
/// its place under it (`Option.instead`).
///
/// In the plain form Settings is drawn in, not a table: rows of the
/// screen's 44 points (D-007), words at 17 points, values and lines in the
/// secondary grey, ticks in the tint. At Large: the words, values, headings
/// and lines go with the iPad's text size, as the rows of Mail's Settings
/// page do, a row as tall as its words, and again when the size changes
/// with the page open (`Theme.scaled`, `TextSizes`, B-166; int19).
final class MailOptionsView: UIStackView {

    /// What the pages are pushed from: the controller whose navigation
    /// controller holds them.
    weak var host: UIViewController?
    /// A value has been set by a row of this view or of a page it opened.
    var onChange: ((MailOptions.Option) -> Void)?

    /// Draws each row's value again from `MailOptions`.
    private var redraws: [() -> Void] = []
    /// Sets each label's type again at the text size (B-166).
    private let restyles = Restyles()

    init(sections: [MailOptions.Section]) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 0
        for section in sections { add(section) }
        NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged),
                                               name: TextSizes.didChange, object: nil)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    /// Every row as `MailOptions` has it now: on coming back from a page.
    func redraw() { redraws.forEach { $0() } }

    /// The iPad's text size or Bold Text has changed with the page open
    /// (`TextSizes`, B-166): every word at the new size, the rows with it.
    @objc private func textSizeChanged() {
        restyles.again()
        setNeedsLayout()
    }

    // MARK: - Parts

    private func add(_ section: MailOptions.Section) {
        if let heading = section.heading {
            let label = line(heading.uppercased(), size: 13)
            label.accessibilityTraits = .header
            addArrangedSubview(gap(22))
            addArrangedSubview(label)
            addArrangedSubview(gap(6))
        } else {
            addArrangedSubview(gap(22))
        }
        for row in section.rows { add(row) }
        if let footer = section.footer {
            addArrangedSubview(gap(6))
            addArrangedSubview(line(footer, size: 13))
        }
    }

    private func add(_ row: MailOptions.Row) {
        switch row {
        case .option(let option) where option.isSwitch:
            addSwitch(option)
        case .option(let option):
            addChoice(option)
        case .values(let option):
            for (index, word) in option.choices.enumerated() { addValue(word, index, of: option) }
            note(option)
        case .page(let title, let sections):
            let control = OptionRow(title: title, value: nil, opens: true, live: true)
            restyles.keep { [weak control] in control?.restyle() }
            control.addAction(UIAction { [weak self] _ in
                self?.open(title, sections)
            }, for: .touchUpInside)
            addArrangedSubview(control)
        }
    }

    /// Title and switch, one stop, the switch called by the title.
    private func addSwitch(_ option: MailOptions.Option) {
        let live = MailOptions.built.contains(option)
        let toggle = UISwitch()
        toggle.isOn = option.isOn
        toggle.isEnabled = live
        toggle.accessibilityLabel = option.title
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            guard let toggle else { return }
            option.isOn = toggle.isOn
            self?.changed(option)
        }, for: .valueChanged)
        let title = line(option.title, size: 17, live: live)
        title.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [title, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minHitTarget).isActive = true
        addArrangedSubview(row)
        redraws.append { [weak toggle] in toggle?.isOn = option.isOn }
        note(option)
    }

    /// Title and value, opening the page of its values.
    private func addChoice(_ option: MailOptions.Option) {
        let live = MailOptions.built.contains(option)
        let control = OptionRow(title: option.title, value: option.value, opens: live, live: live)
        control.isEnabled = live
        restyles.keep { [weak control] in control?.restyle() }
        control.addAction(UIAction { [weak self] _ in
            self?.open(option.title, MailOptions.valuesPage(of: option))
        }, for: .touchUpInside)
        addArrangedSubview(control)
        redraws.append { [weak control] in control?.value = option.value }
        note(option)
    }

    /// One of a choice's values, ticked where chosen; a tap chooses it.
    private func addValue(_ word: String, _ index: Int, of option: MailOptions.Option) {
        let live = MailOptions.built.contains(option)
        let control = OptionRow(title: word, value: nil, opens: false, live: live)
        restyles.keep { [weak control] in control?.restyle() }
        control.ticked = option.chosen == index
        control.isEnabled = live
        control.addAction(UIAction { [weak self] _ in
            guard option.chosen != index else { return }
            option.chosen = index
            self?.changed(option)
            self?.redraw()
        }, for: .touchUpInside)
        addArrangedSubview(control)
        redraws.append { [weak control] in control?.ticked = option.chosen == index }
    }

    /// What Blackmail does in a greyed row's place, under it.
    private func note(_ option: MailOptions.Option) {
        guard let instead = option.instead else { return }
        addArrangedSubview(line(instead, size: 13))
        addArrangedSubview(gap(6))
    }

    private func changed(_ option: MailOptions.Option) {
        onChange?(option)
        NotificationCenter.default.post(name: MailOptions.changed, object: option)
    }

    private func open(_ title: String, _ sections: [MailOptions.Section]) {
        let page = MailOptionsPage(title: title, sections: sections)
        page.onChange = { [weak self] option in self?.onChange?(option) }
        host?.navigationController?.pushViewController(page, animated: true)
    }

    // MARK: - Pieces

    private func line(_ text: String, size: CGFloat, live: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        restyles.keep { [weak label] in label?.font = .systemFont(ofSize: Theme.scaled(size)) }
        label.textColor = size >= 17 && live ? Theme.primaryText : Theme.secondaryText
        return label
    }

    private func gap(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

/// A row of Mail's page that takes a tap: its title, a value after it in
/// grey, and a chevron where it opens a page, or a tick where it is the
/// value chosen. Greyed, with no tap, where `live` is false. Lit in the
/// list's selection grey while a finger is on it, as a table's row.
private final class OptionRow: UIControl {

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let mark = UIImageView()
    private let symbol: String

    var value: String? {
        didSet {
            valueLabel.text = value
            accessibilityValue = value
        }
    }

    var ticked = false {
        didSet {
            mark.isHidden = !ticked
            accessibilityTraits = ticked ? [.button, .selected] : .button
        }
    }

    init(title: String, value: String?, opens: Bool, live: Bool) {
        symbol = opens ? "chevron.right" : "checkmark"
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.textColor = live ? Theme.primaryText : Theme.secondaryText
        titleLabel.numberOfLines = 0
        valueLabel.textColor = Theme.secondaryText
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        mark.tintColor = opens ? Theme.secondaryText : Theme.tintBlue
        mark.contentMode = .scaleAspectFit
        mark.setContentHuggingPriority(.required, for: .horizontal)
        mark.isHidden = !opens
        let row = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel, mark])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minHitTarget),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        self.value = value
        valueLabel.text = value
        accessibilityValue = value
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The title, the value and the chevron or tick at the text size, as
    /// the rest of the app's words and their symbols (`Theme.symbol`, B-166).
    func restyle() {
        titleLabel.font = .systemFont(ofSize: Theme.scaled(17))
        valueLabel.font = .systemFont(ofSize: Theme.scaled(17))
        mark.image = Theme.symbol(symbol)
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Theme.selection : nil }
    }
}

/// One of Mail's pages, opened from a row of Settings: Swipe Options,
/// Privacy Protection, or a choice's values, under its title, drawn as
/// Settings is.
final class MailOptionsPage: UIViewController {

    var onChange: ((MailOptions.Option) -> Void)?

    private let options: MailOptionsView

    init(title: String, sections: [MailOptions.Section]) {
        options = MailOptionsView(sections: sections)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        options.host = self
        options.onChange = { [weak self] option in self?.onChange?(option) }
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        options.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(options)
        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            options.topAnchor.constraint(equalTo: content.topAnchor, constant: 2),
            options.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            options.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            // The content guide's width, as Settings ties it, for the same
            // reason: it scrolls vertically only.
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            options.widthAnchor.constraint(equalToConstant: 520),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        options.redraw()
    }
}

#endif
