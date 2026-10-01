import Foundation

/// A sender's own `<html>`/`<head>`/`<body>` wrapper, and taking it off.
///
/// Pure and Foundation-only, and separated from the reading pane that uses
/// it so the suite on Linux can test it — the pane is UIKit and WebKit and
/// cannot exist on the test host.
enum DocumentWrapper {

    /// `html` without its wrapper.
    ///
    /// This is not tidiness, it is the fix for a real and near-universal bug.
    /// WebKit merges an inner `<body>`'s attributes onto the outer one, and an
    /// inline style beats a stylesheet — so a message whose body tag carries
    /// `style="padding: 0"` silently cancelled our padding and the letter
    /// rendered flush against the pane divider while the header above it stayed
    /// inset. Almost every real HTML email ships a styled body tag, so this was
    /// not an edge case. With the wrapper gone a sender cannot set the letter's
    /// margin or type size at all.
    ///
    /// What goes, in any case: every `<!DOCTYPE …>`, `<html …>`, `</html …>`,
    /// `<body …>` and `</body …>`, each to the first `>` after it, and every
    /// `<head …>` with everything up to the first `</head>` after it. A tag
    /// that never reaches a `>`, and a head that never reaches a `</head>`,
    /// stay as they came.
    ///
    /// The head's tag name must END where HTML ends a tag name, at white
    /// space, `/` or `>`. A bare `<head` also matched HTML5's `<header>`, the
    /// element newsletters put at the top of each article, and read on from
    /// it for a `</head>` that `</header>` does not supply; where a later one
    /// did exist, as in a forwarded letter quoting a whole document of its
    /// own, everything from the first `<header>` to it went, which is most of
    /// the letter.
    ///
    /// One pass over the bytes. It used to be four regular expressions, one
    /// per piece, and one that is never closed made each of its openings read
    /// to the end of the letter: 48 KB of `<head>` took 8.5 s, and a megabyte
    /// would have taken about an hour, off the main thread but with no way to
    /// stop it. Here the next `>` and the next `</head>` are each looked for
    /// once from where the last search found one, or found none, so no byte
    /// is read more than a few times. It takes off what the expressions took
    /// off, byte for byte, on every letter that is not built to make them
    /// disagree: they ran one after another, so a tag of one kind whose `>`
    /// lay beyond a `</head>` could once be taken first. Every name here is
    /// ASCII and no other character folds to one of its letters, so matching
    /// in any case is matching ASCII in any case; the white space after
    /// `<head` is the expressions' `\s`, which is Unicode's White_Space: the
    /// ASCII controls from tab to carriage return, the space, and the likes
    /// of U+0085 and U+00A0.
    static func stripped(from html: String) -> String {
        var contiguous = html
        let out = contiguous.withUTF8 { bytes in
            var pass = Pass(bytes)
            return pass.run()
        }
        return out.map { String(decoding: $0, as: UTF8.self) } ?? html
    }

    private struct Pass {
        let b: UnsafeBufferPointer<UInt8>
        /// The last search for a `>`: where it began and what it found, nil
        /// for none from there to the end.
        var greater: (from: Int, at: Int?) = (Int.max, nil)
        /// The same for `</head>`.
        var headClose: (from: Int, at: Int?) = (Int.max, nil)

        init(_ bytes: UnsafeBufferPointer<UInt8>) {
            b = bytes
        }

        /// The letter without its wrapper, or nil when there was none to
        /// take off.
        mutating func run() -> [UInt8]? {
            var out: [UInt8] = []
            var copied = 0
            var i = 0
            let n = b.count
            while i < n {
                guard b[i] == lt, let end = wrapperEnd(at: i) else {
                    i += 1
                    continue
                }
                if out.isEmpty { out.reserveCapacity(n) }
                out.append(contentsOf: UnsafeBufferPointer(rebasing: b[copied..<i]))
                i = end
                copied = end
            }
            guard copied > 0 else { return nil }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: b[copied..<n]))
            return out
        }

        /// Where the piece of wrapper starting with the `<` at `i` ends, just
        /// past its last byte, or nil when none starts there.
        mutating func wrapperEnd(at i: Int) -> Int? {
            if matches(doctype, at: i) { return next(greaterFrom: i + doctype.count).map { $0 + 1 } }
            if matches(htmlOpen, at: i) { return next(greaterFrom: i + htmlOpen.count).map { $0 + 1 } }
            if matches(htmlClose, at: i) { return next(greaterFrom: i + htmlClose.count).map { $0 + 1 } }
            if matches(bodyOpen, at: i) { return next(greaterFrom: i + bodyOpen.count).map { $0 + 1 } }
            if matches(bodyClose, at: i) { return next(greaterFrom: i + bodyClose.count).map { $0 + 1 } }
            if matches(headOpen, at: i), endsTagName(at: i + headOpen.count),
               let tagEnd = next(greaterFrom: i + headOpen.count),
               let close = next(headCloseFrom: tagEnd + 1) {
                return close + headCloseTag.count
            }
            return nil
        }

        /// The first `>` at or after `start`.
        mutating func next(greaterFrom start: Int) -> Int? {
            if start >= greater.from, greater.at.map({ $0 >= start }) ?? true {
                return greater.at
            }
            var j = start
            while j < b.count, b[j] != gt { j += 1 }
            greater = (start, j < b.count ? j : nil)
            return greater.at
        }

        /// The first `</head>`, in any case, at or after `start`.
        mutating func next(headCloseFrom start: Int) -> Int? {
            if start >= headClose.from, headClose.at.map({ $0 >= start }) ?? true {
                return headClose.at
            }
            var j = start
            while j < b.count, !(b[j] == lt && matches(headCloseTag, at: j)) { j += 1 }
            headClose = (start, j < b.count ? j : nil)
            return headClose.at
        }

        func matches(_ needle: [UInt8], at index: Int) -> Bool {
            guard index + needle.count <= b.count else { return false }
            for k in 0..<needle.count where lowered(b[index + k]) != needle[k] { return false }
            return true
        }

        /// Whether the character at `index` is one the expressions' `(?=[\s/>])`
        /// let end the head's tag name.
        func endsTagName(at index: Int) -> Bool {
            guard index < b.count else { return false }
            let c = b[index]
            if c < 0x80 { return (c >= 0x09 && c <= 0x0D) || c == 0x20 || c == slash || c == gt }
            var decoder = UTF8()
            var rest = UnsafeBufferPointer(rebasing: b[index...]).makeIterator()
            guard case let .scalarValue(scalar) = decoder.decode(&rest) else { return false }
            return scalar.properties.isWhitespace
        }
    }
}

private let lt = UInt8(ascii: "<")
private let gt = UInt8(ascii: ">")
private let slash = UInt8(ascii: "/")

private let doctype = Array("<!doctype".utf8)
private let htmlOpen = Array("<html".utf8)
private let htmlClose = Array("</html".utf8)
private let bodyOpen = Array("<body".utf8)
private let bodyClose = Array("</body".utf8)
private let headOpen = Array("<head".utf8)
private let headCloseTag = Array("</head>".utf8)

private func lowered(_ c: UInt8) -> UInt8 {
    (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
}
