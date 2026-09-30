# Investigation evidence

Raw findings from the four investigations, kept so later readers can check the
reasoning rather than taking `BUILD_DECISION.md` on faith.

---

## Investigation 1

**Verdict.** Swift-without-a-Mac is real today — I built it, on this host. Using the stock swift.org Swift 6.2 Linux toolchain plus a free community iPhoneOS SDK and xtool's patched `ld64.lld`, I compiled and linked a UIKit app to a genuine `arm64` iOS-device Mach-O executable (`LC_BUILD_VERSION platform=2, minos 16.0`, linking only `/usr/lib/swift/libswiftCore.dylib`, `UIKit`, `Foundation`), and then did the same through SwiftPM (`swift build --swift-sdk arm64-apple-ios -c release`, 57 s). No Mac, no Xcode, no Xcode.xip. BUT the specific app the package asks for will not build that way today: SwiftMail's dependency graph — even at SwiftMail's own declared minimum `swift-nio 2.101.3` — needs a Swift 6.2 stdlib (`Span`, `RawSpan`, `InlineArray`, `SendableMetatype`), which only exists in the iOS 26 SDK. The newest freely-mirrored SDK is iPhoneOS 18.6 (Swift 6.1.2 stdlib) and it fails with 731 errors. So: the *toolchain* question is answered yes; the *SwiftMail* question is "only via an Xcode 26 .xip" (downloadable on Linux with an Apple ID, ~10 GB, no Mac needed) or by forking SwiftMail's manifest onto an older NIO. The honest fallback — a rented cloud Mac — costs $0.062/min on GitHub Actions and puts a 90-year-old end user's daily mail client behind a rented machine, a signing identity in a cloud secret store, and an annually-expiring profile; I'd avoid it given a working local path exists.


### The stock swift.org Swift 6.2 Linux toolchain's compiler fully understands arm64-apple-ios as a target; it is only the runtime/SDK pieces that are absent from the tarball.

Confidence: high

```
$ swiftc -print-target-info -target arm64-apple-ios16.0
{ "target": { "triple": "arm64-apple-ios16.0", "platform": "iphoneos", "arch": "arm64", "swiftRuntimeCompatibilityVersion": "5.7", ... },
  "paths": { "runtimeLibraryPaths": [ ".../usr/lib/swift/iphoneos", "/usr/lib/swift" ] } }

$ ls .../usr/lib/swift/
apinotes Block clang CoreFoundation dispatch embedded _FoundationCShims _foundation_unicode FrameworkABIBaseline host _InternalSwiftScan _InternalSwiftStaticMirror linux migrator os pm shims swiftToCxx
  -> only 'linux'; no iphoneos/macosx dir. Tarball: swift-6.2-RELEASE-ubuntu24.04.tar.gz, 1,007,380,084 bytes, 3.2 GB extracted, runs on Arch after symlinking libncursesw.so.6 -> libncurses.so.6.
```

### PROVEN: Swift source importing Foundation and UIKit compiles to arm64 iOS Mach-O object code on Linux against the free theos sparse iPhoneOS SDK.

Confidence: high

```
$ swiftc -target arm64-apple-ios16.0 -sdk /mnt/extra/cmail-swift/sdks/iPhoneOS16.5.sdk -resource-dir /mnt/extra/cmail-swift/darwin-resource -c hello.swift -o hello.o
exit=0  errors=0
$ file hello.o
hello.o: Mach-O 64-bit arm64 object, flags:<|SUBSECTIONS_VIA_SYMBOLS>
(hello.swift contains `import Foundation`, `import UIKit`, an NSObject subclass, and a UILabel factory. Source at /tmp/cmail/swift-nomac/t1/hello.swift)
```

### PROVEN: a complete UIKit iOS-device executable links on Linux. The binary has the correct Mach-O shape for ad-hoc signing and install — platform 2 (iOS device, not simulator), no bundled Swift runtime.

Confidence: high

```
$ file /tmp/cmail/swift-nomac/t1/ClassicMailTest
Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|BINDS_TO_WEAK|PIE>
Load commands (parsed with python struct):
  LC_ENCRYPTION_INFO_64
  LC_BUILD_VERSION platform=2 minos=16.0.0 sdk=16.5.0
  LC_MAIN
  LC_LOAD_DYLIB /usr/lib/libSystem.B.dylib
  LC_LOAD_DYLIB /usr/lib/swift/libswiftCore.dylib
  LC_LOAD_DYLIB /usr/lib/swift/libswiftFoundation.dylib
  LC_LOAD_DYLIB /System/Library/Frameworks/UIKit.framework/UIKit
  ... (source: main.swift with UIApplicationMain + AppDelegate + UIWindow)
```

### PROVEN: the SwiftPM path works. A hand-rolled Swift SDK artifactbundle installs with `swift sdk install`, and `swift build --swift-sdk arm64-apple-ios -c release` produces the app binary.

Confidence: high

```
$ swift sdk install /mnt/extra/cmail-swift/ios18.artifactbundle
Swift SDK bundle ... successfully installed as ios18.artifactbundle
$ swift sdk list
ios186
$ cd /mnt/extra/cmail-swift/apptest && swift build --swift-sdk arm64-apple-ios -c release
Building for production...
ld64.lld: warning: directory not found for option -L .../resource/iphoneos
Build complete! (57.31s)
$ file .build/arm64-apple-ios/release/ClassicMailApp
Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>
LC_BUILD_VERSION platform=2 minos=16.0.0 sdk=16.0.0; dylibs: libSystem, UIKit, libswiftCore, Foundation, libobjc
```

### swiftlang/swift-sdk-generator (the official SE-0387 Swift SDK tooling) does NOT support Darwin/iOS as a target. It is Linux/FreeBSD-only. It is a dead end for this project.

Confidence: high

```
From https://github.com/swiftlang/swift-sdk-generator README: supported targets are FreeBSD 14.3+, Ubuntu 20.04+, Debian 11/12/13, RHEL/Fedora, Amazon Linux 2. "FreeBSD and Linux are supported as both host and target platforms. macOS is only supported as a host platform." macOS arm64/x86_64 show ❌ in the 'Supported Version as Target' column.
```

### xtool is the real, actively-maintained Xcode-replacement for Linux, but its documented path requires downloading Xcode 26 as an .xip from Apple (Apple ID login in a browser; no Mac needed) plus Swift 6.3 and usbmuxd.

Confidence: high

```
xtool release 1.19.2 published 2026-09-11 (xtool-x86_64.AppImage, 53.7 MB, 475 downloads). Documentation/xtool.docc/Installation-Linux.md: "Install the Swift 6.3 toolchain ... from https://swift.org/install/linux"; "### Xcode.xip — Download **Xcode 26** from https://developer.apple.com/download/all/?q=Xcode ... You'll be asked to log in with your Apple ID"; "xtool will extract the Xcode XIP to generate and install an iOS Swift SDK for you" then `swift sdk list` -> `darwin`. Login modes: API Key (paid Developer Program) or Apple ID password.
```

### The single indispensable non-Apple binary is xtool's patched ld64.lld. The ld64.lld shipped inside Swift 6.2 (LLVM 17) flatly refuses iOS-device linking; xtool's LLVM-20 build from a personal fork of llvm-project succeeds. This is the one supply-chain single point of failure in the whole pipeline.

Confidence: high

```
Swift 6.2's own linker:
$ ld64.lld -arch arm64 -platform_version ios 16.0 16.5 ... app.o -o out
ld64.lld: error: This version of lld does not support linking for platform iOS

xtool's toolset (github.com/xtool-org/darwin-tools-linux-llvm v1.0.1, toolset-x86_64.tar.gz, 43.7 MB, contains exactly three binaries: ld64.lld, libtool, dsymutil; MIT licence, Copyright (c) 2024 Kabir Oberai; built from submodule https://github.com/kabiroberai/llvm-project.git):
$ /mnt/extra/cmail-swift/toolset/bin/ld64.lld --version
LLD 20.0.0
$ ... same link command ...
$ file ClassicMailTest
Mach-O 64-bit arm64 executable
```

### You do NOT need Xcode.xip for the SDK itself. Free community-mirrored iPhoneOS SDKs work: theos/sdks (up to iPhoneOS16.5) and xybp888/iOS-SDKs (up to iPhoneOS18.6). Both include the Swift stdlib .swiftinterface and libswift*.tbd stubs the compiler needs.

Confidence: high

```
$ git clone --filter=blob:none --no-checkout --depth 1 https://github.com/theos/sdks.git && git sparse-checkout set iPhoneOS16.5.sdk   -> 271 MB
$ ls iPhoneOS16.5.sdk/usr/lib/swift/Swift.swiftmodule
arm64-apple-ios.swiftinterface  arm64-apple-ios.swiftdoc  arm64e-apple-ios.swiftinterface ...
$ ls iPhoneOS16.5.sdk/usr/lib/swift/*.tbd | wc -l -> 78 (incl. libswiftCore.tbd, libswiftFoundation.tbd, libswiftUIKit.tbd)
xybp888/iOS-SDKs contents: iPhoneOS10.3 ... iPhoneOS17.5, iPhoneOS18.0 ... iPhoneOS18.6.sdk (sparse checkout 126 MB). Its stdlib interface header: "// swift-compiler-version: Apple Swift version 6.1.2 effective-5.10 (swiftlang-6.1.2.1.2)". No iOS 26 SDK in that mirror.
```

### Four concrete gaps had to be closed to make it work; each has a cheap, legal fix. Nobody has written these down together, so record them.

Confidence: high

```
(1) The Linux toolchain's own lib/swift SHADOWS Darwin clang modules. Swift passes `-isystem <resource-dir>` so Dispatch/os/Block/CoreFoundation resolve to the Linux corelibs versions -> "no type named 'DispatchQueue' in module 'Dispatch'". Fix: build a Darwin-only resource dir (apinotes + clang resource dir + the SDK's own shims) and pass -resource-dir. That alone turned 118 errors into 0.
(2) Dispatch.apinotes and os.apinotes ship only in Xcode's toolchain — but they are in the open-source repo, Apache-2.0: https://github.com/swiftlang/swift/tree/main/apinotes (Dispatch.apinotes 9,795 B, os.apinotes 1,658 B).
(3) layouts-arm64.yaml (legacy type info) ships only in Xcode. "error: IR generation failure: Cannot read legacy layout file at .../resource/iphoneos/layouts-arm64.yaml". It is only consulted when the deployment target predates the ObjC metadata-update callback, and SwiftPM passes each dependency's OWN floor (I observed `-target arm64-apple-ios12.0` for swift-log). Fix: `-Xfrontend -disable-legacy-type-info`. Verified harmless: same module compiled rc=0 with the flag at ios12.0 and rc=0 without it at ios15.0.
(4) libswiftCompatibility56.a / libswiftCompatibilityPacks.a ship only in Xcode. At deployment target iOS 15: "ld64.lld: warning: auto-linked library not found for -lswiftCompatibility56" + undefined `_swift_FORCE_LOAD_$_swiftCompatibility56` -> link fails. At iOS 16.0 the link succeeds cleanly.
```

### HARD BLOCKER for the iOS 16.5 SDK: typed throws (`throws(E)`) reproducibly SEGFAULTS the Swift 6.2 compiler when targeting Darwin. The same three-line file compiles fine for Linux. This is compiler-vs-SDK-stdlib skew, not a setup mistake.

Confidence: high

```
Three-line repro (/tmp/cmail/swift-nomac/t2/v.swift):
public func f<T,E:Error>(_ b:() async throws(E)->T) async throws(E)->T { do { return try await b() } catch { throw error as! E } }
$ swiftc -target arm64-apple-ios13.0|15.0|16.0 -sdk iPhoneOS16.5.sdk ...   -> Segmentation fault (core dumped), rc=139, at every deployment target, in both -swift-version 5 and 6
Stack: #6 swift::Lowering::SILGenFunction::emitThrow(...)  #4 swift::DeclContext::getASTContext() const
Matrix: typed throws+async = CRASH; typed throws sync = CRASH; untyped throws+async = rc=0; async/await+Foundation = rc=0.
Cross-check on the real dependency: swift-log 1.15.1 Logger.swift compiled for LINUX rc=0 and for arm64-apple-ios rc=139 with identical flags. Root cause: the iOS 16.5 SDK's stdlib is Swift 5.8, which predates typed throws (Swift 6.0) entirely. Confirmed by re-testing the identical repro against the iPhoneOS18.6 SDK (Swift 6.1.2 stdlib): rc=0, 'Mach-O 64-bit arm64 object'.
```

### SwiftMail CANNOT be built this way today with any freely-available SDK. Its dependency graph requires a Swift 6.2 stdlib, which means the iOS 26 SDK, which means Xcode 26.

Confidence: high

```
Package.swift (github.com/Cocoanetics/SwiftMail) declares .iOS("15.0") and depends on swift-nio from 2.101.3, swift-nio-ssl from 2.37.1, swift-nio-imap from 0.3.0, swift-log, swift-collections, SwiftCross, swift-dotenv, swift-argument-parser, swift-testing exact 6.3.2.
Build against iPhoneOS18.6 SDK, unpinned (resolves nio 2.103.0): 731 errors.
Build against iPhoneOS18.6 SDK with nio pinned to SwiftMail's own minimum (.upToNextMinor(from: "2.101.3")) and collections 1.1.6: still 731 errors.
Unique error set: cannot find type 'Span' / 'RawSpan' / 'OutputSpan' / 'MutableRawSpan' / 'OutputRawSpan' / 'InlineArray' / 'SendableMetatype' / 'ExecutorJob' in scope. All of these are Swift 6.2 stdlib (or 5.9 for ExecutorJob) additions; they exist only in an iOS 26 SDK's Swift.swiftinterface.
Against iPhoneOS16.5 it is worse: 1,239 errors plus the typed-throws compiler crash.
```

### Good news buried in the bad: BoringSSL (the C/C++ half of swift-nio-ssl) cross-compiles cleanly. The failures are purely Swift-stdlib-version failures, not C/asm/Darwin-ABI failures.

Confidence: high

```
Build logs show hundreds of successful lines like '[218/386] Compiling rsa_asn1.cc', 'Compiling x509_trs.cc', 'Compiling x_spki.cc' for the CNIOBoringSSL target under --swift-sdk arm64-apple-ios, with zero C/C++ errors in any of the four build attempts (/tmp/cmail/swift-nomac/build18.log, build18b.log, swiftmail-build*.log).
```

### Theos cannot be the Swift vehicle here. Theos does have Swift rules, but there is no swift.mk and it expects a `swiftc` binary on PATH, which does not exist on the iPad.

Confidence: high

```
$ ls /var/jb/opt/theos/makefiles/  ->  instance legacy.mk library.mk master messages.mk null.mk package package.mk platform rules.mk simbltweak.mk stage.mk subproject.mk target.mk targets tool.mk tweak.mk vercmp.mk xcodeproj.mk   (no swift.mk)
makefiles/targets/_common/darwin_head.mk:13: _THEOS_TARGET_SWIFTC := swiftc
makefiles/targets/_common/darwin_tail.mk:55: _THEOS_TARGET_SWIFT_RESOURCE_DIR := $(dir $(shell type -p $(TARGET_SWIFTC)))../lib/swift
makefiles/common.mk:224: _THEOS_INTERNAL_SWIFTFLAGS = -DTHEOS_SWIFT ... -module-name ...
$ ls /var/jb/usr/bin/swift*  ->  No such file (only Apple's /usr/bin/swift-inspect from the OS)
So theos' Swift support presumes an Xcode-style toolchain that Procursus does not provide.
```

### The iPad is a usable fallback linker if the ld64.lld fork ever becomes a problem: it carries a real Apple ld64.

Confidence: medium

```
$ ipad-run '/var/jb/usr/bin/ld -v'
@(#)PROGRAM:ld-classic  PROJECT:ld64-951.9
configured to support archs: x86_64 ... arm64 arm64e arm64v8 arm64_32 riscv
Binaries present: ld, ld-classic, ld64, ldid, ldid2, clang-16, clang++-16. So a split pipeline (swiftc -c on Linux -> ship .o -> ld64 on the iPad) is available without the LLVM fork.
```

### macOS GitHub Actions for a private repo is cheap in dollars and expensive in operational fragility.

Confidence: high

```
GitHub docs (https://docs.github.com/en/billing/concepts/product-billing/github-actions): "macOS 3-core or 4-core (M1 or Intel) | actions_macos | $0.062" per minute; macOS 12-core $0.077; macOS 5-core (M2 Pro) $0.102. Linux 2-core $0.006. Included minutes per month for private repos: GitHub Free 2,000; Pro 3,000; Team 3,000; Enterprise Cloud 50,000 — macOS consumes these at roughly 10x (the docs page rendered the rates table but not an explicit multiplier column). A build of this size took ~60 s locally, so call it 3-6 min on a cold runner = $0.19-$0.37 per rebuild, i.e. a few dollars a year. The real cost is not money: the .p12 distribution identity and its password must live in GitHub secrets on a machine you do not own; the ad-hoc provisioning profile expires annually and the build silently starts producing un-installable IPAs when it does; Apple rotates the available Xcode images on the runners, which changes the compiler under you without warning; and the elderly user's mail client becomes un-rebuildable on any day GitHub's macOS pool is degraded.
```

### Licensing, not technology, is the soft spot on the Xcode.xip path. Apple's Xcode licence limits use to Apple-branded hardware; the community SDK mirrors redistribute Apple headers without permission.

Confidence: low

```
Observed, not adjudicated: xtool's own docs instruct you to log in with an Apple ID and download Xcode 26 to a Linux box, and xtool has 475 downloads on its latest x86_64 AppImage alone, so this is normal practice in the community. theos/sdks and xybp888/iOS-SDKs are public GitHub repos of extracted Apple SDKs. I am not a lawyer and did not read the current Xcode EULA text; it is a decision for the owner, who already ships ad-hoc builds under a real Apple Developer Program membership (Team JGLH7HX44Y).
```

**Risks noted:**

