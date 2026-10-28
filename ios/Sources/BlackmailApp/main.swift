// The entire executable: everything else is the `Blackmail` LIBRARY target.
//
// The split exists so the parsers can be tested. The library is compiled for
// the HOST as well as for the device — MIME and IMAP parsing is pure
// Foundation, so it runs and is tested on Linux in seconds rather than through
// a build, sign, deploy and screenshot cycle on a physical iPad.
//
// Guarded because `swift test` builds every target in the package, including
// this one, and on Linux there is no UIKit to launch into. On the host this
// file compiles to an empty program that is never run.
#if canImport(UIKit)

import UIKit
import Blackmail

// The principal class is the app's own, which answers Large for the text
// size whatever the iPad's (`BlackmailApplication`, B-166).
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv,
                  NSStringFromClass(BlackmailApplication.self),
                  NSStringFromClass(AppDelegate.self))

#endif
