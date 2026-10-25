import XCTest
@testable import Blackmail

/// To, Cc and Bcc as Mail's when he types with a bubble picked out or its
/// menu up, and Cc and Bcc opened and folded as Mail's are (B-134).
///
/// With a bubble's menu up and letters typed, the list of suggestions
/// opened under the menu, only its lowest row in sight, and the bubble
/// stayed. Mail's field has the recipient it picks out as its selection:
/// what he types takes its place, and a backspace takes it off. Here the
/// letters take the bubble's place, its menu goes with it, and the list
/// comes up for the letters with nothing over it; a tap on a bubble closes
/// the list and takes the caret into its field; while a bubble is picked
/// out nothing is offered; and a tap on the line puts back a bubble a
/// backspace picked out, as a tap moving Mail's caret ends its selection.
/// "Cc/Bcc" opens Cc and Bcc and goes while they show; they fold back as
/// the caret leaves them with nobody in them. The share sheet keeps its
/// colours under a menu, as the app's composer does.
///
/// The rules are `RecipientBubbles` and `ComposeForm`, run here; the field
/// and the two sheets are UIKit and never build on this host, so their
/// wiring is read from their source.
final class BubbleMenuTypingTests: XCTestCase {

    private let sam = "Sam Example <sam@example.org>"
    private let jo = "jo@example.com"

    // MARK: - Typing over a bubble picked out

    /// A letter typed with a bubble picked out, by a tap or a backspace,
    /// takes its place, as typing over Mail's selected recipient does: the
    /// bubble goes and the letter is on the line. Typing with nothing
    /// picked out never takes a bubble.
    func testALetterTypedOverAPickedOutBubbleTakesItsPlace() {
        // Tapped, its menu up.
        var field = RecipientBubbles(entries: [jo, sam])
        field.select(1)
        XCTAssertTrue(field.typingTakesThePicked("s"))
        field.type("s")
        XCTAssertEqual(field.entries, [jo])
        XCTAssertEqual(field.typed, "s")
        XCTAssertNil(field.selected)
        XCTAssertEqual(field.recipients, [jo, "s"])

        // Picked out by a backspace.
        var backed = RecipientBubbles(entries: [jo, sam])
        backed.backspace()
        XCTAssertEqual(backed.selected, 1)
        backed.type("j")
        XCTAssertEqual(backed.entries, [jo])
        XCTAssertEqual(backed.typed, "j")

        // The first of several, picked out by a tap: the others stay, in
        // their order.
        var first = RecipientBubbles(entries: [sam, jo, "pat@example.com"])
        first.select(0)
        first.type("p")
        XCTAssertEqual(first.entries, [jo, "pat@example.com"])

        // Nothing picked out: the letters go after the bubbles, every
        // bubble stays.
        var plain = RecipientBubbles(entries: [jo, sam])
        XCTAssertFalse(plain.typingTakesThePicked("s"))
        plain.type("s")
        XCTAssertEqual(plain.entries, [jo, sam])
        XCTAssertEqual(plain.typed, "s")

        // Letters already on the line when the bubble was tapped: the next
        // one typed takes the bubble's place and the line keeps them all.
        var half = RecipientBubbles(entries: [jo, sam])
        half.type("sa")
        half.select(0)
        XCTAssertTrue(half.typingTakesThePicked("sab"))
        half.type("sab")
        XCTAssertEqual(half.entries, [sam])
        XCTAssertEqual(half.typed, "sab")

        // Typed in the middle of the line, or a word pasted over it: the
        // same, whatever the line read before.
        var middle = RecipientBubbles(entries: [jo, sam])
        middle.type("sa")
        middle.select(1)
        XCTAssertTrue(middle.typingTakesThePicked("sxa"))
        var pasted = RecipientBubbles(entries: [jo, sam])
        pasted.select(0)
        XCTAssertTrue(pasted.typingTakesThePicked("carlo@example.org"))
        pasted.type("carlo@example.org")
        XCTAssertEqual(pasted.entries, [sam])
        XCTAssertEqual(pasted.typed, "carlo@example.org")
    }

