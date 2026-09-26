# Build decision

Produced 2026-09-19 from four investigations (Swift toolchain,
mail engine, visual measurement of the period reference, and a fact-check of
the brief). Supporting evidence for every claim is in `docs/INVESTIGATIONS.md`.

This supersedes `spec/docs/IMPLEMENTATION_PLAN.md` phases 0 and 2-9 and all of
`spec/starter/PROJECT_SETUP.md`, which assume Xcode and cannot be executed here.

---

=============================================================
BLACKMAIL — BUILD DECISION
=============================================================

## 1. THE TOOLCHAIN CALL

**Build it in Objective-C on the existing theos → zsign → CloudFront pipeline. Do not take the Swift lane, and do not buy or rent a Mac.**

The Swift investigation is the most impressive result in the package and it still loses. It proved, on this host, that a UIKit app compiles and links to a genuine `arm64` iOS-device Mach-O with `LC_BUILD_VERSION platform=2, minos 16.0`, and that `swift build --swift-sdk arm64-apple-ios -c release` works end to end in 57 seconds. That is real and it should be preserved. But it does not buy what it was supposed to buy. The entire reason to want Swift here is SwiftMail, and SwiftMail's dependency graph needs a Swift 6.2 stdlib — which means the iOS 26 SDK, which means downloading a ~10 GB Xcode 26 `.xip` from Apple. Against the newest freely-mirrored SDK (iPhoneOS 18.6) SwiftMail produces 731 errors; against 16.5 it produces 1,239 plus a reproducible compiler **segfault** on typed throws. So the actual choice is not "Swift vs ObjC", it is "Swift *without* SwiftMail vs ObjC without SwiftMail" — and once SwiftMail is off the table, Swift's remaining advantages are language ergonomics, paid for with:

- a 3.2 GB Ubuntu-built toolchain running on Arch behind two hand-made shared-library symlinks (`libncurses.so.6`, `libxml2.so.2`);
- one 43 MB prebuilt `ld64.lld` from a single person's LLVM fork as the *only* thing in the world that can link iOS-device Mach-O on Linux (upstream LLD in Swift 6.2 refuses outright: "does not support linking for platform iOS"), last released 2024-12-01;
- a deployment floor forced up to **iOS 16.0** (iOS 15 fails on the missing `libswiftCompatibility56.a`), narrowing which of the elderly user's possible iPads can run it;
- `-Xfrontend -disable-legacy-type-info` as a permanent load-bearing workaround;
- a structural failure mode where a dependency bump silently turns into hundreds of `cannot find type 'Span'` errors, or worse, a compiler crash;
- and a binary that has **never been signed, installed, or run** — "links correctly" is not "runs".

Against that: theos/clang-16 on the iPad with zsign on Linux is an already-proven pipeline, and I verified its shipped artifacts directly. A shipped IPA carries the team's wildcard ad-hoc profile, with the concrete per-app entitlement substituted at sign time, `get-task-allow=false`, `MinimumOSVersion 14.0`, loose PNG icons via `CFBundleIconFiles`, and **no `UIApplicationSceneManifest`** — i.e. the proven shape is a plain `UIApplicationMain` + `UIWindow` app with no scenes and no asset catalog. That is exactly the shape Classic Mail wants. A UIKit-in-ObjC app with a code-driven, deterministic layout is the *easiest possible* thing for this pipeline.

There is one clean switch condition, and the owner should know it: **if you are ever willing to sign in with your Apple ID and pull the Xcode 26 `.xip` onto this Linux box (no Mac required — xtool does this), Swift + SwiftMail becomes viable and this call flips.** Until that decision is made, ObjC is the answer. Keep `/mnt/extra/cmail-swift` and mirror the `darwin-tools-linux-llvm` tarball locally so the lane stays open; the single cheapest way to keep it alive is to wrap the already-built `ClassicMailApp` binary in a `.app`, zsign it, and install it — an hour's work that converts "links" into "runs".

**What is LOST by choosing Objective-C, stated plainly:**