- Single point of failure: iOS-device Mach-O linking depends on ONE 43 MB prebuilt binary (ld64.lld) from one person's LLVM fork (kabiroberai/llvm-project), last released 2024-12-01. Upstream LLVM's lld still refuses iOS device targets in the Swift 6.2 build I tested. Mitigation: mirror the toolset tarball locally, and keep the iPad's real Apple ld64-951.9 as a documented fallback (compile .o on Linux, link on device).
- Compiler/SDK skew is the structural fragility of the whole approach, and it bites on dependency upgrades, not on your own code. A Swift 6.2 compiler against an iOS 18.6 SDK silently works until a dependency adopts a 6.2 stdlib type, then produces hundreds of 'cannot find type Span in scope' errors. Worse, against a 16.5 SDK it does not error, it SEGFAULTS. Any Swift plan must pin the whole dependency graph and treat `swift package update` as a release-gated operation.
- I did not run the produced binary on a device. The iPad was not modified during this work, so the artifacts were never bundled, signed with zsign, or launched. The load commands are correct and the signing/install pipeline is already proven for ObjC apps, but 'links correctly' is not the same as 'runs'. This is the single cheapest remaining validation: wrap /mnt/extra/cmail-swift/apptest/.build/arm64-apple-ios/release/ClassicMailApp in a .app with an Info.plist, zsign it, install over the existing OTA source.
- No actool. Asset catalogs (.xcassets) cannot be compiled on Linux. The spec's UI is entirely code-driven UIKit so this only affects the app icon and any bundled imagery, which must be loose PNGs referenced from Info.plist — already the solved pattern on this pipeline, but it does mean any Xcode-generated asset catalog in a future contribution is a dead end.
- `-Xfrontend -disable-legacy-type-info` is a workaround, not a fix. It is safe only because every real deployment target here is >= iOS 12.2; it is required only because SwiftPM passes each dependency package's OWN platform floor (I observed -target arm64-apple-ios12.0 for swift-log even with an iOS 15 root package). If a future dependency legitimately needs pre-12.2 back-deployment layouts this silently produces wrong code rather than an error.
- Legal/provenance: both the SDK (community-mirrored Apple headers) and the Xcode.xip route (Apple's licence limits Xcode to Apple-branded hardware) are unresolved questions I am not qualified to answer. Needs the owner's decision before this becomes the permanent build path for the end user's mail client.
- Operational risk of the GitHub Actions fallback is understated by its price. $0.062/min is trivial; putting the distribution .p12 in a cloud secret store, depending on a runner image whose Xcode version Apple and GitHub rotate without notice, and having an annually-expiring ad-hoc profile fail silently are not. For a daily-driver appliance owned by someone who cannot debug it, a local reproducible build is worth more than the money saved.
- Scratch state left on this host: /mnt/extra/cmail-swift (~5.4 GB: toolchain, two SDKs, two artifactbundles, build trees) and ~/.swiftpm (495 MB, contains the installed 'ios186' Swift SDK). /tmp/cmail/swift-nomac holds the small repros and logs.

---

## Investigation 2

**Verdict.** Rank for this project and this user: (1) **libetpan alone, driven straight from Objective-C** — it is actively maintained (last commit 2026-09-07), it is pure C, and it now ships a ready-made Apple `config.h` (`build-spm/config/config.h`) that selects the **CFNetwork TLS backend** and leaves OpenSSL, GnuTLS and Cyrus-SASL **undefined**, so on the theos SDK it needs nothing beyond `-lz -liconv -lxml2` plus CFNetwork/Security/CoreFoundation — all present in the sparse iPhoneOS16.5 SDK. (2) **MailCore2**, which is the nicer API (its `MCOIMAPSession` maps almost 1:1 onto ARCHITECTURE.md's `MailRepository`) and is also ObjC, but its *only* iOS build path is `xcodebuild` against four vendored deps, so you inherit a ~200-TU port plus stubbing ctemplate and tidy and patching its SMTP off `mailesmtp_auth_sasl`; promote it to #1 if a one-day spike gets `libMailCore.a` to link on the iPad. (3) **A private Gmail gateway** — the fastest path to a live-mail demo (a few days of ObjC over NSURLSession) and an excellent *second* `MailRepository` implementation, but wrong as the permanent transport: it filters the content of outgoing mail in ways that reject ordinary letters, its attachment cap is far below the 20 MB attachment the spec tests, it truncates large bodies, and it is Gmail-only. (4) **Hand-rolled IMAP** last: ~8.5k–11k lines of ObjC and a long correctness tail, against a spec whose quality bar is literally "no crashes on malformed MIME". Best combined answer: libetpan for IMAP, hand-rolled SMTP (~500 lines, genuinely easy), and the gateway kept behind the same repository protocol as a demo/fallback. **Caveat: I compiled nothing** — no SDK on this host, iPad untouched — so every "it will build" below is source inspection, not a green build.


### MailCore2 is not dead but is barely maintained: no tagged release since 0.6.4 (2020-08-01), a dead zone from 2022-11-08 to 2026-07-28, then a burst of ~8 commits by the original author (dinhvh / Hoa Dinh) on 2026-07-28/29. No GitHub Actions runs at all; the README still shows a travis-ci.org badge (travis-ci.org shut down in 2021). So nothing anywhere proves the iOS build works today.

Confidence: high

```
gh api repos/MailCore/mailcore2 → {"archived":false,"pushed_at":"2026-07-29T08:30:29Z","stargazers_count":2698,"open_issues_count":233}. Commits: 2026-07-29 dinhvh "Added build folder to gitignore" … 2026-07-28 dinhvh "Fix IMAP IDLE teardown races" | 2022-11-08 haithngn "Merge pull request #1951". Releases: 0.6.4 2020-08-01, 0.6.3 2018-06-04. `gh api repos/MailCore/mailcore2/actions/runs` → empty. https://github.com/MailCore/mailcore2
```

### MailCore2's iOS build system is xcodebuild and nothing else. There is a CMakeLists.txt but it is Linux/macOS-only (it calls `xcrun --sdk macosx` on Apple and has no iOS branch), and every iOS dependency is built by shelling out to `xcodebuild -project <dep>.xcodeproj -sdk iphoneos…`. Nothing in the repo produces an iOS artifact without Xcode.

Confidence: high

```
scripts/include.sh/build-dep.sh: `sdkversion="`xcodebuild -showsdks 2>/dev/null | grep iphoneos …`"` then `xcodebuild -project "$xcode_project" -sdk $sdk -scheme "$xcode_target" …`. scripts/build-libetpan-ios.sh sets `xcode_project="libetpan.xcodeproj"`, `xcode_target="libetpan ios"`. build-mac/README.md's only non-Xcode option is "Download the latest build for iOS" (a prebuilt .a from d.etpan.org). Package.swift is a `.binaryTarget` pointing at MailCore2-2020-09-24.xcframework.zip on a third party's fork (mattmaddux).
```

### But MailCore2 CAN be compiled by hand: the repo already contains a plain-make, non-Xcode build of the exact same core (build-android/jni/Android.mk, wildcard-based ndk-build). That file is a directly reusable template for a theos Makefile, and theos supports .cpp/.cc/.mm and SUBPROJECTS, so the language and build-system fit are fine.

Confidence: high

```
build-android/jni/Android.mk: `core_src_files := $(filter-out … $(wildcard $(src_dir)/core/basetypes/*.cpp) …)` over subdirs core/basetypes, core/imap, core/rfc822, core/smtp, async/imap, async/smtp. theos makefiles/instance/rules.mk: `_THEOS_CXX_FILE_TYPES = .mm .mii .cc .cp .cxx .cpp .ii .xm .xmi`, `OBJC_FILES = $(filter %.m %.mm …)`, `_SUBPROJECTS := …`. The proven local recipe is an earlier theos app's Makefile: `TARGET := iphone:clang:16.5:14.0`, `ARCHS := arm64`, `PACKAGE_FORMAT := ipa`.
```

### MailCore2's iOS dependency set reduces to FOUR external libraries, and on Apple two of them (ICU, OpenSSL) vanish entirely. Link line for iOS is `-lctemplate-ios -letpan-ios -lxml2 -lsasl2 -liconv -ltidy -lz -ObjC -lresolv`. Of those, libxml2/libiconv/libz/libresolv are shipped by the theos sparse SDK; libetpan, ctemplate, tidy-html5 and cyrus-sasl are not.

Confidence: high

```
build-mac/mailcore2.xcodeproj/project.pbxproj OTHER_LDFLAGS (iOS config) exactly as quoted; IOS_HEADERS_SEARCH_PATHS = "…/src/core/basetypes/icu-ucsdet/include …/Externals/libetpan-ios/include …/Externals/ctemplate-ios/include …/Externals/tidy-html5-ios/include/tidy /usr/include/libxml2". `gh api repos/theos/sdks/contents/iPhoneOS16.5.sdk/usr/lib` → libxml2.tbd, libiconv.tbd, libz.tbd, libresolv.tbd, libicucore.tbd, libsqlite3.tbd present; **no libsasl2**. usr/include has libxml2/, iconv.h, zlib.h, resolv.h, unicode/. System/Library/Frameworks has CFNetwork, Security, CoreFoundation, Foundation, UIKit, WebKit, QuickLook, Network.
```

### ICU is a non-problem on Apple. MCString.cpp hard-defines `DISABLE_ICU 1` under `#if __APPLE__` and routes case-folding/comparison/charset conversion through CoreFoundation; every ucnv_/uregex_/udat_ call site is inside a non-Apple or _MSC_VER branch. The only ICU left is a 22-file in-tree subset (src/core/basetypes/icu-ucsdet) that ships with the repo and is already in the Xcode target.

Confidence: high

```
src/core/basetypes/MCString.cpp lines 5-7: `#if __APPLE__` / `#define DISABLE_ICU 1` / `#endif`. `ucnv_open` at lines 1380 and 2270 both sit inside `#else` arms of `#if __APPLE__` blocks (1316/1371/1406 and 2234/2260/2298). MCMailProvider.cpp's `uregex_open` (line 207) is inside `#ifdef _MSC_VER` (204) — the POSIX arm at 227 uses <regex.h>. MCDateFormatter.cpp's `udat_open` (256) is inside `#else` of `#if USE_COREFOUNDATION` (206/233/261). `ls src/core/basetypes/icu-ucsdet` → 22 .c/.cpp + include/unicode/*.h; pbxproj references them (grep -c 'csdetect.cpp\|ucsdet.cpp' = 12).
```

### OpenSSL is also a non-problem on Apple: MailCore2 validates certificates through Security.framework, and libetpan does TLS through a CFNetwork/CFStream backend that MailCore2 explicitly turns on at init. So neither library needs a cross-built OpenSSL for iOS.

Confidence: high

```
src/core/security/MCCertificateUtils.cpp: `#if __APPLE__ / #include <Security/Security.h> / #else / #include <openssl/x509.h> …`, and the Apple arm uses SecPolicyRef/SecTrustRef. src/core/basetypes/MCLibetpan.cpp INITIALIZE(Libetpan): `// It will enable CFStream on platforms that supports it.` `mailstream_cfstream_enabled = 1;`. libetpan src/data-types/mailstream_ssl.c dispatches `#if HAVE_CFNETWORK … #elif defined(HAVE_OPENSSL)`; src/data-types/mailstream_cfstream.c exists.
```

### Cyrus-SASL is avoidable with a ~10-line patch. libetpan compiles fine with USE_SASL undefined and implements AUTH LOGIN/PLAIN/CRAM-MD5 itself, and MailCore2's IMAP default path already uses plain `mailimap_login`. Only MailCore2's SMTP goes through `mailesmtp_auth_sasl` unconditionally, so that one call site must be swapped to `mailsmtp_auth()`.

Confidence: high

```
libetpan src/low-level/smtp/mailsmtp.c line 971 `#ifndef USE_SASL` guards `static int mailsmtp_auth_login(mailsmtp*, const char*, const char*)`; public `int mailsmtp_auth(mailsmtp*, const char*, const char*)` at line 1196, `mailesmtp_auth_sasl` at 1525. mailcore2 src/core/imap/MCIMAPSession.cpp:830 `r = mailimap_login(mImap, utf8username, utf8password);` for the default auth type. mailcore2 src/core/smtp/MCSMTPSession.cpp:529/547/575 all `mailesmtp_auth_sasl(mSmtp, "PLAIN"/"LOGIN"/…)`.
```

### ctemplate and tidy-html5 are reachable only from two small files (759 lines combined) that this app does not need, because ARCHITECTURE.md already says render htmlBody directly in WKWebView. Excluding or stubbing MCHTMLRenderer.cpp and MCHTMLCleaner.cpp removes two whole cross-builds; libxml2's HTMLparser (already linked) can back a replacement cleaner.

Confidence: medium

```
grep -rl ctemplate src → only src/core/renderer/MCHTMLRenderer.cpp (625 lines, 9 ctemplate refs) and src/objc/abstract/MCOHTMLRendererDelegate.h. grep -rl tidy src → only src/core/basetypes/MCHTMLCleaner.cpp (134 lines). MCHTMLCleaner is called from MCString.cpp (flatten-HTML path used for list previews), so that one needs a replacement rather than plain deletion. ARCHITECTURE.md line 60: "Use `WKWebView` with: remote content blocked by default if feasible…".
```

### libetpan is the most actively maintained thing in this whole stack and ships a prebuilt Apple config.h, which removes the autotools/cross-compile question entirely — you do not need to run ./configure at all, on Linux or on the iPad.

Confidence: high

```
gh api repos/dinhviethoa/libetpan → pushed_at 2026-09-07T00:47:47Z; recent commits include 2026-09-07 "Fix out-of-bounds read in IMF address parsing", 2026-08-21 "Add STARTTLS roundtrip XCTest coverage". build-spm/config/config.h: `#define HAVE_CFNETWORK 1`, `#define HAVE_ICONV 1`, `#define HAVE_ZLIB 1`, `/* #undef USE_SASL */`, `/* #undef HAVE_OPENSSL */`, `/* #undef HAVE_GNUTLS */`. Package.swift cSettings: `.define("HAVE_CONFIG_H","1")`, `.define("HAVE_CFNETWORK","1")`, `.define("HAVE_COREFOUNDATION_CHARCONV","1")` plus ~35 headerSearchPath entries; linkedFramework CFNetwork/CoreFoundation/Foundation/Security. 200 .c files are listed explicitly in the `sources:` array — a ready-made build file list.
```

### MailCore2 pins libetpan at a 2017 commit, so taking MailCore2 as-published means shipping 9-year-old C parsers for untrusted input. Use libetpan HEAD instead: mailcore2 master already requires it (src/core/activesync includes <libetpan/mailactivesync.h>, which only exists at HEAD), and HEAD is where the memory-safety fixes land.

Confidence: high

```
scripts/build-libetpan-ios.sh: `rev=5164ba2ebd3c7cbc7a9230aad32bdf8e24e207de`; `gh api repos/dinhviethoa/libetpan/commits/5164ba2…` → date 2017-03-23. mc2 src/core/activesync/MCActiveSyncSession.cpp:7 `#include <libetpan/mailactivesync.h>`; that header exists only in current libetpan (build-spm/include/libetpan/mailactivesync.h, src/low-level/activesync/). Both licences are BSD (mc2 LICENSE, etpan COPYRIGHT) — no copyleft trap.
```

### Realistic theos build size: ~400 translation units for a trimmed MailCore2, ~200 for libetpan alone. That is a few minutes of clang on an M1-class iPad, not a heavy build.

Confidence: medium

```
In mc2: core .cpp/.c excluding activesync, zip, nntp, pop, Win32, GTK = 88 files (of which 22 are icu-ucsdet); async/imap + async/smtp = 41; src/objc excluding nntp/pop/activesync = 69 .mm; src/ui/ios + src/ui/common = 3 .mm. Total 201. libetpan Package.swift lists 200 .c. LOC anchors: mc2 src/core+src/objc+src/async = 107,175 lines; libetpan src/low-level/imap = 45,439, imf = 14,866, mime = 11,374, smtp = 3,296.
```

### Effort estimate, MailCore2 on theos: 2-5 days to a first linking libMailCore.a, plus 2-4 days of shakeout against a real IMAP server — call it 1-2 weeks of one engineer, with a real tail risk that 2013-era C++ trips clang-16/modern-libc++ strictness (the only unknown I could not retire without compiling). libetpan alone: 1-3 days to a linking .a, because it is C, the file list and config.h are handed to you, and there are zero sub-dependencies to build.

Confidence: low

```
Derived from the above: mc2 needs (a) theos Makefiles for 401 TUs, (b) the mailesmtp_auth_sasl→mailsmtp_auth patch, (c) ctemplate/tidy stubs, (d) exclusion lists for activesync/nntp/pop/java/zip, (e) -DU_COMMON_IMPLEMENTATION=1 + the icu-ucsdet include path. libetpan needs only the Package.swift `sources:` list, build-spm/config + build-spm/include on the header path, and three -D flags. No compile was attempted on either (no iOS SDK on this host; the iPad was not used).
```

### Minimum IMAP command set for PRODUCT_SPEC.md's v1 is genuinely small — about 14 commands. CAPABILITY; LOGIN (or AUTHENTICATE PLAIN/XOAUTH2); LIST "" "*" with SPECIAL-USE (fall back to XLIST on Gmail) for the mailbox pane and role detection; STATUS (MESSAGES UNSEEN UIDNEXT UIDVALIDITY) for unread badges; SELECT / EXAMINE; UID FETCH n:* (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE) for the list, plus UID FETCH BODY.PEEK[<part>]<0.2048> for previews and BODY.PEEK[<part>] for bodies/attachments; UID STORE +/-FLAGS.SILENT (\Seen) and (\Flagged); UID MOVE (RFC 6851) with a UID COPY + UID STORE +FLAGS \Deleted + UID EXPUNGE (UIDPLUS) fallback and a bare EXPUNGE fallback under that; APPEND for Drafts and for Sent-reconciliation; UID SEARCH; IDLE/DONE; LOGOUT/NOOP. SMTP is EHLO, STARTTLS, EHLO again, AUTH LOGIN|PLAIN, MAIL FROM, RCPT TO, DATA with dot-stuffing, QUIT.

Confidence: high

```
Mapped from docs/PRODUCT_SPEC.md "Required features — v1" (lines 51-69: folder listing, inbox sync, read/unread, flag, compose/reply/reply-all/forward, delete, move, Sent, Drafts, Trash, attachments, search current mailbox, cached offline) and docs/IMPLEMENTATION_PLAN.md Phase 4 (LIST, special-use, SELECT, fetch headers, fetch full, STORE, MOVE/delete, APPEND) and Phase 5. ARCHITECTURE.md line 73 asks for IDLE while active but explicitly does not promise background connectivity.
```

### Hand-rolled engine size: ~8,500-11,000 lines of Objective-C, because iOS gives you only two of the six hard pieces. You get base64 (NSData) and charset conversion (CFStringConvertIANACharSetNameToEncoding → NSStringEncoding, which covers ISO-2022-JP, GB18030, Big5, KOI8-R and mUTF-7 via kCFStringEncodingUTF7_IMAP). You get nothing for quoted-printable, RFC 2047 encoded words, RFC 5322 address parsing, MIME multipart, or BODYSTRUCTURE. Compare: emersion/go-imap is 14,122 non-test lines (imapclient alone 5,375) and go-message only 2,842 — and Go's stdlib hands it mime/quotedprintable, mime.WordDecoder, mime/multipart and net/mail, all of which you would be writing yourself.

Confidence: medium

```
git clone --depth 1 emersion/go-imap → `find … ! -name '*_test.go' | xargs wc -l` = 14122 total; goimap/imapclient = 5375; goimap/internal = 1835. emersion/go-message = 2842 total, charset/charset.go = 64 lines (it just wires to x/text). Breakdown estimate: wire/literal reader ~800, response parser incl. BODYSTRUCTURE/ENVELOPE ~2000-2500, command+session+IDLE+reconnect ~1200, SMTP ~500, MIME/RFC2047/RFC2231/QP ~2000-2500, RFC5322 builder ~600, address parser ~400, dates ~200, TLS transport+trust+timeouts ~600.
```

### Top 5 places a hand-rolled IMAP client goes wrong, in the order they will actually bite: (1) LITERALS AND THE READER — `{123}\r\n` octet-counted literals appear inside astrings anywhere in LIST/FETCH/SEARCH responses, plus LITERAL+/LITERAL- non-synchronising forms and untagged EXISTS/EXPUNGE/FETCH arriving mid-stream; one miscount desyncs the connection and the corruption surfaces minutes later somewhere unrelated. (2) BODYSTRUCTURE — deeply nested, BODY and BODYSTRUCTURE differ in extension data, servers emit NIL in surprising slots, message/rfc822 parts nest an ENVELOPE + body + line-count, and RFC 3501 §6.4.5 part numbering is subtle (a single-part message's body is "1"; inner parts of an embedded message are "1.1"); get the path wrong and you silently download the wrong bytes. (3) RFC 2047 + CHARSETS — adjacent encoded words must be concatenated BEFORE decoding or you split a multi-byte rune, charsets are routinely mislabelled (windows-1252 as us-ascii), base64 words arrive without padding, and filenames use RFC 2231 continuations (`filename*0*=utf-8''…`); the visible symptom is mojibake subjects and attachment names. (4) UID/STATE BOOKKEEPING — a UIDVALIDITY change must nuke the whole cache, EXPUNGE renumbers sequence numbers under you (so UIDs everywhere, never sequence numbers), no CONDSTORE/QRESYNC means full re-sync, and Gmail's All Mail makes "move out of INBOX" a label removal rather than a move, which breaks optimistic-UI reconciliation. (5) TLS AND CONNECTION LIFECYCLE — real certificate validation (not a permissive trust callback), STARTTLS downgrade protection, and the iPadOS-specific one: the app is suspended, the IDLE socket dies silently, and with no timeout the user gets a spinner forever, which to this user reads as "the app is broken". Sixth, cheap to get wrong: SMTP DATA dot-stuffing and bare-LF normalisation.

Confidence: medium

```
Failure modes derived from the protocol requirements and cross-checked against the size of the code that exists to handle them: libetpan src/low-level/imap = 45,439 lines and src/low-level/imf = 14,866 lines are almost entirely this problem. Concretely in-repo: libetpan's most recent commit is 2026-09-07 "Fix out-of-bounds read in IMF address parsing" — a memory-safety bug in header parsing found in a 25-year-old, widely deployed parser.
```

### Gateway option: a private Gmail gateway was considered and rejected as the permanent transport, because it is Gmail-only, caps attachment and body sizes well below what the spec tests, and filters the content of outgoing mail in ways that reject ordinary letters.

Confidence: high

```
Basis: the gateway's own documentation and source, read directly.
```

### The spec's own preferred engine, SwiftMail, is simply unavailable here and nothing in the research changes that; but ARCHITECTURE.md's MailRepository protocol is exactly the seam that makes all four options interchangeable, so the mock-first milestone in BRIEF.md is unaffected by which one wins.

Confidence: high

```
docs/ARCHITECTURE.md lines 28-44 define `protocol MailRepository` with listMailboxes/listMessages/loadMessage/markRead/move/delete/send/saveDraft and name two implementations (MockMailRepository, SwiftMailRepository). BRIEF.md line 47: "Only after visual approval should you wire IMAP/SMTP." The starter tree already has Mail/MailRepository.swift + Mail/MockMailRepository.swift. Not re-checked here: no swiftc on the iPad, in Procursus, or on the Linux host.
```

**Risks noted:**

- I compiled nothing. There is no iOS SDK on this Linux host and the iPad was not used, so every claim of the form 'this will build' is inference from reading source, build files and the theos sparse-SDK manifest. The single highest-value next step is a one-day spike on the iPad: compile libetpan's 200 .c files with the three -D flags above and see if a .a falls out. If it does, do the same for MailCore2's 201 files.
- MailCore2's C++ is 2013-era and was last built in anger against Xcode 13 (commit 'Fixed build for Xcode 13+', 2022-06-28). clang-16 with a modern libc++ may reject things older clangs accepted (dynamic exception specifications, narrowing conversions, OSSpinLock deprecation warnings-as-errors). Unknown until compiled; budget an extra week if the first link-through goes badly.
- MailCore2 master now contains src/core/activesync, which only compiles against libetpan HEAD, while scripts/ still pin libetpan at a 2017 commit. Nobody has built this combination on iOS — there is no CI on the repo at all. Excluding activesync and using libetpan HEAD is my recommendation but it is an untested combination.
- I could not verify whether Gmail still accepts app-specific passwords for IMAP/SMTP in 2026. If Google has retired them for consumer accounts, options 1, 2 and 4 all need XOAUTH2 with a registered iOS OAuth client and a device/loopback flow, which is a substantial extra chunk of work and shifts the ranking materially toward the gateway. Verify this BEFORE committing to an engine; docs/SECURITY_AND_AUTH.md line 30 already flags the equivalent question for iCloud.
- Nobody has established which mailbox this is. If it is not one of the owner's Gmail accounts, option 3 needs an OAuth consent from a third party; if it is not Gmail at all, option 3 is dead. Confirm the provider before any of this ranking is actionable.
- libetpan is C parsing hostile network input, and a fresh out-of-bounds read in IMF address parsing was fixed on 2026-09-07. Options 1 and 2 both inherit that exposure. For a sandboxed single-user app that is acceptable, but it argues for tracking libetpan HEAD rather than pinning, and against the 2017 revision MailCore2 ships with.
- theos SUBPROJECTS support is documented in makefiles/instance/rules.mk but I have not seen it used for a 200-file C library on this pipeline. A plainer fallback is a hand-written Makefile that produces libetpan.a and libMailCore.a, with the theos app Makefile just adding them via _LDFLAGS — less elegant, fewer unknowns.
- The sparse SDK I inspected is theos/sdks' published iPhoneOS16.5.sdk, not literally the copy at /var/jb/opt/theos/sdks/iPhoneOS16.5.sdk on the iPad. They are almost certainly the same artifact, but the libxml2/iconv/z/resolv availability claim rests on that assumption and takes ten seconds to confirm on the device.

---

## Investigation 3

**Verdict.** The primary reference URL is alive, and better: the same IDG CDN path with the `-orig.png` suffix returns the **untouched 2732x2048 device capture** (the `?auto=webp` "large" variant is only 580x435), so 1 image pixel = exactly 0.5 pt on a 1366x1024 pt canvas and every number below is a direct pixel read, not a guess. Provenance is solid — the article is Caitlin McGarry, Macworld, 7 Jul 2016, and the screenshot's own detail header reads "To: Caitlin McGarry", i.e. it is the author's own iOS 10 iPad Pro. Measured: panes are 287 / 375 / 703 pt separated by two solid 0.5 pt #8E8E93 hairlines; mailbox rows pitch 44.5 pt, message rows pitch exactly 104.0 pt; all top chrome is 20 pt status + 44 pt bar = 64 pt; selection is #D9D9D9 full-bleed with black text; the unread dot is 12.0 pt of #007AFF with its left edge 8 pt from the pane edge. Type resolves cleanly to the classic iOS ladder (17 / 15 / 22 / 12 / 11 pt) because a known 17 pt cap measures exactly 24 px, giving a 1.4092 px-per-pt cap calibration that every other run agrees with to within 1 px. Two findings contradict the handed-down UI_SPEC and matter: the sender line is semibold for **read and unread alike** (unread is signalled by the dot only), and the toolbar order the spec guesses at (flag, move, delete, reply, compose) is exactly what the pixels show. The only fabricated-risk numbers I refused to invent are UIBarButtonItem frames (I report glyph ink boxes), and whether Apple's pane widths were fixed points or fractions — one screenshot cannot distinguish those.


### The primary reference URL is NOT dead, and an undocumented `-orig.png` variant of the same asset returns the native 2732x2048 capture — the exact 2x of a 12.9" iPad Pro landscape canvas, so measurement is exact at 0.5 pt granularity. The URL in REFERENCE_SCREENSHOTS.md returns only a 580x435 downscale.

Confidence: high

```
$ curl ... 'https://images.techhive.com/images/article/2016/07/ios-10-ipad-mail-100669665-large.png?auto=webp&quality=85%2C70' -> HTTP 200, PNG 580 x 435.
$ curl 'https://images.techhive.com/images/article/2016/07/ios-10-ipad-mail-100669665-orig.png' -> HTTP 200, 1675350 bytes, 'PNG image data, 2732 x 2048, 8-bit/color RGB, non-interlaced'.
sha256 = 1fa636e3197cbefdebaf34551916d07891d4a7453f6e65110d8a152080e15c5f. Saved at /tmp/cmail/visual/ios10_ipad_mail_orig.png
```

### Provenance: the shot is the Macworld author's own device, not a mockup or a render. The article is by Caitlin McGarry (7 Jul 2016) and the screenshot's message-detail header reads 'To: Caitlin McGarry'. Combined with the exact native 2732x2048 dimensions, this is an authentic unscaled iOS 10 12.9" iPad Pro capture.

Confidence: high

```
Fetched https://www.macworld.com/article/228321/ios-10-on-the-ipad-pro-the-8-features-you-need-to-know.html -> 'Author and Date: Caitlin McGarry, July 7, 2016'. OCR/visual read of pane C header in the image: 'Gilt City NYC / To: Caitlin McGarry'.
```

### MEASURED — pane widths. Two vertical divider columns at x=574 px and x=1325 px, each exactly 1 device px wide with ZERO variance over 1500 sampled rows. Pane A = 287.0 pt (0.21010 W), divider 0.5 pt, pane B = 375.0 pt (0.27452 W), divider 0.5 pt, pane C = 703.0 pt (0.51464 W). Sums to 1366.0 pt exactly.

Confidence: high

```
Method: for every column x, mean and per-channel std over the content band y=400..1900; keep columns with std<6 and mean<250.
Output: 'x=574..574 (w=1) meanRGB=[142. 142. 147.] std=[2.36]' and 'x=1325..1325 (w=1) meanRGB=[142. 142. 147.] std=[2.36]'.
Per-channel: 'x=574 mean=[142. 142. 147.] median=[142. 142. 147.] std=[0. 0. 0.]'.
Neighbour columns 573/575 and 1324/1326 are white (255). Script /tmp/cmail/visual/m1.py, m2.py
```

### MEASURED — pane divider colour is SOLID #8E8E93 (142,142,147), not a translucent overlay. It reads identically over a white row and over a #D9D9D9 selected row, so it is an opaque line, and it is the only non-neutral grey in the chrome.

Confidence: high

```
a[500,574]=[142 142 147] on white; a[800,574]=[142 142 147] with a[800,575]=[217 217 217] (selected-row grey) immediately to its right. std over 1500 rows = 0.00 on all three channels.
```

### MEASURED — mailbox list (pane A) row pitch is 89 px = 44.5 pt, with the first row of each section 88 px = 44.0 pt. Mean over the 17-row second section = 88.94 px = 44.47 pt. Practical construction: a 44 pt row plus a 0.5 pt separator drawn BELOW it.

Confidence: high

```
Separator y-positions detected as rows >=40% exact #C8C7CC across x 0..573: 184, 272, 361 | 418, 506, (595), (684), 773, 862, 951, 1040, 1129, 1218, 1307, 1396, 1485, 1574, 1663, 1752, 1841, 1930. Deltas from a blank-column darkness-minimum detector (x 330..500): [88, 89, ..., 88, 89, 89, 89, ...]. 1930-418 = 1512 px / 17 rows = 88.94 px. The two parenthesised separators are hidden under the selected 'Junk' row. Scripts m4.py, and the blank-column rerun.
```

### MEASURED — message list (pane B) row pitch is EXACTLY 208 px = 104.0 pt, uniform, no jitter at all.

Confidence: high

```
Separator rows (>=35% #C8C7CC across x 575..1324): 423, 1047, 1255, 1463, 1671, 1879 — all deltas exactly 208 px; 423->1047 = 624 = 3 x 208 with 631 and 839 hidden under the selected 'Gilt City NYC' row. First row runs 216..423 = 208 px (search bar bottom hairline is at y=215). Script /tmp/cmail/visual/m5.py
```

### MEASURED — list separator colour is the classic #C8C7CC (200,199,204) EXACTLY, 0.5 pt, in BOTH pane A and pane B. Pane C's message-header rules are a DIFFERENT, neutral grey #C8C8C8 (200,200,200). Do not use one for the other.

Confidence: high

```
Counter over a[1047,700:1300] -> [((200,199,204), 600)] (pane B). Counter over a[1218,200:560] -> [((200,199,204), 360)] (pane A). Pane C rules at y=224, 372, 655 -> [((200,200,200), 1406)] / [((200,200,200), 1364)].
```

### MEASURED — separator left insets, per pane: pane A top-level mailbox rows 55.0 pt; pane A indented sub-folder rows 86.0 pt (indent step 31.0 pt); pane B message rows 29.0 pt; pane C header rules 21.0 pt. All separators run flush to their pane's right edge (no right inset).

Confidence: high

```
First #C8C7CC pixel per separator row, pane-relative: pane A 'xfirst=110 (pt 55.0)' for Inbox/Drafts/Sent/Junk/Trash/[Gmail]/Boyfriend/Notes/Personal/Receipts/Recipes; 'xfirst=172 (pt 86.0)' for Important/Starred/BFFs/Bills and Finance/Shopping. Pane B 'inset=29.0pt' on every row. Pane C: a[372,1367]=(255,255,255), a[372,1368]=(200,200,200) -> 1368 px = 684.0 pt abs = 21.0 pt pane-relative. Separator right end = 286.5 pt (pane A) / 374.5 pt (pane B), i.e. the last pixel before the divider.
```

### MEASURED — selection highlight is #D9D9D9 (217,217,217), full-bleed edge-to-edge across the pane, and the row's text STAYS BLACK. Identical in both panes. The separators above and below a selected row are suppressed.

Confidence: high

```
Counter over pane A 'Junk' row a[600:680,300:560] -> [((217,217,217), 20529), ((128,128,128), 116)]. Counter over pane B 'Gilt City NYC' row a[650:830,700:1300] -> [((217,217,217), 91537), ((142,142,142), 4171), ((0,0,0), 2477)]. Text ink in both is (0,0,0). The #C8C7CC detector finds no separator at y=631/839 or y=595/684, confirming suppression under the grey.
```

### MEASURED — the unread dot is #007AFF (0,122,255), 24 px = 12.0 pt diameter, left edge 8.0 pt from the pane's left edge, centre x = 14.0 pt, centre y = 21.75 pt below the row top (vertically centred on the sender line's cap height).

Confidence: high

```
Blue-pixel mask ((b>200)&(r<120)&(g<170)&(b-r>90)) over row 1: bbox x 591..614 (24 px), y 248..271 (24 px). Centre pixel value = [0 122 255]. 460 blue pixels -> area-equivalent diameter 12.10 pt, confirming a true circle. Pane B origin x=575 px, so 591 px -> (591-575)/2 = 8.0 pt. Row top 216 px -> dot centre (248+272)/2 = 260 px -> (260-216)/2 = 22.0 pt. Script /tmp/cmail/visual/g3.py
```

### MEASURED — type scale, calibrated against a known anchor. A flat capital 'I' in 'Inbox' measures 24 px cap height; iOS table cell text is 17 pt, giving 1.4092 px-per-pt of cap height (SF capHeight ratio 1443/2048 = 0.7046 predicts 23.96 px — a match to 0.04 px). Every other run was then read against that. Results: nav title 17 semibold, bar button 17, mailbox name 17, unread count 17, list sender 17 semibold, subject 15, preview 15, timestamp 15, detail sender 17 semibold, detail To:/Details/date 15, detail subject 22 bold, status bar 12 semibold, toolbar status line 11.

Confidence: high

```
Pane A 'I' of Inbox: ink y 216..239 = 24 px; 'n' x-height y 222..239 = 18 px; 'M' of Mailboxes 24 px; 'E' of Edit 24 px; '6' unread count 24 px — all -> 17.03 pt.
Pane B flat caps: 'M' of Misfit 24 px, 'T'/'M'/'I' of TUMI 24 px, 'N'/'Y' of 'Gilt City NYC' 24 px, flat 'w' of 'west elm' x-height 18 px -> 17.00 pt.
Subject flat caps: 'A' of Alpha 21 px, 'N','E','W' 21 px, 'U' of Up 21 px, x-height 16 px -> 14.87 / 15.11 pt.
Preview 'A' of Additional 21 px, x-height 16 px -> 15 pt. Timestamp '1' 21 px, 'A' of AM 21 px -> 14.90 pt.
Detail subject flat caps 'A' of An 31 px, 'E' of Extra 31 px, 'T' of The 31 px, 'A' of Adventure 31 px, x-height 24 px -> 21.99 pt = 22 pt (round caps O/S/C measure 33 px from overshoot; do not use those).
Status bar digits 17 px -> 12.06 pt. Toolbar 'N' of Now 16 px cap + flat 'w' 12 px x-height -> 11.33 / 11.35 pt.
```

### MEASURED and CONTRADICTS THE SPEC — the message-list sender line is SEMIBOLD for read rows too. UI_SPEC.md says 'Sender on first line, semibold for unread'; in the reference the only read row ('Gilt City NYC', no blue dot) is rendered at identical weight to the unread rows. Unread is signalled by the blue dot ALONE. Both are clearly heavier than pane A's regular-weight 'Inbox'.

Confidence: medium

```
Horizontal stem widths at mid-cap: 'i' of 'Gilt' = 5 px and 'l' of 'Gilt' = 5 px (read row); 'i' of 'Misfit' = 5 px and 5 px (unread row); 'I' of pane A 'Inbox' = 3 px (regular). Ink density in the glyph bbox: Inbox 0.2682, Gap 0.3984, Gilt City NYC 0.3823, Misfit 0.4139. 3x zoom stack of all three lines (/tmp/cmail/visual/z_cmp.png) shows Gilt City NYC and Misfit at matching weight, both visibly heavier than Inbox. CAVEAT: only ONE read row is visible in the shot, so n=1 for the read case.
```

### MEASURED — top chrome is 20 pt status bar + 44 pt navigation/toolbar = 64.0 pt total, with the bar fill running continuously behind the status bar and a 0.5 pt bottom hairline that is BLACK AT 30% ALPHA, not a fixed colour.

Confidence: high

```
Bar fill is unbroken from y=0 to y=127 px in all three panes (no internal hairline). Hairline at y=128 px = 64.0 pt. Over white content (pane C) it reads (178,178,178): (255-178)/255 = 0.302. Over #EFEFF4 content (pane A) it reads (167,167,171): (239-167)/239 = 0.301. Same alpha, different substrate -> translucent black.
Cross-check on the 20/44 split: the 17 pt semibold nav title's baseline is at y=96 px = 48.0 pt; a 44 pt bar spanning 20..64 pt has centre 42 pt, and 42 + capHeight/2 (=6.0) = 48.0. Exact.
```

### MEASURED — the nav/toolbar fill is TRANSLUCENT, so there is no single correct opaque value. Over white content it is #F9F9F9; over the #EFEFF4 grouped-table gap in pane A the same bar reads #F5F5F8/#F6F6F8. For a frozen opaque clone, hard-code #F9F9F9.

Confidence: high

```
Counter over pane B bar a[100:120,760:1100] -> [((249,249,249), 6800)]. Same for pane C. Counter over pane A bar a[100:120,330:470] -> [((246,246,248), 1556), ((245,245,248), 1244)].
```

### MEASURED — panes A and B each carry a 44 pt BOTTOM toolbar; pane C does NOT (its reading canvas runs to the screen edge). Top hairline at y=979.5 pt, same black-at-30% treatment.

Confidence: high

```
Vertical profile at x=300 (pane A): 'y 1950..1958 (255,255,255) | y 1959 (178,178,178) | y 1960..2047 (248,248,248)' -> bar from 980.0 to 1024.0 pt = 44.0 pt. At x=1100 (pane B): 'y 1959 (178,178,178) | y 1960..1997 (245,245,245) | y 1998..2047 (246,246,246)'. At x=2000 and x=2600 (pane C): no hairline, no bar; email body pixels continue to y=2047.
```

### MEASURED — pane B's search bar: container 43.0 pt tall filled #C9C9CE (201,201,206), containing a 28.0 pt tall white rounded field inset 8 pt on both sides (359 pt wide), vertically centred; 0.5 pt bottom hairline; the list starts at y = 108.0 pt.

Confidence: high

```
Vertical profile at x=600: 'y 128 (178,178,178) | y 129..143 (201,201,206) | y 145..198 (255,255,255) | y 200..214 (201,201,206) | y 215 (181,181,181) | y 216.. (255,255,255)'. Container y 129..214 px = 64.5..107.5 pt = 43.0 pt. White field at y=170: pane-relative x 8.0..367.0 pt, width 359.0 pt. Field centre (144+199)/2 = 171.5 px == container centre (129+214)/2 = 171.5 px.
```

### MEASURED — message-cell internal layout, as baselines below the row top: sender 27.5 pt, subject 48.0 pt, preview line 1 67.5 pt, preview line 2 87.5 pt; 16.5 pt of padding below the last baseline. Text column left edge 29.0 pt (identical to the separator inset), right edge 359 pt (16 pt right inset). Timestamp sits on the sender baseline, right-aligned.

Confidence: high

```
Row 8 (TUMI, top y=1672 px) flat-bottom glyph bottoms: 'T' 1726 -> baseline 1727 (rel 55 px = 27.5 pt); 'A' of Alpha 1767 -> 1768 (rel 96 px = 48.0 pt); 'A' of Additional 1806 -> 1807 (rel 135 px = 67.5 pt); 'T' of 'To view' 1846 -> 1847 (rel 175 px = 87.5 pt). Same offsets recover on rows 1-8 via the line-band scan: [(29,61),(73,101),(112,140),(152,181)] consistently.
Left: sender ink starts x=632-633 px -> 28.5-29.0 pt pane-relative, matching the 29.0 pt separator inset.
Right: timestamp ink right edge 358.0-358.5 pt on all 5 rows sampled; truncated-subject ellipsis right edge 356.5-357.0 pt -> container edge 359 pt, inset 16 pt.
```

### MEASURED — text colours. Sender #000000, subject #000000, preview #8E8E8E (142,142,142), timestamp #8E8E8E, mailbox name #000000, mailbox unread count #808080 (128,128,128), toolbar 'Updated Just Now' #000000, toolbar 'n Unread' #8E8E93 (142,142,147). Note THREE distinct greys in play: #8E8E8E, #808080 and #8E8E93.

Confidence: high

```
Counter over each ink region: sender [((0,0,0),445)]; timestamp [((142,142,142),452)]; subject [((0,0,0),473)]; preview [((142,142,142),551)]; mailbox name [((0,0,0),350)]; unread count [((128,128,128),113)]; 'Updated Just Now' [((0,0,0),294)]; '9 Unread' [((142,142,147),151)].
```

### MEASURED — pane C detail header. Mailing-list banner 47.5 pt tall filled #F3F3F8 (243,243,248) with a 0.5 pt #C8C8C8 bottom rule; banner title 13 pt semibold, 'Unsubscribe' 13 pt #007AFF. Sender name 17 pt semibold (baseline 144.5 pt), To-line 15 pt (baseline 166.5 pt), blue 'Details' 15 pt right-aligned to 1300 pt, grey avatar circle 36 x 36 pt with its right edge 10 pt from the screen edge (centre y 148.5 pt). Header rule at y=186.0 pt. Subject 22 pt bold, two lines, baselines 242.5 and 270.5 pt -> LINE PITCH 28.0 pt (UIFont's default for 22 pt SF is ~26.2 pt, so there is explicit extra leading). Date line 15 pt grey, baseline 292.5 pt. Second rule at y=327.5 pt, then the HTML body. Content left inset ~20 pt (ink at 20.5-21.0 pt).

Confidence: high

```
Line bands in x 1340..2600: y 149..174, 183..200, [rule 224], 263..295, 311..338, [rule 372], 452..493, 508..541, 563..590, [rule 655].
Banner 'T' of This: y 151..168 = 18 px cap -> 12.77 pt. 'U' of Unsubscribe: y 184..201 = 18 px -> 12.77 pt.
'N' of NYC y 265..288 = 24 px -> 17.00 pt. 'M' of McGarry y 312..332 = 21 px -> 14.87 pt. 'D' of Details y 312..332 = 21 px -> 14.87 pt, right ink 2599 px = 1300.0 pt.
Subject 'A' of An y 453..485... flat cap 31 px; baselines 485 and 541 px, delta 56 px = 28.0 pt.
Avatar (clean window x 2615..2725, y 255..365): bbox x 2640..2711 = 36.0 pt, y 261..332 = 36.0 pt, right edge 1356.0 pt.
Banner fill Counter -> (243,243,248); rules -> (200,200,200).
```

### MEASURED — the pane C toolbar action order is, left to right: [prev chevron, next chevron] ... [Flag, Move/folder, Delete/trash, Reply, Compose], all #007AFF, all vertically centred at y ~41 pt, right group flush to a 20 pt right margin. This is EXACTLY the order UI_SPEC.md guesses at (flag, move, delete, reply, compose) — the spec's stated order is confirmed by the reference, so it can be frozen with confidence.

Confidence: high

```
Blue-cluster bboxes in y 30..127, absolute pt: chevron-up 702.0..722.5 (centre 712.2); chevron-down 740.5..761.0 (centre 750.7); flag 1115.0..1131.5 (centre 1123.2); folder 1164.0..1185.0 (centre 1174.5); trash 1220.0..1239.0 (centre 1229.5); reply 1268.0..1293.0 (centre 1280.5); compose 1323.0..1346.0 (centre 1334.5). Centre-to-centre in the right group: 51.3, 55.0, 51.0, 54.0 (mean 52.8). Compose right ink edge 1346 pt -> 20 pt from the 1366 pt screen edge. Icon pixel colour = (0,122,255). Visual confirmation: /tmp/cmail/visual/crop_paneC_bar.png
```

### MEASURED — pane A grouped-section gap bands are 27.5 pt (the first, directly under the nav bar) and 28.0 pt, filled #EFEFF4 (239,239,244), bounded top and bottom by FULL-WIDTH (zero inset) 0.5 pt #C8C7CC rules. Row icons are #007AFF, optically centred at x = 29.25 pt for top-level rows and x = 65.0 pt for indented rows.

Confidence: high

```
Grey-band runs (>=90% exact #EFEFF4 across x 0..573): 'y 129..183 pt 64.5..91.5 height=55px=27.5pt' and 'y 362..417 pt 181.0..208.5 height=56px=28.0pt'. Bounding separators at y=184, 361, 418 all report 'cover=1.00 xfirst=0 (pt 0.0)'. Icon ink: Inbox x 37..80 px (centre 58.5 px = 29.25 pt), Drafts x 42..75 px (centre 58.5 px = 29.25 pt), Important x 110..150 px (centre 130 px = 65.0 pt). Icon pixel Counter -> [((0,122,255), 314)].
```

### ANOMALY, measured but unexplained — pane A's 'Edit' bar button sits 8.5 pt from its pane's right edge while pane B's identical 'Edit' sits 16.5 pt from its pane's right edge. I cannot tell from one screenshot whether this is an iOS 10 beta layout quirk, a primary-column layout-margin difference, or intentional. Recommend using 16 pt for BOTH in the clone and noting the deviation.

Confidence: medium

```
Pane A Edit ink x 502..556 px -> right edge 278.5 pt; pane A width 287 pt -> gap 8.5 pt. Pane B Edit ink x 1237..1291 px -> pane-relative right edge 358.5 pt; pane B width 375 pt -> gap 16.5 pt. Both are 17 pt regular #007AFF with identical glyph heights (27 px ink band).
```

### GAP, not measurable — pane widths cannot be resolved into 'fixed points' vs 'fractional'. 287.0 / 375.0 / 703.0 pt fits both a hard-coded set and 0.2101 / 0.2745 / 0.5146 of the width. 375 pt is suspiciously exactly the iPhone 6/7 portrait width, which hints at a fixed value, but one screen size cannot prove it. Only the 12.9" iPad Pro is represented.

Confidence: medium

```
Single reference image at one size (2732x2048). No second iOS 10 three-pane capture at a different iPad width was available.
```

### GAP, not measurable — UIBarButtonItem/tap-target frames. Every toolbar number above is a GLYPH INK bounding box; the invisible 44x44 pt hit areas UI_SPEC requires cannot be recovered from pixels. Likewise the exact weight NAME (Semibold vs Medium) is not recoverable; 'semibold' is the best fit from a 4 px stem at 17 pt versus regular's 3 px.

Confidence: high

```
Glyph ink widths vary 16.5-25.0 pt across the five right-hand toolbar icons, and centre-to-centre spacing varies 51.0-55.0 pt purely from glyph asymmetry — so no single button width is derivable. Stem measurement: 'Mailboxes' (semibold) stems 4 px, 'Inbox' (regular) stems 3 px at the same 17 pt.
```

### MODERN ELEMENTS TO BAN (from the Apple help.apple.com current-Mail comparison image, fetched and inspected): a ranked list of 20 things that must never appear. The three most dangerous because a naive UIKit default will produce them: circular sender avatars, a BLUE rounded inset selection pill with white text, and a rounded inset 'card' detail pane floating on grey.

Confidence: high

```
Fetched https://help.apple.com/assets/64067ABCCD41A13D1E3E3BF2/64067ABCCD41A13D1E3E3C00/en_US/04e1e86f3afa769514a4c92ba7dc61ec.png (958x692).
Sampled selected row a[275:300,90:290] -> [((0,122,255), 3787)] i.e. solid #007AFF fill; zoom crop shows rounded corners, inset from both pane edges, WHITE text, and no separator under it (vs classic #D9D9D9 full-bleed, black text).
Page background behind the detail card a[600:610,330:920] -> [((247,247,247), 1260)] with the card at (254,254,254) -> a card on grey, not a flush canvas.
Toolbar crop (/tmp/cmail/visual/z_mtool.png): Reply, Reply-All, Forward, Trash, Folder, then Compose and a CIRCLED ELLIPSIS overflow, all rendered GREY not blue; no Flag in the bar.
Bottom bar crop (/tmp/cmail/visual/z_mbot.png): circled-filter glyph, 'Updated 2 minutes ago', and a window-stack glyph at the right.
Full list to ban: (1) circular sender avatars in list rows AND in the detail header; (2) blue #007AFF rounded inset selection pill with white text; (3) rounded inset detail 'card' with shadow on a grey page; (4) two-pane layout with a collapsible sidebar instead of three persistent panes; (5) floating popover with large rounded icon-over-label action TILES (Reply/Reply All/Forward/Trash); (6) stacked rounded context menu (Remind Me / Unflag / Mark as Unread / Move Message / Archive Message); (7) the multi-colour flag SWATCH row; (8) 'Remind Me' and 'Archive Message' as concepts; (9) the circled-ellipsis overflow button (UI_SPEC already bans hiding actions behind '...'); (10) Stage Manager '...' pill at the window top-centre; (11) home-indicator pill at the screen bottom; (12) rounded app/window corners; (13) inline paperclip + coloured flag chips on message-list rows; (14) reply/reply-all/forward as three separate arrows grouped left-of-centre in the detail toolbar; (15) a SECOND bottom toolbar in the detail pane with a floating reply arrow; (16) recipient chips with a '>' disclosure chevron instead of the blue right-aligned 'Details' text link; (17) grey/monochrome toolbar icons instead of #007AFF; (18) no pinned search bar above the message list (the classic has a permanent 43 pt #C9C9CE search bar); (19) the modern bottom-bar glyph pair (circled filter + window stack) instead of the plain blue funnel with two-line 'Updated .../n Unread'; (20) large-title navigation bars — the classic is a compact centred 17 pt title.
```

### IMPORTANT SCALING RULE (inferred from iOS layout semantics, not from a second screenshot): only the PANE WIDTHS should be expressed as fractions. Row heights, font sizes, insets and the dot diameter are absolute points in iOS and must be hard-coded as points on every iPad — scaling 104 pt rows or 17 pt text by screen width would break the clone on a smaller iPad.

Confidence: medium

```
Points are a device-independent unit on iOS; the measurement itself (1 px = 0.5 pt at @2x) is what makes these numbers portable. This is a design conclusion, not a pixel measurement — flagged as INFERRED.
```

### Artifacts on disk for reuse. Reference capture, annotated measurement overlay, modern comparison, and every measurement script are in /tmp/cmail/visual/. NOTE: the source image is Macworld/IDG copyright; REFERENCE_SCREENSHOTS.md warns against redistributing it inside a public product, so none of these artifacts belong in the app or the repo.

Confidence: high

```
/tmp/cmail/visual/ios10_ipad_mail_orig.png (2732x2048, sha256 1fa636e3197cbefdebaf34551916d07891d4a7453f6e65110d8a152080e15c5f)
/tmp/cmail/visual/measured_overlay.png
/tmp/cmail/visual/modern_mail.png (958x692, Apple help asset)
/tmp/cmail/visual/ink.py (shared measurement helpers), m1.py-m6.py (pane/divider/row structure), g1.py-g17.py (glyph, colour, toolbar, bottom-bar), overlay.py (annotation renderer)
```

**Risks noted:**

- Copyright: the reference is a Macworld/IDG asset and REFERENCE_SCREENSHOTS.md explicitly warns against redistributing it inside a public product. The numbers measured from it are facts about a layout and are safe to hard-code; the IMAGE is not safe to ship. The annotated overlay is a working file, not a product asset — do not fold it into the app bundle or a public repo.
- Single-screen-size risk: every number comes from ONE 12.9" iPad Pro capture. Whether Apple's 287/375/703 pt panes were fixed points or fractions of the width is not determinable, so the clone's behaviour on a 11" or 9.7" iPad is a design decision, not a measurement. Recommend: fixed 287 pt sidebar + fixed 375 pt list + flexible detail, since 375 is exactly the iPhone portrait width and smells hard-coded.
- Scaling trap: it is tempting to express everything as fractions since they 'scale to any iPad'. Do NOT. Row heights (44.5 / 104 pt), font sizes (17/15/22), insets (29/55/86/16) and the 12 pt dot are absolute points on iOS; only the pane widths are proportional. Scaling type by screen width would wreck the elderly-user legibility this product exists for.
- UI_SPEC.md contradiction that will silently produce the wrong look: the spec says the sender line is 'semibold for unread', implying regular for read. The reference shows semibold for BOTH, with the blue dot as the only unread signal. Caveat: only one read row is visible in the shot (n=1), so if a second iOS 10 capture surfaces, re-check before freezing.
- The 11 pt toolbar status text and the 13 pt banner text are the two least certain type sizes (+/-1 pt and +/-0.5 pt respectively) because their cap heights land between two candidate sizes. Everything at 15/17/22 pt is unambiguous (sub-0.2 pt agreement between cap-height and x-height derivations).
- Pane A's 'Edit' button sits 8.5 pt from its pane edge while pane B's identical button sits 16.5 pt. I could not determine whether that is an iOS 10 beta bug or intentional. Copying it faithfully would look like a defect; I recommend 16 pt for both, but that is a deliberate deviation from the reference and should be recorded as such.
- Toolbar hit targets: all icon numbers are glyph INK boxes. UI_SPEC requires 44x44 pt minimum hit areas and the reference cannot tell you where those are. Whoever builds this must add the hit areas from the accessibility requirement, not from these measurements.
- I could not find a second independent iOS 10 three-pane capture at a different iPad size to cross-validate the fixed-vs-fractional question. The Macworld article was fetched and verified directly.

---

## Investigation 4

**Verdict.** The spec package is honest and reasonably well-researched in prose, but three load-bearing things are wrong. (1) Its single most important product premise is false for an ordinary iPad: iOS 10's three-pane Mail existed ONLY on the 12.9-inch iPad Pro, ONLY in landscape, and ONLY when you tapped an opt-in multi-pane button — the package's own cited sources say so. If the elderly user's iPad was not a 12.9" Pro, three panes are not muscle memory, they are a brand-new UI, which inverts the whole product principle. (2) The starter's RootSplitViewController is broken as written: on a .tripleColumn split view, `preferredDisplayMode = .oneBesideSecondary` shows the SUPPLEMENTARY column, not the primary, so the mailbox list is hidden — and `presentsWithGesture = false` also suppresses the only affordance that could bring it back (displayModeButtonItem is explicitly "Not supported for column-style UISplitViewController"). The app would ship with two panes and no route to the third, failing its own Acceptance Test #1. (3) SwiftMail's facts check out (real iOS 15 floor, genuinely implements MOVE/APPEND/IDLE/SMTP+XOAUTH2, very actively maintained), but it has literally zero Objective-C interop — its two entry points are `public actor IMAPServer` / `public actor SMTPServer`, and actors cannot be exposed to ObjC at all. On a no-Swift-compiler pipeline it is not "hard", it is impossible. Separately, the distribution doc omits every operational time bomb, and I verified the real one on this host: the ad-hoc profile AND the distribution certificate both expire at the same instant, 2027-09-18 10:22:36 UTC, after which Apple says the app will not launch.


### SwiftMail's real iOS platform floor is 15.0, exactly as ARCHITECTURE.md claims — and its warning to distrust the README is vindicated: the README still says iOS 14.0+. swift-tools-version is 5.9.

Confidence: high

```
https://github.com/Cocoanetics/SwiftMail/blob/main/Package.swift — `// swift-tools-version:5.9` and `platforms: [.macOS("12.0"), .iOS("15.0"), .tvOS("15.0"), .watchOS("8.0"), .macCatalyst("15.0")]` with the comment "Floors raised to satisfy the SwiftCross dependency (iOS 15 / tvOS 15 / watchOS 8); SwiftCross's own floor is set by its URLSession.bytes shim."  Contrast, from the cloned repo README.md lines 143-147: "## Requirements … - macOS 11.0+ … - iOS 14.0+".
```

### SwiftMail has ONE library product, `SwiftMail`, plus two conditionally-built CLI executables. The library target pulls in six packages: swift-nio, swift-nio-ssl, swift-log, swift-nio-imap, swift-collections, and Cocoanetics/SwiftCross.

Confidence: high

```
Package.swift: `.library(name: "SwiftMail", targets: ["SwiftMail"])` + `(buildCLIDemos ? [.executable(name: "SwiftIMAPCLI"…), .executable(name: "SwiftSMTPCLI"…)] : [])`. Target deps: `.product(name: "NIO", package: "swift-nio")`, `NIOSSL`, `Logging`, `NIOIMAP`, `OrderedCollections`, `SwiftCross`. Manifest-level deps also include swift-dotenv, swift-argument-parser and `.package(url: "https://github.com/apple/swift-testing", exact: "6.3.2")`.
```

### ARCHITECTURE.md's capability claim is NOT aspirational — SwiftMail really does implement IMAP MOVE, APPEND, IDLE and SMTP XOAUTH2 in source, not just in the README.

Confidence: high

```
Cloned repo /tmp/cmail/factcheck/SwiftMail: `Sources/SwiftMail/IMAP/IMAP/Commands/MoveCommand.swift`, `Sources/SwiftMail/IMAP/IMAPServer+Append.swift:17 public func append(`, `Sources/SwiftMail/IMAP/IMAPServer+Idle.swift` (+ IdleRunner, IdleSession, IMAPIdleConfiguration), `Sources/SwiftMail/SMTP/SMTPServer+Authentication.swift:93 public func authenticateXOAUTH2(email:accessToken:)`. It even has a COPY+EXPUNGE fallback: `IMAPError.swift:234 static func moveFallbackFailed(after copyUID: CopyUID?, …)`.
```

### SwiftMail is actively maintained — not a risk on that axis. Created 2025-03-05, latest release 1.11.0 on 2026-08-15, last commit 2026-09-11 (8 days ago), 96 stars, BSD-2-Clause, only 2 open issues, not archived.

Confidence: high

```
`gh api repos/Cocoanetics/SwiftMail` → pushed_at 2026-09-11T09:20:53Z, updated_at 2026-09-15, stars 96, open_issues 2, license BSD-2-Clause, archived false. `gh api .../releases` → 1.11.0 (2026-08-15), 1.10.0 (2026-07-31), 1.9.2/1.9.1/1.9.0 (2026-07-28). Recent commits include "Expose supportsMove, mirroring supportsUIDPlus" and "Add validated partial IMAP body part fetching".
```

### SwiftMail has NO Objective-C interop story whatsoever. Zero @objc/@objcMembers/NSObject subclasses in the entire Sources tree, and its two entry points are Swift actors, which the ObjC runtime cannot represent at all. On a pipeline with no Swift compiler this dependency is not merely inconvenient, it is unusable.

Confidence: high

```
`grep -rn "@objc\|: NSObject\|@objcMembers" Sources/ | wc -l` → 0. `grep -rn "public actor" Sources/SwiftMail` → `IMAP/IMAPServer.swift:30: public actor IMAPServer {` and `SMTP/SMTPServer.swift:49: public actor SMTPServer {`. Public API surface is 3 actors / 34 structs / 19 enums / 1 protocol — none ObjC-representable.
```

### CRITICAL BUG in the starter: `preferredDisplayMode = .oneBesideSecondary` on a `.tripleColumn` split view hides the PRIMARY (mailbox) column, not the secondary. Apple: "The sidebar shown is the primary column for doubleColumn interfaces and the supplementary column for tripleColumn interfaces." The correct constant for three visible panes is `.twoBesideSecondary` (iOS 14+, tripleColumn-only). As written the app renders two panes and fails its own ACCEPTANCE_TESTS line 4.

Confidence: high

```
spec/starter/ClassicMail/UI/RootSplitViewController.swift:8-9 — `super.init(style: .tripleColumn)` then `preferredDisplayMode = .oneBesideSecondary`.  Apple doc JSON (developer.apple.com/tutorials/data/documentation/uikit/uisplitviewcontroller/displaymode-swift.enum/onebesidesecondary.json): "This display mode shows one sidebar tiled next to the secondary view controller. The sidebar shown is the primary column for doubleColumn interfaces and the supplementary column for tripleColumn interfaces."  And .../twobesidesecondary.json: "This display mode is only available for tripleColumn interfaces… shows both sidebars tiled next to the secondary view controller." (iOS 14.0+)
```

### Compounding the above: `presentsWithGesture = false` also suppresses the sidebar-toggle button, and `displayModeButtonItem` does not work on column-style split views. So the hidden mailbox column has NO user-reachable route back — the worst possible outcome for an elderly user.

Confidence: high

```
spec/starter/ClassicMail/UI/RootSplitViewController.swift:10 `presentsWithGesture = false`.  iOS 16.4 SDK header UISplitViewController.h:134-143 — "// Not supported for column-style UISplitViewController" on `displayModeButtonItem`, and on `displayModeButtonVisibility` (iOS 14.5+): "UISplitViewControllerDisplayModeButtonVisibilityAutomatic is the default behavior where setting presentsWithGesture to NO hides the displayModeButton." Fix requires either `.twoBesideSecondary`, or `displayModeButtonVisibility = .always`, or a manual `show(.primary)`.
```

### `preferredSupplementaryColumnWidthFraction = 0.30` is silently ignored on every modern iPad. The default `maximumSupplementaryColumnWidth` is 320 pt, so the fraction is clamped whenever the split view is wider than 320/0.30 = 1067 pt — i.e. every iPad in landscape except the old 1024 pt-wide 9.7"/mini class. The primary's 0.23 is fine (clamps only above 1391 pt, wider than any shipping iPad).

Confidence: high

```
spec/starter/ClassicMail/UI/RootSplitViewController.swift:29-30.  Apple doc JSON maximumsupplementarycolumnwidth.json: "The default value of this property is automaticDimension, which corresponds to a … width of 320 points" and "If the resulting width is greater than the maximum value specified by this property, the width is set to the value in this property." Same 320 pt default for maximumPrimaryColumnWidth. Arithmetic: 1194×0.30=358 (11" Pro), 1366×0.30=410 (12.9" Pro), 1180×0.30=354 (Air) — all clamped to 320. To honour the spec you must also raise `maximumSupplementaryColumnWidth`.
```

### `primaryBackgroundStyle = .sidebar` is at best a no-op and at worst exactly the modern iPadOS sidebar look the product spec forbids — and it directly contradicts UI_SPEC's "Pane A — Mailboxes … White background." Apple's current documentation says the constant has no effect on iOS at all, which makes it dead code that misleads whoever reads the file next.

Confidence: medium

```
spec/starter/ClassicMail/UI/RootSplitViewController.swift:11 `primaryBackgroundStyle = .sidebar`, versus spec/docs/UI_SPEC.md:11 "- White background."  Apple doc JSON primarybackgroundstyle.json: "In macOS, the sidebar of a split view has Liquid Glass behind its view. To achieve this effect in your iPad app when it runs in macOS, set primaryBackgroundStyle to sidebar… Setting the background style to sidebar has no effect when your app is running in iOS or tvOS." The iOS 16.4 SDK header still declares it API_AVAILABLE(ios(13.0)) with no such caveat, so the iOS 15/16 visual behaviour is not settled by docs alone — either way, delete the line.
```

### THE BIG PRODUCT FINDING: iOS 10's three-pane Mail was exclusive to the 12.9-inch iPad Pro, landscape only, and was opt-in behind a multi-pane button — it was not even the default on that device. The package's own cited sources say this plainly. If the target iPad is an ordinary iPad, the user has never seen this layout and building it violates the one requirement that matters ("The user should be able to use the app from memory"). Their actual muscle memory is the TWO-pane iOS 10/11 Mail: a left navigation stack (Mailboxes → Inbox → list) plus a message pane.

Confidence: high

```
Macworld (the package's own primary reference, SOURCES.md line 14): "You'll only see this icon in Notes and Mail, and only on the 12.9-inch Pro" and "To view all three panes, turn your big Pro from portrait to landscape mode and tap a new multi-pane icon on the top left of your screen."  9to5Mac (SOURCES.md line 16): "This triple split view feature is only available on the 12.9-inch iPad Pro and is not offered on the 9.7-inch iPad Pro, because it requires a larger display to be useful."  MacStories (SOURCES.md line 18): "On the 12.9-inch iPad Pro, Mail has received a three-panel mode that shows a mailbox sidebar next to the inbox and message content in landscape."  The package labels the reference correctly in references/REFERENCE_SCREENSHOTS.md:5 ("Primary — iOS 10, 12.9-inch iPad Pro") but then BRIEF.md:8 states the objective flatly as "Create a reliable three-pane iPad mail client".
```

### Ad hoc / distribution provisioning profiles expire 12 months after issue, and Apple states outright that an expired profile means the app will not launch. This is the annual cliff the elderly user will hit. DISTRIBUTION.md does not mention it at all — its only forward-looking line is IMPLEMENTATION_PLAN.md:92 "Document annual signing/profile maintenance."

Confidence: high

```
Apple Platform Deployment, "Distribute proprietary in-house apps" (https://support.apple.com/guide/deployment/distribute-proprietary-in-house-apps-depce7cefc4d/web), verbatim: "Distribution provisioning profiles expire 12 months after they're issued." and "Note: The device needs to be able to verify the provisioning profile when installing or launching the app for the first time. If the provisioning profile is expired, the app won't launch. Verification of the provisioning profile requires internet connectivity."  Note Apple's sentence is scoped to install/first launch; the wider sideloading ecosystem's refresh cycles (AltStore's 7-day loop is the same mechanism) show an expired embedded profile stops subsequent launches too.
```

### VERIFIED ON THIS HOST: the existing ad-hoc profile and the Apple Distribution certificate expire at the SAME instant — 2027-09-18 10:22:36 UTC. The profile's TimeToLive is 364 days. That is the hard date the whole deployment dies on, and it is ~364 days from now.

Confidence: high

```
`openssl smime -inform der -verify -noverify -in <signing directory>/<ad-hoc profile>.mobileprovision` → AppIDName (the wildcard App ID's name), CreationDate 2026-09-18 11:46:33, ExpirationDate 2027-09-18 10:22:36, TimeToLive 364, TeamIdentifier ['JGLH7HX44Y'], application-identifier 'JGLH7HX44Y.wtf.uhoh.*', ProvisionedDevices count = 1.  `openssl x509 -inform der -in <signing directory>/ios_distribution.cer -noout -subject -enddate` → subject=CN=Apple Distribution: A. Developer (JGLH7HX44Y); notBefore=Sep 18 10:22:37 2026 GMT; notAfter=Sep 18 10:22:36 2027 GMT. The cert is 1 year, not the usual 3, because Apple caps it at the membership expiry: "Your distribution certificate is valid for three years from when it was issued or until your Apple Developer … Program membership expires, whichever comes first."
```

### The profile currently contains exactly ONE device. The elderly user's iPad is not in it. Adding it means regenerating the profile, re-signing and re-installing — and Apple's 100-device-per-product-family limit is per membership year, with disabling a device NOT freeing a slot.

Confidence: high

```
Profile plist: `ProvisionedDevices count = 1`.  Apple Developer Account Help, Devices overview (https://developer.apple.com/help/account/devices/devices-overview): "up to 100 devices per product family, per membership year"; "You may disable a device on your list during the year, but doing so won't increase your number of available devices."; at renewal, Account Holders/Admins "will be presented with the option to remove listed devices and restore the available device count to 100 … Once you complete this process, new devices can be added."
```

### Developer Mode on iOS 16 is almost certainly NOT required for this pipeline, because the existing profile is distribution-signed (get-task-allow = false). Apple's blanket sentence in the registered-devices doc is about Xcode's DEBUGGING export, which is development-signed. DISTRIBUTION.md's hedge ("if required by the installation method") is weaker than it needs to be but not wrong.

Confidence: medium

```
Profile entitlements: `get-task-allow = False` (distribution signature, not development).  Apple, Enabling Developer Mode on a device (tutorials/data JSON): "The feature doesn't affect ordinary installation techniques, such as buying apps from the App Store or participating in a TestFlight team. Instead, Developer Mode focuses on scenarios like building and running an app from Xcode, or installing an [.ipa] file with [Apple Configurator]."  Counterpoint, same source family — Distributing your app to registered devices says, in a flow that begins "Select Debugging and click Distribute": "To run your iOS, iPadOS, visionOS, or watchOS app that you install from an iOS Package Archive, enable Developer Mode on that device."  Earlier ad-hoc installs over this OTA path are the decisive empirical evidence — but confirm whether Developer Mode happened to be ON on those devices before promising the elderly user's stock iPad needs nothing.
```

### DISTRIBUTION.md step 4 ("Create an explicit App ID/bundle identifier") is wrong for this pipeline and would cost a pointless profile regeneration. The existing wildcard App ID `JGLH7HX44Y.wtf.uhoh.*` already covers it, and Classic Mail needs no capability (push/iCloud/App Groups/associated domains) that would force an explicit App ID. Keychain, which SECURITY_AND_AUTH.md mandates, works fine under the wildcard.

Confidence: high

```
docs/DISTRIBUTION.md:17 "4. Create an explicit App ID/bundle identifier." vs the live profile's `application-identifier = JGLH7HX44Y.wtf.uhoh.*` and `keychain-access-groups = ['JGLH7HX44Y.*', 'com.apple.token']`. Entitlement keys present: application-identifier, com.apple.developer.team-identifier, get-task-allow, keychain-access-groups.
```

### The starter cannot actually launch as shipped: AppDelegate returns `UISceneConfiguration(name: "Default Configuration", …)` but the package contains no Info.plist and therefore no UIApplicationSceneManifest naming SceneDelegate. Nothing in the package ever references SceneDelegate by name.

Confidence: high

```
`find spec -type f` returns 21 files, no Info.plist. starter/ClassicMail/App/AppDelegate.swift:8 `UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)`. Xcode's template would generate the manifest, but starter/PROJECT_SETUP.md:6 tells the developer to "Delete generated view-controller UI", and the template manifest also carries a UISceneStoryboardFile that must be removed.
```

### The starter prototype is not navigable at all: neither table view controller implements `tableView(_:didSelectRowAt:)`, no column ever talks to another, and `compose()` / `moveMessage()` / `deleteMessage()` / `replyMessage()` are empty. BRIEF.md:31 calls the first milestone "a fully navigable mock-data UI prototype" — none of it exists yet.

Confidence: high

```
MailboxListViewController.swift and MessageListViewController.swift contain only numberOfRowsInSection and cellForRowAt. MessageViewController.swift:38-41: `@objc private func moveMessage() {}` … all four bodies empty. MessageListViewController.swift:30-32 `@objc private func compose() { // TODO: present ComposeViewController modally… }`.
```

### The message-row design is unbuildable with the code the starter uses. UI_SPEC.md requires "Time/date aligned to upper-right" over sender/subject/preview, but `cell.defaultContentConfiguration()` (UIListContentConfiguration) has only text/secondaryText and cannot place a trailing-top timestamp. A custom UITableViewCell subclass is mandatory, and the starter's `content.secondaryText = "\(subject)\n\(preview)"` with rowHeight 74 is the modern list look, not classic Mail density.

Confidence: high

```
docs/UI_SPEC.md:19-25 ("Sender on first line, semibold for unread. Subject on second line. Preview snippet below. Time/date aligned to upper-right.") vs starter/ClassicMail/UI/MessageListViewController.swift:19 `tableView.rowHeight = 74` and :46-51 `var content = cell.defaultContentConfiguration(); content.text = message.sender; content.secondaryText = "\(message.subject)\n\(message.preview)"`.
```

### The repository protocol's `page: Int` pagination is the wrong abstraction for IMAP and will desync the message list the moment new mail arrives mid-scroll — page indices shift when messages are prepended. IMAP needs UID ranges / sequence sets, which the architecture itself acknowledges elsewhere ("Reconcile message list by stable IMAP UID").

Confidence: high

```
docs/ARCHITECTURE.md:31 and starter/ClassicMail/Mail/MailRepository.swift:5 — `func listMessages(in mailboxID: String, page: Int) async throws -> [MessageSummary]` — versus docs/ARCHITECTURE.md:69 "3. Reconcile message list by stable IMAP UID."
```

### The MailRepository protocol is missing three things PRODUCT_SPEC.md requires as v1 features: search, flag/unflag, and attachment download. Phase 7 of the plan assumes search exists.

Confidence: high

```
starter/ClassicMail/Mail/MailRepository.swift lists only listMailboxes, listMessages, loadMessage, markRead, move, delete, send, saveDraft. docs/PRODUCT_SPEC.md:57 "- Flag/unflag if straightforward", :66 "- Attachments: view/download/share", :67 "- Search current mailbox". docs/IMPLEMENTATION_PLAN.md:65-69 "## Phase 7 — Search". The domain model has `Attachment` with `id/filename/mimeType/size` but no way to fetch bytes.
```

### SECURITY_AND_AUTH.md's iCloud suggestion will hit two concrete walls that the doc does not flag: iCloud IMAP advertises neither MOVE nor SPECIAL-USE, so IMPLEMENTATION_PLAN Phase 4 step 4 ("Identify special-use folders") and step 9 ("MOVE/delete") both need name-matching / COPY+EXPUNGE fallbacks.

Confidence: high

```
SwiftMail README.md capability matrix (captured by its author from live servers, Exchange row noted "captured 2026-03-05 from outlook.office365.com:993"): MOVE row → Gmail ✅, iCloud ❌, Dovecot ✅, Exchange ✅. SPECIAL-USE row → Gmail ✅, iCloud ❌, Dovecot ✅, Exchange ❌. XLIST → iCloud ❌. SwiftMail does ship the fallback (IMAPError.moveFallbackFailed) and recently added `supportsMove` (issue #225), so this is manageable but must be planned. docs/IMPLEMENTATION_PLAN.md:83 already lists "server MOVE unsupported" as a hardening test, so the author half-knew.
```

### Unmentioned but valuable for this exact user: the app should set `UIRequiresFullScreen = YES` so an accidental Slide Over / Split View drag cannot collapse the three-pane layout to a compact stack. This still works precisely BECAUSE the pipeline links against the iPhoneOS16.5 SDK — Apple deprecated the key in iPadOS 26.0 and apps linked against the newer SDK are forced resizable.

Confidence: high

```
Apple doc JSON bundleresources/information-property-list/uirequiresfullscreen.json → platforms iOS 9.0 deprecatedAt 26.0, iPadOS 9.0 deprecatedAt 26.0; "UIRequiresFullScreen allows apps to opt out of this multitasking and dynamic resizing in iOS 9 and later"; "In iPadOS 26 and later, support multitasking and dynamic resizing…". Related: iOS 16.4 SDK header UISplitViewController.h:52 documents `UISplitViewControllerColumnCompact` — "If a vc is set for this column, it will be used when the UISVC is collapsed, instead of stacking the vc's for the Primary, Supplementary, and Secondary columns" — which the starter does not set, so its portrait fallback (docs/UI_SPEC.md:62) is currently whatever UIKit defaults to.
```

### Architecturally, UISplitViewController(.tripleColumn) is the wrong tool for this product regardless of the display-mode bug. It IS the iPadOS 14 sidebar redesign, it is adaptive by construction (auto-collapse, display-mode changes on rotation/size class, animated column transitions), and its width properties are explicitly only 'preferred'. The spec demands the opposite: "explicit view controllers and deterministic layout", "Controls never move based on context", "Do not animate panes dramatically", "lock layout constants". A plain container UIViewController with three child VCs and hard Auto Layout constraints is both period-correct for 2016 (tripleColumn did not exist until iOS 14) and a better fit for the spec — and it removes the iOS 14+ API dependency entirely.

Confidence: high

```
BRIEF.md:22 "Use explicit view controllers and deterministic layout", :15 "no … adaptive button relocation", UI_SPEC.md:60 "Do not animate panes dramatically", IMPLEMENTATION_PLAN.md:97 "lock layout constants".  Apple doc JSON uisplitviewcontroller/style-swift.enum.json: "In iOS 14 and later, UISplitViewController supports column-style layouts… Before iOS 14, UISplitViewController supported just one split view interface style". preferredPrimaryColumnWidthFraction doc: "The split view controller attempts to use the width you specify, but may change this value to accommodate the available space." iOS 16.4 header:146: "This preferred width will be limited by the maximum and minimum properties (and potentially other system heuristics)."
```

### If a real mail engine is needed on the ObjC-only pipeline, MailCore2 is the only live candidate — it is ObjC/C++ with an ObjC API (MCOIMAPSession/MCOSMTPSession), still maintained, but it is not a drop-in: it vendors libetpan and needs icu/ctemplate/tidy/uchardet, which is a heavy native build on an iPad.

Confidence: medium

```
`gh api repos/MailCore/mailcore2` → language C++, pushed_at 2026-07-29T08:30:29Z, archived false, 2698 stars, 233 open issues. Latest tag 0.6.4. Recent commits 2026-07-29 ("Simplify ActiveSync mail API", "Fix Linux build with modern ICU"). I did not verify its dependency build on the theos/Procursus toolchain — that is unproven and would need a spike.
```

### Everything the package cites still resolves — the reference screenshots and articles are all live, so the visual-reference workflow is executable as written.

Confidence: high

```
curl -o /dev/null -w '%{http_code} %{content_type} %{size_download}': techhive iOS 10 iPad Mail PNG → 200 image/png 207192; help.apple.com modern-Mail PNG → 200 image/png 367145; macworld article → 200 text/html; macstories review p20 → 200 text/html.
```

### DISTRIBUTION.md's one substantive warning is correct: TestFlight builds do expire (90 days), so it is indeed unsuitable as a permanent path. But the doc does not acknowledge that Ad Hoc's own 12-month profile cliff is the same class of problem, just slower.

Confidence: medium

```
docs/DISTRIBUTION.md:24 "Do not use TestFlight as the permanent deployment path because TestFlight builds expire." The 90-day TestFlight build expiry is Apple's documented policy; I did not re-fetch a citation for it, so treat the exact number as unverified here — the directional claim is sound.
```

### Minor but worth knowing: SwiftMail pins `swift-testing` at `exact: "6.3.2"`, whose own manifest is swift-tools-version 6.2 — the author's comment says "every platform that compiles the test targets needs Swift 6.2+". If SwiftPM does not prune that test-only dependency for a non-root package, a consumer would be forced onto a Swift 6.2+ toolchain (Xcode 26+), contradicting the swift-tools-version 5.9 floor. Moot on a no-Swift pipeline, but relevant if anyone ever builds this on a Mac.

Confidence: low

```
Package.swift: `.package(url: "https://github.com/apple/swift-testing", exact: "6.3.2"),` with the comment "swift-testing releases track toolchain versions: 6.3.2's manifest is swift-tools-version 6.2, so every platform that compiles the test targets needs Swift 6.2+." I could not confirm SwiftPM's test-only-dependency pruning behaviour from the SwiftPM CHANGELOG or GitHub code search.
```

**Risks noted:**

- The three-pane premise may be wrong for this user. Before writing any more UI code, establish which iPad the elderly user actually used in the iOS 10/11 era. If it was not a 12.9" iPad Pro, a faithful clone is TWO panes (left navigation stack: Mailboxes -> Inbox -> message list; right: message), and building three panes actively defeats the product's only requirement.
- Hard deadline 2027-09-18 10:22:36 UTC. On that date the profile and the certificate both die and Apple says the app will not launch. Somebody must own a calendar reminder at ~2027-08-01 to renew membership, regenerate the profile, re-sign and re-push through the AltStore source. Design the update so it is a silent OTA refresh, not something the elderly user has to understand. Also verify now whether pushing a profile-only refresh through the source actually replaces the embedded profile without a full reinstall.
- SwiftMail is unusable on this pipeline (pure Swift, actor-based, zero ObjC interop) and there is no Swift compiler anywhere in the pipeline. Every Swift file in starter/ is throwaway. The mail engine is the single biggest unknown in the project: either spike MailCore2 on theos/Procursus early, or write IMAP/SMTP directly against CFNetwork/NSURLSession + a hand-rolled IMAP client in ObjC. Do this spike BEFORE the UI, because it can kill the project.
- The starter's RootSplitViewController is actively misleading: it looks authoritative but produces a two-pane app with an unreachable third column. If anyone ports it line-for-line to ObjC UISplitViewController they will inherit the bug. Recommend not porting it at all and using a plain container view controller with three fixed-width children.
- Apple's own docs conflict on whether Developer Mode is needed for an .ipa install. Earlier installs on this pipeline are the real evidence, but confirm whether Developer Mode happened to be ON on those devices before promising a stock, never-developer-touched iPad needs no setup.
- iCloud IMAP lacks both MOVE and SPECIAL-USE. If the target account is iCloud, folder-role detection and the Move flow both need hand-written fallbacks (name matching; COPY + STORE \\Deleted + EXPUNGE). Decide the provider now, not at Phase 4.
- IMPLEMENTATION_PLAN Phase 9 ("Archive in Xcode", "Export Ad Hoc IPA") and PROJECT_SETUP ("Create a new Xcode iOS App project", "Add SwiftMail through Swift Package Manager") are unexecutable here. The whole plan needs a rewrite of Phases 0, 2-9 against the theos/zsign/OTA pipeline before anyone follows it "exactly" as BRIEF.md:53 instructs.
- No heavy build was run on this host. The MailCore2-on-theos question is unresolved and would need an actual compile attempt on the iPad, which was not attempted here.

# Live test against a real Gmail account, 2026-09-20

Burner account, real mailbox, on the dev iPad. Everything below was observed
on screen, not inferred.

## Works end to end

| path | evidence |
|---|---|
| TLS + LOGIN | authenticated in ~1.4s from launch to populated inbox |
| LIST + special-use | INBOX, Drafts, Sent Mail, Spam, Trash, All Mail, Important, Starred all resolved from `\All \Drafts \Sent \Junk \Flagged \Trash`; `[Gmail]` correctly skipped as `\Noselect` |
| STATUS | unread counts per folder, and they update |
| SELECT + UID SEARCH + UID FETCH | real senders, subjects, dates, flags |
| ENVELOPE parsing | including timestamps rendering as times / "Yesterday" / dd/MM/yy |
| BODY.PEEK + MIME decode | an HTML newsletter rendered with logo, headings, body text and an embedded screenshot |
| dark-mode body | body background measured (6,6,2), region mean 18, images NOT inverted |
| UID STORE \Seen | survived an app restart, so it reached the server |
| UID STORE \Flagged | survived an app restart |
| UID MOVE to Trash | message left Inbox and arrived in Trash WITH its flag intact |
| SMTP send | delivered; appeared in Sent Mail as exactly ONE copy |
| attachment indicator | paperclip in the leading gutter on a real receipt with a PDF |

## The capability question, settled

Gmail advertises `MOVE` and `UIDPLUS` **only after** authentication:

    pre-auth : IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN
               X-GM-EXT-1 XYZZY SASL-IR AUTH=XOAUTH2 ...
    post-auth: ... UIDPLUS COMPRESS=DEFLATE ENABLE MOVE CONDSTORE ESEARCH
               UTF8=ACCEPT LIST-EXTENDED LIST-STATUS LITERAL- SPECIAL-USE

`connect()` re-reads them after LOGIN, so `move()` uses `UID MOVE` and never
the COPY + `\Deleted` + plain `EXPUNGE` fallback — the one path that could
have taken messages another client had marked. Confirmed by the Trash test.

## Found by testing, fixed

**Compose address fields had no keyboard type.** Typing a real address gave
`someone,example.org` — on the default iPad keyboard the key where `@`
sits on the email layout is a COMMA. The address would have been rejected as
unparseable, and a 90-year-old hunting for an `@` is a reason not to send the
letter at all. `To` and `Cc` now set `.emailAddress`.

## List previews: done, and what the wire actually looks like

Previews are a **second pass** behind the list rather than part of it. The
rest of a row comes from `ENVELOPE`, which arrives for a whole page in one
reply; preview text is BODY, and a page of HTML mail is several hundred
kilobytes of it. Folding that into `listMessages` would have traded a list
that appears in about a second for one that appears in four, so the rows go
up with the preview blank and `previews(for:in:)` fills them in behind.

The section a preview lives in **differs per message** and a FETCH applies
the same item to every UID in its set, so the page is grouped by (section,
window). Measured against the live account, an eight-message inbox:

    a027 → UID FETCH 3:5,7:9 (UID BODY.PEEK[1]<0.2048>)     6 messages
    a029 → UID FETCH 2       (UID BODY.PEEK[1.1]<0.2048>)   1 message
    a031 → UID FETCH 1       (UID BODY.PEEK[1]<0.8192>)     1 message, HTML-only

Three commands for eight messages, the whole pass in **~700 ms**, and the
list was already on screen 70 ms before it started. The three groups are
exactly the three shapes real mail comes in: a plain part at section 1, a
plain part nested at 1.1 under a mixed/alternative, and an HTML-only message
with no plain alternative at all.

Note the STATUS commands for the folder counts interleave with these on the
same connection — visible proof that `IMAPClient`'s exchange gate serialises
overlapping commands, which actor isolation alone would not have done.

| verified on device | result |
|---|---|
| plain-text preview | a newsletter's opening line, truncated at the cap with "…" |
| nested alternative (1.1) | correct plain part chosen, not the HTML sibling |
| HTML-only, iso-8859-1, quoted-printable | an order receipt's greeting and first line — clean prose out of 8 KB of markup |
| every row in the folder | has two lines of preview; none blank |

**Why the HTML window is 8 KB and the plain one 2 KB.** The readable text of
an HTML mail begins only after the doctype, the head and a stylesheet, and
template stylesheets routinely run past 4 KB. A smaller window does not give
a shorter preview, it gives an empty one. Preferring the plain alternative
whenever the sender provided one is what keeps a page to kilobytes rather
than hundreds of them — it is a cost decision before it is a tidiness one.

Three bugs the host tests caught before the device ever saw them, all mine:

- The character cap was checked *after* appending, and a separator plus the
  character that needed it can cross the bound twice in one turn: 241.
- Zero-width padding survived. `&zwnj;` is a format character, so Swift folds
  it into the grapheme cluster in front of it — iterating `Character` yields
  one `"y\u{200C}"` that is not zero-width by any test. The filter had to move
  to scalars. This matters because a marketing template pads its preheader
  with hundreds of `&zwnj;&nbsp;` pairs precisely to defeat previews.
- A UTF-8 sequence cut in half by the byte-counted window made the *whole*
  fragment fail UTF-8, so the Latin-1 fallback turned every accented
  character in the preview to mojibake. One split character at the end
  corrupted everything before it.

## Found by testing, fixed (2)

**A deploy that had succeeded reported `FAILED: not running`.** SpringBoard
will not foreground an app onto a dark display: `uiopen` still exits 0,
nothing launches, and no crash log is written, so it looks exactly like a
launch crash. I went looking for one that had never happened.
`deploy-to-ipad.sh` now wakes the screen with `shotc2` (the screenshot
daemon's client calls `SBSUndimScreen()`) before launching, and retries three
times. This is the second time this script has caught a false conclusion I
was about to draw from it, which is the whole reason it exists.

## Move: works, and the reason it was "blocked" was my own bad inference

Tested on device against the live account, **both directions**:

| step | result |
|---|---|
| Edit → tick a row → Move | picker sheet opens with the folder list |
| INBOX → `[Gmail]/Important` | message left Inbox, arrived in Important, still unread, preview intact |
| `[Gmail]/Important` → INBOX | moved back; account returned to its exact baseline |
| after each move | Edit mode exits, list reloads, previews repopulate |

**The "sheets are unreliable" claim was wrong.** I had written that Move was
untestable because synthetic taps on presented sheets do not land, citing
B-009. They land fine — the diagnostics sheet's Clear and Done buttons, the
picker's rows, all of it. B-009 is about moving focus between two
`UITextField`s and nothing else. Move was never blocked; it was untested, and
I had filed a guess as a cause. See KNOWN_ISSUES B-009, scope corrected.

### Three defects the test found, all fixed

**1. The folder counts went stale after every move and delete.** After
moving an unread message out of the Inbox the sidebar still read Inbox 6 and
destination 1 while the destination plainly held two unread messages. Cause:
`onMessagesChanged` only cleared the detail pane; only the Refresh *button*
refreshed the counts. The numbers beside the folder names are the one thing
on screen that says there is something new, and they were lying until he
happened to press Refresh. Both callbacks now go through one
`refreshMailboxes()`. Verified live: Inbox 5→6 and Important 2→1 updated
with no Refresh tap.

**2. Edit mode showed a red DELETE badge on every row.** `editTapped`
assigned `allowsMultipleSelectionDuringEditing` *after* `setEditing(true)`,
so the rows were built while it was still false and got the `.delete`
editing style. Tapping one revealed a Delete button that did nothing, since
no `commit editingStyle:` exists. A red minus beside every letter, when the
control means "choose", is precisely the kind of thing this product exists
to avoid. The property is now set once in `viewDidLoad`. Its old comment
claimed it suppressed swipe-to-delete; it does not and never did — swiping
is absent because neither `commit editingStyle:` nor
`trailingSwipeActionsConfigurationForRowAt` is implemented.

**3. The picker offered the folder you were already in.** `move()` correctly
no-ops when source equals destination, so tapping it dismissed the sheet and
did nothing — which reads as the app ignoring you. Now filtered out, with a
case-insensitive compare: the list pane opens on the role word `inbox` while
LIST names the same folder `INBOX`, so an exact compare would have left
Inbox in its own picker on the one screen the app always starts on.

## Reply and forward: both worked, and both were quietly broken

Tested on device against the live account. All test mail was kept inside the
one burner mailbox: forward to self first, then reply to that, so nothing
was ever sent to an outside address.

| step | result |
|---|---|
| Reply / Reply All / Forward sheet | opens, three labelled choices |
| Forward prefill | `Fwd: …` subject, empty To, quoted body with From/Subject header |
| typing a recipient | `carlo@example.org`, `@` on the main keyboard layer |
| forward delivered | Sent Mail, exactly one copy |
| Reply prefill | To = sender, `Re: …` (not doubled when already `Re:`), `>` quoting |
| reply delivered | Sent Mail, exactly one copy |

Both *worked*. Both were also broken in ways nothing on the sending device
could show, which is the point worth keeping.

### Replies did not thread — proven on the wire, not inferred

`openCompose` set `draft.inReplyTo` faithfully. `send()` called
`RFC5322Builder.build(draft:from:)` and never passed `inReplyToHeaders`, so
the field was **read by nobody**. The builder's support for threading is
complete and careful and had never once been called.

Fetched straight from `[Gmail]/Sent Mail` with imaplib:

    uid 3  (old build)   In-Reply-To: <ABSENT>   References: <ABSENT>
    uid 4  (fixed)       In-Reply-To: <22fd8db0-…@example.org>
                         References:  <22fd8db0-…@example.org>
    uid 6  (fixed, 2nd hop)
                         In-Reply-To: <428fe55e-…@example.org>
                         References:  <22fd8db0-…> <428fe55e-…>

The last one is the one that matters: the ancestry was rebuilt by parsing
the parent's own `References` back off the server and appending its
Message-ID, so the whole path is exercised and not just the builder.

**It looked fine in Gmail the whole time.** Gmail falls back to matching
subject lines, so a reply with no headers still landed in the right
conversation on the machine doing the testing. Apple Mail, Outlook and
Thunderbird thread on `References` and would have opened a new conversation
for every reply he ever sent — visible only to the person he was writing to.

A second bug sat underneath it: `draft.inReplyTo = m.id` passed the app's
internal `"<uidvalidity>/<uid>"`, so even once wired it would have emitted
`In-Reply-To: <1/9>`. `Message` now carries the real `Message-ID` and
`References` headers, parsed raw — a Message-ID is an addr-spec, never an
encoded word, and running it through `decodeWord` could only corrupt an id
that has to match byte for byte.

### Forwarding an HTML-only message sent an empty letter

`m.textBody` is nil when a message has no plain-text alternative, so the
forward body was the "Forwarded message" header and nothing else. Caught on
device forwarding a real receipt: the compose sheet was empty while the same
message rendered perfectly in the pane directly behind it.

HTML-only is not an edge case, it is most transactional mail. `Message`
gained `quotableText`, which falls back to a plain-text rendering of the
HTML. The scanner moved out of `PreviewText` into `HTMLText` so previews and
quoting share one walk of the markup and differ only in the finish — a
preview flattens to one line, a quote keeps its paragraphs. Block elements
(`p`, `div`, `br`, `tr`, `li`, …) end a line; `<b>` and `<a>` do not, or
every sentence containing a link would be shattered across three lines.

Verified after the fix: the same receipt forwards with its full text,
paragraphs intact, no CSS, entities decoded.

### And the grammar

Every reply opened `On Today at 11:18 PM, Carlo wrote:`.
`detailTimestamp` already yields "Today at …" / "Yesterday at …", so the
template's leading "On " was wrong in two cases out of three. Dropped.

## Forwarding now carries the files — and the trap underneath it

`Draft` gained `attachments`, held as POINTERS rather than bytes:
`(sourceMessageID, sourceMailboxID, attachmentID, filename, mimeType)`.
Loading the data when the compose sheet opens was rejected twice over — it
would stall the sheet behind a download of unknown size with nothing on
screen to explain the wait, then hold those megabytes in memory for as long
as someone takes to write a letter. Resolving at Send puts the wait where a
wait is already expected, and usually costs nothing: the source message is
still cached in `lastBody` from being displayed a moment earlier.

A failed fetch **throws** rather than sending without the file. A letter
whose text says "here is the receipt", with no receipt, delivered while the
sender watches Send succeed, is worse than a send he can retry.

Replies deliberately carry nothing. Quoting somebody's text back is normal;
posting their files back at them is not, and every reply to a photograph
would re-upload the photograph.

### The bug this turned up, which I put there

First forward attached **44782 bytes beginning `JVBER`**. A PDF begins
`%PDF`. `JVBER` is what `%PDF` looks like in base64.

`fetchAttachmentData` returns a MIME part's bytes *as they sit in the
message* — still base64-encoded — and I fed those to the builder, which
base64-encoded them again. The recipient would have got a file that, once
decoded, was still a base64 transcript. No reader on earth opens that.

It survived to the wire because **this method had never had a caller**. The
attachment UI is still inert labels, so forwarding was the first code ever
to ask for an attachment's bytes, and the missing decode had never been
exercised by anything.

Fixed at the right level: `fetchAttachmentData` now returns the FILE, which
is what its name and every future caller want. That needs the part's
transfer encoding, so the uncached path fetches BODYSTRUCTURE first and
**refuses** if it cannot read it — guessing base64 would shred a 7bit text
part, and guessing 7bit is precisely the bug above.

Verified against the live account by fetching both messages back and
comparing:

    forwarded copy (sent uid 8)      original (INBOX uid 17)
    Invoice-QX7T2KDA-0001.pdf        Invoice-QX7T2KDA-0001.pdf
      32502 bytes  %PDF-               32502 bytes  %PDF-
      sha256 matches                   sha256 matches
    Receipt-4417-2093-6621.pdf       Receipt-4417-2093-6621.pdf
      33336 bytes  %PDF-               33336 bytes  %PDF-
      sha256 matches                   sha256 matches

Byte-identical. The compose sheet also now names what it is carrying
(`📎 Invoice-…pdf, Receipt-…pdf`), because the failure runs both ways: he
must be able to see that the receipt is going, and equally that a
photograph he did not mean to pass on is about to be.

## A signature, and the Settings screen it needed

He has a custom signature that goes out on everything. There was no
signature support and nowhere to put one.

**There was also no Settings screen** — while `MailError` has been telling
him *"Password needs to be updated in Settings."* since the error strings
were written. An instruction pointing at a screen that does not exist is
worse than no instruction, because he would go looking for it. Settings
now exists and holds the three things that are his rather than the
mailbox's: display name, signature, and a new app password.

It lives in the message list's bottom toolbar, in what used to be dead
space kept there only to centre "Updated Just Now". Not in the folder pane:
that pane is 250 pt wide and a button beside "Mailboxes" left 8.5 pt
between them, measured on device.

**A name or signature change does not touch the keychain.** `saveAccountOnly`
exists so that editing a sign-off cannot fail in the one way that locks him
out of his own mail. A new password still gets proved against the server
before it replaces a working one — same rule as setup.

**Placement.** Signature above the quoted text in replies and forwards,
which is where every client puts it and where a reader looks; below the
quote it is buried under however much of the original he kept. A `-- ` line
precedes it (RFC 3676), which is what lets the recipient's client trim it
instead of accumulating his address down a thread — and is not added twice
if he pastes in a signature that already has one.

### The bug a test caught before the device saw it

Adding `signature` to `MailAccount` broke every account already stored.

**Swift's synthesized `Decodable` does not use property default values** —
a missing key throws `keyNotFound` whether the property has a default or
not. So the account on disk failed to decode, `loadAccount()` returned nil,
and the app would have shown the SETUP FORM to a man who was already set
up. With the bootstrap import gone (B-010), the only way back would have
been retyping the app password.

`MailAccount` now decodes field by field with `decodeIfPresent`, so every
defaulted field is optional on the way in and the next one added cannot do
this again. Verified on device: the existing account still loads.

## Paging past the first fifty, verified

`listMessages` always took a `beforeUID` cursor — paging by UID rather
than page index, so a page boundary cannot shift when mail is delivered —
but the list never asked for a second page. Fifty was a hard stop.

**SEARCH ALL is now issued once per listing, not once per page.**
`beforeUID == nil` means "start from the top" and is the only thing that
re-reads it. Without that a 20,000-message mailbox re-downloads 20,000
UIDs for each fifty it shows: quadratic in the length of the mailbox, paid
by the person scrolling. Reusing the snapshot also keeps the list still —
mail arriving while he reads back through last year must not renumber what
is under his thumb.

**Appended with `insertRows`, never `reloadData`.** Existing rows keep
their index paths so nothing moves, and the selected row stays selected,
because it is the letter open in the pane to the right.

### Verified on device with the page size temporarily cut to 5

| | result |
|---|---|
| pages walked | 4 (5 + 5 + 5 + 2) across a 17-message inbox |
| last row | an order receipt — the server's **oldest** message, uid 1 |
| first row | the server's newest, uid 19 |
| termination | short final page set the stop flag; footer disappeared; scrolling stopped |
| duplicates | none |
| previews | present on **every** row, including later pages |

That last line is the one worth keeping. The preview generation token used
to be bumped on any list change, so appending a page would have cancelled
previews still in flight for the rows already on screen — blanking the
page he is looking at to fill in the one below. Replacing and appending
are now different things and only replacing invalidates.

Restored to 50 and re-verified: 17 messages fit one page, no footer.

### A toolchain hazard caught in passing

`swift build -c release` reported **"Build complete! (0.24s)"** without
recompiling a source file that had just changed. The stale binary was
byte-identical in SIZE to the correct one — only one integer constant
differed — so nothing but the timestamp check would have caught it.
`package.sh`'s staleness guard did, and refused to package. A forced
rebuild took 69 s and produced a different binary.

This is the second time that guard has paid for itself (see B-009's
"the thing that actually cost the time"). Its rule generalises: **verify
the artifact, not the build's opinion of the artifact.** If a release
build ever returns implausibly fast after an edit, delete
`.build/arm64-apple-ios/release` rather than trusting it.

## An oversize message refuses loudly, before it uploads

Forwarding something near Gmail's ceiling used to spend a minute pushing
bytes up the wire and then say **"Message was not sent."** — true, useless,
and an invitation to try again and fail again the same way.

**The limit is read from the server, not hardcoded.** Gmail's EHLO
advertises `SIZE 35882577`, measured. That is 34.2 MiB: the 25 MB
attachment limit after base64 inflates it by a third, which is why it is
not a round number. Reading it means the app is also right on a server that
is not Gmail, and stays right if Google changes it. `SIZE 0` means "no
stated limit" per RFC 1870 and must not be read as a limit of zero, or
every message would be refused.

Three layers, in order of how early they catch it:

1. **The compose sheet shows the total** — `Invoice-….pdf, Receipt-….pdf —
   68 KB` — so the weight is visible while he is still writing rather than
   only at the end.
2. **A local check before `MAIL FROM`.** Nothing is uploaded. The bytes are
   already built by then, so this counts the real message, not an estimate.
3. **`SIZE=` is declared on MAIL FROM**, and 552/523 map to the same error —
   for a server that advertised no limit, or whose real limit is under what
   it advertised. 554 is generic and is deliberately NOT claimed.

### A fifth user-facing string, on purpose

`PRODUCT_SPEC.md` fixes four sentences. This adds
**"This message is too big to send. Try sending fewer attachments."**

The rule those four exist to enforce is that raw protocol text never reaches
him, and that rule is kept: "552 5.2.3 Your message exceeded Google's
message size limits" is exactly what he must never see. What is not kept is
the pretence that "Message was not sent." covers this. It names nothing he
can act on, and this is the one send failure with an obvious remedy.

### Verified on device

The real case cannot be produced against Gmail at all, and that is worth
recording: its IMAP `APPENDLIMIT=35651584` is **below** its SMTP
`SIZE 35882577`, so nothing that can be put into the mailbox can fail
coming out of it. The case is only reachable for mail that arrived by
inbound delivery above the sending limit — which I did not manufacture.

So the path was exercised with the threshold temporarily lowered to 50 KB,
then reverted and re-verified:

| | result |
|---|---|
| forward over the limit | alert shown, **compose sheet stayed open with the letter intact** |
| bytes uploaded | none — Sent Mail's highest UID was unchanged |
| threshold reverted | a normal forward sends again |

One correction worth keeping: the first attempt used a 100 KB threshold and
did not fire, because the forward is **92,632 bytes** — not the 126,672 I
expected. That figure was from *before* the double-base64 fix. The code was
right and the test parameter was wrong.

## The folder counts update on read, per MESSAGE not per folder

Reading a message marked it read on the server and left the sidebar number
untouched until the next Refresh. The fix is a local decrement — the
alternative, `refreshMailboxes()`, is a LIST plus one STATUS per folder,
nine round trips, and that on every message tap is indefensible.

The hard part is not the arithmetic. **In Gmail a folder is a LABEL and
`\Seen` belongs to the message**, so reading one letter drops the unread
count of every folder carrying it. A counter that decremented only the
folder on screen would leave the rest permanently high — and because all
eight rows are visible at once, it would show states the server cannot
represent, like All Mail reading fewer unread than Inbox.

### Measured against the live server, not assumed

Three rules, each established by probing the account, and one of them inverted what I expected:

- **X-GM-LABELS omits the label of the folder you have SELECTed.** The same
  message reads `X-GM-LABELS ()` from INBOX and `("\Inbox")` from All Mail.
  The selected folder is implicit and has to be added back.
- **All Mail is not a label and never appears.** Every message is in it
  implicitly.
- **Except that Trash and Spam are EXCLUSIVE.** A trashed message still
  carried `\Starred` while Starred's STATUS reported zero messages, so a
  message in Trash is in no other folder whatever its labels claim.

The label→folder table is built from LIST attributes, which also settled two
aliases that are not the identity mapping: **Starred is advertised as
`\Flagged`**, and **Draft's folder as the plural `\Drafts`**.

X-GM-LABELS rides the FETCH the list already issues, so knowing a message's
folders costs **no extra round trip**. It is gated strictly on
`X-GM-EXT-1` — deliberately NOT with the `capabilities.isEmpty || …`
optimism `move()` uses, because an unrecognised item inside a FETCH makes
the server reject the whole command, which here would empty the message
list rather than merely lose the labels.

### Verified end to end

Tapping one unread self-sent message (labelled Inbox + Sent):

| folder | before | after | server |
|---|---|---|---|
| INBOX | 9 | **8** | 8 |
| Sent Mail | 4 | **3** | 3 |
| All Mail | 9 | **8** | 8 |
| Important | 1 | 1 | 1 |

All eight folders matched the server exactly afterwards, with zero STATUS
round trips.

### The bug this uncovered, which predates it

Reading the decrement closely suggested it would silently no-op on Inbox
because the message pane carries the role word `"inbox"` while every
sidebar row carries the LIST name `"INBOX"`. Checking that claim showed
something worse already shipping: `select(mailboxID:)` does the same exact
`==`, so **the Inbox row has never been highlighted at launch**. Measured
on device — the row background read **12.8**, identical to unselected rows,
against **51.1** for a genuinely selected one. The single question the third
pane exists to answer by looking has been unanswered on the primary folder,
every launch, since the layout landed. After the fix it reads **48.6**.

Both now go through `firstIndex(matchingMailboxID:)`, which falls back to
matching on `Mailbox.Role` — that is what makes `"trash"` find
`"[Gmail]/Trash"`, which no string comparison would, and what makes it work
on an account whose folders are not in English.

### Other findings acted on

- The decrement is committed **only after the STORE succeeds**, and the
  unread dot is restored if it fails. Previously `try?` swallowed the error;
  decrementing anyway would convert a stale-HIGH count (nags) into a
  stale-LOW one (hides mail).
- A per-controller set of already-counted message ids. `guard !isRead` is
  not enough: a reload can re-derive `isRead` from server FLAGS that predate
  the STORE, put the dot back, and re-arm the guard for a second billing.
- The sidebar patches the visible cell directly. `reloadRows` deselects what
  it reloads, and the row being adjusted is nearly always the open folder —
  it would have destroyed the highlight that was just fixed.
- `reload()` gained a generation token, so two overlapping sweeps cannot
  land oldest-last and visibly revert the counts.
- **A live bug, unrelated to this work:** moving or deleting from the detail
  pane's toolbar never updated the sidebar at all. `onNeedsListRefresh` was
  wired only to the message list.

## The paperclip opens now

Attachments were one blue label listing `name (size), name (size)` — styled
exactly like a link and not one. That is the worst state a control can be
in, and for a reader who cannot distinguish "nothing happened" from "I
missed", it is actively cruel.

Now one tappable row per file, each with a paperclip, the sender's filename
and the size, each its own `minHitTarget`-sized target. Tapping downloads
the file and opens it in **QuickLook**.

QuickLook rather than anything hand-rolled, and that is a scope decision as
much as an effort one: it renders PDFs, photographs, Word and Pages files
natively, and it arrives with a Done button and a share button already on
it. The share sheet is what makes *save* work without this app growing a
file manager.

Verified on device with a forwarded vendor receipt:

| step | result |
|---|---|
| both files listed | `📎 Invoice-QX7T2KDA-0001.pdf (34 KB)` / `📎 Receipt-…pdf (34 KB)` |
| tap | spinner on that row, then full-screen preview |
| render | the real invoice — logo, line items, totals — titled with the sender's filename |
| share sheet | "PDF Document · 33 KB", **Save to Files**, Print, AirDrop, Gmail |
| Done | returns to the message, both rows intact |

The system reading it as a 33 KB *PDF Document* is the part that matters:
that is iOS independently confirming the bytes are a real PDF, which is
exactly what the double-base64 bug would have failed.

**Per-row progress, not one spinner somewhere.** A few megabytes is several
seconds of nothing, which reads as a tap that missed — and the response to
a tap that missed is to tap again.

### Filenames come from strangers

`AttachmentStore` is the only place in the app that creates a file whose
name someone else chose, so the sanitising is load-bearing rather than
defensive habit. Three ways a name escapes the directory it is appended to,
all of them arriving in one header field:

- path separators (`../../Documents/bootstrap.json`)
- `.` and `..`, which survive every character filter — neither contains
  anything illegal — and both name a DIRECTORY, so
  `appendingPathComponent("..")` hands back the parent
- control characters and colons, legal in POSIX and a mess in every picker

Each file goes in its own UUID directory rather than getting a uniquified
name, so two attachments genuinely called `scan.pdf` cannot collide and the
reader still sees the name the sender gave it instead of `scan-2.pdf`. 11
tests, including one that asserts a hostile name still lands inside the
store.

Everything written is purged at launch. The system reclaims the temporary
directory eventually, but "eventually" on a tablet that is never restarted
and holds one man's entire correspondence is not a bound.

### Draft construction moved out of the view controller

`Draft.replying(to:all:myAddress:)` and `Draft.forwarding(_:)` are now pure
functions in the model layer. Four separate bugs have been found in those
few lines — a Reply All that CC'd the sender himself, an empty quote for
HTML-only mail, threading headers built and discarded, and double-encoded
attachments — and not one was visible on the sending screen. Code with that
history belongs where a test can reach it. 24 tests now do.

## Still open

- **A read taken DURING a server sweep is still lost.** The sweep's STATUS
  for that folder may have run before the `UID STORE`, so the snapshot it
  installs is one too high. Deliberately not fixed by replaying the delta
  on top of the fresh array: when the STATUS ran *after* the STORE the
  replay double-decrements, and that error is under-reporting — "no new
  mail" when there is. Over-reporting nags; under-reporting hides mail. The
  ambiguity is unresolvable from the client, so the safe error was chosen
  and the next refresh corrects it.
- ~~**The setup form still needs one clean-install run by hand.**~~
  **DONE — see B-031.** A real address and app password were typed into a
  device with no stored account: Gmail accepted them, `CredentialStore.save`
  wrote them, the root swapped to the mail interface and the Inbox loaded.
  A deliberately wrong password first produced the right error and kept the
  other fields. The one route into this product is proven from nothing.

## Opening the folder at a day (2026-09-20)

What actually goes wrong: he uses Apple Mail, he is very
old, and his main problem is jumping to a date. Everything below follows
from taking that literally — Mail's
behaviour everywhere it has one, and an invention only at the point where
Mail leaves him stuck.

**Measured on device.** Calendar button → month grid → 19 September → the
Inbox reopens at the first message of the 19th, status bar reads "Showing
September 19", and scrolling up walks back through today's mail to the true
top of the folder with no duplicates, no gaps and correct descending order.
Verified twice: once at the shipping page size of 50, and once with the page
size temporarily cut to 5 so the two-ended paging seams were crossed
repeatedly rather than hidden inside a single page.

### The list grows in two directions now, which it never did

`listMessages(in:beforeUID:limit:)` only ever walked DOWN from the newest
message, because until now the list could only ever start there. A jump puts
mail on both sides, so there is a matching `afterUID` direction and a
`messages(around:in:limit:)` that returns a window plus the index to scroll
to.

Prepending is the hard half. Every row already on screen changes index, so
the scroll position is corrected by hand — inserted row count times
`tableView.rowHeight`, which is exact only because this app fixes its row
height and never uses self-sizing rows. Without the correction the list
lurches down by a page and he loses the letter he was reading. The insert is
wrapped in `performWithoutAnimation`, because an animated insert ABOVE the
viewport animates content out from under the reader and lands the offset fix
a frame late.

### SENTSINCE, not SINCE — they are different dates

`SINCE` tests INTERNALDATE, when the server took delivery. The list rows show
the envelope `Date`, what the sender's own clock said. For mail delayed
overnight those differ, and jumping on the wrong one lands him on a row whose
visible date is not the one he asked for — which reads as the feature being
broken rather than as a distinction between two timestamps.

Two more ways the wire date fails silently, both now pinned by tests:
`en_US_POSIX`, because `MMM` on a French device renders `juin` and the server
answers BAD (surfaced to him as "Can't connect to mail server"); and the
local calendar, because formatting in UTC from a timezone west of Greenwich
turns an evening in June into the 21st.

### What the tests caught that review did not

`PageWindow.newer(than:)` took a SUFFIX of the newer UIDs — the newest in the
mailbox — where it needed a PREFIX, the ones adjacent to the cursor. On
device that would have prepended today's mail directly above the day he
jumped to and silently swallowed the four months between. The comment in the
source argued for the wrong one in so many words; the test disagreed and was
right.

The arithmetic now lives in `PageWindow`, which has no `Network` dependency,
so `PagingTests` calls the REAL walk instead of the hand copy it used to
assert against. That copy was the standing risk the old file admitted to:
the two could drift and the suite would stay green while the product broke.

### Found by driving it, not by reading it

- **Cross-mailbox results poisoned every follow-up call.** An All Mailboxes
  search runs against All Mail and its hits carry All Mail's UIDs, but
  `previews`, `setRead`, `move` and `delete` all passed the mailbox the PANE
  was showing. First device run: every search result came up with two blank
  grey lines. The same bug would have flagged, moved or DELETED whatever
  happened to wear that UID in the Inbox. All four now use the row's own
  `mailboxID`.
- **"No results" was hidden behind the keyboard.** The empty-state label was
  centred in the pane; while he is typing a search the keyboard covers the
  bottom two thirds of it, so a search with no hits showed an empty black
  rectangle and no explanation. Moved near the top.
- **The preview-part cache flushed instead of evicting.** Crossing 500
  entries called `removeAll()`, which was tolerable while a folder was one
  page of fifty and is not once a search pages past its first hundred: it
  threw away the parts for rows still ON SCREEN. Now drops the oldest.

### Search: the ceiling was silent

Search returned the newest 100 hits and stopped, with no cursor and no way to
ask for the hundred-and-first — paging was explicitly disabled whenever
results were showing. For someone searching years of mail that is not
a limit, it is the letter not being there. Search now pages exactly like the
folder does, and a short page ends it.

Two smaller things went with it. A search used to be one full IMAP round trip
PER KEYSTROKE, so a six-letter name fired six searches and the answer shown
was whichever returned last, not necessarily the one for what was in the
field; there is now a 350 ms debounce. And failures were swallowed by `try?`
into an empty array, so a dropped connection told him the letter did not
exist — it does exist, we could not look, and it now says so.

### Debug iOS builds no longer link

`swift build --swift-sdk ios165` fails with `undefined symbol:
swift_coroFrameAlloc`. Swift 6.2 emits that call for coroutine accessors, the
symbol is absent from the iOS 16.5 runtime this app targets, and only the
optimiser removes the calls — so release builds clean and debug does not.

It mattered because `deploy-to-ipad.sh` opened with a debug build as a fast
error check, under `set -e`, so its failure aborted the whole deploy before
anything was packaged. That step now builds `-c release`, which is also the
only configuration that has ever shipped: `package.sh` copies from
`.build/arm64-apple-ios/release`.

## All Mailboxes means three mailboxes (2026-09-20)

The Trash gap in B-011 was built rather than deferred, despite the cost.

**Why one SELECT was never going to be enough.** Gmail's All Mail contains
everything except Trash and Spam — exclusivity this codebase already leans on
in `countedFolders` — so searching it alone can never return a letter he
binned, which for someone who searches constantly is the one result he would
most obviously expect to find.

**Why it costs more than two more searches.** A UID is only meaningful inside
the mailbox that issued it. UID 900 in Trash and UID 900 in All Mail are
unrelated messages, so three hit-sets cannot be concatenated, cannot be
sorted numerically, and cannot be paged by the `beforeUID` cursor that every
other list in this app uses. Ordering has to be by envelope date, and a date
cursor has no natural home in the existing protocol.

What went in instead is a `SearchSession` held by the repository: the All
Mail UID walk and its cursor, a buffer of rows fetched from it but not yet
emitted, Trash and Spam hits fetched whole and sorted, and every row emitted
so far. The last of those is what makes a re-asked page free and, more
importantly, non-destructive — replaying a page already handed out must not
advance the streams, or the page after it silently skips whatever the second
call consumed.

**The one rule that makes the merge correct.** When the All Mail buffer
empties but the server still has hits to give, the merge must STOP rather
than fall through to the binned stream. Fall through and a message trashed
last March is emitted the instant the current chunk runs out, landing above
hundreds of newer letters that simply have not been fetched yet — a result
list that is silently, plausibly out of order. That is the `primaryExhausted`
flag in `SearchMerge.take`, it is the least obvious line in the feature, and
there is a test named after it.

Ties break on id and not on date alone. Two messages sharing a timestamp to
the second is ordinary — anything sent by a machine — and without a TOTAL
order the comparison is ambiguous, which across a page boundary means one of
them emitted twice or skipped entirely. Both failures are invisible: a
duplicate looks like two similar letters, and a dropped one looks like a
letter that was never there, which is indistinguishable from the complaint
this whole feature exists to answer.

**Measured on device, both directions.** Trash held exactly one message, a
newsletter containing "eval" and nothing else in the account did. From the
Inbox with All Mailboxes selected, it came back FIRST and in correct date
position, ahead of the All Mail hits; toggling to Current Mailbox dropped it
and left only the Inbox hits, which also proves the scope control re-runs the
search rather than filtering what is on screen. Paging was then re-checked at
page size 3 so that page boundaries fell between the two streams: the binned
hit appeared exactly once, mid-stream, and the dates stayed strictly
descending across every boundary.

**Bounds accepted rather than hidden.** Trash and Spam are fetched whole up
to 200 hits each rather than paged, because they cannot be paged alongside
All Mail; past that the oldest binned matches are dropped. And a Trash that
fails to open is swallowed, so the All Mail half of a search survives it —
losing half a search is a gap, losing all of it is the feature not working.

## To and Cc matching, proved by sending one letter (2026-09-20)

The TO/CC search fields had been unit-tested only: every message on the dev
account is Carlo to Carlo, so no recipient differs from its sender and no
existing message could discriminate. Exactly one test letter was sent to
close it.

**Method.** From the app, to `desk@example.net`, Cc
`owner@example.com`, with the subject and body written to contain
neither token — so each string exists in exactly one header and nowhere
else in the account. `owner-mail` was chosen for Cc because that mailbox
can be read directly from the build host, which turns "it appeared in
Sent" into "it was actually delivered".

**Result, three independent confirmations.**

1. Reading the delivered copy from the build host shows real `To:` and `Cc:`
   headers, so Cc reached the message and not merely `RCPT TO`.
2. Searching `desk` in the app, from the Inbox, All Mailboxes:
   exactly one hit, the sent letter. That token is in the To header alone.
3. Searching `owner`: same single hit. Cc header alone.

The signature also went out correctly delimited, `-- ` with its trailing
space, which had only been seen in the composer before.

### The bug this found, which was not the one being tested

Cc had never worked. See B-014: the row was `addSubview`d into a wrapper
instead of handed to the stack, so its height constraint never applied and
the field had no tappable area. It rendered, which is why nobody had
noticed. Tapping it did nothing and the next thing typed appended to
whichever field still had focus — which during this test produced
`desk@example.netowner@example.com` as a single To recipient,
and on a real send would have been a malformed address and a bounce.

Worth stating plainly: the feature being verified passed its unit tests and
was fine. The thing that was broken was the form the owner would have used
to exercise it, and only driving it by hand found that.

### Harness notes

- `type-on-ipad.sh` gained a SPACE key, measured the same way as the
  letters and cross-checked against them (row 3 at y 1362 and "@" at
  x 1818 both matched the existing table, so the frame is unchanged). It
  still refuses uppercase deliberately, and still cannot type a comma:
  comma sits behind `.?123` on the email keyboard, which is a layer switch
  and a second coordinate set. That is why this test used one To and one Cc
  rather than two of each — `ComposeViewController` splits recipients on
  commas only.
- While adding that key I ran what I called a dry check and it was not one:
  it typed "hello world" into the live To field. Cleared with backspaces.
  The script types for real every time it is invoked; there is no dry mode.
- The first `touchsim` tap after an idle period is regularly dropped
  (B-015). Repeat the tap before suspecting the coordinates.

## Finishing a letter you put down (2026-09-20)

Docket item 1, and the first of the Apple Mail parity gaps. Notes on the
two things that were not obvious.

**A refresh race that impersonated a bug.** After saving a reopened draft
the folder showed TWO copies, which looks exactly like the replacement
having failed. It had not: `onDraftsChanged?()` was being fired beside the
save's `Task` rather than after its `await`, so the list reloaded in the
window between the replacement being appended and the old copy being
removed. A manual Refresh a moment later showed one copy, which is what
told the race apart from a real failure — worth remembering as a
diagnostic, because the two are indistinguishable in a screenshot. The
callback now runs after the await, and everything the work needs is
captured before `dismiss` so it outlives the window without holding it
alive.

**APPENDUID is what makes replacement possible at all.** IMAP's APPEND
does not say where it put the message. Re-SELECTing and taking the highest
UID is a race against any delivery. UIDPLUS answers `[APPENDUID
<validity> <uid>]` on the tagged OK, so the parser reads it from
`IMAPCommandResult.detail`. It returns nil rather than guessing when the
server is silent: the save still happened, and the caller degrades to
leaving a duplicate draft, which is annoying and far better than deleting
a message chosen at random. It lives in `MailWireTypes` rather than on
`IMAPClient` so it can be tested — the client is Network-gated and absent
on the machine the suite runs on, the same reason `PageWindow` and
`SearchCriteria` were pulled out.

**Harness note.** Tapping the compose button twice to defeat the
dropped-first-tap problem (B-015) BACKFIRES for anything that opens a
sheet: the first tap opened the composer and the second landed on the
dimming view behind it and dismissed it again, after which the remaining
taps in the sequence fell through onto the message list and marked two
messages read. Tap once, screenshot, and retry only if nothing happened.

## The empty letter that was a dropped connection (2026-09-21)

Filed the day before as "a heavily quoted reply shows no body", with two
candidate explanations: a genuinely near-empty body, or content sitting
below the fold. Both were wrong, and pulling up the actual content
rather than leaving it filed is what found that.

**The evidence, in order.** The list preview for that reply already showed
body text — "Today at 11:33 PM, Carlo wrote: > > >" — which rules out an
empty body before touching the device, because the preview and the body
come from the same part. Opening it again raised an alert: **"Can't
connect to mail server."** Tapping the identical row once more loaded it,
body and all. So: not empty, not below the fold, and not deterministic.

**The mechanism.** Gmail closes an idle IMAP connection without the client
noticing. `IMAPClient.teardown()` clears `connected` when a command fails,
so the FIRST command after the drop fails and the SECOND reconnects and
succeeds. That is exactly the observed pattern, and it is a much worse bug
than the one being investigated: this reader picks the iPad up several
times a day, and every first action after a gap would fail.

Reads now retry once, gated on `imap.isConnected == false` so that a
UIDVALIDITY mismatch or a server NO — which also throw — are not retried
into failing twice as slowly. Writes are deliberately excluded (B-024):
a MOVE may have reached the server before the socket died.

**The second defect, which the first was hiding.** The reading pane draws
its header from the SUMMARY before fetching the body, so a failed load
leaves a sender, a subject, a date, and nothing underneath. That does not
read as an error. It reads as an empty letter — and for someone who cannot
be expected to diagnose it, an empty letter is a letter that has lost its
contents. The pane now says so itself, not only in an alert that can be
dismissed before it is read.

**Worth generalising.** The symptom was in rendering and the cause was in
the transport, and nothing about the blank pane pointed at the network.
The only reason the two were connected is that the retry was tried by hand
before writing anything down.

## Sam's signature, and what a plain-text client can carry of it (2026-09-21)

The signature field has been configurable since Settings existed; what
was missing was the actual text. It was taken from the letters Sam has
been sending, found in `owner@example.com` by searching for his address:
about 200 messages, all carrying the same block.

**His client sends HTML only.** No `text/plain` alternative in any of the
three messages checked, and the markup is Apple Mail's on iOS
(`UICTFontTextStyleBody`, and a `lineBreakAtBeginningOfSignature`
anchor). So there was no canonical plain-text form to copy; it had to be
transcribed from a table layout.

What Blackmail now carries, shown with stand-in values (the full block
also has an address and a disclaimer paragraph):

    Sam Example
    Example Organisation
    555-555-0142
    sam@example.com

**What is lost, and it is not nothing.** His signature is a two-column
table with a photograph, a small logo, and his name in
bold. This app composes plain text, so the images and the weight are
gone and the two columns become one. The words are all there and in
order. If the pictures matter to him, that is an HTML composer, which is
a different product.

**The disclaimer is included because he sends it.** Ninety words of
boilerplate on every letter, and it sits ABOVE the quoted text — which
is not this app being odd, it is what his own client already does
(`lineBreakAtBeginningOfSignature` puts the signature at the very top).
Trimming it is two taps in Settings if he would rather not.

**Note for whoever does the real setup.** This was written straight into
`UserDefaults` over SSH because the typing harness can only produce
lowercase, space, `@` and `.` — it cannot type "Sam Example", a telephone
number, or a bracket. A human at the device types or pastes it in
Settings in the ordinary way. If you ever edit the plist by hand again:
kill the app first, and `killall -9 cfprefsd` afterwards, or the
preferences daemon writes its cached copy back over yours.

## What Apple Mail actually composes, and what this app now sends

The requirement: the app cannot just compose plain text, it has to
compose whatever Apple Mail composes. The open question was whether
that means rich text.

**It means HTML, and it does not mean rich text.** iOS Mail has no
plain-text preference — the one macOS has under Message Format does not
exist on iPhone or iPad — so with no switch to consult Mail picks the
wire format from the content. Three shapes all come out of the same
composer, and all three are genuinely Apple Mail:

- `text/html` with no `text/plain` sibling, when anything rich is
  present. 326 of 433 de-duplicated messages from `sam@example.com`.
- genuine `text/plain`, 102 of 433, overwhelmingly one-liners and bare
  YouTube links. Their replies still carry Apple's quote form, U+202F
  and all, so these are Mail's output and not another client's.
- both parts, 5 of 433, unexplained. Three are the same thread,
  interleaved in time with html-only messages from the same day. No
  property separates them from their neighbours.

**He has never once applied formatting.** Across 715 sent messages
spanning three years, the region he typed himself contains only `div`,
`br` and text: no bold, no italic, no colour, no lists, no font sizes.
What pushes his mail into HTML is never his typing. It is his signature
— a Google-Docs table with a photograph, the organisation logo and his name in
bold — plus the originals he quotes. So the gap was an ENVELOPE and not
an editing surface, and a format bar would have been a rebuild of the
composer in exchange for a capability with zero observed demand.

**The rule for when to emit HTML is content-driven, and keying it on
the signature is wrong.** A signature always forces HTML — 0 of 102
plain-only messages carry one — but the converse fails: 19 of 331 HTML
messages have no signature, and 18 of those 19 contain a quoted or
forwarded HTML original. A signature-keyed rule would therefore drop
the HTML from precisely the letters where it carries the quote.

### The skeleton, read off his own device

Verified against one of his real replies and a real forward, not
inferred:

    <html><head><meta http-equiv="content-type" content="text/html;
    charset=utf-8"></head><body dir="auto">

No DOCTYPE, exactly one tag in the `<head>`. The first line of typed
text sits BARE in the body and later lines are each wrapped in a plain
`<div>` — an asymmetry that looks like a bug and is not. Then
`<br id="lineBreakAtBeginningOfSignature">`, the signature, and the
quote as TWO SIBLING blockquotes:

    <div dir="ltr"><br><blockquote type="cite">On Sep 20, 2026, at
    8:12&#8239;PM, Name &lt;addr&gt; wrote:<br><br></blockquote></div>
    <blockquote type="cite"><div dir="ltr">…original…</div></blockquote>

The attribution alone in the first one. The blockquotes are bare, with
no inline style at all — the grey left bar is the renderer's, not the
sender's. A forward is the same with `Begin forwarded message:` and a
header blockquote of bold `From:`/`Date:`/`To:`/`Subject:`, the subject
value bolded too.

### Why the structure is parsed back out of the text

`AppleMailHTML.layout` reads the finished plain body and splits it into
typed text, signature and quote, rather than the Draft carrying those
regions alongside the string. That looks like the long way round and it
is what keeps drafts safe: a draft is APPENDed to the server as a real
message and reopened by parsing that message, so any structure held
beside the text survives the first save and is gone from the second.
The letter would quietly change shape the first time he was interrupted
and came back to it. Deriving it means a reopened draft and a fresh one
take the same path.

The cost, recorded honestly: the quoted original is the FLATTENED text
of the original inside a blockquote, not the original's own markup the
way Mail nests it. A quoted table comes back as text. That is still
strictly better than before, when it came back as text with no
blockquote at all and with words broken in half. (Since 2026-09-30 a quote
he has not touched carries the original's own markup instead, and the
flattened text is what goes once he has changed it; see B-050.)

### The portrait in his signature is dead

The 73×73 photograph points at a `lh3.googleusercontent.com` URL that
returns **403 today**, so every recipient of his current mail already
sees a broken image. The organisation logo beside it still serves (200, 20 kB
PNG). The stored markup here drops the dead `<img>` and keeps
everything else. Strict parity would have meant reproducing a broken
image in every letter he sends; this is the one place the copy
deliberately departs from his device. Reversible by putting the tag
back if the URL ever returns.

### Editing the stored account by hand: it is DATA, not a string

`CredentialStore.loadAccount()` reads `defaults.data(forKey:)`. The
account JSON is stored in the plist as `<data>`, and writing it back as
a plist `<string>` — which is what `plistlib` does if you hand it a
Python `str` — makes `data(forKey:)` return nil, which makes
`loadAccount()` return nil, which shows **the setup form to a man who is
already set up**. Observed on the dev iPad doing exactly this. The
symptom is indistinguishable from a decode failure and there is no error
anywhere. So: `json.dumps(acct).encode("utf-8")`, assert
`isinstance(value, bytes)` before writing, and check the sha256 of the
file on the device against the one you built.

## Does conversation grouping make his mail vanish? (2026-09-21)

Three of twelve recent messages from Sam report mail seeming to
disappear.
Grouping is the one feature in this app whose entire mechanic is
showing one row where there were several, so it was the obvious
suspect. It was measured rather than argued about, against 600 of his
own messages.

**How much grouping actually hides.** Inbox: 600 messages become 531
rows, so 69 are behind another row — **11.5%**, and 480 of 531 threads
are a single letter, so the list barely shortens. All Mail, where sent
and received merge and where a cross-mailbox date jump lands: 600
messages become 441 rows, **26.5% hidden**. Largest thread, 11.

**The hypothesis I expected to confirm, and it is false.** A thread
sits at its NEWEST message's date, so an old letter in a live
conversation should be displaced away from the day he jumps to —
which would break the date jump, this app's headline feature. It does
not happen in his mail. Of 159 hidden messages in All Mail, the number
displaced by even a week is **zero**; the median is 0.2 days and the
worst case is 3. His conversations resolve in days, not months. The
date jump and grouping do not fight.

**And the "vanishing" is already mitigated** in the ordinary list: a
multi-letter row prints its count on the sender line, "Margaret, Carlo
(3)", so nothing is silently absent.

### What the measurement DID find, which is a real defect

**Search results were grouped too.** `filtered = hits` then `regroup()`,
and `rebuildRows` grouped whatever was visible. A conversation row
stands for its newest letter — that is the sender it names, the subject
it prints, the preview it shows — so a hit that was not newest in its
thread came back displayed as a *different message*. He searches for a
phrase and gets a row that does not contain it, under somebody else's
subject, with the letter he wanted one tap inside and no reason given
to tap.

At 26.5% non-newest in All Mail, roughly a quarter of any result set
was being misrepresented. And search is one of his most frequent
habits: he uses it all the time.

Fixed: `MessageThread.rows(for:grouped:)`, grouped when browsing a
folder and not when showing results. Each hit becomes a conversation of
one, so it draws exactly as a single letter — no count, no participants
list — and everything downstream still works on one type. Verified on
device: "security" now returns the individual messages of a thread that
previously collapsed into one row.

**Conclusion on grouping itself: keep it.** It is what Mail does, it
hides an eighth of the Inbox behind rows that announce their own size,
and it demonstrably does not disturb the dates. If it ever does need to
go, Mail's own "Organize by Thread" setting is the shape of the
answer, and `rows(for:grouped:)` is already the seam to hang it on.

## The signature's images were broken for every recipient (2026-09-21)

Measured, not assumed: the organisation logo's `docs.google.com/uc?export=download`
URL returns 200 with a PNG to `curl`, but renders as a broken-image box in
an actual client — reproduced in headless Chromium against the sample
letter. The portrait's `lh3.googleusercontent.com` URL 403s in every
size variant. So the signature as he sends it from Apple Mail today is
text plus two broken boxes, for everyone.

**The fix**: the logo now travels with the letter. `multipart/related`
carries the alternatives plus one `image/png` part with
`Content-ID: <sig-logo>`, and the stored signature markup points at
`cid:sig-logo`. Downscaled 832x620 → 210x156 (7.5 kB) because it
displays at 35x25 — sending 20 kB for a 35-pixel logo in every letter
for years' worth of mail would have been its own waste.

**Verified end to end without sending anything**: a letter built
through the real pipeline (`AppleMailHTML.part` → `RFC5322Builder.build`)
was parsed by Python's `email` module — an implementation that shares no
code with ours — which walked the tree as related > alternative >
{plain, html} + image/png with the right Content-ID and inline
disposition, and extracted logo bytes whose sha256 matched the source
exactly. The decoded HTML rendered in Chromium shows the wordmark in
the signature block.

**The earlier note in this file** ("The stored markup here drops the
dead `<img>`… Reversible by putting the tag back if the URL ever
returns") is superseded: the logo is no longer dropped, it is embedded,
and no URL has to return.

**One deviation kept**: the portrait stays out until the owner supplies
a photograph.
