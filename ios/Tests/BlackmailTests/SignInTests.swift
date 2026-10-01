import XCTest
@testable import Blackmail

/// Signing in, when Gmail will not have it, and what is kept safe around it:
/// what setup and Settings check before keeping a password (`SignInCheck`),
/// a new password signed in with at once (`PasswordChange`), what the
/// alerts and the forms say, the signature first set (`OriginalSignature`),
/// and the order the password item is written in (`PasswordWrite`).
///
/// Over the scripted IMAP server and scripted submission servers, through
/// the shipping clients and repository; nothing is sent anywhere.
final class SignInTests: XCTestCase {

    private static let suite = "SignInTests"
    private static let newPassword = "new-app-password"

    /// Gmail's 534 for a sign-in it wants made on the web first, line for
    /// line as its users quote it (Atlassian's help page for
    /// AuthenticationFailedException, Esko's KB182042961): the sign-in
    /// address in angle brackets broken over five lines, its ">" followed
    /// by the sentence, the help page, the tag. The token in the address is
    /// made up, as long as Gmail's.
    private static let gmail534 = [
        "534-5.7.14 <https://accounts.google.com/signin/continue?sarp=1&scc=1&plt=AKgnsbex",
        "534-5.7.14 Ex4mpleT0kenAaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz01",
        "534-5.7.14 23456789-_Ex4mpleT0kenAaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVv",
        "534-5.7.14 WwXxYyZz0123456789-_Ex4mpleT0kenAaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQq",
        "534-5.7.14 RrSsTtUuVvWwXxYyZz-ex> Please log in via your web browser and",
        "534-5.7.14 then try again.",
        "534-5.7.14  Learn more at",
        "534 5.7.14  https://support.google.com/mail/answer/78754 a1sm2345678qkb.12 - gsmtp",
    ]

    private var server: ScriptedIMAPServer!
    private var book: RecipientBook!
    private var clock: ManualClock!
    private var root: URL!