1. **SwiftMail itself** — a maintained (last commit 2026-09-11), BSD-2, genuinely capable engine that really does implement IMAP MOVE (with a COPY+EXPUNGE fallback), APPEND, IDLE, and SMTP XOAUTH2. You are giving up a working mail engine and must replace it. This is the single biggest cost and it is not small.
2. **`async`/`await`.** The whole `MailRepository` protocol is `async throws`. In ObjC that becomes completion handlers, and the places that hurt are precisely the ones the spec cares about: optimistic delete/move with rollback, and cache-then-sync reconciliation.
3. **Memory safety exactly where hostile input lands.** ObjC + libetpan means C parsers on untrusted MIME and IMAP responses. libetpan's most recent commit (2026-09-07) is literally "Fix out-of-bounds read in IMF address parsing". Swift would have made that class of bug structurally impossible.
4. **Value-type domain models, `Codable`, and the starter code.** Every `.swift` file in `starter/` is thrown away, and with it `ARCHITECTURE.md`'s protocol snippet, `PROJECT_SETUP.md`, and Phases 0 and 2–9 of the implementation plan.
5. **The test harness.** XCTest via theos is not a solved problem on this pipeline. Deliverables 9 and 10 (unit tests, UI tests) need a substitute — a theos `tool.mk` command-line test binary run on the device covers the parsing/repository logic; automated UI testing does not survive the move and should be renegotiated to scripted manual passes plus screenshots.
6. **Any future contributor's ability to follow the package literally.** The docs will have to be rewritten or they will actively mislead.

---

## 2. THE MAIL ENGINE CALL

**libetpan HEAD, compiled on the iPad with theos as a static library, driven straight from Objective-C behind the repository seam. Not MailCore2 first, not hand-rolled IMAP, and emphatically not a Gmail gateway as the transport.**

libetpan is the best-maintained thing in this entire stack (pushed 2026-09-07), it is pure C so it drops into theos with no C++/ABI questions, it is BSD-licensed, and — the decisive fact — it ships a **ready-made Apple `config.h`** at `build-spm/config/config.h` that selects the CFNetwork TLS backend and leaves OpenSSL, GnuTLS and Cyrus-SASL undefined. So there is no autotools run, no `./configure`, no cross-compile dance, and no OpenSSL to build for iOS. Its `Package.swift` hands you a verbatim 200-file source list and ~35 header search paths. Everything it needs beyond that (`libz`, `libiconv`, `libxml2`, CFNetwork, Security, CoreFoundation) is present in the sparse iPhoneOS16.5 SDK.

Crucially, the SASL problem that makes MailCore2 awkward **is a MailCore2 problem, not a libetpan one**: with `USE_SASL` undefined, libetpan implements AUTH LOGIN / PLAIN / CRAM-MD5 itself and exposes `mailsmtp_auth()`. So libetpan covers **both** IMAP and SMTP with no patching. MailCore2's nicer `MCOIMAPSession` API is tempting — it maps almost 1:1 onto `MailRepository` — but it brings 2013-era C++ never built against clang-16, zero CI, an xcodebuild-only iOS path, four vendored deps, and ~400 translation units. Keep it as the *promotion* candidate: if a one-day MailCore2 spike links, take it; otherwise libetpan alone is fine and you write ~1,500 lines of ObjC glue instead of ~3,000 lines of C++ porting.

**GATE THE PROJECT ON A ONE-TO-THREE-DAY SPIKE, AND DO IT BEFORE ANY UI POLISH.** The spike is: compile libetpan's 200 `.c` files on the iPad with `-DHAVE_CONFIG_H=1 -DHAVE_CFNETWORK=1 -DHAVE_COREFOUNDATION_CHARCONV=1`, produce `libetpan.a`, then write a ~60-line ObjC command-line tool (theos `tool.mk`) that does CAPABILITY → LOGIN → SELECT INBOX → `UID FETCH n ENVELOPE` over TLS against a real server. If that prints an envelope, the project is de-risked. If it does not, stop and re-open the Xcode-26-`.xip` Swift question rather than grinding.

