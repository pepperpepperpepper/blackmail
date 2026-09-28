# Toolchain

Lives at `/mnt/build/apple-toolchain` (158 GB free). Not installed system-wide:
it is a project dependency, not a machine one, and `rm -rf` should undo it.

    . /mnt/build/apple-toolchain/env.sh

| Piece | Version | Where |
|---|---|---|
| Swift (Linux, Ubuntu 24.04 build) | 6.2 | `/mnt/extra/cmail-swift/swift-6.2-RELEASE-ubuntu24.04` |
| `ld64.lld` (Mach-O linker) | LLD 20.0.0 | `/mnt/extra/cmail-swift/toolset` |
| xtool | 1.19.2 | `bin/xtool.AppImage` |
| Darwin Swift SDK | pending | built from Xcode 26 by `fetch-xcode.sh` |

## Why Xcode 26 specifically, and not the newest

SwiftMail needs a Swift 6.2 stdlib. Xcode 26.0 is the **oldest** release that
has one, so it is the smallest possible jump. That matters beyond tidiness: the
SDK a binary links against is what decides whether iPadOS draws it with legacy
or contemporary UIKit appearance (see D-005), and this product would rather be
as far back as it can get away with.

Currently installed: Xcode 26.0, Swift 6.2, iOS SDK 26.0, sha1
`6ff54e55537cc50c89cdc84085e4a4d151b58e9f`.

## Arch vs Ubuntu

Three sonames differ, shimmed in `lib/` and reached via `LD_LIBRARY_PATH`:
Arch ships only wide-character ncurses (`libncursesw.so.6.6`), treats `tinfo` as
an alias of it, and its libxml2 is on soname 16. Note `/usr/lib/libncurses.so`
is a *linker script*, not a library — symlinking the shim at that name yields
"file too short", which reads like a corrupt download and is not one.

libxml2's "no version information available" on stderr is a soname-version
warning only. Symbols resolve; every tool returns correct output.

## The supply-chain risk, named

`ld64.lld` comes from one person's LLVM fork
(`xtool-org/darwin-tools-linux-llvm`, MIT, last release 2024-12-01). It is the
only thing in existence that links iOS-device Mach-O on Linux — upstream LLD in
Swift 6.2 refuses outright with "does not support linking for platform iOS". The
tarball is mirrored locally so a deleted upstream does not strand the project.

## Authentication

Apple gates the Xcode download behind a signed-in developer session, and that is
the one step nothing here can automate. `fetch-xcode.sh` reads the
`ADCDownloadAuth` cookie from `~/.apple-signing/adc-cookie` and passes it via
`--cookie` with the value read from the file rather than placed in `argv`, where
any other user on the box could read it out of `/proc`.

Note this is a *browser session* cookie, unrelated to the distribution
certificate and provisioning profile in the same directory. It is short-lived
and can be deleted once the download completes.

## Host-side tests

    cd ios && swift test          # Linux, no device, ~0.7s

38 tests over the MIME decoder, the IMAP response parser and the outgoing-mail
builder. They run natively on this box because the package is split:

    Sources/Blackmail      library, built for arm64-apple-ios AND for the host
    Sources/BlackmailApp   the entry point, three lines
    Tests/BlackmailTests   @testable import Blackmail

Everything needing UIKit, Network or Security is wrapped in
`#if canImport(...)` and compiles away on Linux, leaving the pure-data code —
which is the code most likely to be wrong, and the code no screenshot can
check. `swift test` builds every target in a package, so the entry point needs
the guard too.

One coupling had to be broken to make this possible: `TLSConnection.decode`
(which imports Network) was the only Apple-only reference inside the parsers.
It moved to `MailText.decode`, four Foundation-only lines.

The protocol clients and the repository used to compile away as well,
because they held a `TLSConnection` directly. They now hold a `MailTransport`
(`Net/MailTransport.swift`), which `TLSConnection` implements on the device,
so `IMAPClient`, `SMTPClient` and `IMAPMailRepository` build on Linux too.
Still guarded: `TLSConnection` itself, the initialisers that default to it,
and `IMAPMailRepository.fromStoredCredentials`, which reads the keychain.
`Tests/BlackmailTests/Support/ScriptedIMAPServer.swift` is a Gmail-shaped IMAP
server with its own in-memory transport, and `RepositoryWireTests` runs the
real repository against it, recording which mailbox every command ran in.
Its transport supplies only the link, like `TLSConnection` on the device;
everything above the link is `Net/LinkTransport.swift`, which both run: the
framing (`Net/ReadBuffer.swift`), the deadlines and what each does when it
fires (`Net/TransportDeadline.swift`), what `close()` ends, and the B-034
`WIRE-OUT`/`WIRE-ACK` probes. So what the tests see on cancellation, a silent
peer or a stalled uplink is what the device does, and a mistake in any of it
fails a host test. What stays device-only is `TLSConnection`'s own glue:
which `NWConnection` states count as up or failed, the receive and send
callbacks, the `NWError` mapping, and the TCP options.

**The `swiftUIKit` link flag is `.when(platforms: [.iOS])`.** Without the
condition the host link fails with `cannot find -lswiftUIKit`.

**Nothing may compile to an OS version check.** There is no compiler-rt for
iOS in this toolchain, so `if #available(...)`, and any stdlib API that is
back-deployed past the 16.0 deployment target, builds for the host and for the
device and then fails the device link with `undefined symbol:
__isPlatformVersionAtLeast`. `withTaskCancellationHandler` is one: every
spelling of it in the iOS 16.5 SDK is back-deployed from 16.4.
`IMAPClient.beginExchange` watches for cancellation with an `async let` child
instead. Only the device build finds this; the host tests pass either way.

**`package.sh` copies `BlackmailApp`, not `Blackmail`.** The target rename
meant the old path silently packaged whatever stale binary was left from a
previous build and reported success. There is now a guard that refuses to
package a binary older than the newest source file.