    /// What does not take the bubble's place: a comma or a ";", which end
    /// what he typed, as in Mail, where they leave the selected recipient,
    /// at the end of the line or in its middle; a space with nothing but
    /// spaces before it, which the line drops; and a letter taken out.
    func testACommaASpaceOrALetterTakenOutLeavesThePickedOutBubble() {
        for ender in [",", ";", " ", ", ", "  ;"] {
            var field = RecipientBubbles(entries: [jo, sam])
            field.select(1)
            XCTAssertFalse(field.typingTakesThePicked(ender), ender.debugDescription)
            field.type(ender)
            XCTAssertEqual(field.entries, [jo, sam], ender.debugDescription)
        }
        // "sa" and a comma under the menu: "sa" a bubble after the others,
        // the one picked out still there.
        var ended = RecipientBubbles(entries: [jo, sam])
        ended.type("sa")
        ended.select(0)
        XCTAssertFalse(ended.typingTakesThePicked("sa,"))
        ended.type("sa,")
        XCTAssertEqual(ended.entries, [jo, sam, "sa"])
        // A comma typed in the middle of the line, and a space at its
        // start, which the line drops: the bubble stays, as at the end.
        var middle = RecipientBubbles(entries: [jo, sam])
        middle.type("sa")
        middle.select(0)
        XCTAssertFalse(middle.typingTakesThePicked("s,a"))
        middle.type("s,a")
        XCTAssertEqual(middle.entries, [jo, sam, "s"])
        XCTAssertEqual(middle.typed, "a")
        var leading = RecipientBubbles(entries: [jo, sam])
        leading.type("sa")
        leading.select(0)
        XCTAssertFalse(leading.typingTakesThePicked(" sa"))
        XCTAssertFalse(leading.typingTakesThePicked("  sa"))
        leading.type(" sa")
        XCTAssertEqual(leading.entries, [jo, sam])
        XCTAssertEqual(leading.typed, "sa")
        // A letter taken out.
        var shorter = RecipientBubbles(entries: [jo, sam])
        shorter.type("sa")
        shorter.select(1)
        XCTAssertFalse(shorter.typingTakesThePicked("s"))
        shorter.type("s")
        XCTAssertEqual(shorter.entries, [jo, sam])
        // The line as it was.
        var same = RecipientBubbles(entries: [jo, sam])
        same.type("sa")
        same.select(1)
        XCTAssertFalse(same.typingTakesThePicked("sa"))
    }