### Phased engine scope

- **E0 (spike, 1–3 d):** `libetpan.a` builds; ObjC smoke tool reads one envelope over TLS. Go/no-go.
- **E1 (read path):** `CMLibetpanRepository` implementing `listMailboxes` (LIST `"" "*"` + SPECIAL-USE, XLIST fallback on Gmail, **name-matching fallback for iCloud which has neither**), `STATUS (MESSAGES UNSEEN UIDNEXT UIDVALIDITY)`, SELECT/EXAMINE, `UID FETCH n:* (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE)` for rows and `BODY.PEEK[<part>]<0.2048>` for previews.
- **E2 (bodies + state):** `UID FETCH BODY.PEEK[<part>]` for full bodies; `UID STORE +/-FLAGS.SILENT (\Seen)` and `(\Flagged)`; UIDVALIDITY-change cache nuke; UIDs everywhere, never sequence numbers.
- **E3 (mutations):** `UID MOVE` (RFC 6851) with `UID COPY` + `STORE \Deleted` + `UID EXPUNGE` (UIDPLUS) fallback and a bare `EXPUNGE` fallback under that; optimistic UI + rollback.
- **E4 (send):** libetpan SMTP — EHLO, STARTTLS, EHLO, `mailsmtp_auth()`, MAIL FROM/RCPT TO/DATA with dot-stuffing; RFC 5322 builder; APPEND to Drafts and Sent reconciliation.
- **E5 (attachments + search):** BODYSTRUCTURE part addressing, RFC 2231 filename continuations, Quick Look preview; local cached search first, `UID SEARCH` second.
- **E6 (IDLE + hardening):** IDLE/DONE while foregrounded only, with a hard socket timeout — the iPadOS-specific killer is a suspended app whose IDLE socket died silently, leaving a spinner forever, which to this user reads as "the app is broken".

### A Gmail gateway

A private Gmail gateway was considered as the transport and rejected, leaving it at most a demo and diagnostic fallback behind `CMMailRepository`: it is Gmail-only, has small attachment and body size caps and no forward route, and it filters the content of outgoing mail in ways that reject ordinary letters.

If E0 fails outright, the honest fallback is not the gateway either — it is a hand-rolled ObjC IMAP read path (~8,500–11,000 lines, because iOS gives you base64 and charset conversion and nothing else: no quoted-printable, no RFC 2047, no RFC 5322 address parsing, no MIME multipart, no BODYSTRUCTURE), which is a 2–3 month commitment with a long correctness tail against a spec whose quality bar is "no crashes on malformed MIME".

---

## 3. WHAT TO BUILD FIRST

Target: `/mnt/finished/classic-mail/ios/`. Language: Objective-C with ARC. Bundle id `wtf.uhoh.blackmail` (covered by the existing wildcard profile — no new App ID). Milestone A is the mock-data prototype from `BRIEF.md:30-47`, built so that it **installs on a real iPad and can be screenshotted for approval**, because there is no simulator here.

Two architectural decisions baked in before the first line:

- **No `UISplitViewController`.** Use a plain container `UIViewController` with three child `UINavigationController`s and hard Auto Layout constraints. `tripleColumn` *is* the iPadOS 14 sidebar redesign; it is adaptive by construction and its widths are only "preferred". Keeping `UINavigationController` per pane buys the correct 20+44 pt chrome, centred 17 pt titles, and free 44×44 bar-button hit targets.
- **Fixed pane widths, flexible detail.** 287 pt / 0.5 / 375 pt / 0.5 / rest. On the 12.9" reference that reproduces 703 pt exactly; on the dev iPad (iPad13,6, 1194×834 landscape) detail becomes 531 pt, which is fine. Only widths are proportional-ish; **every row height, font size, inset and the 12 pt dot are absolute points and must never be scaled**.

### Ordered build list

