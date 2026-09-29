// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import UIKit

/// Finds views whose size or position Auto Layout has not actually been
/// told, and says so in the connection log.
///
/// Written after two bugs of exactly one shape, a week apart, both of which
/// were invisible until something unrelated moved:
///
/// - **B-027.** `MessageHeaderView` takes its height from a chain that runs
///   through an `attachmentStack`, and an empty `UIStackView` has no
///   intrinsic height. On a message with no files, nothing decided how tall
///   the header was. Auto Layout picked the content height in the
///   single-message pane, which looked perfect, and 760 of an 834 pt pane in
///   the conversation pane, which left the web view 0 points tall and the
///   reading pane blank.
/// - **B-029.** The search band was a `tableHeaderView`, so it scrolled away
///   with the mail, and when it was pinned instead, its height was read back
///   from a frame the table resets in the same layout pass — so the scope bar
///   drew on top of the first message.
///
/// The common property is the dangerous one: **an ambiguous layout is not a
/// crash and not a warning.** It is a view that is correct everywhere you
/// happened to look, and wrong somewhere you did not. UIKit will happily pick
/// a value, and it is entitled to pick a different one tomorrow.
///
/// `hasAmbiguousLayout` is public API and answers this question directly, so
/// the hunt does not have to be a reading of constraint chains.
enum LayoutAudit {

    /// One thing worth saying about one view.
    struct Finding {
        let path: String
        let detail: String
        /// Used to report each distinct problem once rather than every tick.
        var signature: String { path + "|" + detail }
    }

    /// Subtrees not worth descending into.
    ///
    /// The text editing machinery and the keyboard are full of views that
    /// are legitimately zero-sized or ambiguous — a selection view with no
    /// selection, for one — and reporting them buries the handful of
    /// findings that are ours. Matched on a prefix so the private classes
    /// behind each are covered too.
    ///
    /// Deliberately NOT a blanket "ignore anything that is not ours":
    /// B-027's symptom was a `WKWebView` at 613x0, and a filter that strict
    /// would have missed the bug this file was written for.
    private static let skippedSubtrees = [
        "UIFieldEditor", "_UITextLayout", "UITextSelection", "UIKeyboard",
        "UIRemoteKeyboard", "UIInputSetHost", "UICompatibilityInputViewController",
        "UIPredictionViewController", "_UIKBCompat",
        // Alert and action-sheet internals: the header scroll view is
        // legitimately zero-high on a sheet with no title or message,
        // which is every sheet this app presents.
        "_UIAlertController", "_UIInterfaceAction",
        // The calendar grid in `Go to Date` keeps zero-sized cell views
        // for the days outside the month.
        "_UIDatePicker", "UICalendarView",
    ]

    /// Walks a view tree and reports what is not nailed down.
    static func findings(in root: UIView, path: String = "") -> [Finding] {
        let name = String(describing: type(of: root))
        if skippedSubtrees.contains(where: { name.hasPrefix($0) }) { return [] }

        var out: [Finding] = []
        let here = path.isEmpty ? name : path + " > " + name

        // The window itself reports ambiguous whenever UIKit has a
        // presentation in flight over it. Its own frame is the screen and
        // is not something this app sets, so only its contents are worth
        // reporting.
        if root.hasAmbiguousLayout, !(root is UIWindow) {
            out.append(Finding(path: here,
                               detail: "AMBIGUOUS frame "
                                   + "\(Int(root.frame.width))x\(Int(root.frame.height))"))
        }

        // A view with children and no height is the SHAPE of B-027: the
        // content exists and there is nowhere to draw it. Reported
        // separately because such a view is not necessarily ambiguous —
        // something may have confidently decided it is zero.
        if !root.isHidden, !root.subviews.isEmpty,
           root.frame.height == 0 || root.frame.width == 0 {
            out.append(Finding(path: here,
                               detail: "ZERO SIZE with \(root.subviews.count) subviews"))
        }

        // A view positioned by its autoresizing mask that ALSO carries
        // constraints is the classic way to get a conflict that UIKit
        // resolves by breaking one of them. Scroll views and the system's
        // own internals do this legitimately, so only our own classes are
        // reported.
        if root.translatesAutoresizingMaskIntoConstraints, !root.constraints.isEmpty,
           isOurs(root) {
            out.append(Finding(path: here,
                               detail: "autoresizing mask + \(root.constraints.count) constraints"))
        }

        for child in root.subviews {
            out += findings(in: child, path: here)
        }
        return out
    }

