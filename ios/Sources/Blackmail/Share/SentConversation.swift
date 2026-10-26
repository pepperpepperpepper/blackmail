import Foundation

/// Who a letter that went was written to, as iOS is told it for the people
/// at the top of the share sheet (B-163).
///
/// Mail's: with Siri's Show When Sharing on, as it is from the factory, the
/// share sheet opens with a row of the people he sends to most, each with
/// the badge of the app he sends to them with, and a tap on one opens that
/// app's share sheet with them already in To. An app is in that row by
/// telling iOS of each message that goes, as an `INSendMessageIntent`, and
/// by its share extension saying it takes one (`IntentsSupported` in
/// ShareInfo.plist). Apple's "Supporting suggestions in your app's share
/// extension". Blackmail told iOS nothing, so a share through it always
/// began with the Blackmail icon and an empty To.
///
/// Told after each letter the server has taken, from the app's composer and
/// its Outbox (`IMAPMailRepository.send`) and from the share sheet
/// (`ShareSheet`), as the book counts only letters that went
/// (`RecipientBook.used`); never for one that did not go.
///
/// The people are To and Cc. Bcc is left out: the circle fills To, and a
/// person sent a blind copy put in To on the next share would be shown to
/// everyone it goes to. His own addresses are left out too
/// (`OwnAddresses`), and a letter to nobody else tells iOS nothing: iOS
/// does not show a man himself in that row, by the reports of people who
/// send themselves links in Messages and in Mail and never see their own
/// circle there.
struct SentConversation: Equatable {

    /// Each person once, in the letter's order, To then Cc: the address as
    /// it went, and the name it was given, if any.
    let people: [MailFormat.Recipient]

    /// What tells one conversation from another: the people's addresses,
    /// bare, in lower case, in order and joined by ",". The same people in
    /// another order, or spelt in another case, are the same circle.
    var identifier: String {
        people.map { $0.address.lowercased() }.sorted().joined(separator: ",")
    }

    /// The name under the circle: a person's name, or the address where
    /// the letter gave none; for several, theirs one after the other,
    /// with ", " between.
    var name: String {
        people.map { $0.name ?? $0.address }.joined(separator: ", ")
    }

    /// The conversation `draft` was, or nil when it names nobody but him
    /// (`mine`) in To and Cc. An entry that is not an address, an empty
    /// group among them, names nobody.
    static func of(_ draft: Draft, mine: OwnAddresses) -> SentConversation? {
        var seen = Set<String>()
        var people: [MailFormat.Recipient] = []
        for entry in (draft.to + draft.cc).flatMap(MailFormat.addresses(in:))
        where !MailFormat.isEmptyGroup(entry) {
            guard let person = MailFormat.recipient(in: entry),
                  let key = OwnAddresses.key(person.address),
                  !mine.contains(person.address),
                  seen.insert(key).inserted else { continue }
            people.append(MailFormat.Recipient(name: person.name,
                                               address: MailFormat.bareAddress(person.address)))
        }
        return people.isEmpty ? nil : SentConversation(people: people)
    }

    /// To, for a share opened from one of the circles: the people iOS
    /// handed back with it, each as the field keeps an entry
    /// (`MailFormat.recipientEntry`), or, when it handed back none, the
    /// addresses in `identifier`. Empty for anything else, and To starts
    /// empty, as before.
    static func to(people: [MailFormat.Recipient], identifier: String?) -> [String] {
        var seen = Set<String>()
        let named = people.compactMap { person -> String? in
            guard let key = OwnAddresses.key(person.address), seen.insert(key).inserted else { return nil }
            return MailFormat.recipientEntry(name: person.name, address: MailFormat.bareAddress(person.address))
        }
        if !named.isEmpty { return named }
        return (identifier ?? "").split(separator: ",").compactMap { piece -> String? in
            let address = String(piece).trimmingCharacters(in: .whitespaces)
            guard let key = OwnAddresses.key(address), seen.insert(key).inserted else { return nil }
            return address
        }
    }
}

#if canImport(Intents)

import Intents

extension SentConversation {

    /// Tells iOS of a letter that went, as the people it went to: what puts
    /// their circle, with Blackmail's badge, at the top of the share sheet.
    /// The share sheet's own (`ShareViewController`).
    ///
    /// Apple's way: the outgoing interaction with a name for the circle and
    /// an identifier for the conversation, each person by address with no
    /// picture, since the app does not read Contacts (B-017), and no
    /// sender, which an outgoing one leaves to iOS. Filed under the
    /// identifier, so a conversation's can be taken back
    /// (`INInteraction.delete(with:)`). The log says it was told, or the
    /// error's number, and how many people: no address.
    static func donate(_ conversation: SentConversation) {
        let recipients = conversation.people.map { person in
            INPerson(personHandle: INPersonHandle(value: person.address, type: .emailAddress),
                     nameComponents: nil, displayName: person.name ?? person.address,
                     image: nil, contactIdentifier: nil, customIdentifier: person.address)
        }
        let intent = INSendMessageIntent(
            recipients: recipients, outgoingMessageType: .outgoingMessageText, content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: conversation.name),
            conversationIdentifier: conversation.identifier, serviceName: "Blackmail",
            sender: nil, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.groupIdentifier = conversation.identifier
        let count = recipients.count
        interaction.donate { error in
            Diagnostics.log(.note, "SHARE-SUGGESTION people=\(count) "
                + (error.map { "error=\(($0 as NSError).code)" } ?? "donated"))
        }
    }

    /// The app's: told only by a build that carries the share extension
    /// (`ShareMirror.app`), the one thing a tap on a circle can open. A
    /// build without it tells iOS nothing, as before.
    static let fromTheApp: @Sendable (SentConversation) -> Void = { conversation in
        guard ShareMirror.app != nil else { return }
        donate(conversation)
    }

    /// Everything told, taken back: the account has been taken out of the
    /// app, and its people are no longer his to share with through it.
    static func forgetAll() {
        INInteraction.deleteAll { error in
            if let error {
                Diagnostics.log(.note, "SHARE-SUGGESTION forget error=\((error as NSError).code)")
            }
        }
    }
}

#else

extension SentConversation {

    /// Nothing to tell on a host without Intents.
    static let fromTheApp: @Sendable (SentConversation) -> Void = { _ in }

    static func forgetAll() {}
}

#endif