**Step 0 — pipeline skeleton (half a day; prove install before writing UI)**
1. `ios/Makefile` — `TARGET := iphone:clang:16.5:14.0`, `ARCHS := arm64`, `PACKAGE_FORMAT := ipa`, `APPLICATION_NAME = Blackmail`, `Blackmail_FRAMEWORKS = UIKit WebKit QuickLook CoreFoundation Security CFNetwork`, `Blackmail_CFLAGS = -fobjc-arc -Wall`, `Blackmail_CODESIGN_FLAGS = -S`, `include $(THEOS_MAKE_PATH)/application.mk`.
2. `ios/control`.
3. `ios/Resources/Info.plist` — `CFBundleIdentifier wtf.uhoh.blackmail`, `UIDeviceFamily [2]`, `MinimumOSVersion 14.0`, `UIRequiresFullScreen YES` (works precisely because you link the 16.5 SDK; deprecated in iPadOS 26), landscape-first `UISupportedInterfaceOrientations~ipad` with portrait retained, `LSRequiresIPhoneOS`, `UILaunchScreen {}`, loose-PNG `CFBundleIconFiles`. **No `UIApplicationSceneManifest`.**
4. `ios/main.m` — `UIApplicationMain(argc, argv, nil, @"CMAppDelegate")`.
5. `ios/App/BMAppDelegate.{h,m}` — `UIWindow` + `CMRootViewController`. No `SceneDelegate`, ever.
   → build, zsign, install a blank blue screen on the dev iPad. Do not proceed until that works.

**Step 1 — theme and domain**
6. `ios/Theme/CMTheme.h` + `.m` — every constant in the `constants` array below, as `static const CGFloat` / `+ (UIColor *)`. This file is the frozen contract from `IMPLEMENTATION_PLAN` Phase 10; nothing else may hard-code a number.
7. `ios/Model/CMMailbox.h/.m`, `CMMessageSummary`, `CMMessage`, `CMAttachment`, `CMDraft` — plain `NSObject`, `NSCopying`, immutable where possible. `CMMailboxRole` enum: inbox/sent/drafts/trash/archive/junk/custom.
8. `ios/Mail/CMMailRepository.h` — the protocol, **corrected**: completion-handler based; `listMessagesInMailbox:beforeUID:limit:completion:` (UID range, *not* `page:`); plus the three the spec forgot — `searchMailbox:query:completion:`, `setFlagged:forUID:mailbox:completion:`, `fetchAttachment:ofUID:mailbox:completion:`.
9. `ios/Mail/CMMockMailRepository.{h,m}` — deterministic fixtures: three mailbox sections (Inbox/Drafts/Sent/Junk/Trash, then `[Gmail]` with four indented children, then custom folders), ~30 messages of which 9 unread, one HTML-only, one with a 2-line-truncating subject, one with an attachment, and one deliberately **empty** folder (the quality bar names empty folders explicitly).

