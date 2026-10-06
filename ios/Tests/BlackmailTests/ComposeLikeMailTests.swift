import XCTest
@testable import Blackmail

/// The composer and the share sheet behave as Apple Mail's do on the iPad
/// (B-069). What the form decides is `ComposeForm`, run here; the two
/// sheets are UIKit and never build on this host, so their wiring is read
/// from their source, as `EraseQuestionTests` reads its controllers'.
@MainActor
final class ComposeLikeMailTests: XCTestCase {

    private let seen = Date(timeIntervalSince1970: 1_700_000_000)

    private var book: [KnownRecipient] {
        [KnownRecipient(address: "owner@example.net", name: nil, uses: 40, lastSeen: seen),
         KnownRecipient(address: "carlo@example.org", name: "Carlo", uses: 3, lastSeen: seen),
         KnownRecipient(address: "carla@example.com", name: "Carla", uses: 1, lastSeen: seen)]
    }

    private func message(attachments: [Attachment] = []) -> Message {
        Message(id: "1/9", mailboxID: "INBOX",
                sender: "Carlo <carlo@example.org>", senderAddress: "carlo@example.org",
                to: ["owner@example.com"], cc: [], subject: "Lunch",
                date: seen, textBody: "See you at one.", htmlBody: nil,
                attachments: attachments, messageID: "<a@example.org>", references: nil)
    }

    // MARK: - The title

    /// The subject as he types it, "New Message" while there is none.
    func testTheTitleFollowsTheSubject() {
        XCTAssertEqual(ComposeForm.title(subject: ""), "New Message")
        XCTAssertEqual(ComposeForm.title(subject: "   "), "New Message")
        XCTAssertEqual(ComposeForm.title(subject: "S"), "S")
        XCTAssertEqual(ComposeForm.title(subject: "Sunday lunch "), "Sunday lunch")
    }

    // MARK: - Send

    /// Grey until To, Cc or Bcc holds an address, whichever it is.
    func testSendIsLiveOnlyWithSomeoneToSendTo() {
        XCTAssertFalse(ComposeForm.canSend(to: "", cc: "", bcc: ""))
        XCTAssertFalse(ComposeForm.canSend(to: " ,  , ", cc: " ", bcc: ""))
        XCTAssertTrue(ComposeForm.canSend(to: "carlo@example.org", cc: "", bcc: ""))
        XCTAssertTrue(ComposeForm.canSend(to: "carlo@example.org, ", cc: "", bcc: ""))
        XCTAssertTrue(ComposeForm.canSend(to: "", cc: "carlo@example.org", bcc: ""))
        XCTAssertTrue(ComposeForm.canSend(to: "", cc: "", bcc: "carlo@example.org"))
    }

    // MARK: - Cancel

    /// A new letter, a reply and a forward he never touched close without
    /// a word, though each has words in it: his signature, the quote.
    func testALetterAsItOpenedIsNotAskedAbout() {
        let sig = "Sam\n1 Example Street"
        let file = Attachment(id: "2", filename: "Menu.pdf", mimeType: "application/pdf",
                              size: 33_000)
        for opened in [Draft.blank(signature: sig),
                       Draft.replying(to: message(), all: false, myAddress: "owner@example.com",
                                      signature: sig),
                       Draft.forwarding(message(attachments: [file]), signature: sig)] {
            XCTAssertFalse(ComposeForm.asksBeforeClosing(opened, opened: opened))
        }
    }

