import Foundation

struct Mailbox: Identifiable, Hashable {
    let id: String
    var name: String
    var unreadCount: Int
    var role: Role?

    enum Role: String, Codable {
        case inbox, sent, drafts, trash, archive, junk
    }
}

struct MessageSummary: Identifiable, Hashable {
    let id: String
    let mailboxID: String
    var sender: String
    var subject: String
    var preview: String
    var date: Date
    var isRead: Bool
    var isFlagged: Bool
}

struct Message: Identifiable {
    let id: String
    let mailboxID: String
    let sender: String
    let to: [String]
    let cc: [String]
    let subject: String
    let date: Date
    let textBody: String?
    let htmlBody: String?
    let attachments: [Attachment]
}

struct Attachment: Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int64?
}

struct Draft {
    var to: [String] = []
    var cc: [String] = []
    var bcc: [String] = []
    var subject: String = ""
    var body: String = ""
}