**Step 2 — the three-pane shell**
10. `ios/UI/CMRootViewController.{h,m}` — container VC; three `UINavigationController` children plus two 0.5 pt `#8E8E93` hairline views; constraints A=287, B=375, C=remainder. **This is the only object that wires A→B→C**; the table VCs stay dumb. Portrait: hide A, show a "Mailboxes" bar button at top-left of B, identical action order elsewhere.
11. `ios/UI/CMMailboxListViewController.{h,m}` — grouped-style table; 44 pt rows with a 0.5 pt `#C8C7CC` separator below; separator inset 55 pt top-level / 86 pt indented; `#007AFF` glyphs centred at x=29.25 / 65.0; right-aligned `#808080` 17 pt unread count at 16 pt inset; `selectedBackgroundView` = full-bleed `#D9D9D9` with text staying black; 28 pt `#EFEFF4` section gaps bounded by zero-inset rules; a 44 pt bottom toolbar with 11 pt "Updated Just Now".
12. `ios/UI/CMMessageCell.{h,m}` — **mandatory custom cell.** `UIListContentConfiguration` cannot place a trailing-top timestamp, which is why the starter's design is unbuildable. Five subviews: 12 pt `#007AFF` dot (centre x 14, centre y 22 from row top), sender (17 pt **semibold — for read and unread alike**), timestamp (15 pt `#8E8E8E`, right-aligned, on the sender baseline), subject (15 pt), preview (15 pt `#8E8E8E`, 2 lines). Baselines 27.5 / 48.0 / 67.5 / 87.5 from row top; text column left 29 pt, right edge 359 pt.
13. `ios/UI/CMMessageListViewController.{h,m}` — pinned 43 pt `#C9C9CE` search bar containing a 28 pt white field inset 8 pt each side; list top at 108 pt; `rowHeight = 104`; 29 pt separator inset; Edit bar button (use 16 pt inset in **both** panes — see §4); bottom toolbar.
14. `ios/UI/CMMessageHeaderView.{h,m}` — sender 17 pt semibold (baseline 144.5), To: line 15 pt, blue "Details" 15 pt right-aligned, subject 22 pt bold with **explicit 28 pt line pitch** (UIFont's default 26.2 pt is wrong), date 15 pt grey, `#C8C8C8` rules inset 21 pt. **No avatar** — the reference has a 36 pt one; `UI_SPEC` bans it; ban wins.
15. `ios/UI/CMMessageDetailViewController.{h,m}` — header view + `WKWebView` (remote content blocked, viewport CSS, no arbitrary navigation). Top bar: `[prev, next]` chevrons leading; `[Flag, Move, Delete, Reply, Compose]` trailing at ~52.8 pt pitch, 20 pt right inset, all `#007AFF`, all with 44×44 hit areas regardless of glyph ink. **This order is confirmed by the pixels — freeze it.**
16. `ios/UI/CMReplyActionSheet.{h,m}` — `UIAlertController` `.actionSheet` anchored to the reply button: Reply / Reply All / Forward. Period-correct and satisfies `PRODUCT_SPEC` "Reply" step 3.
17. `ios/UI/CMComposeViewController.{h,m}` — modal form sheet; To / Cc-Bcc toggle / Subject / Body; Cancel fixed left, Send fixed right.
18. `ios/UI/CMMoveMessageViewController.{h,m}` — plain mailbox table in a form sheet; tap destination, done.
19. `ios/UI/CMAdminSettingsViewController.{h,m}` — PIN-gated stub: account fields, repository selector (Mock / libetpan / Gateway), diagnostics log.
20. `ios/Support/CMErrorPresenter.{h,m}` — only the four literal strings from `PRODUCT_SPEC` lines 87–90. Raw IMAP text goes to the admin log, never to him.

**Step 3 — the approval loop (no Mac, no simulator)**
`make package` on the iPad → zsign on Linux → install → drive with the existing headless iPad screenshot daemon → upload each screen → owner approves or rejects. Produce one screenshot per required prototype screen (`BRIEF.md:33-45`): mailbox list, selected mailbox, message rows with unread state and timestamps and preview, selected message, fixed top toolbar, compose modal, reply/forward sheet, move sheet, delete action. That set *is* the Phase 1 deliverable and also seeds `IMPLEMENTATION_PLAN` Phase 10's "document screenshots of every screen".

Run the **libetpan E0 spike in parallel from day one** — it is the thing that can kill the project, and the mock UI work does not depend on its outcome.

---

## 4. CORRECTIONS TO THE SPEC PACKAGE

**`primaryBackgroundStyle = .sidebar` contradicts the product's own rule, and it must be deleted.** `UI_SPEC.md:11` says Pane A has a **white background**. `.sidebar` is the iPadOS 14 sidebar material — the single most recognizable element of the modern redesign the product exists to avoid. Apple's current documentation says it has no effect on iOS at all (it is a Mac Catalyst / Liquid Glass affordance), but the iOS 16.4 SDK header still declares it `API_AVAILABLE(ios(13.0))` with no such caveat, so the iOS 15/16 behaviour is not settled by docs alone. Either it does nothing, in which case it is dead code that misleads the next reader, or it does something, in which case it is precisely the banned look. Delete the line. And note the deeper version of the same problem: **`UISplitViewController(style: .tripleColumn)` is itself the iPadOS 14 sidebar redesign API** — it did not exist in 2016, it is adaptive by construction, and `BRIEF.md:22` / `UI_SPEC.md:60` / `IMPLEMENTATION_PLAN.md:97` all demand the opposite. Replacing it with a plain container VC is both period-correct and spec-correct.

Everything else that must change:

**Starter code (all of it is being discarded, but record these so nobody ports the bugs):**
- `RootSplitViewController.swift:9` — `preferredDisplayMode = .oneBesideSecondary` on a `.tripleColumn` split view shows the **supplementary** column, not the primary. The mailbox pane would be hidden. The correct constant is `.twoBesideSecondary`. As written the app ships two panes and fails its own `ACCEPTANCE_TESTS.md:4`.
- `RootSplitViewController.swift:10` — `presentsWithGesture = false` also suppresses the sidebar toggle, and `displayModeButtonItem` is documented "Not supported for column-style UISplitViewController". So the hidden column has **no user-reachable route back** — the worst possible outcome for this user.
- `RootSplitViewController.swift:30` — `preferredSupplementaryColumnWidthFraction = 0.30` is silently clamped on every modern iPad, because the default `maximumSupplementaryColumnWidth` is 320 pt (clamps above 1067 pt of width). The 0.23 primary is safe (clamps only above 1391 pt).
- `MessageListViewController.swift:19,46-51` — `rowHeight = 74` is wrong (measured **104**), and `defaultContentConfiguration()` cannot produce the required upper-right timestamp. A custom cell is mandatory.
- `AppDelegate.swift:8` returns a `UISceneConfiguration` but the package has **no `Info.plist`** and therefore no `UIApplicationSceneManifest`. The starter cannot launch. The proven pipeline ships no scene manifest at all — drop `SceneDelegate` entirely.
- Neither table VC implements `didSelectRowAt`; `compose()`, `moveMessage()`, `deleteMessage()`, `replyMessage()` are all empty. "A fully navigable mock-data UI prototype" does not exist yet in any form.

**Specs and docs:**
- **`BRIEF.md:8` — the three-pane premise needs owner confirmation.** iOS 10's three-pane Mail existed only on the **12.9-inch iPad Pro**, only in **landscape**, and only behind an **opt-in multi-pane button** — it was not even the default there. The package's own cited sources (Macworld, 9to5Mac, MacStories) say so explicitly. If he used any other iPad, his muscle memory is the **two-pane** iOS 10/11 Mail (left navigation stack Mailboxes → Inbox → list; right: message), and building three panes defeats the one requirement that matters.
- **`UI_SPEC.md:20` "semibold for unread" is wrong.** Measured: the sender line is semibold for **read and unread alike** (5 px stems, ink density 0.38 vs 0.41, both clearly heavier than pane A's regular 3 px). Unread is signalled by the blue dot **alone**. Caveat: only one read row is visible in the reference, so n=1.
- **`UI_SPEC.md:39-45` toolbar order is CONFIRMED.** Flag, Move, Delete, Reply, Compose is exactly what the pixels show. Freeze it; the spec's hedge at line 46 can be closed.
- **`UI_SPEC.md:10,19` width ranges are slightly off.** Measured 21.01% and 27.45%; the spec says 22–25% and 28–32%. Replace the ranges with fixed 287 pt and 375 pt.
- **`ARCHITECTURE.md:75-80` (SwiftMail) must be rewritten.** The facts in it are correct — iOS 15 floor, README stale, MOVE/APPEND/IDLE/XOAUTH2 all real, actively maintained — but SwiftMail has **zero** ObjC interop: `grep` for `@objc`/`NSObject`/`@objcMembers` across its Sources returns 0, and its two entry points are `public actor IMAPServer` / `public actor SMTPServer`. Actors cannot be exposed to the ObjC runtime at all. On this pipeline it is not hard, it is impossible.
- **`ARCHITECTURE.md:31` `page: Int` is the wrong abstraction.** Page indices shift when new mail is prepended mid-scroll; the architecture contradicts itself four lines later at :69 ("reconcile by stable IMAP UID"). Use UID ranges.
- **The protocol is missing three required v1 features:** search (`PRODUCT_SPEC:67`), flag/unflag (:56), and attachment byte fetching (:66 — `Attachment` has id/filename/mimeType/size and no way to get the data).
- **`DISTRIBUTION.md:17` step 4 ("Create an explicit App ID") is unnecessary here** — verified: shipped IPAs embed the wildcard ad-hoc profile while the signed binary carries the concrete per-app entitlement. `wtf.uhoh.blackmail` needs no new App ID.
- **`DISTRIBUTION.md` omits the real cliff.** It warns correctly that TestFlight builds expire, then says nothing about the ad-hoc profile's own 12-month expiry — which for this deployment is a hard, verified timestamp (see §5).
- **`IMPLEMENTATION_PLAN.md` Phases 0 and 2–9 and all of `starter/PROJECT_SETUP.md` are unexecutable** ("Create a new Xcode iOS App project", "Add SwiftMail through Swift Package Manager", "Archive in Xcode", "Export Ad Hoc IPA"). They must be rewritten against theos/zsign/CloudFront before anyone follows them "exactly" as `BRIEF.md:53` instructs.
- **`SECURITY_AND_AUTH.md:29-30` (iCloud) needs a warning:** iCloud IMAP advertises neither MOVE nor SPECIAL-USE, so Phase 4 steps 4 and 9 both need hand-written fallbacks (name matching; COPY + STORE \Deleted + EXPUNGE).
- **Add `UIRequiresFullScreen = YES`** so an accidental Slide Over drag cannot collapse the three panes into a compact stack. This still works because you link the iPhoneOS16.5 SDK; Apple deprecated it in iPadOS 26.
- **Pane A's "Edit" button** sits 8.5 pt from its pane edge in the reference while pane B's identical button sits 16.5 pt. Use **16 pt for both** and record it as a deliberate deviation — copying it faithfully would read as a defect.
- **Add to `Theme`, not to the reference:** the reference's 36 pt sender avatar and its Macworld copyright. The measurements are facts about a layout and safe to hard-code; the **image** must never ship in the bundle or a public repo.

---

## 5. WHAT THE OWNER MUST DECIDE OR KNOW

1. **⏰ HARD DEADLINE — 2027-09-18, 10:22:36 UTC.** Verified on this host: the ad-hoc provisioning profile and the Apple Distribution certificate expire at *the same instant*, ~364 days from now. Apple states an expired profile means the app will not launch. Put a calendar reminder at **2027-08-01**: renew the Developer Program membership, regenerate the profile, re-sign, re-publish. Decide now who does this if you are unavailable — an elderly user whose mail client silently stops opening has no recourse.
2. **Which iPad did he actually use in 2016–17, and which will he use now?** If it was not a 12.9" iPad Pro, the faithful clone is **two** panes, not three, and the whole UI plan changes. Answer this before more UI code is written.
3. **His iPad must be registered — and that means regenerating the profile.** The current profile contains exactly **one** device, and his is not it. Profiles are immutable (no PATCH), so adding his means recreate + re-sign + re-publish every IPA. Slots are 100 per product family per membership year and disabling a device does *not* free one, so do not burn slots on typo'd UDIDs.
4. **Which mail provider?** Gmail / iCloud / an ISP. This decides authentication (app-specific password vs XOAUTH2 with a registered OAuth client and a device flow) and whether you need MOVE/SPECIAL-USE fallbacks. It is a prerequisite for Phase 4, not a Phase 4 detail.
5. **The first install on a non-jailbroken iPad has never been tested on this pipeline.** Apple's 2026 wording suggests iOS 18+ may require a device restart to complete profile trust. Burn the first install on your own **stock** iPad, not his.
6. **There is no silent update path.** Every Blackmail update means he opens **Safari** specifically — not a link tapped in Messages or Mail, which opens a webview that silently does nothing — and taps Install. Decide how you will walk him through that, and how often you are willing to.
7. **You cannot skip IMAP by using a Gmail gateway.** See §2; it is a demo lane only.
8. **Budget and the one gate:** ~1–2 weeks to the approved mock prototype, in parallel with a **1–3 day libetpan spike that is the project's go/no-go**. If the spike fails, the realistic options are a hand-rolled ObjC IMAP client (2–3 months) or reopening the Swift lane.
9. **The Swift escape hatch, if you want it:** downloading Xcode 26 as a `.xip` with your Apple ID (on Linux, no Mac) unlocks Swift + SwiftMail entirely. It is ~10 GB and raises an unresolved licensing question (Apple's EULA limits Xcode to Apple-branded hardware; the community SDK mirrors redistribute Apple headers). That is your call, not an engineering one.
10. **Housekeeping:** ~5.9 GB of Swift scratch is parked at `/mnt/extra/cmail-swift` and `~/.swiftpm`. Keep it if you want the lane open; delete it if you have decided.

---

## 6. WHAT THE INVESTIGATIONS COULD NOT ESTABLISH

- **Nothing was compiled for the mail engine.** No iOS SDK on this host and nothing was built on the iPad, so every "libetpan/MailCore2 will build" claim is source and build-file inspection, not a green build. The E0 spike exists precisely to close this.
- **Whether the Swift binary runs.** It links with correct load commands, but it was never bundled, signed, or launched. "Links" ≠ "runs".
- **Whether MailCore2's 2013-era C++ survives clang-16 and a modern libc++.** Last built in anger against Xcode 13; the repo has no CI at all. And `master` needs libetpan HEAD (for `mailactivesync.h`) while its own scripts still pin libetpan at a 2017 commit — an untested combination.
- **Whether Gmail still accepts app-specific passwords for IMAP/SMTP in 2026.** This was not checked. If Google has retired them, every engine option needs XOAUTH2 plus a registered iOS OAuth client, which materially changes the estimates.
- **Which iPad model, which iPadOS version, which mail provider, and which mailbox.** None of it is known, and items 2–4 of §5 all hang on it.
- **Whether Apple's pane widths were fixed points or fractions of the width.** One screenshot at one screen size cannot distinguish them. 375 pt being exactly the iPhone portrait width hints at hard-coding, but that is a hunch.
- **`UIBarButtonItem` frames and tap targets.** Every toolbar number is a glyph *ink* bounding box; the invisible 44×44 pt hit areas are not recoverable from pixels and must come from the accessibility requirement.
- **The exact font weight name** (Semibold vs Medium) — "semibold" is the best fit from a 4 px stem at 17 pt versus regular's 3 px.
- **The 11 pt toolbar status text and 13 pt banner text** are ±1 pt and ±0.5 pt respectively; everything at 15/17/22 pt is unambiguous.
- **Whether pane A's 8.5 pt "Edit" inset is an iOS 10 beta quirk or intentional.**
- **Whether "semibold for read rows" generalizes** — only one read row is visible in the reference.
- **Whether Developer Mode is needed on a stock iPad,** and whether iOS 18+ demands a restart after an ad-hoc install. Apple's own docs conflict; every install so far went onto a jailbroken device, which proves nothing about a stock one.
- **Whether a profile-only refresh can replace an app's embedded profile without a full reinstall** — directly relevant to the 2027 renewal.
- **Whether theos `SUBPROJECTS` handles a 200-file C library.** Documented in `rules.mk`, never exercised on this pipeline. A plain hand-written Makefile producing `libetpan.a` plus `_LDFLAGS` in the app Makefile is the lower-unknown fallback.
- **The legal status** of the community SDK mirrors and of running Xcode's toolchain on non-Apple hardware. Flagged, not adjudicated.
