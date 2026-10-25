import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A YouTube video's title, asked of YouTube, for the subject of a share
/// that came with the link alone (B-126).
///
/// Mail's subject for a share from the YouTube app is the video's title,
/// which the YouTube app hands to Mail and never to a share extension
/// (B-125). The owner's ruling of 2026-10-25: fetch it from YouTube, and
/// leave the subject empty when YouTube does not answer. YouTube's oEmbed
/// answers with the title the YouTube app gives Mail. Read against his own
/// Sent Mail of the 30 days before, 920 shares from the YouTube app: 884
/// had the subject Mail sent, character for character, 132 of them long
/// titles cut as the YouTube app cuts them (`subject`); 14 YouTube would
/// not name (a video kept from other sites, or gone), which stay empty
/// here; in the other 22 the subject was not the title as it is now, in 7
/// of them for words he had added after it.
///
/// One address is asked, YouTube's oEmbed, with the video's own watch page
/// and nothing of his: no cookie, nothing kept, no account. It is asked as
/// the sheet comes up, and nothing waits for it: Send never does, and a
/// subject he has typed is never written over (`ShareSheet.named`).
enum VideoTitle {

    /// How long the sheet listens for YouTube's answer, at most.
    static let wait: TimeInterval = 10

    /// One question to the web and its answer: the body and the HTTP
    /// status, either nil when there was none. Called back on any thread.
    typealias Fetch = (URLRequest, @escaping (Data?, Int?) -> Void) -> Void

    /// The video a link plays, by its eleven-character id: youtu.be/ID, the
    /// YouTube app's shape, or on youtube.com, www., m. or music.,
    /// /watch?v=ID, /shorts/ID, /live/ID or /embed/ID. Nil for any other
    /// link, a channel's or a playlist's among them.
    static func id(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" {
            id = parts.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
                    .contains(host) {
            if parts == ["watch"] {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) {
                id = parts[1]
            }
        }
        guard let id, id.count == 11,
              id.unicodeScalars.allSatisfy({ idCharacters.contains($0) }) else { return nil }
        return id
    }

    private static let idCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// What is asked: YouTube's oEmbed, for the video's watch page, as
    /// JSON. The id is only letters, digits, "-" and "_" (`id`), so the
    /// address needs no more escaping than it has here.
    static func question(for id: String) -> URLRequest {
        let address = "https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D"
            + id + "&format=json"
        var request = URLRequest(url: URL(string: address)!,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: wait)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        return request
    }

    /// The title in YouTube's answer, on one line; nil unless the answer
    /// is a 200 with a title in it. A video that is private or gone is
    /// answered otherwise, and keeps the subject empty.
    static func title(in data: Data?, status: Int?) -> String? {
        guard status == 200, let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["title"] as? String else { return nil }
        let line = title.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return line.isEmpty ? nil : line
    }

    /// The subject as the YouTube app hands a title to Mail: whole up to
    /// 75 characters, a longer one cut to its first 72 and "...". So were
    /// all 132 of his 920 that were longer, and titles of exactly 75 went
    /// whole. Counted in characters as they show: three of the long ones
    /// had accents in them, and were cut where characters are counted, not
    /// where UTF-16 would cut them.
    static func subject(from title: String) -> String {
        title.count <= 75 ? title : String(title.prefix(72)) + "..."
    }

    /// Asks YouTube for the title of the video `link` plays, and hands
    /// `done` the subject it makes (`subject`), or nil when it has none:
    /// on the main thread, once, within `seconds` however the asking goes.
    static func ask(for link: URL, through fetch: Fetch, within seconds: TimeInterval = wait,
                    done: @escaping (String?) -> Void) {
        let once = Once(done)
        guard let id = id(of: link) else {
            DispatchQueue.main.async { once.call(nil) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { once.call(nil) }
        fetch(question(for: id)) { data, status in
            let made = title(in: data, status: status).map(subject(from:))
            DispatchQueue.main.async { once.call(made) }
        }
    }

    /// `done`, called the first time and never again. Only ever called on
    /// the main thread.
    private final class Once {
        private var done: ((String?) -> Void)?

        init(_ done: @escaping (String?) -> Void) { self.done = done }

        func call(_ subject: String?) {
            let call = done
            done = nil
            call?(subject)
        }
    }
}

#if canImport(UIKit)
extension VideoTitle {

    /// The asking, on a session of its own that keeps nothing: no cookie
    /// sent or taken, no cache, nothing waited for when there is no
    /// connection. The log has YouTube's status, or the error's code where
    /// there was no answer, numbers alone.
    static let web: Fetch = { request, answer in
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = wait
        settings.timeoutIntervalForResource = wait
        settings.waitsForConnectivity = false
        settings.httpShouldSetCookies = false
        settings.httpCookieAcceptPolicy = .never
        settings.urlCache = nil
        let session = URLSession(configuration: settings)
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            Diagnostics.log(.note, "SHARE-TITLE status=\(status ?? 0) "
                + "error=\((error as NSError?)?.code ?? 0)")
            answer(data, status)
        }.resume()
        session.finishTasksAndInvalidate()
    }
}
#endif