    /// A space typed after letters takes the bubble's place, as Mail's
    /// field lets any text but Return, Tab and a comma replace its picked
    /// recipient, and the list for the letters is in sight. It left the
    /// bubble, its menu was put up again, and the list for "sa" opened
    /// under it.
    func testASpaceAfterLettersTakesThePickedOutBubbleAndTheListIsInSight() {
        let book = [KnownRecipient(address: "sam@example.org", name: "Sam Example", uses: 3,
                                   lastSeen: Date(timeIntervalSince1970: 0))]
        var field = RecipientBubbles(entries: [jo])
        field.type("sa")
        field.select(0)
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .bubbleTapped), [])
        XCTAssertTrue(field.typingTakesThePicked("sa "))
        field.type("sa ")
        XCTAssertEqual(field.entries, [])
        XCTAssertNil(field.selected)
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).map(\.address),
                       ["sam@example.org"])
        // In the middle of the line, between letters, the same.
        var between = RecipientBubbles(entries: [jo])
        between.type("sa")
        between.select(0)
        XCTAssertTrue(between.typingTakesThePicked("s a"))
    }

    /// While a bubble is picked out, as it is while its menu is up, the
    /// list offers nothing, whatever the line holds: it would open under
    /// the menu. The field keeps the bubble picked out under its menu
    /// through a comma (`keepMenu`), and the letters after the comma are
    /// still on the line.
    func testNothingIsOfferedWhileABubbleIsPickedOut() {
        let book = [KnownRecipient(address: "sam@example.org", name: "Sam Example", uses: 3,
                                   lastSeen: Date(timeIntervalSince1970: 0)),
                    KnownRecipient(address: "al@example.net", name: "Al", uses: 1,
                                   lastSeen: Date(timeIntervalSince1970: 0))]
        var field = RecipientBubbles(entries: [jo])
        field.type("sa")
        field.select(0)
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed), [])
        // "s,a" under the menu: "s" a bubble, "a" on the line, the bubble
        // kept picked out by the field.
        field.type("s,a")
        field.select(0)
        XCTAssertEqual(field.typed, "a")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed), [])
        // Put back: the list for "a".
        field.select(nil)
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).map(\.address),
                       ["al@example.net", "sam@example.org"])
    }

    /// The person whose bubble the letters took is offered again under
    /// them, as anyone not in the field is, and the list is for what he
    /// typed: the list that opened under the menu is now the list for the
    /// letters, with no bubble or menu left over it.
    func testThePersonTypedOverIsOfferedAgain() {
        let book = [KnownRecipient(address: "sam@example.org", name: "Sam Example", uses: 3,
                                   lastSeen: Date(timeIntervalSince1970: 0)),
                    KnownRecipient(address: "jo@example.com", name: nil, uses: 2,
                                   lastSeen: Date(timeIntervalSince1970: 0))]
        var field = RecipientBubbles(entries: [jo, sam])
        field.select(1)
        field.type("sa")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).map(\.address),
                       ["sam@example.org"])
        // A bubble left in the field is still not offered.
        field.type("j")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed), [])
    }

    // MARK: - A backspace over a bubble picked out

    /// A backspace with a bubble picked out is the bubbles', letters on
    /// the line or not, and takes that bubble off; with nothing picked out
    /// it is the line's while letters are on it.
    func testABackspaceTakesThePickedOutBubbleWithLettersOnTheLine() {
        var field = RecipientBubbles(entries: [jo, sam])
        field.type("sa")
        XCTAssertFalse(field.backspaceIsTheBubbles(lineEmpty: false), "a letter off the line")
        field.select(0)
        XCTAssertTrue(field.backspaceIsTheBubbles(lineEmpty: false))
        XCTAssertTrue(field.backspace())
        XCTAssertEqual(field.entries, [sam])
        XCTAssertEqual(field.typed, "sa", "the letters stay")
        XCTAssertNil(field.selected)

        var empty = RecipientBubbles(entries: [jo])
        XCTAssertTrue(empty.backspaceIsTheBubbles(lineEmpty: true), "picks out the last")
        var none = RecipientBubbles()
        XCTAssertTrue(none.backspaceIsTheBubbles(lineEmpty: true))
        XCTAssertFalse(none.backspace(), "nothing to pick out or take off")
        none.select(3)
        XCTAssertFalse(none.backspaceIsTheBubbles(lineEmpty: false))
        empty.select(9)
        XCTAssertFalse(empty.backspaceIsTheBubbles(lineEmpty: false))
    }

    /// A tap on the line, or beside the bubbles, with no menu up puts back
    /// the bubble a backspace picked out, as a tap moving Mail's caret
    /// ends its selection: the next letter goes after the bubbles, and
    /// every bubble stays. It stayed picked out, and the next letter took
    /// it off. The next backspace picks out the last bubble again.
    func testATapOnTheLinePutsBackTheBubbleABackspacePickedOut() {
        var field = RecipientBubbles(entries: [jo, sam])
        field.backspace()
        XCTAssertEqual(field.selected, 1)
        XCTAssertTrue(field.lineTapped())
        XCTAssertNil(field.selected)
        XCTAssertFalse(field.typingTakesThePicked("c"))
        field.type("c")
        XCTAssertEqual(field.entries, [jo, sam])
        XCTAssertEqual(field.typed, "c")
        // Nothing picked out: nothing to put back.
        var plain = RecipientBubbles(entries: [jo])
        XCTAssertFalse(plain.lineTapped())
        // Two backspaces after the tap still pick out, then take off.
        var again = RecipientBubbles(entries: [jo, sam])
        again.backspace()
        XCTAssertTrue(again.lineTapped())
        again.backspace()
        XCTAssertEqual(again.selected, 1)
        again.backspace()
        XCTAssertEqual(again.entries, [jo])
    }

    // MARK: - The list and the menu

    /// A tap on a bubble offers nothing, whatever is on the line: the list
    /// closes as the menu goes up, so it is never under it.
    func testATappedBubbleClosesTheList() {
        let book = [KnownRecipient(address: "janet@example.org", name: "Janet", uses: 1,
                                   lastSeen: Date(timeIntervalSince1970: 0))]
        var field = RecipientBubbles(entries: [sam])
        field.type("ja")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).count, 1)
        field.select(0)
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .bubbleTapped), [])
        // A letter typed then takes the bubble's place and offers again.
        field.type("jan")
        XCTAssertEqual(ComposeForm.suggestions(book, in: field, after: .typed).map(\.address),
                       ["janet@example.org"])
        XCTAssertEqual(field.entries, [])
    }

    // MARK: - Cc and Bcc

    /// Mail's rule as the caret goes into a field: open while it is in Cc
    /// or Bcc or Cc holds someone, folded back otherwise. Spaces are
    /// nobody. Anyone in Bcc keeps them open too, on purpose: Mail counts
    /// a Bcc only once it differs from the one the letter opened with
    /// (`bccAddressesDirtied`), and folds an unchanged one out of sight;
    /// here a Bcc he cannot see is never left.
    func testCcAndBccStandOpenByMailsRule() {
        XCTAssertTrue(ComposeForm.showsCcAndBcc(inCcOrBcc: true, cc: [], bcc: []))
        XCTAssertTrue(ComposeForm.showsCcAndBcc(inCcOrBcc: false, cc: [jo], bcc: []))
        XCTAssertTrue(ComposeForm.showsCcAndBcc(inCcOrBcc: false, cc: [], bcc: [sam]))
        XCTAssertTrue(ComposeForm.showsCcAndBcc(inCcOrBcc: true, cc: [jo], bcc: [sam]))
        XCTAssertFalse(ComposeForm.showsCcAndBcc(inCcOrBcc: false, cc: [], bcc: []))
        XCTAssertFalse(ComposeForm.showsCcAndBcc(inCcOrBcc: false, cc: [" "], bcc: ["", "\n"]))
        // A letter that opens with someone in Cc or Bcc opens them, as
        // before, and they stand open by the rule wherever the caret goes.
        var draft = Draft()
        draft.bcc = [sam]
        XCTAssertTrue(draft.showsCcAndBcc)
        XCTAssertTrue(ComposeForm.showsCcAndBcc(inCcOrBcc: false, cc: draft.cc, bcc: draft.bcc))
    }

    // MARK: - The field, read from the source

    /// Letters typed over the bubble picked out close its menu before the
    /// field takes them; a backspace asks the field first, which takes it
    /// for a bubble picked out with letters on the line; a tap on a bubble
    /// tells the sheet before its menu goes up.
    func testTheFieldTypesOverThePickedOutBubble() throws {
        let code = try source("UI/RecipientField.swift")
        for line in ["let had = bubbles let now = input.text ?? \"\" "
                        + "if bubbles.typingTakesThePicked(now) { closeMenu() } bubbles.type(now) keepMenu()",
                     "private func closeMenu() { menuFor = nil menuEntry = nil "
                        + "if let menu, menu.presentingViewController != nil { menu.dismiss(animated: true) } }",
                     "override func deleteBackward() { if markedTextRange == nil, "
                        + "let backspaceToBubbles, backspaceToBubbles() { return } super.deleteBackward() }",
                     "input.backspaceToBubbles = { [weak self] in self?.backspace() ?? false }",
                     "private func backspace() -> Bool { guard bubbles.backspaceIsTheBubbles(lineEmpty: "
                        + "(input.text ?? \"\").isEmpty) else { return false }",
                     "bubbles.select(index) rebuild() sendActions(for: .valueChanged)"] {
            XCTAssertTrue(code.contains(line), line)
        }
        XCTAssertFalse(code.contains("backspaceWhenEmpty"), "a backspace with letters on the line asks too")
        // A tap on the line, or beside the bubbles, with no menu up puts
        // back the bubble a backspace picked out, seen beside the line's
        // own taps.
        for line in ["let tap = UITapGestureRecognizer(target: self, action: #selector(lineTapped)) "
                        + "tap.cancelsTouchesInView = false tap.delaysTouchesEnded = false "
                        + "tap.delegate = self input.addGestureRecognizer(tap)",
                     "@objc private func tappedBeside() { lineTapped() input.becomeFirstResponder() }",
                     "@objc private func lineTapped() { guard menuFor == nil, bubbles.lineTapped() "
                        + "else { return } rebuild() }",
                     "func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, "
                        + "shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }",
                     "final class RecipientField: UIControl, UITextFieldDelegate, UIGestureRecognizerDelegate {"] {
            XCTAssertTrue(code.contains(line), line)
        }
        // The sheet is told before the menu goes up.
        let told = try XCTUnwrap(code.range(of: "sendActions(for: .valueChanged)"))
        let shown = try XCTUnwrap(code.range(of: "owner.present(menu, animated: true)"))
        XCTAssertLessThan(told.lowerBound, shown.lowerBound)
    }

    // MARK: - The sheets, read from the source

    /// Both sheets: a bubble tapped closes the list and takes the caret
    /// into its field while a field has it; "Cc/Bcc" opens Cc and Bcc with
    /// the caret in Cc, and the row goes while they show; the caret going
    /// into any field asks Mail's rule, into Cc or Bcc as such.
    func testBothSheetsCloseTheListAndOpenAndFoldCcAndBcc() throws {
        for (file, entered, offer) in [
            (Self.composer, "@objc private func addressEditingBegan(_ field: RecipientField) { "
                + "activeAddressField = field refreshSuggestions(after: .entered) "
                + "caretWentInto(ccOrBcc: field === ccField || field === bccField) }",
             "activeAddressField = field refreshSuggestions(after: .bubbleTapped) }"),
            (Self.share, "@objc private func addressEntered(_ field: RecipientField) { "
                + "offer(field, after: .entered) "
                + "caretWentInto(ccOrBcc: field === ccField || field === bccField) }",
             "offer(field, after: .bubbleTapped) }"),
        ] {
            let code = try source(file)
            for line in [entered,
                         "field.addTarget(self, action: #selector(addressBubbleTapped(_:)), for: .valueChanged)",
                         "@objc private func addressBubbleTapped(_ field: RecipientField) { "
                            + "let fields: [UIView] = [toField, ccField, bccField, subjectField, bodyView] "
                            + "if !field.isFirstResponder, fields.contains(where: { $0.isFirstResponder }) { "
                            + "field.becomeFirstResponder() } " + offer,
                         "ccToggle.addTarget(self, action: #selector(openCcAndBcc), for: .touchUpInside)",
                         "@objc private func openCcAndBcc() { showCcAndBcc(true) ccField.becomeFirstResponder() }",
                         "showCcAndBcc(ComposeForm.showsCcAndBcc(inCcOrBcc: ccOrBcc, cc: ccField.recipients, "
                            + "bcc: bccField.recipients))",
                         "ccRow.isHidden = !open bccRow.isHidden = !open ccToggleRow.isHidden = open }",
                         "let toggleRow = ccToggleRow",
                         "func textViewDidBeginEditing(_ textView: UITextView) { caretWentInto(ccOrBcc: false) }",
                         "func textFieldDidBeginEditing(_ textField: UITextField) { caretWentInto(ccOrBcc: false) }"] {
                XCTAssertTrue(code.contains(line), "\(file): \(line)")
            }
            XCTAssertFalse(code.contains("toggleCc"), file)
            XCTAssertFalse(code.contains("isHidden.toggle()"), file)
            XCTAssertFalse(code.contains("ccVisible.toggle()"), file)
            XCTAssertEqual(count("caretWentInto(ccOrBcc:", in: code), 4, file)
        }
        // The whole of each sheet's showCcAndBcc: the share sheet's guard
        // the right way round, and the composer's open state kept.
        XCTAssertTrue(try source(Self.composer).contains("private func showCcAndBcc(_ open: Bool) { "
            + "guard open != ccVisible else { return } ccVisible = open ccRow.isHidden = !open "
            + "bccRow.isHidden = !open ccToggleRow.isHidden = open }"))
        XCTAssertTrue(try source(Self.share).contains("private func showCcAndBcc(_ open: Bool) { "
            + "guard open == ccRow.isHidden else { return } ccRow.isHidden = !open "
            + "bccRow.isHidden = !open ccToggleRow.isHidden = open }"))
        XCTAssertTrue(try source(Self.composer).contains("stack.addArrangedSubview(toggleRow) "
            + "toggleRow.isHidden = ccVisible"))
        XCTAssertTrue(try source(Self.share).contains("let toggleRow = ccToggleRow "
            + "toggleRow.isHidden = draft.showsCcAndBcc"))
    }

    /// The share sheet keeps Cancel, Send and the rest in their colours
    /// while a menu is up, as the app's composer does; UIKit greyed them
    /// there, the sheet being the root of the extension's window. The
    /// app's composer sets nothing: UIKit leaves a sheet's colours.
    func testTheShareSheetKeepsItsColoursUnderAMenu() throws {
        let share = try source(Self.share)
        XCTAssertTrue(share.contains("styleBar(nav.navigationBar) nav.view.tintAdjustmentMode = .normal "
            + "nav.navigationBar.tintAdjustmentMode = .normal addChild(nav)"))
        XCTAssertFalse(share.contains(".dimmed"))
        let composer = try source(Self.composer)
        XCTAssertFalse(composer.contains("tintAdjustmentMode"))
    }

    // MARK: - Helpers

    private static let composer = "UI/ComposeViewController.swift"
    private static let share = "Share/ShareViewController.swift"

    private func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

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
