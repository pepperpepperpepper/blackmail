import Foundation

// What is on screen while something he asked for is on its way: the words
// on the list's status line, an alert held until the sheet he chose from
// has gone, and a draft he tapped, being downloaded.
//
// Out of the view controllers for the reason `SearchAnswer` is: they are
// UIKit and do not exist on the machine the suite runs on.

/// The line under the message list: how fresh it is or where he is, and
/// while a jump, a Move or Edit mode's Delete he asked for is on its way,
/// that.
///
/// A jump and a Move used to start only once their sheet had finished
/// sliding away, about a third of a second, and nothing on screen said
/// either was happening until it was over. Now each says so from the tap
/// ("Going to 3 May…", "Moving…"), and the line goes back to what it said
/// when it is done, or to what it has been given to say since: the day the
/// jump landed on, or "Updated Just Now" from a Refresh that overtook it.
struct StatusLine: Equatable {

    /// What the line says when nothing is on its way.
    private(set) var resting: String
    /// What is on its way, oldest first.
    private var working: [Work] = []
    private var lastID = 0

    private struct Work: Equatable {
        let id: Int
        let text: String
    }

    init(resting: String) {
        self.resting = resting
    }

    /// What the line says: the latest thing still on its way, or else the
    /// resting words.
    var text: String { working.last?.text ?? resting }

    /// Something to say for good, such as where he is. Shown once nothing
    /// he asked for is on its way any more.
    mutating func rest(_ text: String) {
        resting = text
    }

    /// Something he asked for has started. Returns what to hand `finish`.
    mutating func start(_ text: String) -> Int {
        lastID += 1
        working.append(Work(id: lastID, text: text))
        return lastID
    }

    /// It has finished, whichever way.
    mutating func finish(_ id: Int) {
        working.removeAll { $0.id == id }
    }

    /// While a jump to `day` is on its way.
    static func goingTo(_ day: Date) -> String {
        "Going to \(IMAPDate.spokenDay(day))…"
    }

    /// While a Move is on its way.
    static let moving = "Moving…"

    /// While Edit mode's Delete is on its way (B-062), as "Moving…" says a
    /// Move is. The pane's Delete is one letter, gone from the pane and the
    /// list at the tap, and says nothing, as before.
    static let deleting = "Deleting…"
}

/// Alerts held while a sheet is on its way off the screen.
///
/// UIKit will not present anything over a sheet that is still being
/// dismissed: the alert is dropped, with a line in the console and nothing
/// on screen. That did not matter while a jump or a Move started only once
/// its sheet had gone. Started at the tap, a failure fast enough, as with no
/// connection at all, lands during the slide, and "Can't connect to mail
/// server." would never be seen. So an alert asked for then waits, and is
/// shown when the sheet has gone.
///
/// The sheet's going is reported by its dismissal's completion, and UIKit
/// does not always call that: a dismissal it ignores, as one asked for
/// while the sheet is already on its way out, never completes. Waiting on
/// the report alone, one that never came would hold every alert in the app
/// from then on, and each "Can't connect" after it would be silent. So a
/// sheet is waited for at most `bound`, a few times its slide.
///
/// Only one alert can be up at a time, and every one asked for meanwhile is
/// kept, to be tried latest first when the sheet has gone. The earlier ones
/// can be for a screen the sheet's choice has replaced during the slide, as
/// a jump into All Mail replaces the list, and have nothing left to be
/// shown over; the latest is for what is on screen now.
struct AlertHold<Alert> {

    /// How long a sheet is waited for, in seconds. Its slide takes about a
    /// third of one.
    static var bound: TimeInterval { 1 }

    /// Sheets on their way off, and when each stops being waited for.
    private var leaving: [Int: Date] = [:]
    private var lastID = 0
    private var held: [Alert] = []

    /// A sheet has started to go. Returns what to hand `sheetGone`.
    mutating func sheetLeaving(at now: Date) -> Int {
        lastID += 1
        leaving[lastID] = now.addingTimeInterval(Self.bound)
        return lastID
    }

    /// The alerts to try now, latest first, until one is shown: this one,
    /// and any held before it. None while a sheet is going.
    mutating func show(_ alert: Alert, at now: Date) -> [Alert] {
        held.append(alert)
        return due(at: now)
    }

    /// The sheet `id` has gone. The alerts held for it, once no sheet is
    /// still going. A sheet dismissed with nothing asked of it, by its
    /// Cancel, says so too, and changes nothing.
    mutating func sheetGone(_ id: Int, at now: Date) -> [Alert] {
        leaving[id] = nil
        return due(at: now)
    }

    /// The alerts held, once every sheet has gone or been waited for as
    /// long as `bound`; asked again at the bound for a sheet that never
    /// reports back.
    mutating func due(at now: Date) -> [Alert] {
        leaving = leaving.filter { $0.value > now }
        guard leaving.isEmpty else { return [] }
        defer { held = [] }
        return held.reversed()
    }
}

/// A draft tapped in the Drafts folder, on its way to the composer.
///
/// A draft has to be downloaded before the composer can open it, for as
/// long as a letter takes, and the row used to drop its highlight at the
/// tap with nothing on screen until the sheet came up: a tap that seemed
/// to have missed, and the answer to that is to tap again, which fetched
/// the draft a second time. Now the row stays highlighted with a spinner
/// until the sheet opens, and a second tap on it meanwhile does nothing.
struct DraftOpening: Equatable {

    /// The draft being downloaded, if any.
    private(set) var loading: String?

    /// Whether a tap on the draft `id` downloads it. Not while that same
    /// draft is on its way. A tap on another draft does, and the first is
    /// no longer wanted: opening it when it came would put a composer he
    /// has moved on from over the one he chose.
    mutating func tap(_ id: String) -> Bool {
        guard loading != id else { return false }
        loading = id
        return true
    }

    /// The draft `id` has come, or could not be fetched: whether that is
    /// still wanted, and so opened, or said to have failed.
    mutating func landed(_ id: String) -> Bool {
        guard loading == id else { return false }
        loading = nil
        return true
    }
}
