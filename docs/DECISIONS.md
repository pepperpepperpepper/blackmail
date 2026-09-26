# Decision log

Every place this build departs from `spec/`, and why. The brief was written
without knowledge of the toolchain it has to be built in, so some departures are
forced rather than chosen; those are marked FORCED.

---

## D-001 — Swift, cross-compiled on Linux

**Status:** RESOLVED 2026-09-19, then FLIPPED the same day
**Flipped by:** the owner, once the ~10 GB download was weighed and accepted

The switch condition written into this entry fired within the hour. Downloading
Xcode 26 as a `.xip` (on Linux, with an Apple ID, no Mac) supplies the iOS 26
SDK and its Swift 6.2 stdlib, which is the whole of what SwiftMail needs. So the
choice is no longer "Swift without SwiftMail vs ObjC without SwiftMail" — it is
Swift **with** SwiftMail, and that wins on every axis the ObjC case was built to
defend against.

What this buys back, item by item from the losses listed below: SwiftMail
itself; `async`/`await`, which the entire `MailRepository` protocol is written
in; memory safety where untrusted MIME and IMAP responses are parsed, which was
the most serious of the losses; the starter's domain models; and XCTest.

It also means `spec/starter/` is reusable rather than discarded — with the
corrections in D-002 and in `BUILD_DECISION.md` §4, which still stand, because
they are about the starter being wrong rather than about the language.

The libetpan plan in `BUILD_DECISION.md` §2 is superseded. The E0 spike that
was the project's go/no-go is cancelled; SwiftMail is the engine.

Toolchain and its one remaining blocker: `docs/TOOLCHAIN.md`.

### The reasoning before the flip, kept because the tradeoff is worth remembering

**Forced by:** not the absence of a Swift toolchain, as it turns out

The surprise: **Swift for iOS on Linux works.** The investigation did not just
research it, it built it here — swift.org's Swift 6.2 Linux toolchain, a
community-mirrored iPhoneOS SDK, and xtool's patched `ld64.lld` compiled and
linked a UIKit app to a genuine arm64 iOS-device Mach-O (`LC_BUILD_VERSION
platform=2, minos 16.0`), and `swift build --swift-sdk arm64-apple-ios` worked
end to end in 57 s. No Mac, no Xcode.

It still loses, because the only reason to want Swift here was SwiftMail, and
SwiftMail needs a Swift 6.2 stdlib, which means the iOS 26 SDK, which means a
~10 GB Xcode 26 `.xip` from Apple. Against the newest freely-mirrored SDK
(18.6) SwiftMail produces 731 errors; against 16.5, 1,239 errors and a
reproducible compiler segfault. So the real choice was never Swift vs ObjC — it
was *Swift without SwiftMail* vs *ObjC without SwiftMail*, and once the engine
is gone, Swift costs a 3.2 GB toolchain, a deployment floor raised to iOS 16.0,
and a single 43 MB linker from one person's LLVM fork as the only thing on
earth that links iOS Mach-O on Linux.

Against a pipeline that is already proven.

**The switch condition, recorded so it is not forgotten:** if the owner is ever
willing to sign in with an Apple ID and pull the Xcode 26 `.xip` onto this Linux
box — no Mac needed, xtool automates it — Swift and SwiftMail both become
viable and this decision flips. The Swift scratch build is parked at
`/mnt/extra/cmail-swift` so the lane stays open.

**What Objective-C costs us, stated plainly:** SwiftMail itself (maintained,
BSD-2, real IMAP MOVE/APPEND/IDLE and SMTP XOAUTH2); `async`/`await`, which the
whole `MailRepository` protocol is written in; memory safety exactly where
hostile input lands, since C parsers will be handling untrusted MIME; every
`.swift` file in `spec/starter/`; and XCTest, which is not a solved problem on
this pipeline.

### The original finding, kept for the record

**Forced by:** absence of a Swift toolchain

`spec/starter/PROJECT_SETUP.md` says to create an Xcode project, add SwiftMail
through Swift Package Manager, and archive in Xcode. Verified today:

