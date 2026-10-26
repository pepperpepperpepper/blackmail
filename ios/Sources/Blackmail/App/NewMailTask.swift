// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit) && canImport(BackgroundTasks) && canImport(UserNotifications)

import UIKit
import BackgroundTasks
import Network
import UserNotifications

extension AppBadge {
    /// The app's: the number on its icon, through iOS's notification
    /// centre, which sets it only once he has said yes to iOS's question
    /// and Badges are on for the app in Settings, as Mail's own.
    static let app = AppBadge { count in
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }
}

/// The check for new mail iOS runs while the app is in the background, and
/// the banners it puts up (B-161; `NewMailBanners` for what Mail does).
///
/// An app refresh (`BGAppRefreshTask`), the one way iOS lets an app with
/// no server of its own look for mail while it is not in front: asked for
/// as he leaves the app and after each check, `NewMailBanners.interval` at
/// the soonest, and run when iOS chooses. Its name is in Info.plist, and
/// it is registered at every launch before the launch ends, as iOS
/// requires: a launch into the background for it would otherwise be ended.
///
/// A check goes only with his yes to iOS's question and banners or the
/// number on for the app, with an account set up, with the iPad on charge
/// and on Wi-Fi, as Mail fetches from the factory (`mailWouldFetch`), and
/// when no launch and no check is unfinished (`SafeStart.checkBegins`).
/// Otherwise iOS's wake is held at once, the next asked for. It ends within
/// `NewMailBanners.allowance`, or when iOS says its time is up, or as he
/// opens the app, which calls it off before anything of it is shown: no
/// banner is put up while the app is in front, as Mail puts up none for
/// the Inbox in front of him.
@MainActor
enum NewMailTask {

    /// The check on its way, and how it ends, once.
    private static var running: (work: Task<Void, Never>, end: (Bool) -> Void)?

    /// The question in front of the app's screens, asked once (`BannerQuestion`).
    private static var question = BannerQuestion()