    /// Anything changed asks: words, a subject, someone in any field or
    /// moved from one to another, a file added or taken off. Typed and
    /// taken out again, it is as it opened.
    func testAnythingChangedIsAskedAbout() {
        let file = Attachment(id: "2", filename: "Menu.pdf", mimeType: "application/pdf",
                              size: 33_000)
        let opened = Draft.forwarding(message(attachments: [file]), signature: "Sam")

        var words = opened
        words.body = "Have a look\n" + opened.body
        var subject = opened
        subject.subject = "Fwd: Lunch on Sunday"
        var to = opened
        to.to = ["carlo@example.org"]
        var bcc = opened
        bcc.bcc = ["carlo@example.org"]
        var moved = to
        moved.to = []
        moved.cc = ["carlo@example.org"]
        var off = opened
        off.attachments = []
        var added = opened
        added.attachments.append(DraftAttachment(
            source: .localFile(URL(fileURLWithPath: "/staged/Garden.jpg")),
            filename: "Garden.jpg", mimeType: "image/jpeg", size: 3))
        for (changed, what) in [(words, "words"), (subject, "subject"), (to, "To"),
                                (bcc, "Bcc"), (off, "a file off"), (added, "a file on")] {
            XCTAssertTrue(ComposeForm.asksBeforeClosing(changed, opened: opened), what)
        }
        XCTAssertTrue(ComposeForm.asksBeforeClosing(moved, opened: to), "To to Cc")

        var back = words
        back.body = opened.body
        XCTAssertFalse(ComposeForm.asksBeforeClosing(back, opened: opened), "taken out again")
        var blanks = opened
        blanks.to = [" "]
        XCTAssertFalse(ComposeForm.asksBeforeClosing(blanks, opened: opened), "a blank is nobody")
    }

    /// Emptied by hand, there is nothing to keep, and nothing is asked, as
    /// before; with someone still in To there is.
    func testAnEmptiedLetterIsNotAskedAbout() {
        let opened = Draft.blank(signature: "Sam")
        XCTAssertFalse(ComposeForm.asksBeforeClosing(Draft(), opened: opened))
        var addressed = Draft()
        addressed.to = ["carlo@example.org"]
        XCTAssertTrue(ComposeForm.asksBeforeClosing(addressed, opened: opened))
    }

    /// The share sheet asks for a file taken off as well as for words, an
    /// address or a subject of his, and still not for the share as it
    /// began.
    func testTheShareSheetAsksForAFileTakenOff() {
        let sheet = shareSheet()
        let photo = SharedItem.file(URL(fileURLWithPath: "/staged/0/Garden.jpg"),
                                    filename: "Garden.jpg", mimeType: "image/jpeg", size: 3)
        let started = sheet.letter(from: [photo])
        XCTAssertFalse(sheet.asksBeforeCancelling(started))
        var off = started
        off.attachments = []
        XCTAssertTrue(sheet.asksBeforeCancelling(off))
    }

    // MARK: - Suggestions

    /// Picked, the list closes, and comes back only when he types again,
    /// without what is already in the field.
    func testThePickedListClosesUntilHeTypesAgain() {
        let picked = MailFormat.replacingRecipientToken(in: "", with: "owner@example.net")
        XCTAssertEqual(ComposeForm.suggestions(book, field: picked, after: .picked), [])

        // Going back into a field that holds an address offers nothing.
        XCTAssertEqual(ComposeForm.suggestions(book, field: picked, after: .entered), [])

        // He types: what matches, but never the address already there.
        XCTAssertEqual(ComposeForm.suggestions(book, field: picked + "car", after: .typed)
                           .map(\.address), ["carlo@example.org", "carla@example.com"])
        XCTAssertEqual(ComposeForm.suggestions(book, field: picked + "carlo", after: .typed)
                           .map(\.address), ["carlo@example.org"])
        // A letter typed and taken out again closes the list. Until B-073
        // it offered his most used, as an empty field did.
        XCTAssertEqual(ComposeForm.suggestions(book, field: picked, after: .typed), [])
    }

    /// A whole address typed offers nothing; an address in the field in
    /// another spelling is still the one in the field (B-069). This test
    /// also held that an empty field offered his most used as he went in,
    /// which made his own second address one tap. The owner chose Mail's
    /// way on 2026-10-06 (B-073), and that is the tests below.
    func testAWholeAddressOrOneInTheFieldIsNotOffered() {
        XCTAssertEqual(ComposeForm.suggestions(book, field: "carlo@exam", after: .typed), [])
        XCTAssertEqual(ComposeForm.suggestions(book, field: "Carlo <CARLO@example.org>, car",
                                               after: .typed).map(\.address),
                       ["carla@example.com"])
    }