| | |
|---|---|
| `swiftc` / `swift` on the iPad | absent |
| `swiftc` / `swift` in Procursus | absent |
| `swiftc` / `swift` on the Linux host | absent |
| `.swiftmodule` interfaces in the theos iPhoneOS16.5 SDK | **present** |
| Swift runtime on the target device | present, in the dyld shared cache |

So the SDK side of Swift is there and the runtime side is there; the compiler is
the only missing link. That makes the question "can we get a Swift compiler that
emits arm64-apple-ios, without a Mac?" rather than "is Swift possible at all?",
and it is worth answering properly before defaulting to Objective-C.

Options under evaluation:

1. Objective-C on the existing theos pipeline. Proven in use.
   Costs us SwiftMail, so IMAP has to come from somewhere else.
2. A Swift cross-compilation toolchain on Linux targeting Darwin.
3. A hosted macOS CI runner for the build step only. CI is an acceptable
   lane for some apps, but this app is a 90-year-old end user's
   daily mail client, and making every rebuild depend on a rented cloud Mac is a
   different kind of commitment.

Resolution and reasoning to be recorded here once the evidence is in.

---

## D-002 — `.sidebar` contradicts the brief, and so does `.tripleColumn` itself

**Status:** RESOLVED 2026-09-19 — confirmed, and it goes deeper than I thought

