import Foundation
import XCTest
@testable import Blackmail

/// The copy of his mail kept on the iPad (D-016), which the app's
/// repository always has, for the suites that build one: a shelf over a
/// directory of the test's own, holding `Kept/` as Application Support holds
/// it in the app, removed when the test ends.
///
/// Each call is a launch's shelf, over whatever the shelves made before it
/// in the same test kept, as each launch of the app reads what the last one
/// left. So the command sequences a suite pins are the ones the app sends,
/// shelf and all: a suite that built its repository with none never ran
/// the rules that keep a launch's wire as it was, and undoing one of them
/// left every pinned sequence green.
extension XCTestCase {

    func keptShelf(for account: MailAccount) -> MailShelf {
        MailShelf(root: KeptRoots.shared.root(for: self), address: account.address,
                  host: account.imapHost)
    }
}

/// One directory per test, made the first time the test asks and removed,
/// with every shelf over it ended, as it finishes.
private final class KeptRoots: @unchecked Sendable {

    static let shared = KeptRoots()

    private let lock = NSLock()
    private var roots: [ObjectIdentifier: URL] = [:]

    func root(for test: XCTestCase) -> URL {
        let key = ObjectIdentifier(test)
        lock.lock()
        if let known = roots[key] {
            lock.unlock()
            return known
        }
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeptShelves-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Kept", isDirectory: true)
        roots[key] = root
        lock.unlock()
        test.addTeardownBlock { [weak self] in
            MailShelf.wipe(root: root)
            try? FileManager.default.removeItem(at: base)
            self?.forget(key)
        }
        return root
    }

    private func forget(_ key: ObjectIdentifier) {
        lock.lock()
        roots[key] = nil
        lock.unlock()
    }
}
