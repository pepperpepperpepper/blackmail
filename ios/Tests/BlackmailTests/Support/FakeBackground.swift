import Foundation
@testable import Blackmail

/// iOS's background time as the tests hand it out: numbered from 1, each
/// asking and giving back written down, and running out when told to.
@MainActor
final class FakeBackground {
    var begun: [String] = []
    var ended: [Int] = []
    /// Whether iOS gives any time at all.
    var grants = true
    var log: (String) -> Void = { _ in }
    private var expiries: [Int: @MainActor () -> Void] = [:]
    private var last = 0

    var time: BackgroundTime {
        BackgroundTime(
            begin: { [unowned self] name, expired in
                begun.append(name)
                log("begin \(name)")
                guard grants else { return nil }
                last += 1
                expiries[last] = expired
                return last
            },
            end: { [unowned self] id in
                ended.append(id)
                log("end \(id)")
            })
    }

    /// iOS wants time `id` back.
    func expire(_ id: Int) {
        expiries[id]?()
    }
}