    /// The share sheet's fields offer the same, from the book mirrored.
    func testTheShareSheetOffersTheSame() {
        let sheet = shareSheet(recipients: book)
        let picked = "owner@example.net, "
        XCTAssertEqual(sheet.suggestions(for: picked, after: .picked), [])
        XCTAssertEqual(sheet.suggestions(for: picked, after: .entered), [])
        let typed = sheet.suggestions(for: picked + "e", after: .typed).map(\.address)
        XCTAssertEqual(typed, ["carlo@example.org", "carla@example.com"])
        XCTAssertFalse(typed.contains("owner@example.net"))
        // Going into an empty field offers nothing (B-073). It offered his
        // most used until the owner chose Mail's way.
        XCTAssertEqual(sheet.suggestions(for: "", after: .entered), [])
    }

    // MARK: - Suggestions only as he types (B-073)

    /// Mail offers nothing as he goes into an empty field. It offered his
    /// most used until 2026-10-06, to make his own second address one tap;
    /// the owner chose Mail's way.
    func testGoingIntoAnEmptyFieldOffersNothing() {
        XCTAssertEqual(ComposeForm.suggestions(book, field: "", after: .entered), [])
        XCTAssertEqual(ComposeForm.suggestions(book, field: "  ", after: .entered), [])
    }

    /// Nor as he goes into one that holds something: a whole address, one
    /// picked with the comma after it, or a name half typed.
    func testGoingIntoAFilledFieldOffersNothing() {
        for field in ["owner@example.net", "owner@example.net, ", "c",
                      "owner@example.net, ca", "Carlo <carlo@example.org>, car"] {
            XCTAssertEqual(ComposeForm.suggestions(book, field: field, after: .entered), [], field)
        }
    }

    /// One letter typed offers what matches it, at once, as Mail's does;
    /// after a comma too, without the address already there.
    func testTypingALetterOffersWhatMatches() {
        XCTAssertEqual(ComposeForm.suggestions(book, field: "c", after: .typed).map(\.address),
                       ["carlo@example.org", "carla@example.com"])
        XCTAssertEqual(ComposeForm.suggestions(book, field: "o", after: .typed).first?.address,
                       "owner@example.net")
        XCTAssertEqual(ComposeForm.suggestions(book, field: " c ", after: .typed).map(\.address),
                       ["carlo@example.org", "carla@example.com"])
        XCTAssertEqual(ComposeForm.suggestions(book, field: "carlo@example.org, c", after: .typed)
                           .map(\.address), ["carla@example.com"])
    }

    /// Typed and taken out again, back to nothing: the list closes, in an
    /// empty field and after a comma alike.
    func testTakingWhatHeTypedBackOutClosesTheList() {
        for (typed, emptied) in [("c", ""), ("owner@example.net, c", "owner@example.net, "),
                                 ("owner@example.net, c", "owner@example.net,")] {
            XCTAssertFalse(ComposeForm.suggestions(book, field: typed, after: .typed).isEmpty, typed)
            XCTAssertEqual(ComposeForm.suggestions(book, field: emptied, after: .typed), [], emptied)
        }
    }

    /// Spaces are nothing typed, alone or after a comma, and so is a line
    /// break pasted in.
    func testATokenOfSpacesOffersNothing() {
        for field in [" ", "   ", "\t", "owner@example.net,   ", "owner@example.net, \n"] {
            XCTAssertEqual(ComposeForm.suggestions(book, field: field, after: .typed), [],
                           field.debugDescription)
        }
    }

    /// A pick offers nothing, whatever the field reads after it.
    func testAPickOffersNothing() {
        for field in ["", "c", "owner@example.net, ", "owner@example.net, c"] {
            XCTAssertEqual(ComposeForm.suggestions(book, field: field, after: .picked), [], field)
        }
    }