    override func setUp() {
        super.setUp()
        server = ScriptedIMAPServer()
        clock = ManualClock()
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        book = RecipientBook(defaults: defaults)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SignInTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let server { XCTAssertEqual(server.violations, []) }
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        if let root { try? FileManager.default.removeItem(at: root) }
        for outcome in ["ok", "fail"] {
            let transcript = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("blackmail-send-\(CaptureProbe.session)-\(outcome).txt")
            try? FileManager.default.removeItem(atPath: transcript)
        }
        server = nil
        book = nil
        clock = nil
        root = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// IMAP to the scripted server, and a submission server per connection
    /// on 465, made by `submissions`.
    private func transport(_ submissions: Submissions) -> MailTransportFactory {
        let imap = server.transportFactory
        return { host, port in port == 465 ? submissions.next() : imap(host, port) }
    }

    private func makeRepository(password: String,
                                submissions: Submissions) -> IMAPMailRepository {
        let clock = self.clock!
        return IMAPMailRepository(account: server.account, password: password,
                                  transport: transport(submissions), recipients: book,
                                  now: { clock.now() }, signatureImages: { [] },
                                  shelf: keptShelf(for: server.account))
    }

    private func until(file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("never happened", file: file, line: line)
    }

    private func letter(_ subject: String) -> Draft {
        var draft = Draft()
        draft.to = ["carlo@example.org"]
        draft.subject = subject
        draft.body = "Lunch at one?"
        return draft
    }

    private var logins: [String] {
        server.log.filter { $0.verb == "LOGIN" }.map(\.command)
    }

    // MARK: - The submission server's refusals

    /// Gmail's 534 wants a sign-in made some other way first, a sign-in on
    /// the web: a refused sign-in, not the password's, which sent a helper
    /// off to make app password after app password. It is final as the
    /// password's is: AUTH LOGIN is not tried with the same secret.
    func testASubmissionServersWebLoginRefusalIsNotThePasswords() async throws {
        let submission = ScriptedSubmission(
            authReply: "534 5.7.14 Please log in via your web browser and then try again.")
        let client = SMTPClient(account: server.account, transport: { _, _ in submission })
        do {
            try await client.send(Data("Subject: Sunday\r\n\r\nLunch.\r\n".utf8),
                                  from: server.username, to: ["carlo@example.org"],
                                  password: server.password)
            XCTFail("a refused sign-in must not send")
        } catch {
            XCTAssertEqual(error as? MailError, .sendingSignInRefused)
        }
        await client.lettingGo?.value
        let auths = await submission.commands.filter { $0.hasPrefix("AUTH") }
        XCTAssertEqual(auths.count, 1)
    }

    /// Sending is checked by signing in and saying goodbye: EHLO, AUTH and
    /// QUIT, and nothing that could become a letter.
    func testCheckingSendingSendsNoLetter() async throws {
        for refuses in [false, true] {
            let submission = ScriptedSubmission(refusesPassword: refuses)
            let client = SMTPClient(account: server.account, transport: { _, _ in submission })
            do {
                try await client.checkSignIn(password: server.password)
                XCTAssertFalse(refuses)
            } catch {
                XCTAssertTrue(refuses)
                XCTAssertEqual(error as? MailError, .passwordNeedsUpdating)
            }
            await client.lettingGo?.value
            let verbs = await submission.commands.map { String($0.prefix(4)) }
            XCTAssertEqual(verbs, ["EHLO", "AUTH", "QUIT"], "refused: \(refuses)")
            let closed = await submission.isClosed
            XCTAssertTrue(closed)
            let letters = await submission.letters
            XCTAssertEqual(letters, [])
        }
    }

    // MARK: - What setup and Settings check

    /// A password IMAP takes and SMTP refuses is Gmail's wrong-account trap
    /// (B-033): an app password made in another Google account, which
    /// reads that account's mail and sends nothing. It no longer passes.
    /// Checked on the wire: IMAP's LOGIN, LIST and LOGOUT, then the
    /// submission server's EHLO, AUTH and QUIT, and no letter.
    func testAPasswordThatReadsButCannotSendIsNotKept() async throws {
        let submissions = Submissions { ScriptedSubmission(refusesPassword: true) }
        let verdict = await SignInCheck.run(account: server.account, password: server.password,
                                            transport: transport(submissions))
        XCTAssertEqual(verdict, .sendingRefused)
        XCTAssertEqual(server.log.map(\.verb), ["LOGIN", "LIST", "LOGOUT"])
        // The goodbye follows on its own, as a letter's does.
        try await until { await submissions.commands().contains("QUIT") }
        let commands = await submissions.commands().map { String($0.prefix(4)) }
        XCTAssertEqual(commands, ["EHLO", "AUTH", "QUIT"])
        let letters = await submissions.letters()
        XCTAssertEqual(letters, [])
    }

    /// Each outcome: a password both take is kept; one IMAP refuses, for
    /// the password or for a reason of Google's own, is not, and is not
    /// sent to SMTP as well; SMTP's 534 is a sign-in refused for sending
    /// alone, with Gmail's words; a submission server that cannot be
    /// reached says nothing against a password IMAP took.
    func testWhatTheCheckMakesOfEachAnswer() async throws {
        let taken = Submissions { ScriptedSubmission() }
        var verdict = await SignInCheck.run(account: server.account, password: server.password,
                                            transport: transport(taken))
        XCTAssertEqual(verdict, .works)

        let untried = Submissions { ScriptedSubmission() }
        verdict = await SignInCheck.run(account: server.account, password: "not-the-password",
                                        transport: transport(untried))
        XCTAssertEqual(verdict, .passwordRefused)
        XCTAssertEqual(untried.made, 0, "a refused password is not sent a second time")

        server.passwordRevoked = true
        server.loginRefusal = "[ALERT] Web login required (Failure)"
        verdict = await SignInCheck.run(account: server.account, password: server.password,
                                        transport: transport(untried))
        XCTAssertEqual(verdict, .signInRefused(alert: "Web login required (Failure)"))
        XCTAssertEqual(untried.made, 0)
        server.passwordRevoked = false

        let webLogin = Submissions {
            ScriptedSubmission(authReply: "534 5.7.14 Please log in via your web browser.")
        }
        verdict = await SignInCheck.run(account: server.account, password: server.password,
                                        transport: transport(webLogin))
        XCTAssertEqual(verdict, .sendingSignInRefused(text: "Please log in via your web browser."))

        let blocked = Submissions { ScriptedSubmission(failsToOpen: true) }
        verdict = await SignInCheck.run(account: server.account, password: server.password,
                                        transport: transport(blocked))
        XCTAssertEqual(verdict, .works, "sending could not be asked, and nothing was said against it")

        server.isSilent = true
        server.timeout = .milliseconds(50)
        verdict = await SignInCheck.run(account: server.account, password: server.password,
                                        transport: transport(taken))
        XCTAssertEqual(verdict, .unreachable)
    }

    /// What each form says of each outcome. The wrong-account trap names the
    /// Google account the password has to be made in, and, since Gmail is
    /// said to answer the same while it turns away sign-ins to send for a
    /// while, what to do if it was made there; Google's own sentence is
    /// given where it gave one; Settings says the old password is still
    /// there whenever the new one is not kept.
    func testWhatTheFormsSay() {
        let address = server.username
        func said(_ verdict: SignInCheck.Verdict, _ form: SignInCheck.Form) -> String? {
            SignInCheck.sentence(for: verdict, address: address, in: form)
        }
        XCTAssertNil(said(.works, .setup))
        XCTAssertNil(said(.works, .settings))
        XCTAssertEqual(said(.passwordRefused, .setup),
                       "Google refused that password. Check it is an APP password, not your normal one.")
        XCTAssertEqual(said(.passwordRefused, .settings),
                       "Google refused that password. Check it is an APP password.")
        XCTAssertEqual(said(.unreachable, .setup),
                       "Could not reach Gmail. Check the network and try again.")
        XCTAssertEqual(said(.unreachable, .settings),
                       "Could not reach Gmail. Your old password is still in place.")
        XCTAssertEqual(said(.sendingRefused, .setup),
                       "Gmail took that password for reading mail but refused it for sending. "
                       + "Make the app password while signed in to Google as owner@example.com. "
                       + "If you are sure it was made as owner@example.com, wait an hour and "
                       + "try again.")
        XCTAssertEqual(said(.sendingRefused, .settings),
                       "Gmail took that password for reading mail but refused it for sending. "
                       + "Make the app password while signed in to Google as owner@example.com. "
                       + "If you are sure it was made as owner@example.com, wait an hour and "
                       + "try again. Your old password is still in place.")
        XCTAssertEqual(said(.signInRefused(alert: "Web login required."), .setup),
                       "Gmail refused the sign-in. The server returned the error: Web login required.")
        XCTAssertEqual(said(.signInRefused(alert: nil), .settings),
                       "Gmail refused the sign-in. Your old password is still in place.")

        // What the form does: a password that works, or that only SMTP's 534
        // turned away, is kept, the second with a word for the helper; any
        // other is not, with its sentence under the button.
        func done(_ verdict: SignInCheck.Verdict, _ form: SignInCheck.Form) -> SignInCheck.Outcome {
            SignInCheck.outcome(of: verdict, address: address, in: form)
        }
        for form in [SignInCheck.Form.setup, .settings] {
            XCTAssertEqual(done(.works, form), .keep(notice: nil))
            XCTAssertEqual(done(.sendingSignInRefused(text: nil), form),
                           .keep(notice: MailAlert(
                               title: "Cannot Send Mail",
                               message: "Gmail accepted the password for reading mail but is "
                                   + "refusing to send for now.",
                               offersSettings: false)))
            for refused in [SignInCheck.Verdict.passwordRefused, .sendingRefused,
                            .signInRefused(alert: "Web login required."), .unreachable] {
                XCTAssertEqual(done(refused, form),
                               .refuse(sentence: said(refused, form) ?? "none"), "\(refused)")
            }
        }
    }

    /// Gmail's 534 to a password IMAP has just taken: it wants a sign-in on
    /// the web, or something else done, before it lets the account send.
    /// The password is kept, and signed in with at once, as one that works
    /// is; the helper is told, over the screens built again, that reading
    /// works and sending does not for now, in Gmail's own words, its
    /// sign-in link and its tag left out. The next LOGIN carries it. A
    /// letter waiting in the Outbox meets the 534 at the next pass and stops
    /// it, and his own Send says so, as each did before.
    @MainActor
    func testASignInRefusedForSendingAtTheCheckKeepsThePasswordAndSaysSo() async throws {
        let gmail = Self.gmail534.joined(separator: "\r\n")
        let submissions = Submissions { ScriptedSubmission(authReply: gmail) }
        let background = FakeBackground()
        let drafts = LocalDrafts(store: LocalDraftStore(root: root), account: server.username,
                                 background: background.time)
        let old = makeRepository(password: server.password, submissions: submissions)
        _ = try await old.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        submissions.offline = true
        do {
            try await drafts.send(letter("Waiting"), as: "waiting", to: old, progress: nil)
            XCTFail("with no connection it waits")
        } catch {
            XCTAssertTrue(error is Outbox.Waiting)
        }
        submissions.offline = false
        server.replacePassword(with: Self.newPassword)

        let verdict = await SignInCheck.run(account: server.account, password: Self.newPassword,
                                            transport: transport(submissions))
        let words = "Please log in via your web browser and then try again. Learn more at "
            + "https://support.google.com/mail/answer/78754"
        XCTAssertEqual(verdict, .sendingSignInRefused(text: words))
        for form in [SignInCheck.Form.setup, .settings] {
            XCTAssertEqual(SignInCheck.outcome(of: verdict, address: server.username, in: form),
                           .keep(notice: MailAlert(
                               title: "Cannot Send Mail",
                               message: "Gmail accepted the password for reading mail but is "
                                   + "refusing to send for now. The server returned the error: "
                                   + words,
                               offersSettings: false)))
        }

        // Saved (`CredentialStore.save` counts it) and signed in with at once.
        LocalDraftStore.notePasswordSaved(in: root)
        let fresh = await PasswordChange.handOver(from: old, drafts: drafts) {
            self.makeRepository(password: Self.newPassword, submissions: submissions)
        }
        try await until { [server] in server!.log.contains { $0.verb == "LOGOUT" } }
        server.clearLog()
        _ = try await fresh.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(logins, ["LOGIN \"owner@example.com\" \"\(Self.newPassword)\""])

        await drafts.uploadWaiting(to: fresh)?.value
        XCTAssertEqual(drafts.outbox.map(\.key), ["waiting"])
        XCTAssertNil(drafts.uploadWaiting(to: fresh), "the Outbox has stopped")
        do {
            try await drafts.send(letter("His own"), as: "own", to: fresh, progress: nil)
            XCTFail("Gmail is not letting it send")
        } catch {
            XCTAssertEqual(error as? MailError, .sendingSignInRefused)
        }
        let sent = await submissions.letters()
        XCTAssertEqual(sent, [])
    }

    /// The forms and the screens are UIKit and never build on this host, so
    /// their wiring is read from their source, as `ReadingPaneCcTests` reads
    /// the header's: comments out, every run of spaces one space.
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // BlackmailTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // ios
            .appendingPathComponent("Sources/Blackmail/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }

    /// Settings and setup do what the outcome says: keep the password and
    /// hand on the word for the helper, or keep what was there and say why
    /// under the button. The word goes with the password to the screens
    /// built again, which put it up once they are on the screen.
    func testTheFormsKeepWhatTheCheckKeepsAndTheScreensSayIt() throws {
        let wiring: [(String, [String])] = [
            ("UI/SettingsViewController.swift", [
                "switch SignInCheck.outcome(of: verdict, address: updated.address, in: .settings) { "
                    + "case .keep(let notice): save(updated, password: newPassword, notice: notice) "
                    + "case .refuse(let sentence): say(sentence) }",
                "dismiss(animated: true) { signIn?(updated, password, notice) }",
            ]),
            ("UI/AccountSetupViewController.swift", [
                "switch SignInCheck.outcome(of: verdict, address: account.address, in: .setup) { "
                    + "case .keep(let said): notice = said "
                    + "case .refuse(let sentence): show(sentence) return }",
                "try CredentialStore.save(account: account, password: password) "
                    + "onConnected?(account, password, notice)",
            ]),
            ("UI/MessageListViewController.swift", [
                "settings.onPasswordSaved = { [weak self] account, password, notice in "
                    + "self?.onPasswordSaved?(account, password, notice) }",
            ]),
            ("UI/RootViewController.swift", [
                "self?.signIn(as: account, password: password, saying: notice)",
                "window.rootViewController = RootViewController(repository: fresh, saying: notice)",
                "self.notice = notice",
                "override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated) "
                    + "guard let notice else { return } self.notice = nil "
                    + "ErrorPresenter.say(notice, on: self) }",
            ]),
            ("App/AppDelegate.swift", [
                "setup.onConnected = { [weak nav] account, password, notice in",
                "RootViewController(repository: repository, saying: notice)",
            ]),
            ("UI/ErrorPresenter.swift", [
                "put(alert.message, title: alert.title, offeringSettings: alert.offersSettings, on: vc)",
            ]),
        ]
        for (file, lines) in wiring {
            let code = try source(file)
            for line in lines { XCTAssertTrue(code.contains(line), "\(file): \(line)") }
        }
    }

    /// Whatever Settings has to say of a password, the check under way, a
    /// refusal or a save that failed, goes under the password field with
    /// the keyboard put down and the line scrolled into view. Left at the
    /// foot of the sheet it sat under the keyboard, and Save looked as if it
    /// had done nothing.
    func testSettingsSaysWhatBecameOfThePasswordWhereHeCanReadIt() throws {
        let code = try source("UI/SettingsViewController.swift")
        let field = try XCTUnwrap(code.range(of: "stack.addArrangedSubview(passwordField)"))
        let line = try XCTUnwrap(code.range(of: "stack.addArrangedSubview(statusLabel)"))
        let grouping = try XCTUnwrap(code.range(of: "stack.addArrangedSubview(organizeRow)"))
        XCTAssertLessThan(field.lowerBound, line.lowerBound, "under the password field")
        XCTAssertLessThan(line.lowerBound, grouping.lowerBound, "before the switches below it")
        XCTAssertTrue(code.contains("private func say(_ text: String) { statusLabel.text = text "
                                    + "view.endEditing(true) view.layoutIfNeeded() "
                                    + "scrollView.scrollRectToVisible("))
        XCTAssertEqual(code.components(separatedBy: "statusLabel.text =").count - 1, 1,
                       "every message goes through say")
    }

    /// Gmail's words in a 534, kept as an ALERT's are: the codes, the
    /// bracketed sign-in address and the server's tag go, the help page
    /// stays, one line of printable characters, no longer than an ALERT's.
    /// Where nothing is left, nil. The address goes whole however many
    /// lines Gmail breaks it over, from its "<" to its ">"; a "<" nothing
    /// closes is kept, and so is what a second "<" finds held.
    func testA534IsReadForItsWords() {
        // The lines as the reply hands them on, each without "534-" or "534 ".
        XCTAssertEqual(SMTPClient.refusalText(Self.gmail534.map { String($0.dropFirst(4)) }),
                       "Please log in via your web browser and then try again. Learn more at "
                       + "https://support.google.com/mail/answer/78754")
        XCTAssertEqual(SMTPClient.refusalText([
                           "5.7.14 <https://accounts.google.com/signin/continue?sarp=1&plt=AKgnsbex",
                           "5.7.14 Ex4mpleT0kenAaBbCcDdEeFf>",
                           "5.7.14 Please log in via your web browser and then try again."]),
                       "Please log in via your web browser and then try again.")
        XCTAssertEqual(SMTPClient.refusalText(["5.7.14 Sign-ins <3 and", "5.7.14 more"]),
                       "Sign-ins <3 and more")
        XCTAssertEqual(SMTPClient.refusalText(["5.7.14 a <3 b <https://x", "5.7.14 y> c"]),
                       "a <3 b c")
        XCTAssertEqual(SMTPClient.refusalText([
                           "5.7.9 Application-specific password required. Learn more at",
                           "5.7.9  https://support.google.com/mail/?p=InvalidSecondFactor "
                               + "x1sm123.4 - gsmtp"]),
                       "Application-specific password required. Learn more at "
                       + "https://support.google.com/mail/?p=InvalidSecondFactor")
        XCTAssertEqual(SMTPClient.refusalText(["Please\tlog in\u{7}via the web"]),
                       "Please log in via the web")
        XCTAssertNil(SMTPClient.refusalText(["5.7.14 <https://accounts.google.com/signin/x>"]))
        XCTAssertNil(SMTPClient.refusalText([""]))
        let long = SMTPClient.refusalText([String(repeating: "word ", count: 100)])
        XCTAssertEqual(long?.count, IMAPParser.alertLength + 1)
        XCTAssertTrue(long?.hasSuffix("…") == true)
    }

    // MARK: - What the alerts say

    /// A refused password is Mail's "Cannot Get Mail" with a Settings
    /// button, a sign-in refused otherwise the same title over Google's
    /// sentence, and the line under the list names the third state. Every
    /// other failure is said as it always was.
    func testTheAlertsSayWhatWentWrong() {
        XCTAssertEqual(MailAlert.reaching(MailError.passwordNeedsUpdating),
                       MailAlert(title: "Cannot Get Mail",
                                 message: "The user name or password for “Gmail” is incorrect.",
                                 offersSettings: true))
        XCTAssertEqual(MailAlert.reaching(MailError.signInRefused(alert: "Web login required.")),
                       MailAlert(title: "Cannot Get Mail",
                                 message: "Gmail refused the sign-in. The server returned the "
                                    + "error: Web login required.",
                                 offersSettings: false))
        XCTAssertEqual(MailAlert.reaching(MailError.signInRefused(alert: nil)).message,
                       "Gmail refused the sign-in.")
        XCTAssertEqual(MailAlert.reaching(MailError.cannotConnect),
                       MailAlert(title: nil, message: "Can't connect to mail server.",
                                 offersSettings: false))
        XCTAssertEqual(MailAlert.reaching(CancellationError()).message,
                       "Can't connect to mail server.")

        let now = Date()
        var line = UpdatedLine()
        line.succeeded(at: now)
        line.failed(.signInRefused(alert: "Web login required."))
        XCTAssertEqual(line.text(now: now), "Updated Just Now\nGmail Refused Sign-In")
        line.failed(.passwordNeedsUpdating)
        XCTAssertEqual(line.text(now: now), "Updated Just Now\nPassword Needs Updating")
        line.failed(.cannotConnect)
        XCTAssertEqual(line.text(now: now), "Updated Just Now\nNo Connection")
    }

    /// A Flag, Move or Delete from the reading pane that the server did not
    /// take says why: a revoked password as the password's, where every one
    /// used to say "Can't connect to mail server.".
    @MainActor
    func testAWriteFromThePaneSaysWhyItFailed() async throws {
        func makeRepository() -> IMAPMailRepository {
            IMAPMailRepository(account: server.account, password: server.password,
                               transport: server.transportFactory, recipients: book,
                               shelf: keptShelf(for: server.account))
        }
        let rows = try await makeRepository().listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.passwordRevoked = true
        // A launch after Google revoked it: the first write signs in.
        let repository = makeRepository()

        let refused = await PaneActions.refusal(running: .flag(true), on: rows[3],
                                                inFolderWithRole: .inbox, list: nil,
                                                repository: repository, requestSweep: {})
        XCTAssertEqual(refused, .passwordNeedsUpdating)
        XCTAssertEqual(MailAlert.reaching(refused ?? .cannotConnect).offersSettings, true)
    }

    // MARK: - A new password, at once

    /// Google revokes the app password: the IMAP session already signed in
    /// carries on, and the submission server refuses it, which stops the
    /// Outbox. A helper saves a new one in Settings. From that moment the
    /// next LOGIN on the wire carries the new password, not at the next
    /// launch; the Outbox goes with it at the next pass; and the repository
    /// it replaced closes its connection and sends the old password
    /// nowhere again, a letter included.
    @MainActor
    func testANewPasswordSavedInSettingsIsSignedInWithAtOnce() async throws {
        let submissions = Submissions { [server] in ScriptedSubmission(takesOnly: server!.password) }
        let background = FakeBackground()
        let drafts = LocalDrafts(store: LocalDraftStore(root: root), account: server.username,
                                 background: background.time)
        let old = makeRepository(password: server.password, submissions: submissions)
        _ = try await old.listMessages(in: "inbox", beforeUID: nil, limit: 10)

        // A letter sent with no connection waits in the Outbox.
        submissions.offline = true
        do {
            try await drafts.send(letter("Waiting"), as: "waiting", to: old, progress: nil)
            XCTFail("with no connection it waits")
        } catch {
            XCTAssertTrue(error is Outbox.Waiting)
        }
        submissions.offline = false

        // The password is revoked; the pass meets the refusal and the Outbox stops.
        server.replacePassword(with: Self.newPassword)
        await drafts.uploadWaiting(to: old)?.value
        XCTAssertEqual(drafts.outbox.map(\.key), ["waiting"])
        XCTAssertNil(drafts.uploadWaiting(to: old), "the Outbox has stopped")

        // Checked and saved in Settings (`CredentialStore.save` counts it).
        LocalDraftStore.notePasswordSaved(in: root)
        let fresh = await PasswordChange.handOver(from: old, drafts: drafts) {
            self.makeRepository(password: Self.newPassword, submissions: submissions)
        }
        try await until { [server] in server!.log.contains { $0.verb == "LOGOUT" } }
        server.clearLog()

        _ = try await fresh.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        XCTAssertEqual(logins, ["LOGIN \"owner@example.com\" \"\(Self.newPassword)\""])
        await drafts.uploadWaiting(to: fresh)?.value
        XCTAssertEqual(drafts.outbox.map(\.key), [], "the Outbox has gone")
        let sent = await submissions.letters()
        XCTAssertEqual(sent.count, 1)
        let auths = await submissions.commands().filter { $0.hasPrefix("AUTH PLAIN") }
        XCTAssertEqual(auths.compactMap(ScriptedSubmission.password(inPlain:)),
                       ["app-password", Self.newPassword])

        // The old repository, still held by whatever held it, signs in no
        // more and sends nothing.
        server.clearLog()
        let before = submissions.made
        do {
            _ = try await old.listMessages(in: "inbox", beforeUID: nil, limit: 10)
            XCTFail("a retired repository must not connect")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        do {
            try await old.send(letter("Late"))
            XCTFail("a retired repository must not send")
        } catch {
            XCTAssertEqual(error as? MailError, .cannotConnect)
        }
        await old.warmUp()
        XCTAssertEqual(server.log, [], "no LOGIN, nothing")
        XCTAssertEqual(submissions.made, before)
    }

    /// Retired while a command is still out on its connection, the old
    /// repository sends nothing more on it: its LOGOUT waits for that
    /// command, and a call made meanwhile is refused at once rather than
    /// queued behind it, and work nobody asked for finds it down.
    @MainActor
    func testARetiredRepositorySendsNothingMoreOnItsOldConnection() async throws {
        let submissions = Submissions { ScriptedSubmission() }
        let old = makeRepository(password: server.password, submissions: submissions)
        _ = try await old.listMessages(in: "inbox", beforeUID: nil, limit: 10)
        server.holdReplies(to: "NOOP")
        server.clearLog()
        clock.advance(by: 91)
        let warming = Task { await old.warmUp() }
        try await until { [server] in server!.log.map(\.verb) == ["NOOP"] }

        await old.retire()
        let connected = await old.isConnected
        XCTAssertFalse(connected)
        let refused: Error? = try await finishing(within: 2) {
            do {
                _ = try await old.listMessages(in: "inbox", beforeUID: nil, limit: 10)
                return nil
            } catch {
                return error
            }
        }
        XCTAssertEqual(refused as? MailError, .cannotConnect)

        await server.releaseReplies(to: "NOOP")
        await warming.value
        try await until { [server] in server!.log.contains { $0.verb == "LOGOUT" } }
        XCTAssertEqual(server.log.map(\.verb), ["NOOP", "LOGOUT"])
    }

    /// From the moment the new repository signs in, a letter kept on the
    /// iPad before the save is known for such, as it would be after a
    /// relaunch, so what it names by folder and UID alone is not taken for
    /// the new password's mailbox, which may be another (B-033, B-051); a
    /// letter kept after it is this mailbox's.
    @MainActor
    func testLettersKeptBeforeTheSaveAreKnownForSuchAtOnce() async throws {
        let background = FakeBackground()
        let drafts = LocalDrafts(store: LocalDraftStore(root: root), account: server.username,
                                 background: background.time)
        drafts.keep(letter("Before"), as: "before", unfinished: false)
        LocalDraftStore.notePasswordSaved(in: root)
        let before = try XCTUnwrap(drafts.store.letter("before"))
        XCTAssertFalse(drafts.store.savedSince(before), "not yet: the old repository is in use")

        _ = await PasswordChange.handOver(from: nil, drafts: drafts) {
            MockMailRepository()
        }
        XCTAssertEqual(drafts.store.passwordSaves, 1)
        XCTAssertTrue(drafts.store.savedSince(before))
        drafts.keep(letter("After"), as: "after", unfinished: false)
        let after = try XCTUnwrap(drafts.store.letter("after"))
        XCTAssertFalse(drafts.store.savedSince(after))
    }

    // MARK: - The signature

    /// Setup's Connect keeps the stored account for the same address, and
    /// with it the signature and its formatted twin, changing only the
    /// name; another address is a new account.
    func testSetupKeepsTheSignatureOfTheSameAccount() {
        var stored = MailAccount(address: "Owner@Example.com", username: "Owner@Example.com",
                                 displayName: "Old Name", signature: "With love\nThe owner",
                                 signatureHTML: "<table><tr><td>With love</td></tr></table>")
        stored.smtpPort = 587

        let again = MailAccount.settingUp(" owner@example.com ", name: "New Name", over: stored)
        XCTAssertEqual(again.signature, stored.signature)
        XCTAssertEqual(again.signatureHTML, stored.signatureHTML)
        XCTAssertEqual(again.smtpPort, 587)
        XCTAssertEqual(again.displayName, "New Name")

        let other = MailAccount.settingUp("someone@example.net", name: "Someone", over: stored)
        XCTAssertEqual(other, MailAccount(address: "someone@example.net",
                                          username: "someone@example.net", displayName: "Someone"))
        XCTAssertEqual(MailAccount.settingUp("owner@example.com", name: "", over: nil).signature, "")
    }

    /// The first signature set is kept, text, formatted twin and pictures,
    /// and never written again: a later save, a signature made plain or
    /// emptied, leaves it as it was, and restoring it puts all of it back.
    func testTheOriginalSignatureIsKeptOnceAndRestored() throws {
        let picture = SignatureImages.InlineImage(contentID: "<sig-logo>", filename: "logo.png",
                                                  mimeType: "image/png",
                                                  dataBase64: Data([1, 2, 3]).base64EncodedString())
        var account = MailAccount(address: "owner@example.com", username: "owner@example.com")
        XCTAssertFalse(OriginalSignature.keepIfFirst(account, images: [picture], in: root),
                       "no signature, nothing kept")
        XCTAssertNil(OriginalSignature.load(from: root))

        account.signature = "With love\nThe owner"
        account.signatureHTML = "<table><tr><td>With love</td></tr></table>"
        XCTAssertTrue(OriginalSignature.keepIfFirst(account, images: [picture], in: root))

        var changed = account
        changed.signature = "Sent from my iPad"
        changed.signatureHTML = ""
        XCTAssertFalse(OriginalSignature.keepIfFirst(changed, images: [], in: root))

        let original = try XCTUnwrap(OriginalSignature.load(from: root))
        XCTAssertEqual(original.images, [picture])
        let restored = original.restored(into: changed)
        XCTAssertEqual(restored.signature, account.signature)
        XCTAssertEqual(restored.signatureHTML, account.signatureHTML)
        XCTAssertEqual(restored.address, changed.address)
    }

    /// Settings asks before saving a signature emptied, which takes the
    /// formatted twin with it; not for a signature changed, nor where there
    /// was none.
    func testEmptyingTheSignatureIsAskedAbout() {
        var stored = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                 signature: "With love")
        var edited = stored
        edited.signature = "  \n "
        XCTAssertTrue(stored.losesSignature(to: edited))
        edited.signature = "With love, always"
        XCTAssertFalse(stored.losesSignature(to: edited))

        stored.signature = ""
        stored.signatureHTML = "<b>With love</b>"
        edited = stored
        XCTAssertTrue(stored.losesSignature(to: edited), "the formatted one alone is a signature")

        stored.signatureHTML = ""
        XCTAssertFalse(stored.losesSignature(to: stored), "nothing to lose")
    }

    // MARK: - The password item

    /// A write that fails leaves the password that was there: the new one
    /// is written into the item read, in place, and the siblings go only
    /// after it has worked. The sweep used to come first, so a failed add
    /// left no password, and the next launch showed setup.
    func testAPasswordWriteThatFailsLeavesTheOldPassword() {
        let keychain = FakeKeychain([.init(protocolName: "imaps", port: 993, secret: "old")])
        keychain.failsWrites = -34  // errSecIO: a full disk
        let status = PasswordWrite.write(keychain.items(writing: "new"))
        XCTAssertEqual(status, -34)
        XCTAssertEqual(keychain.stored, [.init(protocolName: "imaps", port: 993, secret: "old")])
        XCTAssertEqual(keychain.read, "old")

        // No item read, and the add fails: what was there stays.
        let stale = FakeKeychain([.init(protocolName: "imap", port: 143, secret: "older")])
        stale.failsWrites = -34
        XCTAssertEqual(PasswordWrite.write(stale.items(writing: "new")), -34)
        XCTAssertEqual(stale.stored.count, 1)
    }

    /// A write that works leaves one item under the account and server,
    /// holding the new password, whatever siblings an older build left
    /// (B-033); where there was none, one is added.
    func testAPasswordWriteLeavesOneItemHoldingTheNewPassword() {
        let keychain = FakeKeychain([.init(protocolName: "imap", port: 143, secret: "stale"),
                                     .init(protocolName: "imaps", port: 993, secret: "old"),
                                     .init(protocolName: "imaps", port: 0, secret: "old")])
        XCTAssertEqual(PasswordWrite.write(keychain.items(writing: "new")), PasswordWrite.success)
        XCTAssertEqual(keychain.stored.map(\.secret), ["new"])
        XCTAssertEqual(keychain.read, "new")

        let empty = FakeKeychain([])
        XCTAssertEqual(PasswordWrite.write(empty.items(writing: "new")), PasswordWrite.success)
        XCTAssertEqual(empty.stored, [.init(protocolName: "imaps", port: 0, secret: "new")])
    }
}

// MARK: - Test doubles

/// A submission server per connection, made by `make` as the connection is
/// asked for; with `offline`, one that cannot be reached.
private final class Submissions: @unchecked Sendable {
    private let lock = NSLock()
    private let make: () -> ScriptedSubmission
    private var servers: [ScriptedSubmission] = []
    private var down = false

    init(_ make: @escaping () -> ScriptedSubmission) {
        self.make = make
    }

    var offline: Bool {
        get { lock.lock(); defer { lock.unlock() }; return down }
        set { lock.lock(); down = newValue; lock.unlock() }
    }

    func next() -> ScriptedSubmission {
        lock.lock()
        defer { lock.unlock() }
        let server = down ? ScriptedSubmission(failsToOpen: true) : make()
        servers.append(server)
        return server
    }

    /// Connections asked for.
    var made: Int {
        lock.lock()
        defer { lock.unlock() }
        return servers.count
    }

    private var all: [ScriptedSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return servers
    }

    func commands() async -> [String] {
        var out: [String] = []
        for server in all { out += await server.commands }
        return out
    }

    func letters() async -> [Data] {
        var out: [Data] = []
        for server in all { out += await server.letters }
        return out
    }
}

/// The Keychain as `PasswordWrite` sees it: internet passwords under one
/// account and server, read by protocol "imaps" at any port, as
/// `CredentialStore.baseQuery` reads them, and added at port 0.
private final class FakeKeychain {
    struct Item: Equatable {
        var protocolName: String
        var port: Int
        var secret: String
    }

    private(set) var stored: [Item]
    private var refs: [Int]
    private var nextRef: Int
    /// Every update and add fails with this, where set.
    var failsWrites: Int32?

    init(_ items: [Item]) {
        stored = items
        refs = Array(0..<items.count)
        nextRef = items.count
    }

    /// What a read finds: the first item it matches.
    var read: String? { stored.first { $0.protocolName == "imaps" }?.secret }

    func items(writing secret: String) -> PasswordWrite.Items<Int> {
        PasswordWrite.Items(
            all: { [unowned self] in refs },
            read: { [unowned self] in
                stored.firstIndex { $0.protocolName == "imaps" }.map { refs[$0] }
            },
            update: { [unowned self] in
                if let failure = failsWrites { return failure }
                var found = false
                for i in stored.indices where stored[i].protocolName == "imaps" {
                    stored[i].secret = secret
                    found = true
                }
                return found ? PasswordWrite.success : PasswordWrite.notFound
            },
            add: { [unowned self] in
                if let failure = failsWrites { return failure }
                guard !stored.contains(where: { $0.protocolName == "imaps" && $0.port == 0 }) else {
                    return PasswordWrite.duplicate
                }
                stored.append(Item(protocolName: "imaps", port: 0, secret: secret))
                refs.append(nextRef)
                nextRef += 1
                return PasswordWrite.success
            },
            remove: { [unowned self] ref in
                guard let i = refs.firstIndex(of: ref) else { return PasswordWrite.notFound }
                stored.remove(at: i)
                refs.remove(at: i)
                return PasswordWrite.success
            })
    }
}
