// Guarded so this file compiles away on a host without UIKit.
#if canImport(UIKit)

import Foundation
import WebKit

/// Serves the pictures that live inside a message to the web view showing it.
///
/// An HTML mail refers to its own images by `Content-ID`:
/// `<img src="cid:ii_1a0b5a437217d709">` points at a MIME part of the very
/// message being read. Nothing resolved those, and the web view was loaded
/// with `baseURL: nil` and no handler, so every one of them rendered as a
/// broken picture — measured against his real mail, 23 of 30 recent
/// attachment-bearing messages refer to at least one. Screenshots people
/// send him, photographs, and the signature block of everyone who writes
/// from Apple Mail: all of it arrived as grey boxes.
///
/// WebKit cannot be given a handler for `cid` itself — the scheme has to be
/// one WebKit does not already know — so the body is rewritten to point at
/// `bmcid://…` on the way in and this answers for that.
final class InlineImageLoader: NSObject, WKURLSchemeHandler {

    /// The custom scheme, defined next to the rewriter that emits it.
    static var scheme: String { InlineImageRewriter.scheme }

    /// Asked for the bytes of one part. Set by the view controller whenever
    /// the message on screen changes; nil between messages.
    var fetch: ((_ contentID: String) async throws -> (Data, String))?

    /// Tasks WebKit has not cancelled yet, with the fetch answering each.
    ///
    /// Load-bearing rather than tidy: replying to a `WKURLSchemeTask` that
    /// WebKit has already stopped raises an Objective-C exception, which is
    /// not catchable from Swift and takes the app down. Stopping happens
    /// routinely and through no fault of anyone's — he taps the next message
    /// while a photograph is still downloading — so every reply is gated on
    /// the task still being live, and the fetch of one stopped is called
    /// off, so the letter he tapped does not wait behind it
    /// (`PictureRequests`).
    private var requests = PictureRequests<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        requests.begin(key)

        // "bmcid://<id>" — the id can be anything a sender chose, so it is
        // read back from the host AND the path and then percent-decoded,
        // rather than assuming it survived as a tidy hostname.
        let url = task.request.url
        let raw = [url?.host, url?.path.replacingOccurrences(of: "/", with: "")]
            .compactMap { $0 }
            .joined()
        let contentID = raw.removingPercentEncoding ?? raw

        guard !contentID.isEmpty, let fetch else {
            finish(task, key: key, with: nil, mimeType: nil)
            return
        }

        requests.answering(key, with: Task { @MainActor in
            let result = try? await fetch(contentID)
            self.finish(task, key: key, with: result?.0, mimeType: result?.1)
        })
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        requests.stop(ObjectIdentifier(task))
    }

    /// One place where a task is answered, so the liveness check cannot be
    /// forgotten on one path.
    ///
    /// Not `@MainActor`, because `WKURLSchemeHandler`'s own methods are not:
    /// WebKit calls them on the main thread but the protocol does not say
    /// so, and marking this isolated makes the synchronous path above fail
    /// to compile. The fetch hop is where the actor boundary is crossed.
    private func finish(_ task: WKURLSchemeTask, key: ObjectIdentifier,
                        with data: Data?, mimeType: String?) {
        guard requests.answer(key) else { return }

        guard let data, !data.isEmpty, let url = task.request.url else {
            // A part that cannot be fetched gets an empty 404 rather than an
            // error: `didFailWithError` leaves WebKit showing its own broken
            // image, which is what this exists to remove.
            let response = HTTPURLResponse(url: task.request.url
                                            ?? URL(string: "bmcid://missing")!,
                                           statusCode: 404,
                                           httpVersion: nil, headerFields: nil)!
            task.didReceive(response)
            task.didFinish()
            return
        }

        task.didReceive(URLResponse(url: url,
                                    mimeType: mimeType ?? "application/octet-stream",
                                    expectedContentLength: data.count,
                                    textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }
}

#endif