`primaryBackgroundStyle = .sidebar` must be deleted. Either it does nothing on
iOS (Apple's current docs say it is a Mac Catalyst affordance) in which case it
is dead code that misleads the next reader, or it does something, in which case
it draws precisely the modern sidebar the product exists to avoid.

The deeper problem I missed: **`UISplitViewController(style: .tripleColumn)` is
itself the iPadOS 14 sidebar redesign API.** It did not exist in 2016. It is
adaptive by construction and its column widths are merely "preferred" — the
supplementary width is silently clamped to 320 pt on every modern iPad, so the
starter's 0.30 fraction would never be honoured. Using the API that embodies the
redesign to reproduce a pre-redesign layout is backwards.

**Decision:** no `UISplitViewController`. A plain container view controller with
three child `UINavigationController`s and hard Auto Layout constraints. Keeping
a navigation controller per pane buys the correct 20+44 pt chrome, centred 17 pt
titles, and free 44×44 pt bar-button hit targets.

### The original finding, kept for the record

`spec/starter/ClassicMail/UI/RootSplitViewController.swift` sets

    super.init(style: .tripleColumn)
    primaryBackgroundStyle = .sidebar

`.sidebar` is the *modern* iPadOS translucent sidebar treatment introduced
alongside the iPadOS 14/15 redesign. `spec/docs/UI_SPEC.md` calls for "Pane A —
White background, plain table rows" and "No oversized section cards", and
`spec/docs/PRODUCT_SPEC.md` forbids visual redesign. If `.sidebar` renders the
contemporary look, the starter code specifies exactly the thing the brief
prohibits, and the starter is wrong rather than the brief.

---

## D-003 — TWO panes

**Status:** RESOLVED 2026-09-19 by the owner: two panes
**History:** I closed this once on the wrong reasoning, reopened it, and it is
now answered by the only authority that counts.

The layout is the iOS 10/11 two-pane iPad Mail arrangement:

- **Left column** — a navigation *stack*, not a fixed list. Root is Mailboxes;
  tapping a mailbox pushes its message list on top, with a labelled
  `< Mailboxes` back button top-left. This is the column that changes.
- **Right column** — the message. It never navigates; it only swaps content.

Why this is better here, not merely more faithful:

1. It is what his hands know, which is the entire product.
2. The message gets more width on an 11-inch iPad, where three columns would
   leave the reading pane cramped.
3. The mailbox list, when shown, gets the *full* left-column width instead of a
   287 pt sliver — bigger targets, and longer folder names before truncation.
4. One fewer permanent region is one fewer place for a control to be.

**What carries over from the three-pane measurements, unchanged:** every row
height, baseline, inset, the 12 pt unread dot, the toolbar order
(Flag/Move/Delete/Reply/Compose) and the detail header metrics. Those were
measured inside the message-list and message panes, and both still exist. The
measurement work survives intact — only the pane arrangement differs.

**What changes:** pane A stops being a column and becomes the left column's
root view controller. Left column width is the message list's measured 375 pt,
not 287+375; the detail pane takes the remainder.

**Still to settle (layout, so it matters):** what portrait does. The brief
allows collapsing but demands obvious Back navigation and no gesture discovery.
Options are a permanently visible left column at reduced width, or the classic
overlay driven by a labelled button. Not blocking the landscape build; both
keep control order identical.

---

## D-004 — The app stops working on 2027-09-18, and he will not know why

**Status:** RESOLVED as to fact; the mitigation is unbuilt and needs a human owner

Verified against the actual certificate and profile on this host: the ad-hoc
provisioning profile and the Apple Distribution certificate expire at **the same
instant, 2027-09-18 10:22:36 UTC**. Apple states an app whose embedded profile
has expired will not launch.

So this is not a vague risk, it is a scheduled outage with a timestamp, landing
on someone who cannot diagnose it and may not be able to describe it.

Required:
1. A calendar reminder at **2027-08-01** — renew membership, regenerate the
   profile, re-sign, re-publish. Six weeks of slack, deliberately.
2. A named human who does it if the owner is unavailable. This is the part that
   actually fails.
3. An in-app warning. The app knows its own profile's expiry date; it should say
   so in plain language for the last month rather than dying silently. Cheap to
   build, and it converts a mystery into a phone call.

---


## D-005 — WITHDRAWN. Appearance is not the requirement; layout is.

**Status:** withdrawn 2026-09-19; the premise was wrong
**Superseded by:** D-007

I argued the old iPhoneOS16.5 SDK link was the build's most valuable property,
because Apple gates UIKit appearance changes on the linked SDK, so an old-SDK
binary gets legacy appearance from a modern iPadOS — a frozen look, for free.

The correction: appearance is not the issue; layout is.

That removes the argument entirely. This product is not trying to look like
2016. It is trying to put the mailbox list, the message list, the message and
the action buttons where a 90-year-old man's hands already expect them, and keep
them there. Whether the navigation bar is drawn with a 2016 gradient or a
current material does not affect that, and pinning an old SDK to control it was
solving a problem nobody has.

Consequences, all simplifying:
- No reason to avoid the iOS 26 SDK, so no tension with the Swift lane.
- The `-platform_version` trick I was about to test (compile against a new SDK,
  declare an old one) is dropped, unneeded.
- `docs/LAYOUT_CONSTANTS.md` splits in two — see D-007.

What this does NOT relax: **control position and order remain absolute.** That
is layout, it is the whole product, and it is frozen.

---

## D-006 — We cannot test on the target hardware

**Status:** open, needs owner action

The only device here is the jailbroken iPad13,6 on iOS 16.5; the targets are
newer hardware on a much newer iPadOS. Less alarming now that D-005 is
withdrawn — appearance drift across OS versions no longer matters — but layout
still has to be confirmed on a real target, because safe-area insets, default
navigation metrics and Dynamic Type all shift what fits.

1. **Register one target iPad and install on it.** The profile carries one
   UDID today, and it is the dev iPad. Adding a device means regenerating the
   profile and re-signing everything — the `resign-all` fan-out, still unwritten.
2. Pin layout explicitly rather than inheriting defaults. Required anyway.

Until then, screenshots from the dev iPad are evidence about layout logic, not
about what he will see.

---

## D-007 — Which measurements are binding, and which are advisory

**Status:** decided 2026-09-19, follows from D-005's withdrawal

`docs/LAYOUT_CONSTANTS.md` holds 86 measured values. They are no longer of equal
weight.

**Binding — these are the product:**
- pane widths and the three-pane/two-pane arrangement
- row heights and the vertical rhythm inside a row (baselines, the unread dot)
- separator insets, text column left and right edges
- toolbar control ORDER and position, and the 44×44 pt hit targets
- which controls exist at all, and that none is hidden behind an ellipsis

**Advisory — match if free, never fight the OS:**
- exact greys (`#C8C7CC` vs `#C8C8C8`), bar fills, selection tint
- hairline widths, gradient and material treatments
- the system font's precise weight name

**Explicitly reopened by the user being 90 years old:** font sizes. The brief
says to match old iPad Mail's scale, which is 15 pt body and 17 pt sender. That
was designed for 2016 eyesight, not for a 90-year-old man. Period fidelity and
legibility genuinely conflict here, and per the product's own logic legibility
should win — but larger type changes row heights, which *are* binding, so it
cannot be adjusted casually at the end.

Proposal, needs the owner: build at the measured scale, then offer one
admin-screen text-size setting with two or three fixed steps that scale the row
heights with the type so the rhythm survives. Do NOT wire up free Dynamic Type —
an accidental swipe in Control Centre must never rearrange his mail.


---

## D-008 — Landscape only, and the header order comes from his screenshot

**Status:** decided 2026-09-19 from the owner's reference screenshot

The owner supplied a photograph of the iPad Mail he means, and the
requirement is landscape. Two consequences.

**Landscape is now the only supported orientation.** `spec/docs/UI_SPEC.md`
already calls landscape the primary target and portrait "secondary", and the
brief permits collapsing in portrait. Locking it goes further than that, and
deliberately: the product's whole thesis is that nothing rearranges, and an
orientation change is the largest rearrangement there is. A 90-year-old who
picks the iPad up at a different angle should not get a different app.

The cost is real and should be said: if he reads in bed holding it upright, the
content will be sideways. One Info.plist key reverses this, and the two-pane
portrait layout already worked — see the earlier screenshots — so nothing is
lost but the decision.

**The detail header is reordered, and the earlier measurement was misleading.**
The 12.9-inch reference I measured put the subject first at 22 pt. His
screenshot does not:

    Sarah Castelblanco        sender, blue, semibold
    To: Eden Sears            grey
    ----------------------
    Not the same without you  subject, black, bold, about sender-sized
    Today at 9:14 AM          grey
    ----------------------
    body

So the subject sits *third* and is close to body size, not 22 pt. Both
observations are accurate about their own screenshots; his is the one whose
layout his hands know, so his wins. `Theme.fontDetailSubject` drops 22 -> 17
and `MessageHeaderView` is rebuilt in that order.

Also taken from it: `Edit` in the left column's navigation bar rather than a
compose button (compose lives once, in the detail toolbar), and the bottom bar
reading "Updated Just Now" — which looks decorative and is not. It is the only
thing on screen that answers "is this actually my mail, or is it stale?", a
question that otherwise ends in a phone call.

Still omitted: the sender avatar in his screenshot's header. The brief bans
sender photographs, and the ban still looks right — it costs horizontal room
and says nothing the name beside it does not. Easy to add if he misses it.

## D-009 — Three panes. D-003 is reversed, by the owner.

**Decision:** Mailboxes | message list | message, all three permanently on
screen, at 20.9% / 27.6% / 51.5% of the screen width.

D-003 chose two panes and the owner confirmed it. The requirement is now the
iOS 10 12.9-inch three-pane reference, which the owner supplied. That call is
made; this entry exists so nobody re-litigates it from the older note.

**Measured**, from the primary iOS 10 12.9-inch reference listed in
`spec/references/REFERENCE_SCREENSHOTS.md`, kept locally as
`spec/references/ios10-12.9-threepane.png` and never committed (it is
Macworld's image). Unlike the owner's own photo this IS a raw screenshot —
580×435, aspect exactly 1.3333, no bezel — at 2.3552 pt/px. The two dividers are the only full-height
low-variance dark columns in the image, at x=121 and x=281:

    mailboxes  285 pt of 1366 = 20.9%
    list       377 pt         = 27.6%
    message    704 pt         = 51.5%

Verified on device at 1194 pt: 250.0 / 330.5 / 613.5 pt, i.e.
20.9% / 27.7% / 51.4%. Within 0.1% of the reference on every pane.

**What three panes buy:** no back button anywhere, and no state in which the
folder you are reading is hidden. "Which folder am I in" becomes something he
looks at rather than remembers, and the selected folder stays highlighted to
say so. For this user that is worth more than the width it costs.

**What it costs, stated plainly:** the reading pane drops from 703 pt to
613 pt, and the folder pane from 370 pt to 250 pt, so long subfolder names
truncate sooner. If reading width turns out to matter more to him than the
permanent folder list, the two constants at the top of `Theme` are the whole
change — this is one line to revert, deliberately.

**Row metrics do NOT come from this reference.** It measures 103.6 pt message
rows and 44.7 pt mailbox rows, which is where the old 104 came from — but it
is a 12.9-inch iPad. The owner's own screenshot says 96, and the standing rule
holds: this reference supplies STRUCTURE, his supplies ROW METRICS, because
his is the iPad he actually used.

**Refresh moved** from the folder pane to the list's bottom bar. At 250 pt the
folder pane left only 8.5 pt between "Mailboxes" and the button (measured). It
now sits bottom-left, the slot the reference uses for its filter control, next
to "Updated Just Now" — the label states the freshness and the button beside
it acts on that. It reloads the folder list too, since someone who taps
Refresh means "get my mail", not "get my mail but leave the unread counts
stale". The brief's point is intact: a visible labelled control, never
pull-to-refresh alone.

## D-010 — The app ships dark. Appearance is now a requirement.

**Decision:** black canvas, white text, blue tint, pinned with
`overrideUserInterfaceStyle = .dark` and never following the system.

The owner had the iPad running **Smart Invert** (confirmed on device:
`InvertColorsEnabled 1`, `AXSClassicInvertColorsPreference 0`), liked what it
did to the app, and that look became the shipped default, with no
accessibility setting required.

This retires the last of D-005's "appearance is not the requirement". Layout
was always the requirement; appearance became one too the moment he specified
it, so the palette in `Theme` is now stated rather than inherited.

**The neutrals are the literal 255-x inversion** of the light values they
replace, because that is what the filter was doing to them:

    canvas   255 -> 0      barFill    249 -> 6
    separator 200 -> 55    selection  217 -> 38
    searchBand (201,201,206) -> (54,54,49)

**Three colours are deliberately NOT inverted.** A display filter cannot know
that a hue carries meaning, and inverted these read as: tint blue -> orange,
Delete red -> cyan, flag orange -> blue. Blue-on-black is what every other app
on his iPad uses for "you can tap this", and a destructive control that does
not look destructive is a safety regression rather than a style choice. These
three are the whole change if he wants the literal version.

**HTML mail is inverted in CSS, not painted over.** A message carries its own
colours and almost always assumes a white page, so a black background behind
it gives black-on-black. The body gets `filter: invert(1) hue-rotate(180deg)`
with images, video and SVG inverted a second time to cancel it — which is
precisely what Smart Invert itself does, and why a photograph still looks like
a photograph.

**Smart Invert must now be OFF**, and the app CANNOT defend itself. See B-006.

---

## D-011 — The app password is masked only when the iPad has a passcode

**Status:** RESOLVED 2026-09-20
**Confirmed by:** the owner, as the right trade for the handover; not to be
flipped

Not a departure from `spec/` so much as a collision with iOS. Recorded here
because it is a security-relevant behaviour that was reviewed and accepted,
rather than one that arrived by accident — the next person to read
`isSecureTextEntry` being conditional should find a decision, not a puzzle.

**The forcing constraint.** A secure text field makes iOS treat the form as a
login form and offer Password AutoFill. AutoFill requires a device passcode.
Without one, iOS presents "Set A Passcode" over the app and dismisses the
keyboard, which makes the field impossible to type into at all. Full
diagnosis in B-009; suppressing AutoFill with `textContentType` does not
work, because the trigger is the secure field itself.

**What was chosen.** Ask `LAContext` whether a passcode exists, and mask only
then. On an ordinary iPad nothing changes. On a passcode-less one the field
is plain and its placeholder reads "shown as you type", so the state is
disclosed rather than silent.

**Why this way round.** The secret is a Google APP password: single-purpose,
mail-only, revocable without touching the account password, and typed exactly
once on setup day with a helper present. Weighed against that, a
setup form that cannot be completed is the larger harm — it is the only route
into the product since D-010's bootstrap import was removed (B-010).

**The escape hatch, if the judgement ever changes.** Setting a passcode on
the iPad restores masking with no code change. That is worth knowing during
setup: it is a device setting, like Smart Invert in B-006, and the same visit
can decide both.

**What would reopen this.** A second secret ever being typed into this app —
an OAuth token, a second account, anything not revocable in one click — would
break the premise the trade rests on, because the reasoning is about the
value of *this* credential and not about passwords in general.

---

## D-012 — The calendar button, and Mail's habits beating our doctrine

**Decided 2026-09-20.** Three ratified rules bent at
once, so all three are written down together rather than discovered later as
inconsistencies.

**The requirement.** Match Apple Mail, which he already uses and knows. He
is very old, and his main difficulty has been getting back to a date, so
that has to be easy: the calendar button must be easy to reach.

Two halves, and the order matters. Match Mail wherever Mail has an answer,
because he already has the habit. Where Mail has NO answer and he is stuck
anyway — getting back to a date — invent, and make it obvious.

### 1. A control the reference does not have (D-007 says which controls exist is BINDING)

A calendar button now sits in the message list's leading nav-bar slot, and
opens a month grid that reopens the folder at the chosen day.

Mail has never had this. That is the reason it exists: its absence is the
specific thing that goes wrong for him, and Mail's only
answer — scroll — does not work when the day is four months and two thousand
letters up. The slot chosen is the one permanently empty and permanently
visible in that pane (no back button ever appears there, per D-009), so
nothing displaces it and it is never one tap deep in anything.

### 2. Contextual chrome (UI_SPEC:46, BRIEF:14, README all forbid it)

Cancel and a Current Mailbox / All Mailboxes scope bar appear when the search
field is focused and leave when it is not. "Controls never move based on
context" is one of this project's stated non-negotiables.

It loses here, and to its own purpose. The rule exists so a 90-year-old never
hunts for a button that wandered — a good rule for habits we are creating.
This is not one of those: he has used Mail for years, Mail reveals exactly
these two controls on focus, and matching a habit he HAS beats protecting him
from one he does not. The rule's substance is kept: the search field itself
never moves, nor does anything above or beside it. What appears, appears
below, and only while search is on.

### 3. "Search current mailbox" (PRODUCT_SPEC:67), and what it is not

Search now defaults to All Mailboxes, implemented as one SELECT of Gmail's
`\All`. The spec's v1 line is a floor, not a ceiling, and `.currentMailbox`
still exists as the other half of the control.

It does NOT contradict the excluded "unified inbox" (PRODUCT_SPEC:73), which
is several ACCOUNTS merged into one list. There is one account. The
commonest search is "find that letter", and the folder he happens to be
standing in has nothing to do with where it is filed — which is why Mail
defaults the same way.

**Known limit, by Gmail's design.** All Mail excludes Trash and Spam, so an
All Mailboxes search will not find a deleted message. Covering those needs
two more SELECT + SEARCH round trips per query and was not spent.

### What would reopen any of this

Point 2 in particular is a doctrine change, not a feature. If it turns out he
DOESN'T reach for search in Mail — at the time nobody was sure whether he
did — then the scope bar is contextual chrome bought for nothing,
and the honest move is to delete it rather than defend it. The date jump does
not depend on it.

### Resolved, same day

It turned out **he uses search all the time.** So the
contingency above is closed and the scope bar stays. Two consequences beyond
keeping it:

- Search is a PRIMARY path, not a secondary one, and should be treated as
  such when weighing future work against the date jump.
- TO and CC were added to the search fields immediately (`SearchCriteria`).
  Searching a correspondent's name had matched only letters that person
  SENT him — every letter he wrote to them was invisible, which is half of
  any correspondence and exactly what daily use would hit.
- B-011 (an All Mailboxes search cannot reach Trash) is promoted from
  "probably not worth it" to a live question, because its own stated
  trigger has now half fired.

## D-013 — "Whatever Apple Mail composes" is HTML, not a format bar

The requirement is to compose whatever Apple Mail composes, and the
question was whether that means rich text. It means HTML. It does not
mean a rich-text editor, and building one would have made his mail
worse rather than better.

**The evidence, not the reasoning, is what decided this.** 715 of his
own sent messages, three years, and the region he typed himself
contains only `div`, `br` and text. Not one bold word. What forces his
mail into HTML is his signature and the originals he quotes, never his
typing. See INVESTIGATIONS for the counts.

**So the app emits an HTML twin and keeps the plain composer.** The
editor still holds a `String`; `AppleMailHTML` builds Apple's document
around it at BUILD time, and `RFC5322Builder` sends both as
`multipart/alternative`.

**Rejected: a real rich-text editor**, by both available routes.

`UITextView` with `allowsEditingTextAttributes` is one line and gives
the system Bold/Italic/Underline menu free, and it is the wrong answer
here. The serialiser it needs is the easy half; the hard half is that
`NSAttributedString`'s HTML READER is documented as unfit for general
HTML, is main-thread-only, can time out, and has no `NSTextTable` on
iOS — so his pasted Google-Docs signature table cannot survive a round
trip at all. It would introduce a new way to destroy his signature and
his quoted threads, on a ninety-year-old's iPad, in exchange for
formatting he has never used. (Worth recording that the thing feared
first, that iOS cannot WRITE HTML from an `NSAttributedString`, is
false — it is `API_AVAILABLE(ios(7.0))`. The hazard is the other
direction.)

`WKWebView` with `contentEditable` is what Mail itself does, and it is
a composer rewrite that moves the body state out of Swift and into
JavaScript. If the capability is ever wanted, this is the route, and
the HTML emitter built now is a prerequisite under it either way.

**What this does not deliver.** Inline photographs still land as
attachments at the bottom rather than at the cursor; Mail puts them in
the body flow as `cid:` parts inside `multipart/related`. Exactly one
message in 433 is a photo he placed in his own typed region, so this
is deferred rather than dismissed — see B-025.

## D-014 — "Organize by Thread", Mail's own switch, hung on the seam

The measurement said keep grouping (see INVESTIGATIONS, 2026-09-21: no
message in his mail displaced by even a week; rows announce their own
size). But several of his recent messages report mail seeming to
disappear, and grouping is the one feature whose mechanic is showing one
row where there were several — so the off position now EXISTS, as a
switch in Settings in Mail's own words, rather than as a code change
someone would have to make under pressure.

`MessageThread.rows(for:grouped:)` — added so search results would stop
being grouped — is the seam, and this is the whole reason it was built
as a function rather than an inline call. The list passes
`filtered == nil && ConversationSettings.organizeByThread`.

**Default ON**, which is Mail's default. The read uses
`object(forKey:)`, not `bool(forKey:)`: `bool(forKey:)` answers false
for a missing key, which would make the default silently become
ungrouped. Pinned by a test.

**It acts immediately**, not through Save. It is a way of LOOKING at
the mail, not a fact about the account, and a switch left visibly
flipped with nothing changing behind it until another button is pressed
is its own trap. The list regroups while the sheet is still up.

**Search stays ungrouped whichever way the switch points.** The two
rules compose at the seam; a test pins it.
