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

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))

#endif
