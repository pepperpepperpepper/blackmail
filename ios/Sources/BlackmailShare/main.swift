// Deliberately empty.
//
// SwiftPM insists an executableTarget has an entry point, and an app
// extension must NOT use it: the real entry is `NSExtensionMain`, supplied by
// Foundation and selected with `-e _NSExtensionMain` in Package.swift. That
// is exactly what Xcode passes for an extension target. This file exists to
// satisfy SwiftPM and is never called.
