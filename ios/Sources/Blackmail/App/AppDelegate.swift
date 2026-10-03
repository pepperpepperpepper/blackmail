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
        // First, before anything kept on the iPad is read: this launch is
        // counted, and after launches in a row that never finished, what
        // they read before the first frame is set aside (B-057). With no
        // updates ever, a crash at every launch would otherwise end the app
        // for good, and deleting it would take the letters kept only here.
        SafeStart.app.launch()
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
        // The setup form has no page and no pass: half a minute after it
        // is up, the launch has finished. The mail's screens say so
        // themselves, after their first page and first pass.
        if !(window.rootViewController is RootViewController) {
            SafeStart.app.firstPageTried(passEnded: {})
        }
        // Hunts for views Auto Layout has not actually been told the size
        // of. Two bugs of exactly that shape have now reached the device
        // (B-027, B-029), both invisible until something unrelated moved.
        // Bounded to three minutes after launch, and only when switched on
        // from the connection log's Layout button: it does nothing for him
        // and runs on the main thread. See LayoutAudit.enabledKey.
        LayoutAudit.beginSweeping()
        // An account set up by a build from before the share extension had
        // never been handed to it, and the book and the signature's pictures
        // change without passing through the setup form.
        Self.syncShareMirror()
        // The signature as first set, kept once to be restored
        // (`OriginalSignature`). The formatted one reaches the iPad from
        // outside the app (B-035), so a launch is where it is first seen.
        // Off the main thread, on the mirror's queue: a file looked for, and
        // written once.
        Self.mirrorQueue.async {
            guard let account = CredentialStore.loadAccount() else { return }
            OriginalSignature.keepIfFirst(account, images: SignatureImages.load(),
                                          in: OriginalSignature.appRoot)
        }
        return true
    }

    /// The address book is written once per page of mail listed, so the
    /// addresses noted since the last page, if any, are written here, while
    /// the app is still allowed to run. A suspended app can be ended without
    /// being told.
    ///
    /// The copy of his mail kept on the iPad the same (D-016): what has
    /// changed since its last write, the Inbox's page listed a moment ago
    /// or a letter just read, is written now.
    ///
    /// And the launch has finished (`SafeStart`): an app that has come as
    /// far as the background did not crash at launch, however soon he
    /// left. A crash, or iOS's watchdog ending it, never comes here.
    ///
    /// A command on the wire as he leaves is not timed for the connection
    /// log: iOS may hold the app still with it (`Diagnostics.awayOrBack`).
    public func applicationDidEnterBackground(_ application: UIApplication) {
        SafeStart.app.finished()
        Diagnostics.wentAwayOrCameBack()
        RecipientBook.shared.flush()
        (window?.rootViewController as? RootViewController)?.repository.shelf?.flush()
        Self.syncShareMirror()
    }

    /// Ended while it was still running, swiped away in the app switcher
    /// before iOS had suspended it, or ended by iOS for a reason of its own:
    /// the launch got going, and has finished (`SafeStart`). Apple documents
    /// this as called for an app ended while running rather than suspended;
    /// whether a swipe from the switcher sends it to the background first is
    /// not documented, and a quick look ended that way must not count. A
    /// crash, or the watchdog, never comes here.
    ///
    /// For the same reason the tries the pass has on their way are taken
    /// back, as leaving takes them back (`LocalDrafts.wentToBackground`): he
    /// ended the app, which is no fault of the letter's, and a letter swiped
    /// away mid-send three times would otherwise be given up on. Only once
    /// the mail's screens are up: the setup form has no letters to take.
    public func applicationWillTerminate(_ application: UIApplication) {
        SafeStart.app.finished()
        if window?.rootViewController is RootViewController {
            LocalDrafts.shared.wentToBackground()
        }
    }

    /// Back from the background, where he may have shared from Safari: who
    /// those letters went to is taken into the book here.
    ///
    /// And a command that was on the wire while the app was away, whose
    /// answer is read only now, is not timed for the connection log
    /// (`Diagnostics.awayOrBack`).
    public func applicationWillEnterForeground(_ application: UIApplication) {
        Diagnostics.wentAwayOrCameBack()
        Self.syncShareMirror()
    }

    /// A `mailto:` link, from another app or from a letter, opens this app's
    /// composer with the link's fields in it (B-036). Only once an account
    /// is set up: the setup form has nothing to write the letter in.
    ///
    /// Whether iOS hands another app's link here at all is its business: it
    /// sends `mailto:` to the default mail app, which a sideloaded app cannot
    /// become. A link in one of his own letters is handled in the reading
    /// pane and does not come through here.
    public func application(_ app: UIApplication, open url: URL,
                            options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme?.lowercased() == "mailto",
              let root = window?.rootViewController as? RootViewController,
              let draft = MailtoLink.draft(from: url,
                                           signature: CredentialStore.loadAccount()?.signature ?? "")
        else { return false }
        // Over whatever is showing, as a link tapped in a letter opens it.
        var top: UIViewController = root
        while let shown = top.presentedViewController, !shown.isBeingDismissed { top = shown }
        let compose = ComposeViewController(repository: root.repository, draft: draft)
        let nav = UINavigationController(rootViewController: compose)
        nav.modalPresentationStyle = .formSheet
        top.present(nav, animated: true)
        return true
    }

    /// Hands the share extension what it needs to send as the app would
    /// (`ShareMirror`), and takes in who it has sent to; nothing at all in a
    /// build without the extension (`ShareMirror.app`). Off the main
    /// thread: a handful of Keychain reads and an encode of the book have no
    /// business in front of the first frame. One at a time, in order.
    private static let mirrorQueue = DispatchQueue(label: "wtf.uhoh.blackmail.share-mirror",
                                                   qos: .utility)

    private static func syncShareMirror() {
        mirrorQueue.async {
            guard let mirror = ShareMirror.app else { return }
            let account = CredentialStore.loadAccount()
            mirror.sync(account: account,
                        password: account.flatMap(CredentialStore.loadPassword(for:)),
                        signatureImages: SignatureImages.load(),
                        book: .shared)
        }
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
        setup.onConnected = { [weak nav] account, password, notice in
            let repository = IMAPMailRepository(account: account, password: password)
            // Replace the whole root rather than dismissing back to nothing:
            // after setup there is no reason to be able to navigate back to
            // the password form, and a back button that reaches it is a way
            // to break a working account by accident.
            nav?.view.window?.rootViewController = RootViewController(repository: repository,
                                                                      saying: notice)
        }
        return nav
    }
}

#endif
