import Foundation

/// What is up over the mail, as the root sees it: the screens presented one
/// over another, from the one the root presents up to the first on its way
/// out, and among them, perhaps, the warning before the app stops opening
/// (B-137).
///
/// The warning is an alert with OK alone that he did not ask for, put up
/// only with nothing over the mail. It is neither a sheet he has open nor a
/// screen to put anything over: an alert asked for while it is up waits for
/// its OK (`ErrorPresenter`), and by then it has gone, and with it any
/// alert addressed to it.
///
/// Out of `ErrorPresenter` and `RootViewController` for the reason
/// `Sitting` is: they are UIKit and do not exist on the machine the suite
/// runs on. Generic so the suite can hand it screens of its own.
struct OverTheMail<Screen: AnyObject> {

    /// Presented one over another, the root's own first.
    let screens: [Screen]
    /// The warning, while it is up.
    let warning: Screen?
    /// The alerts asked for while the warning is up, waiting for its OK
    /// (`ErrorPresenter.showFirst`).
    let waiting: Int

    init(screens: [Screen], warning: Screen?, waiting: Int = 0) {
        self.screens = screens
        self.warning = warning
        self.waiting = waiting
    }

    /// Something he opened, or is answering, is over the mail: anything up
    /// but the warning alone.
    var sheetOpen: Bool { screens.contains { $0 !== warning } }

    /// What B-003's return to the Inbox after a while away waits for
    /// (`Sitting.onReturn`): a sheet he has open, and an alert waiting
    /// behind the warning, but not the warning alone, which can be left
    /// up overnight with the iPad locked over it: the Inbox comes back, at
    /// its top, under it. An alert waiting is addressed to the screen it
    /// was asked for over, as an Edit-mode refusal is to the list; the
    /// Inbox put in the list's place, it has nothing to go over at OK and
    /// is dropped (`ErrorPresenter.put`), so the return waits, as it did
    /// for the warning. Only while the warning is up: one taken away
    /// without its OK leaves nothing waiting for it.
    var holdsTheReturn: Bool {
        sheetOpen || (waiting > 0 && screens.contains { $0 === warning })
    }

    /// What an alert goes over: the screen in front, below the warning if
    /// it is up; `root` itself with nothing over it, or the warning alone.
    func front(root: Screen) -> Screen {
        screens.prefix { $0 !== warning }.last ?? root
    }

    /// What an alert asked for over `asked` goes over: `asked`, or, for the
    /// warning itself, what the warning is over, `presenter`, which stays
    /// when OK takes the warning away.
    static func host(for asked: Screen, warning: Screen?, presenter: Screen?) -> Screen {
        asked === warning ? presenter ?? asked : asked
    }
}
