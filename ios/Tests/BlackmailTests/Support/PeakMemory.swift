import Foundation

/// How much more memory the test process held at its most, resident, while
/// some work ran, than it held before: Linux's high-water mark, reset first
/// by writing 5 to `/proc/self/clear_refs`.
///
/// An upper bound on what the work kept at once, and a loose one: freed
/// memory the allocator still holds is resident already, and work that
/// fits in it raises nothing. So it is used only to say that something
/// stayed under a bound far above what it needs, which the old way of
/// doing it went far over. The work runs either way; nil where the mark
/// cannot be read or reset, which the test then skips.
enum PeakMemory {

    static func growth(during work: () throws -> Void) rethrows -> Int? {
        let before = start()
        try work()
        guard let before else { return nil }
        return peak().map { $0 - before }
    }

    static func growth(during work: () async throws -> Void) async rethrows -> Int? {
        let before = start()
        try await work()
        guard let before else { return nil }
        return peak().map { $0 - before }
    }

    /// What is resident now, with the high-water mark brought down to it.
    private static func start() -> Int? {
        guard let resident = status("VmRSS"),
              (try? "5".write(toFile: "/proc/self/clear_refs", atomically: false,
                              encoding: .utf8)) != nil,
              let mark = status("VmHWM"), mark <= resident + (8 << 20) else { return nil }
        return resident
    }

    private static func peak() -> Int? { status("VmHWM") }

    /// A `/proc/self/status` figure, in bytes.
    private static func status(_ key: String) -> Int? {
        guard let text = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else {
            return nil
        }
        for line in text.split(separator: "\n") where line.hasPrefix(key + ":") {
            let kilobytes = line.dropFirst(key.count + 1).filter(\.isNumber)
            return Int(kilobytes).map { $0 * 1024 }
        }
        return nil
    }
}