    /// The share sheet the same: nothing as he goes in, matches for a
    /// letter, nothing once it is taken out, nothing for spaces.
    func testTheShareSheetOffersOnlyAsHeTypes() {
        let sheet = shareSheet(recipients: book)
        XCTAssertEqual(sheet.suggestions(for: "", after: .entered), [])
        XCTAssertEqual(sheet.suggestions(for: "owner@example.net, ", after: .entered), [])
        XCTAssertEqual(sheet.suggestions(for: "c", after: .typed).map(\.address),
                       ["carlo@example.org", "carla@example.com"])
        XCTAssertEqual(sheet.suggestions(for: "", after: .typed), [])
        XCTAssertEqual(sheet.suggestions(for: "  ", after: .typed), [])
        XCTAssertEqual(sheet.suggestions(for: "c", after: .picked), [])
    }

    // MARK: - The sheets' wiring

    /// 1. The sheet ends above the keyboard, in both, and the caret is
    /// brought into view as it comes up.
    func testTheBodyEndsAboveTheKeyboard() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertTrue(code.contains(
                "scroller.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)"), file)
            XCTAssertFalse(code.contains(
                "bodyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)"), file)
            XCTAssertTrue(code.contains("let height = scroller.bounds.height defer { shownHeight = height } "
                + "guard height < shownHeight, bodyView.isFirstResponder else { return } "
                + "DispatchQueue.main.async { [weak self] in self?.keepCaretInView() }"), file)
        }
    }

    /// 1, under a tall header. The fields and the body scroll as one, the
    /// body as tall as its words and at least the rest of the sheet, and
    /// the caret is kept in sight as he types and moves it, so the fields
    /// go up out of the way, as Mail's do. With the fields fixed over a
    /// body that scrolled by itself, a Reply All's Cc and Bcc left a line
    /// and a half in landscape, and a forward's files left nothing.
    func testTheFieldsScrollAwayWithTheLetter() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            for line in ["scroller.addSubview(stack)",
                         "bodyView.isScrollEnabled = false bodyView.delegate = self "
                            + "scroller.addSubview(bodyView)",
                         "scroller.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)",
                         "stack.topAnchor.constraint(equalTo: content.topAnchor)",
                         "stack.widthAnchor.constraint(equalTo: shown.widthAnchor)",
                         "bodyView.topAnchor.constraint(equalTo: stack.bottomAnchor)",
                         "bodyView.bottomAnchor.constraint(equalTo: content.bottomAnchor)",
                         "content.heightAnchor.constraint(greaterThanOrEqualTo: shown.heightAnchor)",
                         "func textViewDidChange(_ textView: UITextView) { keepCaretInView() }",
                         "func textViewDidChangeSelection(_ textView: UITextView) { keepCaretInView() }",
                         "let line = bodyView.convert(caret, to: scroller) "
                            + ".insetBy(dx: 0, dy: -bodyView.textContainerInset.bottom) "
                            + "scroller.scrollRectToVisible(line, animated: false)",
                         "guard scrollView === scroller, !suggestionsView.isHidden, "
                            + "let field = activeAddressField else { return }"] {
                XCTAssertTrue(code.contains(line), "\(file): \(line)")
            }
            XCTAssertFalse(code.contains("view.addSubview(stack)"), file)
            XCTAssertFalse(code.contains("view.addSubview(bodyView)"), file)
            XCTAssertFalse(code.contains("stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)"),
                           file)
        }
    }

    /// 2. A pick closes the list, in both.
    func testAPickClosesTheList() async throws {
        let composer = try source(Self.composer)
        XCTAssertTrue(composer.contains("t.deselectRow(at: ip, animated: false) "
            + "refreshSuggestions(after: .picked) updateSend() letterEdited() }"))
        // The field's bubbles, a recipient each, since B-076.
        XCTAssertTrue(composer.contains("ComposeForm.suggestions(RecipientBook.shared.snapshot(), "
            + "in: field.bubbles, after: event)"))
        XCTAssertTrue(composer.contains("refreshSuggestions(after: .entered)"))
        XCTAssertTrue(composer.contains("refreshSuggestions(after: .typed)"))
        let share = try source(Self.share)
        XCTAssertTrue(share.contains("t.deselectRow(at: ip, animated: false) "
            + "offer(field, after: .picked) updateSend() }"))
        XCTAssertTrue(share.contains("sheet.suggestions(in: field.bubbles, after: event)"))
    }

    /// B-073, in both. Going into an address field asks the form as
    /// `.entered`, which offers nothing, so the share sheet putting him
    /// straight into To shows no list, and neither does a tap on To, Cc or
    /// Bcc. The list is shown in one place only, from what the form
    /// offers after one of the three events, so nothing else, the Cc/Bcc
    /// reveal among them, can show it.
    func testOnlyTypingShowsTheListInEither() async throws {
        func count(_ needle: String, in code: String) -> Int {
            code.components(separatedBy: needle).count - 1
        }
        let composer = try source(Self.composer)
        for line in ["field.addTarget(self, action: #selector(addressEditingBegan(_:)), "
                        + "for: .editingDidBegin)",
                     // A field of bubbles since B-076, not a text field.
                     "@objc private func addressEditingBegan(_ field: RecipientField) { "
                        + "activeAddressField = field refreshSuggestions(after: .entered) }"] {
            XCTAssertTrue(composer.contains(line), line)
        }
        XCTAssertEqual(count("refreshSuggestions(after: .", in: composer), 3)
        XCTAssertEqual(count("suggestions = ", in: composer), 1)
        XCTAssertTrue(composer.contains("suggestions = ComposeForm.suggestions("))

        let share = try source(Self.share)
        for line in ["field.addTarget(self, action: #selector(addressEntered(_:)), "
                        + "for: .editingDidBegin)",
                     // A field of bubbles since B-076, not a text field.
                     "@objc private func addressEntered(_ field: RecipientField) { "
                        + "offer(field, after: .entered) }",
                     "override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated) "
                        + "if draft.to.isEmpty { toField.becomeFirstResponder() } }"] {
            XCTAssertTrue(share.contains(line), line)
        }
        XCTAssertEqual(count("offer(field, after: .", in: share), 3)
        XCTAssertEqual(count("suggestions = ", in: share), 1)
        XCTAssertTrue(share.contains("suggestions = sheet.suggestions("))
        XCTAssertTrue(try source(Self.shareRules).contains(
            "func suggestions(for field: String, after event: ComposeForm.FieldEvent = .typed) "
                + "-> [KnownRecipient] { ComposeForm.suggestions(shared.recipients, "
                + "field: field, after: event) }"))

        for (file, code) in [(Self.composer, composer), (Self.share, share)] {
            let assigned = count("suggestionsView.isHidden = ", in: code)
            let closed = count("suggestionsView.isHidden = true", in: code)
            XCTAssertEqual(count("suggestionsView.isHidden = suggestions.isEmpty", in: code), 1, file)
            XCTAssertEqual(assigned, closed + 1, file)
            XCTAssertFalse(code.contains("suggestionsView.isHidden.toggle"), file)
        }
    }

    /// 3. The sheet is held: a tap outside does nothing, a swipe asks what
    /// Cancel asks, and nothing lets it go again after a send.
    func testTheSheetIsHeldAndASwipeAsksAsCancelDoes() async throws {
        let composer = try source(Self.composer)
        for line in ["updateSend() isModalInPresentation = true let centre",
                     "navigationController?.isModalInPresentation = true",
                     "navigationController?.presentationController?.delegate = self",
                     "func presentationControllerDidAttemptToDismiss(_ presentationController: "
                        + "UIPresentationController) { cancelTapped() }",
                     "guard !actions.isSending, presentedViewController == nil else { return }"] {
            XCTAssertTrue(composer.contains(line), line)
        }
        XCTAssertFalse(composer.contains("isModalInPresentation = sending"))
        let share = try source(Self.share)
        for line in ["overrideUserInterfaceStyle = .dark isModalInPresentation = true "
                        + "view.backgroundColor = Theme.canvas",
                     "presentationController?.delegate = self",
                     "if let form { form.cancelTapped() } else { cancel() }",
                     "guard !sheet.isSending, presentedViewController == nil else { return }"] {
            XCTAssertTrue(share.contains(line), line)
        }
        XCTAssertFalse(share.contains("isModalInPresentation = sending"))
    }

    /// 4. Cancel asks only about a changed letter, and closes one as it
    /// opened by `ComposeActions.closeWithoutAsking`.
    func testCancelMeasuresTheLetterAgainstHowItOpened() async throws {
        let composer = try source(Self.composer)
        XCTAssertTrue(composer.contains("opened = currentLetter()"))
        XCTAssertTrue(composer.contains("guard actions.asksAnyway "
            + "|| ComposeForm.asksBeforeClosing(letter, opened: opened) else { "
            + "actions.closeWithoutAsking { letter } return }"))
        XCTAssertFalse(composer.contains("hasContent"))
    }

    /// 5. Return in Subject goes to the top of the body, and the caret
    /// starts there, for Tab. The share sheet shows what was shared under
    /// an empty first line, the caret on it, and reads the letter back
    /// with that line gone if he left it empty.
    func testReturnInSubjectGoesToTheTopOfTheBody() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertTrue(code.contains("subjectField.delegate = self"), file)
            XCTAssertTrue(code.contains("guard textField === subjectField else { return true } "
                + "bodyView.becomeFirstResponder() "
                + "bodyView.selectedRange = NSRange(location: 0, length: 0) "
                + "keepCaretInView() return false"), file)
        }
        XCTAssertTrue(try source(Self.composer).contains("bodyView.text = draft.body"
            + " bodyView.selectedRange = NSRange(location: 0, length: 0)"))
        let share = try source(Self.share)
        XCTAssertTrue(share.contains("bodyView.text = ShareLetter.shown(draft.body)"
            + " bodyView.selectedRange = NSRange(location: 0, length: 0)"))
        XCTAssertTrue(share.contains("draft = sheet.letter(from: items) began = draft.body"))
        XCTAssertTrue(share.contains(
            "draft.body = ShareLetter.written(bodyView.text ?? \"\", began: began)"))
    }

    /// 5, in the share sheet. A link shared opens under an empty first
    /// line, where the caret is: what he types there stays on a line of
    /// its own, and the link on its own under it. It used to run into the
    /// address, "Have a lookhttps://…". Left empty, the line goes, and the
    /// letter is the share as it began, sent as Mail sends it and closed
    /// with nothing asked. Shared words the same; a photo's blank letter
    /// already has its empty line and is shown as it is.
    func testWhatHeTypesAboveASharedLinkIsALineOfItsOwn() {
        let sheet = shareSheet()
        let page = URL(string: "https://en.wikipedia.org/wiki/Mercury_(planet)")!
        let began = sheet.letter(from: [.link(page, title: "Mercury")])
        let shown = ShareLetter.shown(began.body)
        XCTAssertEqual(shown, "\n" + began.body)

        XCTAssertEqual(ShareLetter.written(shown, began: began.body), began.body, "left as it was")
        var untouched = began
        untouched.body = ShareLetter.written(shown, began: began.body)
        XCTAssertFalse(sheet.asksBeforeCancelling(untouched))

        // Typed where the caret starts, at the top.
        let typed = "Have a look" + shown
        var letter = began
        letter.body = ShareLetter.written(typed, began: began.body)
        let lines = letter.body.components(separatedBy: "\n")
        XCTAssertEqual(Array(lines.prefix(2)), ["Have a look", page.absoluteString])
        XCTAssertTrue(sheet.asksBeforeCancelling(letter))

        let words = sheet.letter(from: [.text("Three lines\nof a poem")])
        XCTAssertEqual(ShareLetter.written("Look" + ShareLetter.shown(words.body), began: words.body)
                           .components(separatedBy: "\n").prefix(2),
                       ["Look", "Three lines"])

        let photo = sheet.letter(from: [.file(URL(fileURLWithPath: "/staged/0/Garden.jpg"),
                                              filename: "Garden.jpg", mimeType: "image/jpeg",
                                              size: 3)])
        XCTAssertEqual(ShareLetter.shown(photo.body), photo.body)
        XCTAssertEqual(ShareLetter.written(photo.body, began: photo.body), photo.body)
    }

    /// 6. and 7. Send follows the address fields, the title the subject.
    func testSendAndTheTitleFollowTheFields() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            // Read a bubble at a time since B-076.
            XCTAssertTrue(code.contains("sendItem.isEnabled = ComposeForm.canSend("
                + "to: toField.recipients, cc: ccField.recipients, bcc: bccField.recipients)"),
                file)
            XCTAssertTrue(code.contains("subjectField.addTarget(self, action: "
                + "#selector(subjectChanged), for: .editingChanged)"), file)
            XCTAssertTrue(code.contains("title = ComposeForm.title(subject: subjectField.text ?? \"\")"),
                          file)
            XCTAssertTrue(code.contains("setTitleTextAttributes([.font: Theme.fontBarButton], "
                + "for: .disabled)"), file)
        }
        XCTAssertTrue(try source(Self.composer).contains("refreshSuggestions(after: .typed) updateSend()"))
        XCTAssertTrue(try source(Self.share).contains("offer(field, after: .typed) updateSend()"))
    }

    /// 8. Black and white, and the share sheet's question dark.
    func testTheBodyIsBlackAndTheQuestionDark() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertTrue(code.contains("bodyView.backgroundColor = Theme.canvas"), file)
            XCTAssertTrue(code.contains("bodyView.textColor = Theme.primaryText"), file)
        }
        let share = try source(Self.share)
        XCTAssertTrue(share.contains("confirm.overrideUserInterfaceStyle = .dark"))
        XCTAssertTrue(share.contains("view.window?.overrideUserInterfaceStyle = .dark"))
    }

    /// 9. The fields and the body are named for VoiceOver.
    func testTheFieldsAreNamed() async throws {
        for file in [Self.composer, Self.share] {
            let code = try source(file)
            XCTAssertTrue(code.contains("field.accessibilityLabel = "
                + "text.trimmingCharacters(in: CharacterSet(charactersIn: \":\"))"), file)
            XCTAssertTrue(code.contains("bodyView.accessibilityLabel = \"Message\""), file)
        }
        XCTAssertEqual("Subject:".trimmingCharacters(in: CharacterSet(charactersIn: ":")), "Subject")
    }

    /// 10. The paperclip keeps the size of the words beside it.
    func testThePaperclipHasAFixedSize() async throws {
        XCTAssertTrue(try source(Self.composer).contains(
            "config.preferredSymbolConfigurationForImage = "
                + "UIImage.SymbolConfiguration(font: Theme.fontDetailMeta)"))
    }

    // MARK: - Helpers

    private static let composer = "UI/ComposeViewController.swift"
    private static let share = "Share/ShareViewController.swift"
    private static let shareRules = "Share/ShareSheet.swift"

    private func shareSheet(recipients: [KnownRecipient] = []) -> ShareSheet {
        let account = MailAccount(address: "owner@example.com", username: "owner@example.com",
                                  displayName: "Sam", signature: "Sam", signatureHTML: "")
        return ShareSheet(
            shared: ShareMirror.Shared(account: account, password: "app-password",
                                       signatureImages: [], recipients: recipients),
            transport: { _, _ in ScriptedSubmission() },
            noteSent: { _ in }, finish: {}, cancel: {}, showError: { _ in }, draw: { _ in },
            background: BackgroundTime(begin: { _, _ in nil }, end: { _ in }))
    }

    /// The file's code with its comment lines dropped and its spacing
    /// made single, so a line is found however it is wrapped.
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
}
