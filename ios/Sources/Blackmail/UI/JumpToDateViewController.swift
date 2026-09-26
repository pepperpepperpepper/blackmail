// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// Pick a day, and the folder opens there.
///
/// This screen is the reason the rest of the date work exists. The
/// problem was never "he would like a shortcut" — it was that
/// getting back to a particular day was the thing he could not do. Mail's
/// answer is to scroll, and scrolling is exactly what does not work when the
/// day you want is four months and two thousand letters up.
///
/// So the priorities here are not the app's usual ones. Everywhere else this
/// build copies the 2016 iPad Mail layout it is frozen to; there is no such
/// layout for this, because Mail has never had it. What governs instead is
/// that a very old man has to be able to work it: a real month grid he can
/// see and tap, not a three-wheel spinner he has to drag three times and can
/// overshoot; the day he last chose already selected, because looking through
/// one month usually means looking through the next; and two buttons, one of
/// which is Cancel.
final class JumpToDateViewController: UIViewController {

    /// The chosen day and where to look for it. Not called if he cancels.
    var onPick: ((Date, MailSearchScope) -> Void)?

    private let picker = UIDatePicker()
    private let explain = UILabel()
    /// The same two words the search band uses, and deliberately the same
    /// enum: "where should I look" is one question and he should not have
    /// to learn two answers to it.
    ///
    /// Jumping inside the folder he is standing in is the common case, but
    /// it silently excludes the letters he SENT that day — which for
    /// someone working back through a correspondence is half of it. B-012.
    private let scopeControl = UISegmentedControl(
        items: MailSearchScope.allCases.map(\.title))

    private static let lastScopeKey = "blackmail.lastJumpScope"

    static var lastScope: MailSearchScope {
        get {
            UserDefaults.standard.string(forKey: lastScopeKey)
                .flatMap(MailSearchScope.init(rawValue:)) ?? .currentMailbox
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastScopeKey) }
    }

    /// Where the picker opens.
    ///
    /// Remembered across launches, not reset to today. Someone working back
    /// through a correspondence opens this repeatedly around the same weeks,
    /// and starting at today every time would mean paging the calendar back
    /// four months on every single visit — the very cost this screen exists
    /// to remove.
    private static let lastPickedKey = "blackmail.lastJumpDate"

    static var lastPicked: Date {
        get { UserDefaults.standard.object(forKey: lastPickedKey) as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: lastPickedKey) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        title = "Go to Date"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Go", style: .done, target: self, action: #selector(goTapped))
        for item in [navigationItem.leftBarButtonItem, navigationItem.rightBarButtonItem] {
            item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        }

        picker.datePickerMode = .date
        // The month GRID, not the wheels. `.wheels` is three independent
        // spinners with no view of the month: choosing the 20th of June
        // means dragging day, month and year separately, each of which can
        // overshoot and none of which shows what day of the week anything
        // fell on. `.inline` is a calendar page — the thing he is picturing
        // when he says a date.
        picker.preferredDatePickerStyle = .inline
        // No future. Mail arrives dated tomorrow often enough (a clock set
        // wrong at the far end), but nobody means to jump there, and a
        // mis-tap into next year lands on an empty folder that looks like
        // the feature failed.
        picker.maximumDate = Date()
        picker.date = Self.lastPicked
        picker.tintColor = Theme.tintBlue
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)

        scopeControl.selectedSegmentIndex =
            MailSearchScope.allCases.firstIndex(of: Self.lastScope) ?? 0
        scopeControl.selectedSegmentTintColor = Theme.tintBlue
        scopeControl.setTitleTextAttributes(
            [.foregroundColor: Theme.secondaryText, .font: Theme.fontDetailMeta], for: .normal)
        scopeControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: Theme.fontDetailMeta], for: .selected)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scopeControl)

        explain.text = "Your mail will open at the first message on that day. "
            + "Scroll up for later messages, down for earlier ones."
        explain.numberOfLines = 0
        explain.textAlignment = .center
        explain.font = Theme.fontDetailMeta
        explain.textColor = Theme.secondaryText
        explain.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(explain)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                        constant: 12),
            picker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // Wider than the picker's natural size so the day circles grow
            // with it. An inline picker lays its grid out to the frame it is
            // given, so this is how a 44 pt tap target per day is bought.
            picker.widthAnchor.constraint(equalToConstant: 420),
            picker.heightAnchor.constraint(equalToConstant: 400),

            scopeControl.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 4),
            scopeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scopeControl.widthAnchor.constraint(equalToConstant: 420),
            scopeControl.heightAnchor.constraint(equalToConstant: Theme.searchScopeBarHeight - 6),

            explain.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 10),
            explain.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            explain.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func goTapped() {
        // Read from the picker rather than from a change handler. An inline
        // picker does not fire `.valueChanged` for the month arrows, and a
        // day tapped without the handler having fired would otherwise send
        // the PREVIOUS date — the failure that looks like the jump ignoring
        // him.
        let chosen = picker.date
        let scope = MailSearchScope.allCases[scopeControl.selectedSegmentIndex]
        Self.lastPicked = chosen
        Self.lastScope = scope
        dismiss(animated: true) { [onPick] in onPick?(chosen, scope) }
    }
}

#endif
