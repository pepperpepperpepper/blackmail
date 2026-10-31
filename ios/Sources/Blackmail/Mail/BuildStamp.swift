import Foundation

/// The app's version and build, and the commit it was built from, as one
/// line he or whoever helps him can read out over the phone (B-187):
/// "Version 0.1 (3), 6ce5af1".
///
/// The version and build are the Info.plist's own keys. The commit is not
/// typed by anyone: `package.sh` writes it into the bundle's Info.plist
/// from git as it packages the app, with `BlackmailCommitChanged` when the
/// app's files had changes not yet committed, so a build that is not the
/// commit it names says so. A bundle built some other way, with no commit
/// in it, reads as its version and build alone.
///
/// Shown at the foot of Settings and at the top of the Connection log's
/// view and of what its share button sends; nowhere on the mail screens.
enum BuildStamp {

    /// The short commit, written by `package.sh`.
    static let commitKey = "BlackmailCommit"
    /// True when the app's files had changes not committed, written by
    /// `package.sh` beside the commit.
    static let changedKey = "BlackmailCommitChanged"

    /// This app's line, from its bundle as installed.
    static var app: String { line(Bundle.main.infoDictionary ?? [:]) }

    /// The line from an Info.plist's keys. A missing or empty key is left
    /// out, not shown as a blank: no build, no "( )"; no version, the build
    /// alone; neither, "Version not known".
    static func line(_ info: [String: Any]) -> String {
        let version = word(info["CFBundleShortVersionString"])
        let build = word(info["CFBundleVersion"])
        var text: String
        switch (version, build) {
        case let (version?, build?): text = "Version \(version) (\(build))"
        case let (version?, nil): text = "Version \(version)"
        case let (nil, build?): text = "Build \(build)"
        case (nil, nil): text = "Version not known"
        }
        if let commit = word(info[commitKey]) {
            text += ", \(commit)"
            if info[changedKey] as? Bool == true { text += " plus changes" }
        }
        return text
    }

    /// The Connection log's text with the line above it, a blank line
    /// between, as the log's view shows it and its share button sends it.
    static func atTop(of log: String, stamp: String = BuildStamp.app) -> String {
        stamp + "\n\n" + log
    }

    private static func word(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}
