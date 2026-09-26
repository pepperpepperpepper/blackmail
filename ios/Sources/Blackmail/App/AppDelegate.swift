// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

// `public` because the executable target is now a separate module whose
// main.swift names this class.
public final class AppDelegate: UIResponder, UIApplicationDelegate {
    public var window: UIWindow?

    public override init() { super.init() }

    public func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // No scene delegate and no UIApplicationSceneManifest. The proven
        // shape on this pipeline is plain UIApplicationMain + UIWindow, and
        // the starter's UISceneConfiguration without a manifest is exactly why
        // it could never have launched.
        // Every attachment ever opened was written to the temporary
        // directory to be handed to QuickLook, and nothing deleted them.
        // The system reclaims that directory eventually, but "eventually" on
        // a tablet that is never restarted and holds one man's entire
        // correspondence is not a bound. Launch is the only instant at which
        // nothing can be open.
        AttachmentStore.purge()

        let window = UIWindow(frame: UIScreen.main.bounds)
        // Dark, always, never following the system. The owner's iPad ran
        // with Smart Invert on (D-010), and the requirement is that this look
        // be the default with no setting required — so the app must not hand the
        // decision back to a switch he would then have to find again. Pinning
        // it also keeps the keyboard, alerts and selection highlights dark
        // rather than flashing white over a black app.
        window.overrideUserInterfaceStyle = .dark
        // NOTE: the app cannot defend itself against Smart Invert. Setting
        // `accessibilityIgnoresInvertColors` was tried here AND on the root
        // view controller's view, deployed and photographed both times, and
        // the app still came out white with an orange tint. That property only
        // ever governed images. Smart Invert must be OFF on the device — see
        // docs/KNOWN_ISSUES.md B-006.
        window.rootViewController = Self.makeRoot()
        window.makeKeyAndVisible()
        self.window = window
        // Hunts for views Auto Layout has not actually been told the size
        // of. Two bugs of exactly that shape have now reached the device
        // (B-027, B-029), both invisible until something unrelated moved.
        // Bounded to three minutes after launch; see LayoutAudit.
        LayoutAudit.beginSweeping()
        return true
    }

    /// Real mail if an account has been set up, the setup form if not.
    ///
    /// `MockMailRepository` is deliberately no longer reachable at runtime. It
    /// stays in the tree as a fixture source for tests, but an app that can
    /// silently fall back to fake mail is one where "it works" means nothing —
    /// and the whole lesson of the mock-data builds was that the interface looked
    /// finished while the letters were invented.
    ///
    /// There is exactly ONE way an account gets into this app: somebody types
    /// it into `AccountSetupViewController`, which verifies it against the
    /// server before storing it. A `Documents/bootstrap.json` import used to
    /// sit here as well, for driving setup on the dev iPad where synthetic
    /// touch cannot move focus to the form's second field (B-009). It is
    /// gone. Only root could place that file, so it was never reachable on a
    /// stock iPad — but a code path that takes a password out of a plaintext
    /// file has no business existing in an app that will hold one man's
    /// entire correspondence, and "unreachable in the configuration I tested"
    /// is not a property worth shipping on.
    static func makeRoot() -> UIViewController {
        if let repository = IMAPMailRepository.fromStoredCredentials() {
            return RootViewController(repository: repository)
        }
        let setup = AccountSetupViewController()
        let nav = UINavigationController(rootViewController: setup)
        setup.onConnected = { [weak nav] account, password in
            let repository = IMAPMailRepository(account: account, password: password)
            // Replace the whole root rather than dismissing back to nothing:
            // after setup there is no reason to be able to navigate back to
            // the password form, and a back button that reaches it is a way
            // to break a working account by accident.
            nav?.view.window?.rootViewController = RootViewController(repository: repository)
        }
        return nav
    }
}

#endif