    /// Ours rather than UIKit's. The system's private views break these
    /// rules constantly and correctly, and reporting them would bury the
    /// handful of findings that are actually ours.
    private static func isOurs(_ view: UIView) -> Bool {
        let name = String(reflecting: type(of: view))
        return name.hasPrefix("Blackmail.")
    }

    // MARK: - Running it

    private static var seen = Set<String>()
    private static var timer: Timer?
    private static var started: Date?

    /// How long the sweep keeps running after launch.
    ///
    /// Bounded rather than permanent. The walk itself is trivial, but this
    /// is a tablet that stays on all day for a man in his nineties, and a
    /// timer that exists only to help whoever is developing has no business
    /// still ticking at bedtime. Three minutes covers opening every screen.
    private static let runFor: TimeInterval = 180

    /// The defaults key that turns the launch sweep on. OFF when absent.
    ///
    /// The sweep is for whoever is developing, not for him. It is main-thread
    /// work every two seconds through the first three minutes of a launch,
    /// which is when he is waiting for his mail and making his first taps,
    /// and the SDK files `hasAmbiguousLayout` under "debugging only, never
    /// in shipping code". `#if DEBUG` cannot be the gate: there is no debug
    /// build for the device (B-013), so it would switch the sweep off for
    /// the developer too. Hence a switch in `UserDefaults`, read at launch:
    ///
    /// - The Layout button on the connection log (five taps on the list's
    ///   status line) flips it. Switching it on also sweeps once there and
    ///   then, and keeps sweeping for three minutes from that moment, so the
    ///   screens can be walked straight away; it then stays on for every
    ///   launch until it is switched off again.
    /// - For one launch, a launch argument does the same without touching
    ///   the stored value: `-blackmail.layoutAudit YES`. The deploy script
    ///   opens the app with `uiopen`, which cannot pass one, so this is for
    ///   a launch made some other way.
    static let enabledKey = "blackmail.layoutAudit"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Starts sweeping the key window every couple of seconds, reporting
    /// each distinct finding once. Does nothing unless `isEnabled`.
    static func beginSweeping() {
        guard isEnabled, timer == nil else { return }
        started = Date()
        Diagnostics.log(.note, "layout: sweep started")
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                if let began = Self.started, Date().timeIntervalSince(began) > runFor {
                    Self.timer?.invalidate()
                    Self.timer = nil
                    Diagnostics.log(.note, "layout: sweep finished, "
                                    + "\(Self.seen.count) finding(s) total")
                    return
                }
                sweepNow()
            }
        }
    }

    /// Stops a sweep before its three minutes are up. For the switch on the
    /// connection log.
    static func stopSweeping() {
        guard let running = timer else { return }
        running.invalidate()
        timer = nil
        Diagnostics.log(.note, "layout: sweep stopped, \(seen.count) finding(s) total")
    }

    /// One pass as the panes change (D-015), when the sweep is switched on,
    /// whether or not its three minutes are up. The view button swaps a
    /// constraint and hides a pane, the kind of change this exists to check,
    /// and each arrangement has views the other hides, so a launch in one
    /// says nothing about the other. The log line says which arrangement
    /// the findings after it are in.
    @MainActor
    static func panesChanged(to arrangement: String) {
        guard isEnabled else { return }
        Diagnostics.log(.note, "layout: \(arrangement)")
        sweepNow()
    }

    /// One pass, now. Also what the connection log's switch runs when it is
    /// turned on.
    @MainActor
    @discardableResult
    static func sweepNow() -> Int {
        var fresh = 0
        for window in UIApplication.shared.windows where window.isKeyWindow || window.isHidden == false {
            for finding in findings(in: window) where seen.insert(finding.signature).inserted {
                Diagnostics.log(.note, "layout: \(finding.detail) — \(finding.path)")
                fresh += 1
            }
        }
        return fresh
    }
}

#endif
