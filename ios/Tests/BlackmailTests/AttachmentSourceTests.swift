import XCTest
@testable import Blackmail

/// Tests for an attachment knowing where its bytes come from.
///
/// Until photos could be attached there was only one answer — a part of a
/// message already on the server — and the struct said so in its field
/// names. Adding a second answer meant changing a type that forwarding
/// already depended on, so most of what is pinned here is that forwarding
/// did not quietly break on the way past.
final class AttachmentSourceTests: XCTestCase {

    private func message(with attachments: [Attachment]) -> Message {
        Message(id: "1/9", mailboxID: "INBOX",
                sender: "Jane <jane@example.com>", senderAddress: "jane@example.com",
                to: ["carlo@example.org"], cc: [], subject: "the receipt",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                textBody: "here it is", htmlBody: nil, attachments: attachments)
    }

    private func attachment(_ id: String, _ name: String, size: Int64 = 1024) -> Attachment {
        Attachment(id: id, filename: name, mimeType: "application/pdf", size: size)
    }

    // MARK: - Forwarding still names parts rather than copying them

    func testAForwardCarriesItsFilesAsPartsOfTheORIGINALMessage() {
        // Named, not copied: nothing is downloaded until the letter is
        // actually built, which is what keeps forwarding a large receipt
        // from stalling the composer.
        let m = message(with: [attachment("2", "invoice.pdf")])
        let draft = Draft.forwarding(m)

        XCTAssertEqual(draft.attachments.count, 1)
        guard case let .messagePart(messageID, mailboxID, section, _) =
                draft.attachments[0].source else {
            return XCTFail("a forward must reference the original message")
        }
        XCTAssertEqual(messageID, "1/9")
        XCTAssertEqual(mailboxID, "INBOX")
        XCTAssertEqual(section, "2")
    }

    func testAForwardKeepsEveryFileAndItsNameAndWeight() {
        let m = message(with: [attachment("2", "invoice.pdf", size: 4096),
                               attachment("3", "receipt.pdf", size: 8192)])
        let draft = Draft.forwarding(m)
        XCTAssertEqual(draft.attachments.map(\.filename), ["invoice.pdf", "receipt.pdf"])
        XCTAssertEqual(draft.attachments.compactMap(\.size), [4096, 8192])
    }

    func testAMessageWithNoFilesForwardsWithNone() {
        XCTAssertTrue(Draft.forwarding(message(with: [])).attachments.isEmpty)
    }

    // MARK: - A photo is a file on this device

    func testALocalFileAttachmentKeepsItsURL() {
        let url = URL(fileURLWithPath: "/tmp/Photo.jpg")
        let a = DraftAttachment(source: .localFile(url), filename: "Photo.jpg",
                                mimeType: "image/jpeg", size: 2_000_000)
        guard case let .localFile(stored) = a.source else {
            return XCTFail("expected a local file")
        }
        XCTAssertEqual(stored, url)
        XCTAssertEqual(a.mimeType, "image/jpeg")
    }

    func testTheTwoKindsCanTravelInTheSameLetter() {
        // Forwarding a receipt AND adding a photograph to it is an
        // ordinary thing to want, and the builder sees one flat list.
        var draft = Draft.forwarding(message(with: [attachment("2", "invoice.pdf")]))
        draft.attachments.append(
            DraftAttachment(source: .localFile(URL(fileURLWithPath: "/tmp/P.jpg")),
                            filename: "P.jpg", mimeType: "image/jpeg", size: 100))
        XCTAssertEqual(draft.attachments.count, 2)

        var parts = 0, files = 0
        for a in draft.attachments {
            switch a.source {
            case .messagePart: parts += 1
            case .localFile: files += 1
            }
        }
        XCTAssertEqual(parts, 1)
        XCTAssertEqual(files, 1)
    }

    // MARK: - Removing one

    func testRemovingAnAttachmentLeavesTheOthersInOrder() {
        // Attaching without removing turns one mis-tap in a photo library
        // into a letter he cannot send without starting over.
        var draft = Draft(to: ["a@b.com"], subject: "x")
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            draft.attachments.append(
                DraftAttachment(source: .localFile(URL(fileURLWithPath: "/tmp/" + name)),
                                filename: name, mimeType: "image/jpeg", size: 1))
        }
        draft.attachments.remove(at: 1)
        XCTAssertEqual(draft.attachments.map(\.filename), ["a.jpg", "c.jpg"])
    }

    // MARK: - What reaches the wire

    func testAttachedFilesAreNamedInTheBuiltMessage() {
        let account = MailAccount(address: "carlo@example.org",
                                  username: "carlo@example.org", displayName: "Carlo")
        let draft = Draft(to: ["a@b.com"], subject: "photos", body: "here")
        let raw = RFC5322Builder.build(
            draft: draft, from: account,
            attachments: [(filename: "Photo.jpg", mimeType: "image/jpeg",
                           data: Data(repeating: 0xFF, count: 64))])
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.contains("Photo.jpg"), "the recipient must see a filename")
        XCTAssertTrue(text.lowercased().contains("image/jpeg"), text.prefix(400).description)
    }
}
