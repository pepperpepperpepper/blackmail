// swift-tools-version:5.9
//
// Blackmail. Built on Linux for arm64-apple-ios; there is no Mac and no Xcode
// project. See ../docs/TOOLCHAIN.md.
//
// Deliberately swift-tools-version 5.9 and not 6.x: that keeps the package in
// Swift 5 language mode, so strict concurrency checking stays advisory. UIKit
// view controllers are main-actor by nature and the noise would be constant.
import PackageDescription

let package = Package(
    name: "Blackmail",
    platforms: [.iOS(.v16)],   // 16.0, not the brief's 15: the Linux Swift SDK
                               // has no libswiftCompatibility56.a, so 15 fails to link
    targets: [
        // The library: all of the app except its entry point. Built for the
        // device AND for this Linux host, which is what makes the parsers
        // testable without a device. Everything that needs UIKit, Network or
        // Security is guarded with `#if canImport(...)` and simply vanishes on
        // the host, leaving the pure-data code that the tests exercise.
        .target(
            name: "Blackmail",
            path: "Sources/Blackmail",
            linkerSettings: [
                // The Swift *overlay* for UIKit, which is a separate dylib from
                // UIKit itself. Anything Swift-only lives here -
                // defaultContentConfiguration(), UIListContentConfiguration,
                // IndexPath.row - so a UIKit app that touches any of them
                // fails at link time with undefined symbols, not at compile
                // time. Xcode links it implicitly; building by hand does not.
                //
                // Conditioned on iOS because the library is also built for
                // this Linux host to run the parser tests, and there is no
                // swiftUIKit to link there.
                .linkedLibrary("swiftUIKit", .when(platforms: [.iOS])),
            ]
        ),
        .executableTarget(
            name: "BlackmailApp",
            dependencies: ["Blackmail"],
            path: "Sources/BlackmailApp"
        ),
        // SPIKE (B-036): the share extension. An app extension is a second
        // signed bundle in Blackmail.app/PlugIns/, and nothing on this
        // pipeline has ever produced one — the whole project is SwiftPM on
        // Linux with xtool's linker and zsign, deliberately no Xcode. Whether
        // that can emit a loadable .appex is the question the whole of B-036
        // depends on, so it is being answered before anything is designed.
        .executableTarget(
            name: "BlackmailShare",
            path: "Sources/BlackmailShare",
            linkerSettings: [
                .linkedLibrary("swiftUIKit", .when(platforms: [.iOS])),
                // THE line. An extension's entry point is Foundation's
                // `NSExtensionMain`, not the `main` SwiftPM generates —
                // exactly what Xcode passes for an extension target. Without
                // it the bundle builds, installs, and is silently never
                // loaded by the host process.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"],
                             .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "BlackmailTests",
            dependencies: ["Blackmail"],
            path: "Tests/BlackmailTests"
        ),
    ]
)
