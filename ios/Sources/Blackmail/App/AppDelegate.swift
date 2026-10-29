// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import UserNotifications

// `public` because the executable target is now a separate module whose
// main.swift names this class.
public final class AppDelegate: UIResponder, UIApplicationDelegate {
    public var window: UIWindow?

    public override init() { super.init() }

    /// A launch he sees starts the app at once. A launch into the
    /// background, iOS waking the app for its check for new mail (B-161),
    /// starts nothing of it: no screen, no connection of the mail's, no
    /// pass over the Outbox, nothing kept read or written, and no launch
    /// counted (`SafeStart`). The check goes on a connection of its own,
    /// and the app starts as he opens it (`applicationWillEnterForeground`).
    ///
    /// The check is registered at every launch, before the launch ends, as
    /// iOS requires, and the banners' taps come here (`userNotificationCenter`).
    public func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if application.applicationState != .background { start() }
        NewMailTask.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// The app started: at a launch he sees, or as he opens an app iOS
    /// launched into the background. Once.
    private func start() {
        guard window == nil else { return }
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
        // The size the app is drawn at, Large whatever the iPad's text
        // size (B-166, Changed 2026-10-27), and Bold Text, in `Theme`
        // before any screen is made, and Bold Text followed from now on.
        _ = TextSizes.app

        let window = UIWindow(frame: UIScreen.main.bounds)
        // Dark, always, never following the system. The owner's iPad ran
        // with Smart Invert on (D-010), and the requirement is that this look
        // be the default with no setting required — so the app must not hand the
        // decision back to a switch he would then have to find again. Pinning
        // it also keeps the keyboard, alerts and selection highlights dark
        // rather than flashing white over a black app. Info.plist's
        // UIUserInterfaceStyle is Dark too, for the launch screen the system
        // draws before this runs, which was white while it said Light (B-124).
        window.overrideUserInterfaceStyle = .dark
        // Everything in the window at Large, whatever the iPad's text size
        // or a Per-App size (B-166, Changed 2026-10-27), as the dark above
        // reaches the alerts: what the panes' and the sheets' traits of
        // Large do not, the setup form above all, the window's first
        // screen. The questions, the action sheets and the bubble menu were
        // meant to be held by it too, and on the test iPad were not: each
        // is held on its own (`heldAtLarge`, B-166, found 2026-10-28), and
        // their words, believed to follow the app's own size (not shown),
        // by the app's answering Large (`BlackmailApplication`, the second
        // round). At Large it changes nothing.
        window.minimumContentSizeCategory = .large
        window.maximumContentSizeCategory = .large
        // NOTE: the app cannot keep its own look under Smart Invert. Setting
        // `accessibilityIgnoresInvertColors` was tried here AND on the root
        // view controller's view, deployed and photographed both times, and
        // the app still came out white with an orange tint. That property only
        // ever governed images. Nor is Mail kept dark: with the iPad's Smart
        // Invert on, Mail 16.5.1 comes out light with its tint orange just as
        // Blackmail does (the comparison of 2026-10-29), so Blackmail follows
        // it as Mail does, and its letters come out as Mail's under it
        // (`SmartInvert`, B-179). See docs/KNOWN_ISSUES.md B-006, D-010.
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
    ///
    /// And he has left the app: the number on its icon is set again, mail
    /// that comes from now has banners, and the next check for it is asked
    /// for (B-161). Only for an app that was started: one iOS launched into
    /// the background was never in front of him.
    public func applicationDidEnterBackground(_ application: UIApplication) {
        SafeStart.app.finished()
        Diagnostics.wentAwayOrCameBack()
        RecipientBook.shared.flush()
        (window?.rootViewController as? RootViewController)?.repository.shelf?.flush()
        Self.syncShareMirror(readingContacts: false)
        if window != nil { NewMailTask.leaving() }
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
    ///
    /// A check for new mail on its way is called off first, before anything
    /// of it is shown and before the launch is counted (B-161); and an app
    /// iOS launched into the background for one starts now, as he opens it.
    public func applicationWillEnterForeground(_ application: UIApplication) {
        Diagnostics.wentAwayOrCameBack()
        NewMailTask.cameToFront()
        start()
        Self.syncShareMirror()
    }

    /// In front: started, if coming forward did not start it already.
    public func applicationDidBecomeActive(_ application: UIApplication) {
        NewMailTask.cameToFront()
        start()
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
        let nav = UINavigationController.formSheet(compose)
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

    /// His Contacts are read again here too, if he has said yes, for the
    /// composer and for the extension (B-162): a card changed in Contacts
    /// is offered from his next return to the app. Never asked for here;
    /// only his typing in an address field asks (`AddressContacts`).
    ///
    /// Read at launch and on his return, and not as the app goes into the
    /// background (`readingContacts` false), where iOS may suspend the app
    /// halfway through a read that his return makes again anyway; the copy
    /// is left as it is then. And never in a launch that follows launches
    /// in a row that never finished (`SafeStart`, from its first step): the
    /// read is in the seconds after the first frame, and a card that ended
    /// every launch inside Contacts would otherwise be read again at each.
    private static func syncShareMirror(readingContacts: Bool = true) {
        let reads = readingContacts && !SafeStart.app.steps.forgetsKeptState
        mirrorQueue.async {
            let contacts = reads ? AddressContacts.shared.readIfAllowed() : nil
            guard let mirror = ShareMirror.app else { return }
            let account = CredentialStore.loadAccount()
            mirror.sync(account: account,
                        password: account.flatMap(CredentialStore.loadPassword(for:)),
                        signatureImages: SignatureImages.load(),
                        book: .shared,
                        contacts: contacts)
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

// MARK: - The banners for new mail (B-161)

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// None while the app is in front, as Mail puts up none for the Inbox in
    /// front of him. The check puts up none then either; this is for one
    /// that reached iOS as he opened the app.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler:
                                        @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    /// A banner tapped: its letter opened in the Inbox, as a tap on its row
    /// opens it (`RootViewController.openFromBanner`).
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let letter = NewMailBanners.Tapped(
                userInfo: response.notification.request.content.userInfo) else { return }
        start()
        (window?.rootViewController as? RootViewController)?.openFromBanner(letter)
    }
}

#endif