    /// At every launch, before it ends.
    nonisolated static func register() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: NewMailBanners.taskIdentifier,
                                            using: nil) { task in
            Task { @MainActor in run(task) }
        }
    }

    /// The next check asked for, when banners or the number can be shown:
    /// iOS keeps one at a time, and a new one takes the last one's place.
    static func schedule() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard shows(settings) else { return }
            let request = BGAppRefreshTaskRequest(identifier: NewMailBanners.taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: NewMailBanners.interval)
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                // Background App Refresh off, for the app or the iPad, or
                // Low Power Mode: no check until it is on again.
                Diagnostics.log(.note, "NEW-MAIL not-scheduled")
            }
        }
    }

    /// He has left the app: letters that come from now have banners, and
    /// the number is set again.
    static func leaving() {
        BannerStore.app.update { $0.leftAt = Date() }
        AppBadge.app.again()
        schedule()
    }

    /// He has opened the app: a check on its way is called off, nothing of
    /// it shown, and its count taken back before the launch, if this is
    /// one, is counted; a check's refused sign-in is his to see in the app
    /// now, and the next check may try again.
    static func cameToFront() {
        if let running {
            running.work.cancel()
            running.end(false)
        }
        guard BannerStore.app.load().refusedAt != nil else { return }
        BannerStore.app.update { $0.refusedAt = nil }
    }

    /// Asked of iOS once, at the first moment that interrupts nothing after
    /// the Inbox's list has come (`BannerQuestion`): its own question, its
    /// own words. Badges and banners, as Mail's factory settings have them;
    /// no sound, as Mail's New Mail sound is None from the factory.
    static func askIfDue(inboxListed: Bool, sheetUp: Bool, inHand: Bool) {
        let inFront = UIApplication.shared.applicationState == .active
        guard question.due(inboxListed: inboxListed, sheetUp: sheetUp, inHand: inHand,
                           inFront: inFront) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            let centre = UNUserNotificationCenter.current()
            centre.requestAuthorization(options: [.alert, .badge]) { granted, _ in
                Task { @MainActor in
                    Diagnostics.log(.note, "NEW-MAIL asked granted=\(granted)")
                    guard granted else { return }
                    AppBadge.app.again()
                    schedule()
                }
            }
        }
    }

    /// Whether iOS will show anything of a check: his yes, and banners or
    /// the number on for the app in Settings.
    nonisolated private static func shows(_ settings: UNNotificationSettings) -> Bool {
        settings.authorizationStatus == .authorized
            && (settings.alertSetting == .enabled || settings.badgeSetting == .enabled)
    }

    // MARK: - The check

    private static func run(_ task: BGTask) {
        // The next one first, so a check that is ended still leaves one asked for.
        schedule()
        guard running == nil, UIApplication.shared.applicationState == .background else {
            Diagnostics.log(.note, "NEW-MAIL held")
            task.setTaskCompleted(success: true)
            return
        }
        var ended = false
        let end: (Bool) -> Void = { success in
            guard !ended else { return }
            ended = true
            running = nil
            // Nothing unless the check was counted.
            SafeStart.app.checkEnded()
            task.setTaskCompleted(success: success)
        }
        let work = Task { @MainActor in
            guard await mailWouldFetch() else {
                Diagnostics.log(.note, "NEW-MAIL held not-charging-on-wifi")
                end(true)
                return
            }
            guard !Task.isCancelled, UIApplication.shared.applicationState == .background,
                  SafeStart.app.checkBegins() else {
                Diagnostics.log(.note, "NEW-MAIL held")
                end(true)
                return
            }
            let success = await check()
            end(success)
        }
        running = (work, end)
        task.expirationHandler = {
            Task { @MainActor in
                work.cancel()
                end(false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + NewMailBanners.allowance) {
            Task { @MainActor in
                work.cancel()
                end(false)
            }
        }
    }

    /// Whether Mail would fetch now, as it does from the factory. His Gmail
    /// gives Mail no push, so Mail fetches, and its factory Fetch,
    /// Automatically, "will fetch new data in the background only when your
    /// device is charging and connected to Wi-Fi" (Apple's support article
    /// 102578). On charge, charging or full, and the network up over Wi-Fi;
    /// a state iOS does not say counts as neither.
    private static func mailWouldFetch() async -> Bool {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let power = device.batteryState
        device.isBatteryMonitoringEnabled = false
        guard power == .charging || power == .full else { return false }
        return await onWiFi()
    }

    /// The network as iOS has it now, from a monitor started for its one
    /// answer and stopped as it gives it: up, and over Wi-Fi. No answer
    /// within two seconds counts as not.
    private static func onWiFi() async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "wtf.uhoh.blackmail.new-mail.path")
            // Both answers come on `queue`: the first is told, and stops the
            // monitor; the second finds it stopped.
            let answer: (Bool) -> Void = { onWiFi in
                guard monitor.pathUpdateHandler != nil else { return }
                monitor.pathUpdateHandler = nil
                monitor.cancel()
                done.resume(returning: onWiFi)
            }
            monitor.pathUpdateHandler = { path in
                answer(path.status == .satisfied && path.usesInterfaceType(.wifi))
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) { answer(false) }
        }
    }

    /// One check, and what it found put up: nothing if he has opened the
    /// app meanwhile, or the check has been called off.
    private static func check() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard shows(settings) else { return true }
        guard let account = CredentialStore.loadAccount(),
              let password = CredentialStore.loadPassword(for: account) else { return true }
        let check = InboxCheck(account: account, password: password,
                               transport: TLSConnection.factory, store: .app)
        guard let found = await check.run() else { return false }
        guard !Task.isCancelled, UIApplication.shared.applicationState == .background else {
            return true
        }
        AppBadge.app.counted(found.unread)
        guard settings.alertSetting == .enabled else { return true }
        let centre = UNUserNotificationCenter.current()
        for banner in found.banners {
            let content = UNMutableNotificationContent()
            content.title = banner.title
            content.subtitle = banner.subtitle
            content.body = banner.body
            content.userInfo = banner.userInfo
            try? await centre.add(UNNotificationRequest(identifier: banner.identifier,
                                                        content: content, trigger: nil))
        }
        return true
    }
}

#endif
