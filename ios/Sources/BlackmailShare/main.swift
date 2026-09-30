// The share extension's executable: everything it does is in the Blackmail
// LIBRARY (Sources/Blackmail/Share), which the app links too, so a shared
// letter is built and sent by the app's own code rather than a copy of it.
//
// Never run as a program. SwiftPM insists an executableTarget has an entry
// point, and an app extension must NOT use it: the real entry is
// `NSExtensionMain`, supplied by Foundation and selected with
// `-e _NSExtensionMain` in Package.swift, which is exactly what Xcode passes
// for an extension target. It then finds `ShareViewController` by the name
// ShareInfo.plist gives it.
//
// Guarded because `swift test` builds every target in the package, and on
// Linux there is no UIKit.
#if canImport(UIKit)

import Blackmail

// Named here so the class is plainly part of this executable, whatever the
// linker makes of a class the code never mentions.
_ = ShareViewController.self

#endif
