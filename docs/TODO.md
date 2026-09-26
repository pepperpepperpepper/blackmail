# TODO

One ordered list of what is actually left. Detail lives in
`KNOWN_ISSUES.md` (B-nnn) and `PERFORMANCE.md`; this is the running order.

Last revised 2026-09-22, with the iPad offline.

---

## Doable now — no device needed

Everything here is verifiable by the 366-test suite and a cross-compile on
this host. Ordered by value, not by size.

- [ ] **P1. The reading pane shows the previous letter for the whole fetch.**
      `MessageDetailViewController.swift:165`. Configure the header from
      `summary` and load a "Loading…" document *before* the await;
      `show(thread:)` at :229 already does exactly this and its comment says
      why. Also fixes the case where, after a delete, the next tap re-reveals
      the letter he just deleted. Most-hit action in the app. (B-038 #1)
- [ ] **P2. Batch `RecipientBook`'s flush.** `RecipientBook.swift:92` —
      `record()` re-encodes and rewrites the whole address book per harvested
      address, ~150-190 ms per 50-row page, 1000+ calls on a wide search.
      Drop `save()` from `record()`, dirty-flag it, flush once at the end of
      `summaries()`. Do **not** hoist the `JSONEncoder` — measured, it buys
      nothing. (B-038 #2)
- [ ] **P3. Lock `RecipientBook.entries`.** Same file, correctness not
      performance: mutated from the repository actor, read on the MainActor
      per keystroke, SIGSEGV reproduced 8/8. `NSLock` around the dictionary
      access **only** — never held across `save()`, and do not make it an
      actor. Do it with P2, same file. (B-038 #10)
- [ ] **P4. Delete the duplicate cold-launch reload.**
      `RootViewController.swift:141`. Beyond the wasted round trips it blanks
      out previews that already landed and **erases a search typed in the
      first seconds after launch, dismissing the keyboard**. Delete that line,
      not the list VC's own task at :334 — folder taps depend on it. (B-038 #3)
- [ ] **P5. Fix the send path's CPU.** `SMTPClient.dotStuffed:390` (rewrite
      over an unsafe buffer into a preallocated `[UInt8]`, 40-70x) and
      `RFC5322Builder.uniqueBoundary:658` (stop substring-scanning base64
      payloads — `_` is not in the base64 alphabet, so the scan is provably
      vacuous). Both verified byte-identical. Takes a five-photo send from
      ~3.5 s of local CPU to under 50 ms. (B-038 #4a/4b)
- [ ] **P6. Give Send some feedback.** `ComposeViewController.sendTapped:539`
      — today there is no spinner, no disabled button, and the sheet stays
      live and re-pressable through a multi-second upload. (B-038 #4c)
- [ ] **P7. `#if DEBUG` around `LayoutAudit.beginSweeping()`.**
      `AppDelegate.swift:50`. It ships in release and runs 90 whole-window
      main-thread sweeps over the first three minutes of *every* launch, for
      no user-facing benefit. One line. (B-038 #7)
- [ ] **P8. `MIMEDecoder.decodeBase64` accumulates into `Data`.** :53 —
      `[UInt8]` + `withUnsafeBytes`, exactly as `decodeQuotedPrintable` above
      it already learned to. 5.7-11x on attachment and inline-image decode.
      (B-038 #5)
- [ ] **B-037. The two/three-panel switch.** Small — `RootViewController`
      already holds both column widths. **Hide the pane, do not zero its
      width**: a view with children and no width is the B-027 shape and
      `LayoutAudit` will report it every two seconds. Follow Mail and put the
      control in the leading toolbar slot, persist it like `organizeByThread`,
      and do not let B-003's away-timer re-expand a pane he collapsed.
      *Writable now, not confirmable until the iPad is back.*
- [ ] **B-035. Ship the signature as a compile-time default.** Needs the
      owner's decision first (it puts the end user's phone number and address
      in the source). Without it the rich signature and inline logo cannot reach
      a sideloaded install at all, because they have only ever been installed
      by writing the plist into the app container.
- [ ] **B-036. Patch zsign for per-bundle entitlements.** Unblocks the share
      extension. zsign takes one `-e` for the whole archive, so the `.appex`
      currently gets the app's `application-identifier` while its bundle id is
      `…blackmail.share`. Two-pass signing does not survive — measured.
- [ ] **B-025. Insert a photo at the cursor** (`NSTextAttachment` in the
      composer). Last, deliberately: exactly 1 of his 433 sent messages did it.

## Blocked on the iPad coming back

- [ ] See B-037 rendered at all.
- [ ] Confirm the signature's white sheet **in the reading pane** — the
      outgoing half is verified by tests and Chromium renders, but the in-app
      half only applies to letters carrying the new marker, so it needs one
      send.
- [ ] Register and test the share extension — also needs `ideviceinstaller`,
      which is on neither machine. (B-036 blocker 2)
- [ ] Anything else touching the send path.

## Blocked on the owner

**Before the house visit** — `provision-ipad.sh --check` fails until these
are done, and it is meant to fail at home rather than at his kitchen table:

- [ ] `ideviceinstaller` on the laptop
- [ ] copy `~/.apple-signing` to the laptop
- [ ] **his iPad's UDID**, and regenerate the ad-hoc profile to include it —
      without this the app will not launch on his iPad at all
- [ ] reissue the App Store Connect API key if registration should be
      automatic (the `.p8` is gone; `asc_jwt.py` survives without it)

**Decisions:**

- [ ] **His iPad's iOS version** — decides TrollStore (never expires) against
      a certificate (dies 2027-09-18, on his device, where nobody can fix it)
- [ ] **The real signature logo** — what ships today is a solid black silhouette
      with no legible mark in either channel
- [ ] **Signature in the source?** (B-035)
- [ ] **Mail's conversation stack default** — thirty seconds on an iPhone;
      newest-first is currently a guess, not a copy

## Open, recorded, not scheduled

B-026 (one blank body, never reproduced), B-034 (does not reproduce; the
transcript probe now records every send to a file), B-013 (no debug build for
the device), B-024's bounded write-retry residue, and the "record and leave"
half of `PERFORMANCE.md` — each of which is real and none of which is worth
changing working code for today.
