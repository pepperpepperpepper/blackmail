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
**See D-015:** since 2026-09-29 this arrangement is back, as his choice beside D-009's three.
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

**See D-015:** since 2026-09-29 these three are the default of two arrangements, his choice.

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

**See D-015:** in two panes the view button and `< Mailboxes` come before the calendar in this slot, and the calendar is one tap away while the folders are in front.

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

## D-015 — Two panes or three, his choice, three by default

**Decided 2026-09-29 by the owner:** "there should be a 2 pane and three
pane view (switchable), I believe Apple Mail had that at one point as
well." It did, and on the very layout D-009's three panes were measured
from.

**The authority.** iOS 10 Mail on the 12.9-inch iPad Pro: "A new view
button in the top-left corner toggles between two-pane and three-pane
appearances. Tapping the button adds and removes the additional column"
(9to5Mac, 2016-06-14,
https://9to5mac.com/2016/06/14/ios-10-adds-three-pane-appearance-for-mail-and-notes-on-ipad-pro-12-9-inch/).
MacStories' iOS 10 review says the same: "it can be disabled by tapping a
button in the top left of the title bar". So D-003 and D-009 stop being
rivals. Mail had both and a button between them, and D-012's rule, that
Mail's habits beat our doctrine, puts both here and the button where Mail
put it.

**Three panes** are D-009 exactly: 20.9% / 27.6% / the rest, which is
250 / 330 / 613 pt at 1194 (11-inch) and 285 / 377 / 703 at 1366
(12.9-inch). They are the default, so nothing changes for him until he
taps the button.

**Two panes** are D-003: the left column holds the Mailboxes or a folder's
list in turn, and the message takes the rest and never navigates. A folder
tapped brings its list in front, loaded exactly as a tap in the three-pane
sidebar loads it, with `< Mailboxes` top-left; `< Mailboxes` shows the
folders again with the open one highlighted; the folder already open,
tapped, brings back its list as he left it and fetches nothing. The left
column is D-003's 375 pt, fixed: 375 | 818.5 at 1194, 375 | 990.5 at 1366.
375 is the list's width on the 12.9-inch reference (377 measured), so there
the switch really does just add and remove the Mailboxes column. The
owner's own photo, a two-pane iPad at 1024 pt, puts the divider at 31%,
which is 370 on the 11-inch. A fraction was not taken because what the
column holds does not grow with the screen, and 31% of a 1024 pt iPad is
317.

**The view button** is `sidebar.left`, the symbol later iPadOS draws for
the same control (which glyph iOS 10 drew is not known here), with a 44 pt
target. It is the first item in the bar whose left edge is the screen's,
so it is in the same place in both arrangements: the Mailboxes' bar in
three panes, and in two the left column's bar, whichever of the two is in
front. VoiceOver reads "Hide Mailboxes" in three panes and "Show
Mailboxes" in two.

**Every control in the two bars, both ways:**

| | three panes | two, folders in front | two, a list in front |
|---|---|---|---|
| Mailboxes' bar | view button · "Mailboxes" centred | view button · "Mailboxes" centred | hidden |
| list's bar | calendar · folder name · Edit | hidden | view button · `< Mailboxes` · calendar · folder name · Edit |

The calendar is not displaced (D-012). It stays the list's leading item,
the one beside the title, never replaced and never a tap deep; in two panes
the view button and `< Mailboxes` come before it in the same slot. Edit
stays at the trailing edge and the title between. When the bar is full it
is the title that gives way, cut short with an ellipsis, never a button
and never the word "Mailboxes": at 1194 in two panes the title has about
75 to 85 pt, less with Done than with Edit, which Gmail's own folder names
fit, "Sent Mail" only just, and a long name of his own does not. In three
panes it has about 185. These are estimates from the font's metrics; the
iPad has to confirm them.

**A switch moves things and changes nothing else.** Nothing is fetched.
The folder, its list with his place in it, a search with its text, scope,
results and keyboard, Edit mode and his ticks, the letter in the reading
pane and whatever sheet is open are the same objects afterwards. Edit mode
is kept rather than ended: it is his work in progress, and the switch is
about the room, not the work. From two to three with the folders in
front, the open folder's list goes back in the middle. There is no
animation: an animated switch would slide the list and reflow the letter
and every row for a quarter of a second, where this is one step. Nothing
moves up or down, since the rows are a fixed height and the list keeps
its offset. And the button takes a tap only when nothing else is being
touched, so nothing slides out from under a finger already down.

**Not a navigation controller push, though it works like one.** The list
stays in its own navigation controller in both arrangements and the two
controllers take turns in the left column. Pushed, the list would leave
the window at every switch, and the search field with it, keyboard and
all; and a pushed list's back button is UIKit's, which always takes the
corner the view button needs, and shortens itself to "Back" or a bare
chevron when the bar is full. `< Mailboxes` is the app's own, and keeps
its word.

**Kept across launches**, in `UserDefaults` under `blackmail.panes`, read
with `object(forKey:)`: missing, or anything but "two" or "three", is
three. Later versions of Mail did not keep the choice, and people who used
them complained.

**Unchanged:** row heights and every other metric inside the panes, the
reading pane's toolbar and its order, portrait (there is none, D-008), and
B-003. Coming back after a while lands him on the Inbox's list, in front
in two panes, and leaves two panes two.

**The cost, stated plainly, is D-009's argument run backwards.** In two
panes, while he reads, the folder he is in is a title and not a
highlighted row, and the folders are a tap away rather than in sight. The
letter gets a third more room. Which matters more to him is his to find
out, which is why it is a button and not a decision made here.

---

## D-016 — A copy of his mail is kept on the iPad, and it is only ever what the server last said

**Decided 2026-09-30 by the owner**, choosing the smallest of three designs
compared (the smallest, Mail's own with a database and a background keeper,
and a correctness-first one whose identity rules are taken in here).
The performance review called having no persistence "a deliberate and
defensible trade" (PERFORMANCE.md, What is fine). For him it is not: every
launch after iOS has ended the app is an empty Inbox for seconds, and with
no connection an empty Inbox full stop. The spec asks for the cache (BRIEF,
ACCEPTANCE_TESTS: "Cached Inbox appears within 500 ms", "Offline launch
still shows cached messages", PRODUCT_SPEC: cached reading offline).

**What is kept:** the folder list with its last counts; the newest page of
each folder, as the last listing from the top gave it; and the whole of the
last 300 letters he opened, at most 64 MB, none over 8 MB, never a draft.
**Not kept:** pages below the first, date jumps, searches, letters he never
opened, and any queue of offline changes.

**The rules.** A page is replaced whole by each listing from the top of its
folder, and changed in between only by his own writes after the server's
OK. A letter is served only for the exact folder, UIDVALIDITY, UID and
Gmail message id (X-GM-MSGID) it was fetched under; Gmail Inboxes report
UIDVALIDITY 1, so the message id is what tells two mailboxes apart. A
changed UIDVALIDITY or a mismatched message id on the first page discards
the account's copy. Nothing is sent on a kept row until the server has
vouched for it. The copy is wiped whenever a password is saved (the Gmail
app-password trap, B-033), is excluded from backup, and never appears in a
log. The wire is unchanged except for X-GM-MSGID in the summary FETCH.

**What he sees.** At launch, the kept Inbox and folders in the first frame,
"Checking for Mail…" until the fresh page replaces them, then "Updated Just
Now"; the swap waits for a finger to lift and keeps a place he has
scrolled to (B-042). With no connection, the kept pages stay, the status
line says how old they are ("Updated Yesterday"), and the same one "Can't
connect to mail server." alert as today is kept, as the strongest cue that
the list is old.

**Format: Codable JSON files, not SQLite or Core Data.** This departs from
ARCHITECTURE.md, which asks for a choice and a reason. The reason: nothing
kept is ever queried, only read whole and replaced whole, and JSON runs in
the Linux host suite with nothing added. There is no migration: a file of
another version is deleted, and costs one launch like today's. It owns the
migration, corruption and staleness bug classes the performance review
said the app had avoided.

**Phases.** 0: take out the logging of his correspondence (the B-033
`PAIR` probe, the sender in `SESSION-IDENT`) and add X-GM-MSGID to the
summary FETCH; he notices nothing. 1: the kept folder list and first pages.
2: the kept letters. **Each needs its own decision later:** fetching unread
mail ahead for offline reading, keeping more than one page, offline search.
**Alongside, not inside it:** a local Save Draft with autosave, then an
Outbox (the gap review's "Ways a letter is lost"). They may share the
directory and its atomic write; the cache's wipe and eviction must never
touch them.

**Phase 0, done 2026-09-30.** The `PAIR` probe is out of the tree, and
`SESSION-IDENT` keeps its folder, uidv, exists, uids and first-row but no
longer names a sender. It gains `msgid=`, the first row's X-GM-MSGID: on
Gmail first-row is the thread id, which every letter of a conversation
shares, and the sender was what told apart which of them headed the list
(B-033 addendum 6). Nothing else written beside the wire named a
correspondent or a subject. Every row carries X-GM-MSGID
(`MessageSummary.gmailMessageID`, nil on a server without X-GM-EXT-1),
asked for in the summary FETCH behind the same capability as the labels
and the thread id, so a listing sends the commands it did.
`KeptCopyTests` pins both. **Left for the owner:** the wire log itself
still carries his correspondence, in the server's ENVELOPE lines
(subjects, names, addresses), BODYSTRUCTURE's file names, X-GM-LABELS,
RCPT TO and the words of a search, and `CaptureProbe` writes the last 500
lines of it to `tmp/` on every send, now kept to the newest ten
(2026-09-30, by the owner's word; `CaptureProbe.kept`). With
`PAIR` gone those files are larger, by up to about three quarters where
the traffic is mostly listings, because the ring fills with the FETCH
lines its notes used to displace (`PERFORMANCE.md`, the `CaptureProbe`
entry). Redacting the wire log would take from it the one thing it shows
that numbers do not, what the server actually said about a letter (a
subject that decodes wrong, a sender that parses wrong), and would mean
parsing every line before logging it.

**Phase 1, built 2026-09-30 and seen on the iPad the same day** (B-053). The kept
folders and first pages, in `MailShelf`: its own record types, format 1,
one JSON file for the folders and one per page under
`Application Support/Kept/<hash of the address and the IMAP server>/`, out
of backup, written behind a moment after each change and at once as the
app goes into the background, another account's directory removed at
launch, and the whole of `Kept/` wiped by `CredentialStore.save` and
`clear`, never `Local Drafts/` beside it. The rules above as they were
decided, and six choices made in building them:

- **A read mark and a flag are patched on the letter wherever it is kept**,
  by its Gmail message id, since Gmail's flags are the letter's and not the
  folder's; a delete or a move to Trash or Spam takes it off every kept
  page but that one; a move out of All Mail to a label takes it off none.
  "His own writes after the server's OK", as Gmail itself applies them.
- **The previews are kept** as they arrive for rows on a kept page, and go
  across to the same letter, by UID and message id, when the next listing
  replaces the page. "The page as he saw it" includes its grey lines.
- **Vouching stops once the mailbox is proven.** A write on a kept row, and
  a letter opened from one, is vouched for until a listing from the top in
  this launch has found kept rows under the same UIDs with the same message
  ids, or the row's own folder has been listed. In practice the Inbox's
  first page proves it within seconds; after that a UID kept for any folder
  names the letter it did or none, since every write names its UIDVALIDITY
  (B-039), and a search hit written on later costs no FETCH. Since
  2026-09-30 this holds only for a call that names no letter: a draft
  removed that was found by its Message-ID or whose draft names none, a
  letter kept in Local Drafts that has gone up, opened from its row, and a
  row from a server without Gmail's extension. A call that names
  its row's letter, which is every other, goes by what the server has named
  under the UID in this launch, proven mailbox or not (below).
- **Opening is vouched for by the FETCH that brings the letter.** X-GM-MSGID
  is asked beside BODY.PEEK[] in the one FETCH the letter costs anyway, and
  compared before anything of it is shown: no round trip more, and the
  FETCH still marks nothing read. Another id, or none, and nothing of it is
  shown, no STORE goes, the pane empties and the row leaves the list, as a
  write's refusal does. A letter from a proven row is fetched byte for byte
  as before. Since 2026-09-30 that is so for an opening that names no
  letter; one that names its row's letter is fetched byte for byte once the
  server has named that letter under its UID in this launch, and asks for
  the id in its FETCH while the server has named nothing there yet; with
  another letter named there, nothing is fetched.
- **The watch fetches the kept page afresh** at its first check that
  reaches the server, and does not search from the kept rows: they are an
  earlier launch's word, and news found from their lowest UID would go on
  top of a page nobody has vouched for. That is also the "letter that
  arrived while offline" appearing once the connection is back.
- **The read stays on the main thread.** A launch reads the folder list and
  the Inbox's page, 27 KB for fifty rows, in a median 1.1 ms on the
  development computer in the debug build, a fresh shelf included
  (`MailShelfTests`), far under the 30 ms at which it was to move off it.

"Nothing is sent on a kept row until the server has vouched for it" holds
for a write and for a letter opened alike. What goes before the server has
vouched is the question alone, a read that changes nothing: the write's
vouching FETCH, or the letter's own FETCH with its id asked beside the body,
PEEK. The write waits for the answer, nothing of the letter is shown until
it has come, and a row the server has disowned stays disowned for the
launch, whichever of a tap's read mark and its FETCH is answered first.
Since 2026-09-30 every write and every letter opened names the Gmail
message id of the row he acted on, and the repository holds it against
what the server has named under that UID in this launch, in a row it sent
or in answer to the question: the same letter goes as before, another is
refused with neither the write nor the question sent, and none yet is
asked. So the kept row still drawn after a listing has thrown the copy
away, which the rule of a proven mailbox above let through unasked, is
refused, and that rule now covers only a call that names no letter (B-053,
"Never the wrong mailbox"). The same holds in the copy's own mailbox,
where it asks more than the rule did: a kept row the fresh page lacks,
pushed off it by mail come since, is still drawn while the swap waits for
his ticks or a finger, and in a conversation opened from the kept page at
launch; a write on it is asked about once, at one round trip, and its
letter opened asks in its own FETCH, at none more, where the proven mailbox
let both go unasked. That stays: asking is the safer, and it is rare.
Not built: the letters (phase 2).

**Alongside it, the letters kept in `Local Drafts/`, 2026-09-30** (B-051).
They are not this copy and are never wiped with it, but they name letters
on the server as it did, by folder and UID, and fell to the same trap: a
password saved that opens another mailbox under the same address, or a
folder renumbered under the same UIDVALIDITY, and the copy a draft was
reopened from, a forward's file or a quoted picture, is another letter. Each
now names its letter by X-GM-MSGID as well, kept with the letter, and goes
by the rules above: nothing is removed, fetched into a letter or sent by
folder and UID alone unless the server has shown in this launch that the
UID holds that letter (`seen`, the question, and a FETCH that names the
letter already, which for a part is the one that describes it). Where this
copy is wiped at a password save, a letter cannot be: it may be the only
copy of what he wrote. The save is counted beside the letters instead, and
from the next launch what a letter kept before it names by folder and UID
alone is left out of it. The Outbox's look in Sent Mail (B-052) asks the
same mailbox, and goes by the same count: an attempt cut off after its DATA
before a save is not looked for by a pass, which would find nothing in
another mailbox and send the letter again. It waits in the Outbox, "May
already have been sent.", for him to send it or not.

**The cost:** under 66 MB, none of it in iCloud backup, and a list that can
be old. It always says how old, and offline it is exactly as current as the
last time he had a connection. On an iPad with no passcode (D-011) the files
are not encrypted at rest.
