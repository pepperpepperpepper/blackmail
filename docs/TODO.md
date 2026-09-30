# TODO

One ordered list of what is actually left. Detail lives in
`KNOWN_ISSUES.md` (B-nnn) and `PERFORMANCE.md`; this is the running order.

Last revised 2026-09-30, after the gap review below.

---

## Gap review, 2026-09-30 — what is still missing

A read of the ledger, Apple Mail's everyday features, his own mailbox, and
what it takes to get the app onto his iPad, each claim checked against the
code. **His real volume, from his mailbox over the last 30 days:** 2,535
letters sent (about 71 a day) and about 1,586 received; about half of what
he sends is a link shared from Safari to a second address of his own
(1,186 YouTube, 256 Wikipedia); he never archives (the Inbox goes back
before 2016), deletes about 10 a day, and has about 1,900 drafts. Figures
elsewhere in these docs ("715 sent", "1 of 433") were samples.

**Before it goes on his iPad** (see also "Blocked on the owner" below):

- [ ] His Google account has no app password yet. *Owner.*
- [ ] How the signature and its logo reach his iPad. Compiling it in is
      ruled out (B-035); the old item below is dead. *Owner.*
- [ ] How updates reach him after install; today every fix is a visit.
      *Owner.*
- [ ] A trial install on an ordinary, non-jailbroken iPad: every install so
      far was an SSH copy onto the jailbroken one. *Owner.*
- [ ] Try it against a mailbox his size: Go to Date back to before 2016, an
      All Mailboxes search, ~1,900 Drafts. The test account has 24 letters.
- [ ] Buildable now, for the install-day build:
      - [ ] the in-app warning before the 2027-09-18 expiry (D-004 item 3)
      - [ ] "Password needs updating" on a read, not "Can't connect to mail
            server." for every failure (`MessageListViewController` :504,
            :580, :1167 and the pane's handlers flatten it)
      - [ ] setup and Settings check sending (SMTP) too, so Gmail's
            wrong-account trap cannot pass setup
      - [x] take out the B-033 `PAIR` probe, which logs subject lines
            (done 2026-09-30, D-016 phase 0, with the sender in
            `SESSION-IDENT`)
      - [ ] a build number he or a helper can read out
      - [ ] a guard so the signature cannot be wiped by accident
      - [ ] `provision-ipad.sh`: the TrollStore iOS range is wrong (:132 takes
            all of 16.7.x)
- [ ] On the day: Smart Invert off, what to do about Apple Mail's badges,
      the six-task test with him.

**Ways a letter is lost** (all confirmed in the code):

- [x] Save Draft with no connection throws the letter away silently
      (`ComposeActions.saveAndClose`; a test pins the silence). Mail keeps
      the draft on the iPad.
      *Done 2026-09-30, not yet seen on the iPad: kept on the iPad before
      the sheet goes, listed in Drafts as "On this iPad only", taken to
      Gmail once when the connection works, never twice. See B-051.*
- [ ] Delete inside Trash erases for good with no confirmation, which the
      spec asks for (`IMAPMailRepository` :1169).
- [ ] Delete and Move of several letters in Edit mode fail silently
      (`MessageListViewController` :1070, :1133); Delete shows no progress.
- [x] No autosave: iOS ending the app loses the letter being written.
      *Done 2026-09-30, not yet seen on the iPad: kept three seconds after
      he stops and on leaving the app, and in Drafts at the next launch.
      See B-051.*
- [x] No Outbox: a letter that cannot go stays in the sheet, but only while
      the sheet does. Next, on B-051's store. It will need a state per
      letter (a draft, or waiting to be sent), written before the DATA goes;
      the Message-ID the letter is sent under fixed when it enters the
      Outbox and handed to `RFC5322Builder`, so a send cut off after
      Gmail's 250 is looked for in Sent Mail before it is sent again, as a
      cut-off draft is looked for in Drafts; its own list; and the pass
      that takes kept letters to Drafts taking these to Gmail as well.
      *Done 2026-09-30, not yet seen on the iPad: Send that cannot reach
      Gmail closes the sheet with one notice, the letter waits in an
      Outbox listed in the Mailboxes while it holds anything, and goes by
      itself, once, when the connection is back; one cut off after its
      DATA is looked for in Sent Mail first. A letter Gmail refuses keeps
      the sheet as before. See B-052, and its check under "Blocked on the
      iPad coming back".*

**Small, every day:**

- [ ] Links in plain-text letters cannot be tapped (`PanePage` escapes and
      nothing links them; WebKit's data detectors are off). About a third of
      his own shared links are plain text.
- [ ] Sent and Drafts rows show his own name, not the recipient's.
- [ ] The reading pane never shows Cc, nor any bare address.
- [ ] Reply ignores Reply-To; replying to his own letter addresses it to
      himself; Reply All misses his second address.
- [x] `mailto:` links in letters open Apple Mail. *Done: they open this
      app's composer with the link's To, Cc, Bcc, Subject and Body and his
      signature (`MailtoLink`, B-036), and the app declares the scheme for
      other apps' links, which iOS may not send it. Not yet seen on the
      iPad.*

**Larger:**

- [x] **New mail arrives on its own** while the app is open, and "Updated
      Just Now" ages. *Done on the scripted server: a NOOP on the one
      connection every half minute while the Inbox is in front, a STATUS of
      the Inbox otherwise, new rows held while he is not at the top; the
      line ages as Mail's does and says when a check failed. See B-049;
      seen on the iPad 2026-09-30.*
- [x] **Reply and Forward keep the original's pictures and links.** Today
      both flatten it to plain text (`quotableText`, `HTMLText.plainText`).
      *Done 2026-09-30, not yet seen on the iPad: the letter's HTML carries
      the original's own markup while the quote is untouched, and a
      forward its pictures; a reply leaves out the pictures the original
      carried itself, as below ("Reply with the original's attachments").
      See B-050, and its check under "Blocked on the iPad coming back".*
- [ ] **The share sheet** (B-036): his main way of making mail. *Built
      2026-09-30: zsign patched for the extension's own entitlements, the
      Keychain mirror, the extension's own small compose sheet sending
      through the app's `Submission`, then called `Outbox`. Seen
      registered and sending on the iPad the same day (B-036); opt-in
      until the rest of its checks.*
- [ ] **A copy of the mail kept on the iPad** (D-016, decided 2026-09-30:
      the smallest design). Phase 0, the logging of his correspondence out
      and X-GM-MSGID in: done 2026-09-30; whether to redact the wire log
      itself is the owner's (D-016). Phase 1, the kept folders and first
      pages: *built 2026-09-30 and seen on the iPad the same day: the Inbox
      and the counted folders in the first frame under "Checking for
      Mail…", every folder opened before drawn at once, the kept pages and
      their age with no connection, the copy thrown away when it is not
      this mailbox's, an early write and an early letter opened vouched for.
      See B-053, and what is left to try under "Blocked on the iPad coming
      back".* Phase 2, the last 300 letters he opened.
- [ ] Text size: fixed today; Dynamic Type and Bold Text are ignored.
      *Owner decision* (D-007).
- [ ] His own replies missing from Inbox conversations (Mail's Complete
      Threads).
- [ ] Replied and forwarded arrows on rows.
- [ ] Search: several words may be searched as one phrase (not yet checked
      against Gmail); no suggestions or recent searches.

**Probably used, smaller:**

- [ ] Saving a received photo may crash: no Photos usage description in
      Info.plist. Needs a device check.
- [ ] Mark as Unread and Move to Junk from the Flag menu.
- [ ] Reply with the original's attachments.
- [ ] Attach documents from Files, and video.
- [ ] Undo for Delete and Move; Contacts in address suggestions (B-017);
      app badge and notifications. *Owner decisions.*
- [ ] Pull to refresh, the sent sound, blue bars on quoted text, tap the
      status bar to go to the top, Print.

**Not needed, by his mailbox:** folders and labels, Archive, invitation
buttons (1 of 53 answered in a year), formatting (D-013). **Decided
against:** Mail's filter button (D-009), portrait (D-008).

---

## Doable now — no device needed

Everything here is verifiable by the 366-test suite and a cross-compile on
this host. Ordered by value, not by size.

- [x] **P1. The reading pane shows the previous letter for the whole fetch.**
      `MessageDetailViewController.swift:165`. Configure the header from
      `summary` and load a "Loading…" document *before* the await;
      `show(thread:)` at :229 already does exactly this and its comment says
      why. Also fixes the case where, after a delete, the next tap re-reveals
      the letter he just deleted. Most-hit action in the app. (B-038 #1)
      *Done: `PaneLoads.show` draws the stand-in, the row's sender, subject
      and date over "Loading…", before the body is asked for, and emptying
      the pane now clears the web view as well as hiding it. See B-041.*
- [x] **P2. Batch `RecipientBook`'s flush.** `RecipientBook.swift:92` —
      `record()` re-encodes and rewrites the whole address book per harvested
      address, ~150-190 ms per 50-row page, 1000+ calls on a wide search.
      Drop `save()` from `record()`, dirty-flag it, flush once at the end of
      `summaries()`. Do **not** hoist the `JSONEncoder` — measured, it buys
      nothing. (B-038 #2)
      *Done: `note()` only marks the book dirty and the repository flushes
      once per set of rows it builds (`rows(from:…)`, which every page,
      jump and search goes through); `used()` still writes at once, and
      the app writes whatever is left when it goes into the background.
      A 50-row page is one write, not a hundred (`RepositoryTrafficTests`).
      Release build on this host: 4.5 ms per page against 382 ms, of which
      the device-honest encoding part was about 128 ms.*
- [x] **P3. Lock `RecipientBook.entries`.** Same file, correctness not
      performance: mutated from the repository actor, read on the MainActor
      per keystroke, SIGSEGV reproduced 8/8. `NSLock` around the dictionary
      access **only** — never held across `save()`, and do not make it an
      actor. Do it with P2, same file. (B-038 #10)
      *Done: the dictionary and the dirty flag are under one `NSLock`, held
      for the insert or the copy and never across the encode or the write.
      Flushes queue behind a second lock of their own, which nothing on the
      keystroke path takes. `RecipientBookTests` notes on one thread while
      another asks for suggestions, and while another flushes; without the
      lock either crashes every run. Two flushes caught at once leave the
      later copy on disk, and without the flush lock the older.*
- [x] **P4. Delete the duplicate cold-launch reload.**
      `RootViewController.swift:141`. Beyond the wasted round trips it blanks
      out previews that already landed and **erases a search typed in the
      first seconds after launch, dismissing the keyboard**. Delete that line,
      not the list VC's own task at :334 — folder taps depend on it. (B-038 #3)
      *Done: the line is gone; the list VC's own task is untouched.*
- [x] **P5. Fix the send path's CPU.** `SMTPClient.dotStuffed:390` (rewrite
      over an unsafe buffer into a preallocated `[UInt8]`, 40-70x) and
      `RFC5322Builder.uniqueBoundary:658` (stop substring-scanning base64
      payloads — `_` is not in the base64 alphabet, so the scan is provably
      vacuous). Both verified byte-identical. Takes a five-photo send from
      ~3.5 s of local CPU to under 50 ms. (B-038 #4a/4b)
      *Done: the stuffing is `SMTPClient.dataPayload`, a line at a time into
      one byte array with the terminator, 3.4 s → 22 ms at 27 MB; and `build`
      no longer offers the base64 payloads to `uniqueBoundary`, while the
      text parts, names, types and ids are still scanned, 1.5 s → 0.26 s for
      five photographs. Release build here, a five-photo letter's local work
      4.9 s → 0.28 s, not the 50 ms hoped for: what is left is `build`'s
      own base64 wrapping and joins (PERFORMANCE.md Record and leave).
      Byte for byte the same letter and payload for the same randomness,
      compared with `cmp` against the old code at 1, 5 and 20 MB, and in
      `DataPayloadTests` and `BoundaryTests` against the old functions kept
      as references; PERFORMANCE.md #4.*
- [x] **P6. Give Send some feedback.** `ComposeViewController.sendTapped:539`
      — today there is no spinner, no disabled button, and the sheet stays
      live and re-pressable through a multi-second upload. (B-038 #4c)
      *Done: at the tap Send gives way to a spinner and "Sending…", with
      the share handed to the network for a letter of a megabyte or more
      ("Sending… 40%", from the 64 KB pieces the write already goes in,
      `UploadProgress`); Send, Cancel, Attach Photo and Remove are held and
      the sheet cannot be swiped away until the send is answered, and a
      second tap sends nothing. The sheet closes as soon as the letter has
      gone; a draft's old copy is removed and Drafts told after that, in
      that order. A failure puts everything back, the letter still in the
      sheet, with the reason. `SMTPClient.send` returns at the letter's
      250, leaving QUIT, the close and the transcript to follow unwaited;
      the send and Save Draft run inside background time from iOS. The
      order is `ComposeActions`, checked in `ComposeActionsTests` and
      `SMTPSendTests`; the sheet itself is UIKit, and B-044 below is what
      to look at on the iPad.*
- [x] **P7. `#if DEBUG` around `LayoutAudit.beginSweeping()`.**
      `AppDelegate.swift:50`. It ships in release and runs 90 whole-window
      main-thread sweeps over the first three minutes of *every* launch, for
      no user-facing benefit. One line. (B-038 #7)
      *Done as a runtime switch instead, OFF by default: B-013 means there is
      no debug build for the device, so `#if DEBUG` would have removed the
      sweep for the developer too. Turn it on with the Layout button on the
      connection log (five taps on the list's status line), which also
      sweeps once at the tap; see `LayoutAudit.enabledKey`.*
- [x] **P8. `MIMEDecoder.decodeBase64` accumulates into `Data`.** :53 —
      `[UInt8]` + `withUnsafeBytes`, exactly as `decodeQuotedPrintable` above
      it already learned to. 5.7-11x on attachment and inline-image decode.
      (B-038 #5)
      *Done: 8x on base64 wrapped as mailers wrap it (5 MB 619 → 77 ms in a
      release build here), byte-identical at 1, 5 and 25 MB, and against
      the old decoder in `MIMEDecoderTests`.*
- [x] **Less of the connection spent on work he did not ask for.**
      *Done: cold launch sends LOGIN, one LIST shared by the folder names
      and the Inbox's role, and the Inbox's first page, and only then the
      unread counts (`PERFORMANCE.md` #6), and not at all if that page
      could not be fetched. The counts' sweeps run one at a time, and
      requests made during one become exactly one more, as does a letter
      read during one (`SweepCoalescer`). The Move sheet lists the folders
      from the last LIST, or a LIST alone, with no STATUS. A folder opened
      to jump to a day loads the day instead of loading today first, and a
      jump that fails after the list has moved on leaves it alone
      (`ListOpening`).
      Checked on the scripted server in `RepositoryTrafficTests`; see
      B-040 for what changed that he could notice.*
- [x] **Every UID command in its own mailbox, and the letter he opens
      first.** A SELECT and the command after it took the connection
      separately, so a Delete during a search could bin another letter
      (B-039). *Done: the client owns the selection and sends each UID
      command in one hold with its SELECT and a UIDVALIDITY check; the
      letter he opens, the attachment he taps, a folder's first page and
      his writes go ahead of background work; an All Mailboxes search takes
      the connection once for its three mailboxes and is cancelled when its
      list is replaced; a search cancelled on its way back draws nothing
      (`SearchAnswer`).*
- [x] **What he sees when he acts (the lag fixes, batch 4, first half).**
      *Done: a superseded letter's download is called off, and one called
      off draws nothing (`PaneLoads`); Delete, Move and Flag from the
      reading pane edit the list in place and sweep the counts only when
      one may have changed (`PaneActions`, and `ListLetters`, the list's
      letters, with `RemovedLetters` and `ReadBilling`); a page short of a
      letter binned since the list was fetched is made up from further
      down (`IMAPMailRepository.page(olderThan:)`); a regroup keeps every
      tick of a multi-select (`ListEdit.selectedRows`); Refresh keeps the
      previews already drawn; coming back to the Inbox
      after fifteen minutes fetches it again in the list on screen
      (`Sitting`); and a connection quiet for ninety seconds is probed as
      the app comes back and replaced if it has died
      (`IMAPMailRepository.warmUp`). Checked on the scripted server in
      `PaneLoadsTests`, `PaneActionsTests` and `ComingBackTests`; see B-041
      for what he could notice.*
- [x] **Things that move under him (the lag fixes, batch 4, second half).**
      *Done: a result set that replaces the list starts at the top, and a
      cancelled search puts the folder back at the row he had at the top
      of the pane (`ListPlaces`); every regroup, paging upward after a
      jump included, holds the rows on screen and the selection by their
      letters, taken before the rows are rebuilt (`ListPlace`); the
      folder's previews cut off by a search are asked for again when it
      ends, less any a hit has brought (`ListLetters.endSearch`); Go to
      Date and Move start at the tap and say so on the status line
      (`StatusLine`), with an alert held until the sheet has gone
      (`AlertHold`, through `ErrorPresenter`); the reading pane's header
      lists a letter's files from its row's BODYSTRUCTURE
      (`MIMEDecoder.listedAttachments`), so it does not grow when the
      letter lands; a draft tapped keeps its highlight with a spinner and
      ignores a second tap (`DraftOpening`); a conversation's bodies wait
      for its document to load, and the pane is drawn again from what it
      holds when WebKit's content process ends, once he can see it, the
      bodies put back by script as they first went in, and not a third
      time if it is lost again at once (`PaneDocument`). A Delete or Move
      from Edit mode, or a draft saved, keeps his place in the list
      (`ListPlaces.refetched`). Checked
      in `ListPlaceTests`, `FeedbackTests` and `PaneDocumentTests`; see
      B-042 for what he could notice.*
- [x] **Batch 5 of the lag fixes, the reading pane's CPU.**
      `callAsyncJavaScript` in place of the escaper, the letter's
      preparation off the main thread, and P8.
      *Done: a conversation's body goes to `bmFill` as an argument
      (`ConversationDocument.Fill`, made by `PaneDocument.fill`, held for
      `didFinish` and put back by the redraw as before), so nothing is
      escaped. A letter's page and a conversation letter's body are made by
      `PanePage` away from the main thread, inside the load's own task
      (`PaneLoads`), so one he has left draws nothing. P8 as above, and the
      list's and pane's date formatters are kept (`DisplayDates`). Release
      build here: the app's own code holds the main thread 0.1-0.6 ms while
      a letter of up to a megabyte is drawn, where it was 18-411 ms; WebKit's
      serializing of a conversation's body comes on top, untimed (see the
      device item). Loads settle in the order they were started, so a small
      letter opened after a large one keeps the header. `PanePageTests`,
      `PaneLoadsTests`, `PaneDocumentTests`, `ConversationDocumentTests`,
      `DisplayDatesTests`; PERFORMANCE.md #1 and #5; B-043.*
- [ ] **Left from batch 4.** Opening another letter inside a conversation
      still changes the header to that letter once its body has come, so
      a letter with a different number of files moves the stack then. The
      header could change at the tap instead, with Reply held until the
      letter has come, as the single-letter pane does since P1. And a new
      result set as he types asks for every hit's preview again, where the
      previews already drawn for the same letters could be carried over by
      id, as Refresh does. Also left as it was: a letter reopened in the
      stack whose body is already kept takes the header at once, so a letter
      opened before it and still coming takes the header back when it lands.
- [x] **B-037. The two/three-panel switch.** Small — `RootViewController`
      already holds both column widths. **Hide the pane, do not zero its
      width**: a view with children and no width is the B-027 shape and
      `LayoutAudit` will report it every two seconds, once it is switched on
      with the Layout button on the connection log (it is off by default and
      silent until then). Follow Mail and put the
      control in the leading toolbar slot, persist it like `organizeByThread`,
      and do not let B-003's away-timer re-expand a pane he collapsed.
      *Done: the view button, top-left in both arrangements; two panes as
      D-003 laid them out, three as D-009 did and by default; kept across
      launches (`PaneArrangement`, D-015). Checked in
      `PaneArrangementTests`; see B-048 for what he could notice. Not yet
      seen on the iPad, below.*
- [x] ~~**B-035. Ship the signature as a compile-time default.**~~ *Ruled
      out by the owner, 2026-09-26: his signature never goes in the repo.
      See the gap review above.* Needs the
      owner's decision first (it puts the end user's phone number and address
      in the source). Without it the rich signature and inline logo cannot reach
      a sideloaded install at all, because they have only ever been installed
      by writing the plist into the app container.
- [x] **B-036. Patch zsign for per-bundle entitlements.** Unblocks the share
      extension. zsign takes one `-e` for the whole archive, so the `.appex`
      currently gets the app's `application-identifier` while its bundle id is
      `…blackmail.share`. Two-pass signing does not survive — measured.
      *Done 2026-09-30: `-X KEY=FILE` (`tools/zsign/`, TOOLCHAIN.md), signing
      through `tools/sign-ipa.sh`, and `tools/check-signature.py` failing any
      IPA whose extension is not signed as itself.*
- [ ] **B-025. Insert a photo at the cursor** (`NSTextAttachment` in the
      composer). Last, deliberately: exactly 1 of his 433 sent messages did it.

## Blocked on the iPad coming back

- [ ] See B-037 rendered at all: now B-048, below.
- [ ] Confirm the signature's white sheet **in the reading pane** — the
      outgoing half is verified by tests and Chromium renders, but the in-app
      half only applies to letters carrying the new marker, so it needs one
      send.
- [ ] Register and test the share extension. *Registered and seen
      2026-09-30 through TrollStore's installd path: a Safari link shares,
      sends and arrives; see B-036. Still to try is below.* It also needs `ideviceinstaller`,
      which is on neither machine, or TrollStore. (B-036 blocker 2) The IPA
      is `tools/build-share-ipa.sh` → `ios/Blackmail-share.ipa`, installed
      through installd, not the copy-based deploy. Open the app once, then
      share from Safari and from YouTube: that Blackmail is in the row, that
      the title is the subject, that his second address is offered in To,
      that it sends and arrives with the link tappable, that five full-size
      photos shared at once arrive, and that the app's own password still
      works after the extension build's keychain groups (copy-deploy that
      build to the dev iPad first). Then take `BLACKMAIL_SHARE_EXT` out of
      `package.sh`.
- [ ] Anything else touching the send path. Batch 6 of the lag fixes
      (B-044) went in before the iPad was back; its checks below come
      first.
- [ ] Send one letter to confirm the send path still works now that
      `SMTPClient` runs over the `MailTransport` seam and `TLSConnection`
      reads through `ReadBuffer`, and now that the transport has real
      deadlines: a write goes to the stack in 64 KB pieces, each with the
      30 s bound, the reply after DATA's dot waits up to ten minutes, and
      TCP keepalive and `connectionDropTime` are on. Send a letter with
      several photos, and check the transcript still shows exactly one
      `WIRE-OUT` and one `WIRE-ACK err=none` before the 250. The pieces, the
      probes and the choice of bound are `LinkTransport`, which the host
      tests run (`LinkTransportTests`, `DeadlineWireTests`), and
      `SMTPReplyWaitTests` checks which SMTP reply asks for the long bound.
      No host test sends over TLS, though (the scripted server refuses port
      465), `TLSConnection`'s `NWConnection` glue only runs on the device,
      and nothing has been sent through any of this on the device yet.
- [ ] Time an All Mailboxes search on the device, and a letter tapped
      while it runs, from the connection log. The one-hold search and the
      interactive line are checked on the scripted server, which knows
      nothing of Gmail's own SEARCH time on Trash and Spam, and that time
      decides what the binned half of a search still costs.
- [ ] Watch a cold launch in the connection log: LOGIN, one LIST, the
      Inbox's SELECT, SEARCH and FETCH, and only then a STATUS per folder.
      Then move an unread letter out of the Inbox from the reading pane and
      check both folders' counts come right, which they must within one
      sweep of the MOVE (B-040). The order and the counts are checked on the
      scripted server; the folder pane drawing names first and counts a
      moment later has not been seen on glass.
      The host suite checks the rules, not the UIKit wiring that applies
      them, which it cannot compile, so on glass also check: the counts do
      appear after launch (the folder pane holds them until
      `onFirstLoadFinished` lets them go, and nothing else would), and do
      not after a launch with Wi-Fi off; tapping the newest unread letter
      the moment the Inbox appears leaves the Inbox's count right once the
      counts have settled (`adjustUnreadCounts` asking for one more); and
      the Move sheet opens with its folders at once.
- [ ] **B-041, the reading pane at the tap.** Tap from letter to letter
      in the Inbox: the header must change at the tap to the new sender,
      subject and date with "Loading…" under it, and the previous letter
      must never be on screen beside the new selection, not even for a
      frame. Delete a letter, then tap the next: the binned one must not
      appear at all. Tap four letters about a third of a second apart,
      one of them large: the connection log should show two
      `BODY.PEEK[]` fetches, the first and the last, and the pane should
      end on the last. Tap Reply while a large letter is loading: nothing
      should open until it is there. The web view's first paint of
      "Loading…" and of the letter after it is the part the host cannot
      see: look for a white flash or a blank frame between them. The
      header's height must not change when a letter with files lands
      (B-042).
- [ ] **B-041, Delete, Move and Flag from the pane.** In a folder scrolled
      down a few pages, with previews filled: Delete a read letter. The
      pane empties and the row goes at the tap, nothing else on the list
      moves or blanks, and the connection log shows `UID MOVE` and nothing
      after it. Delete stays grey until it lands. Delete an unread letter:
      the counts drop at once, and the log shows one LIST and a STATUS per
      folder after the MOVE; Trash's count comes right with them. With an
      All Mailboxes search showing, open a hit that is also in the Inbox's
      first page, Delete it, then cancel the search: it must not be in the
      Inbox, and the search's text, results and scroll must have stayed
      until the cancel. With the Inbox's first page only loaded, search the
      Current Mailbox for a letter a few pages down, Delete it from the pane,
      cancel the search and scroll to the bottom: the list must go on to the
      oldest letter, not stop at the page the binned one was in. In All
      Mail, Move a letter to Inbox: the row stays. Flag an All Mailboxes hit
      that is also in the Inbox's first page and cancel the search: the
      Inbox row is flagged. Flag one letter with Wi-Fi off, open another at
      once and Flag it: both flags appear, and both go back with "Can't
      connect". With Edit on and three rows ticked, open a letter inside
      the conversation still in the pane, and Flag from the pane: the three
      ticks stay, and no other row is ticked.
      Flag, and the row's flag appears at once; flag with Wi-Fi turned off,
      within a minute and a half of the last thing he did: the flag goes
      back and "Can't connect" is said (at once, or after the 30 s read
      deadline if the socket is left half open). In a conversation, open
      an unread collapsed letter: the dot and one count go, and the list
      does not reload. The host suite checks the rules; the table view's
      reaction to them, row removal, highlight and empty state, is only
      visible here.
- [ ] **B-041, coming back.** With the Inbox showing, scrolled down, a
      letter open and Edit on, leave the app for more than fifteen minutes
      (or shorten `Sitting.awayBeforeReturningToInbox` for the test, as
      B-003 was checked): the list must be at the top, out of Edit, with its
      old rows and previews on screen until the new page lands, never
      black, the letter still in the reading pane, and the counts' LIST
      and STATUS after the page's SEARCH and FETCH in the log. From another
      folder, the Inbox opens as before. Lock the iPad for two minutes
      after reading a letter, unlock, and before touching anything read the
      log: one NOOP, and after a night away a LOGIN on a new connection
      after it; then the first letter opened should be SELECT and FETCH
      only. After a night away, unlock and Delete the letter in the pane at
      once: the log should show the NOOP, a LOGIN, a second NOOP and the
      MOVE, and the row must not come back. Lock for thirty seconds straight
      after tapping a letter: nothing at all should be sent on the way out
      or on the way back.
- [ ] **B-042, where the list is.** In the Inbox, scroll down three pages
      and note the row at the top of the pane. Type a search: the first
      hit must be the first row under the search band, never above the
      pane, and the keyboard must stay up as the results land (list-11,
      which this makes likelier to show if it is real). Type two more
      letters: the new hits start at the top again. Scroll the results
      down, then Cancel: the noted row is back at the top of the pane at
      the same height, to within a few points, and every row's preview is
      filled within a second or two (the connection log shows a preview
      FETCH after the cancel if any were missing). Scroll down again, tap
      Refresh: the list goes to the top when the new page lands. Scroll a
      screen down, Edit, tick two rows in view and Delete: the rows left in
      view stay where they were. Scroll far past the first page and do the
      same: the list goes to the top. With
      Wi-Fi off, search from far down: "Could not search. Check the
      connection." is on screen, not above it.
- [ ] **B-042, paging upward.** In All Mail, Go to Date a few months back,
      open a letter so its row is highlighted, and scroll up slowly past
      the top of the window until the page above loads: the rows on screen
      must not move, not even by a row, and the highlight must stay on the
      letter in the reading pane. Best on a day where a conversation on
      screen has a later reply: that row alone leaves for the top, and the
      rest stay. Repeat with Edit on and three rows ticked: the same three
      stay ticked. From the reading pane, Delete a letter whose row is just
      above the top of the pane (open it, scroll it off, Delete): the rows
      in view do not move. Flip Organize by Thread in Settings: the row at
      the top stays at the top.
- [ ] **B-042, Go to Date and Move.** Tap Go: "Going to <day>…" must be on
      the status line while the sheet is still sliding away, then
      "Showing <day>". From the Inbox, go to a day in All Mailboxes: All
      Mail opens during the slide, saying "Going to <day>…". Double-tap Go
      quickly: one jump in the connection log. With Airplane Mode on, Go:
      "Can't connect to mail server." must appear, once the sheet has gone
      if the failure came during the slide (the log's timestamps say
      whether it did), and the status line goes back to what it said. Move a letter from the
      reading pane: "Moving…" until the MOVE is answered; with Wi-Fi off,
      the row comes back and the alert appears after the sheet has gone.
      Double-tap a folder in the Move sheet: one MOVE in the log. Edit,
      tick two, Move: "Moving…" until the list is fetched again. Start to
      swipe the Go to Date sheet down and tap Go before letting go, with
      Wi-Fi off: the alert may be lost with the sheet, but alerts after it,
      a second later, must still appear (tap a letter: "Can't connect").
- [ ] **B-042, the header's files.** Open a letter with two PDFs: both file
      rows are in the header at the tap, grey, and turn blue when the
      letter lands; nothing under the header moves then. Open a
      conversation whose newest letter has files: the stack must not shift
      when its body lands. A letter whose only picture is a signature logo
      shows no file row before or after. Open a forwarded letter
      (message/rfc822 inside): the rows before and after must be the same;
      if they are not, the BODYSTRUCTURE and the downloaded letter
      disagree about its parts, which the host cannot see with Gmail's own
      structures. Tap a large PDF in one letter, and at once another letter
      with a file: when the first download ends, the second letter's rows
      stay grey until it lands, and a download of its own keeps its
      spinner.
- [ ] **B-042, Drafts.** Tap a draft: its row stays highlighted with a
      spinner in the left gutter, the text beside it unmoved, until the
      composer opens. Tap it again while it spins: one FETCH in the
      connection log. Tap a second draft while the first spins: only the
      second opens. With Wi-Fi off: the spinner stops, the highlight goes,
      and "Can't connect to mail server." appears.
- [ ] **B-042, WebKit's content process.** Force it out while a letter is
      showing: on a device with a shell, `killall -9
      com.apple.WebKit.WebContent`; otherwise leave for Safari and Photos,
      open many large pages and a few videos, and come back. The
      connection log must say "webview: content process ended". A single
      letter comes back drawn, at the top, with no FETCH of the letter in
      the log; its inline pictures reappear. A conversation with two
      letters opened and one closed comes back the same way round, bodies
      and pictures in; the pictures of any letter but the last one
      downloaded are FETCHed again, which is expected. Killed while he is
      in another app, it is drawn when he comes back, not before (the log
      line comes first, then nothing until the return). Kill it while
      "Loading…" is showing: the letter appears when it lands. Kill it
      twice within a few seconds: "This message could not be shown." in
      the pane, and tapping the letter again draws it. Then open a long
      conversation (twenty letters or more) a few times on fast Wi-Fi: its
      newest letter must never stay on "Loading…" (pane-13).
- [ ] **B-043, the reading pane's CPU.** *Partly seen 2026-09-28 (launch,
      an HTML letter, a four-letter conversation opened, closed, reopened
      and redrawn after a WebContent kill, a quick tap-through, a PDF); see
      B-043. Still to see: the rest below from "a newsletter of a few
      hundred KB", a twenty-letter conversation, a body with backslashes or
      `</script>`, the time zone and 24-hour clock, and the fill's timing.*
      The app must launch at all: the
      pane now binds `callAsyncJavaScript` from `libswiftWebKit`, which the
      16.5 SDK says every iOS 16 has. Open the largest letter in the
      mailbox, a newsletter of a few hundred KB or more, and scroll the list
      while it comes: the list must not catch, and the letter draws. Then a
      long conversation, twenty letters or more, with HTML and plain letters
      in it: the newest fills in, and opening, closing and opening again
      letters in the stack puts each body back, pictures included. A letter
      in a conversation whose text has quotes, backslashes or `</script>` in
      it reads exactly as sent, with no backslashes added. Kill WebContent
      with the conversation open, as for B-042: it comes back with its
      bodies. Tap quickly through several large letters: only the last is
      drawn. Open a 5 MB PDF: it opens sooner than it did. Then change the
      time zone in Settings, and switch the 24-hour clock, and come back:
      rows drawn afterwards, and the pane's date, follow both; and a letter
      from late yesterday says "Yesterday" once the list is drawn again
      after midnight. And time the conversation's fill, `run(fill)` around
      `callAsyncJavaScript` with a letter of a megabyte, in the
      Instruments time profiler or with a signpost: once cold, more than
      10 s after the last fill, when WebKit makes a new `JSContext` in the
      app to serialize the body, and once warm. The host's 0.1-0.6 ms is the
      app's part only. Watch the app's memory for those 10 s alongside
      B-042's WebContent terminations.
- [ ] **B-044, sending.** *Seen 2026-09-29: plain, double tap, reopened
      draft, five pictures, lock at once, Wi-Fi off; see B-044. Still to
      see: Save Draft then lock, Send the moment the picker closes, a tap
      on the sent draft's row as the sheet closes, Look Up or Share during
      a send, Send with the Cancel sheet open.* None of it seen on the device yet; B-044 has
      the same checks on the build before it, to compare with. Write a
      plain letter to himself and Send: Send gives way at once to a spinner
      and "Sending…", Cancel and Attach Photo are grey, the sheet will not
      swipe down, and it closes the moment the letter has gone; the letter
      arrives once. The newest `blackmail-send-*-ok.txt` in the container's
      tmp shows `WIRE-OUT`, `WIRE-ACK err=none` and the 250, and no 221.
      Tap Send twice quickly: one letter arrives. Reopen a saved draft from
      Drafts and send it: the sheet closes before the connection log shows
      the Drafts cleanup (NOOP or LOGIN, SELECT, STORE, EXPUNGE), and the
      draft has gone from Drafts afterwards. Attach five photos and send:
      "Sending… n%" climbs while it goes, the sheet closes, and it arrives
      once with all five. Turn Wi-Fi off and Send: "Can't connect to mail
      server.", the letter still in the sheet as written, and Send, Cancel,
      Attach Photo and each Remove live again. Send a photo letter and lock
      the iPad at once; unlock after a minute: either the letter went, once,
      and the sheet is gone, or it failed with the letter still in the sheet
      and the reason on screen. A letter that went must not be reported as
      failed, and none may arrive twice. Then Save Draft on a photo letter
      and lock at once: the draft is in Drafts when he comes back.
      Choose five photos and tap Send the moment the picker closes: the
      spinner at once, and the letter arrives with all five; the same with
      Save Draft, and the draft has all five. Reopen a saved draft, send
      it, and tap where its row was as the sheet closes: the row has gone,
      nothing opens, and after the cleanup Drafts no longer has it. On a
      photo letter, select a word in the body while it sends and open Look
      Up or Share from the menu: the sheet still closes at Gmail's answer,
      taking it along, and nothing is left held on screen. Tap Cancel on a
      letter with text, and with that sheet still open tap Send: the Cancel
      sheet goes and the letter is sent once.
- [x] **B-045, new mail in the open folder.** *Seen 2026-09-29; see
      B-045. The archive-elsewhere half is still to try.* With the Inbox open, send
      a letter to himself, give it a few seconds to arrive, and tap Refresh
      once: it must be at the top after that one Refresh. The connection
      log should show a `NOOP`, answered with `* n EXISTS`, before the
      `UID SEARCH`, with n the SEARCH's count of UIDs. SESSION-IDENT's
      `exists` can still come out one above its `uids` without anything
      being wrong: a letter that lands after the NOOP is told of on the
      FETCH, as the iPad's log showed, and the next Refresh lists it. Then
      search at once for a word from it: it is found, in All Mailboxes and
      in Current Mailbox. Archive a letter in the Inbox from Gmail on the
      web or the phone, and tap Refresh: it leaves the list.
- [ ] **B-046, the signature's logo in a reopened draft.** *First half
      seen 2026-09-29; the draft with a photo is still to try.* A new letter,
      Cancel, Save Draft; open Drafts and tap the draft: no attachment row.
      Send it: it arrives with no paperclip in the list and no file row in
      the header, and with the logo in the signature; the connection log's
      `WIRE-PAYLOAD raw=` for it should be about what the same letter sent
      fresh gives, not ten kilobytes more. Then a draft with a photo he
      attached: Save Draft, reopen it, the photo's row is there once; send
      it: it arrives with the photo once, and the logo in the signature.
- [ ] **B-047, "Inbox".** *Sidebar and title seen 2026-09-29; the Move
      sheet and VoiceOver still to look at.* The sidebar's first row and the list's title read
      "Inbox" at launch and after tapping it. The Move sheet says "Inbox"
      too. With VoiceOver on, the first row reads "Inbox, N unread", or
      "Inbox" with nothing unread.
- [ ] **B-048, two panes or three.** *Partly seen 2026-09-29: both ways
      with a letter open and a search up, "< Mailboxes" and the open
      folder, the choice kept across a relaunch; see B-048. Still to see:
      Edit mode, another folder from "< Mailboxes", VoiceOver, the layout
      sweep.* Switch the Layout button on in the
      connection log first. Open a letter, scroll the list a few pages
      down, and tap the view button both ways: the letter stays drawn with
      no "Loading…" and nothing new in the connection log, the list keeps
      its rows and the selected one where they were on screen, and the
      folder keeps its highlight. Again with a search active and the
      keyboard up (text, scope, results and keyboard all stay), and with
      Edit mode on and two rows ticked (still in Edit, ticks and Done
      kept). Pane widths: 250 / 330 / 613 in three and 375 / 818.5 in two
      on the 11-inch; the button in the same spot in both. `< Mailboxes`
      shows the folders with the open one highlighted; the open folder
      tapped shows its list where he left it, with no new commands in the
      log; another folder loads as it does in three panes. With the
      folders in front, the view button puts the list back in the middle.
      Nothing truncates in the list's bar in two panes but a long folder
      name, which ends in "…"; "Sent Mail" should fit, and `< Mailboxes`
      is never shortened. Relaunch in two panes: it opens in two, on the
      Inbox's list. VoiceOver reads "Hide Mailboxes" and "Show
      Mailboxes", and lands on the button after a switch. A tap on the
      button with a thumb resting on the list does nothing. The connection
      log shows `layout: three panes`, `layout: two panes, …` and no
      finding after either.
- [ ] **B-050, Reply and Forward as the original looked.** Read what
      arrives in Mail on another device and in Gmail on the web, not in
      Blackmail, whose pane draws no bar beside a quote yet. Forward a
      newsletter with pictures to himself: it arrives looking like the
      original under "Begin forwarded message:" and the From, Date, To and
      Subject lines, its pictures showing and its links working, and the
      connection log's `WIRE-PAYLOAD raw=` for it is about one and a half
      times the size of its markup. Reply to an HTML letter: the quote shows
      with the blue bar, its own formatting and working links. Edit the
      quote before sending, one word changed and one paragraph cut: what
      arrives matches what he saw, with the paragraph gone and the quote as
      plain text, its addresses still links. Delete the quote: nothing of
      the original arrives. Forward a letter with a photograph in its body
      and a PDF: the composer lists both with their weights; it arrives with
      the photograph in the letter and the PDF as a file, no paperclip for
      the photograph. Reply to the same letter: the letter as it looked but
      for the photograph, which is left out, and no paperclip. Forward a
      letter that had a Cc: the Cc line is under To.
      Save a reply to an HTML letter as a draft and reopen it: no attachment
      rows; send it: it arrives as the same reply sent fresh would. Reply to
      one of his own shared links, a plain-text letter: the link in the
      quote can be tapped.
- [ ] **B-051, letters kept on the iPad.** None of it seen on the iPad yet.
      Turn Wi-Fi off in Control Center, write a letter to himself, Cancel,
      Save Draft: the sheet goes with nothing said, and Drafts has it at
      the top, its preview beginning "On this iPad only". Turn Wi-Fi on
      and tap Refresh: it goes up once, the connection log shows one
      APPEND for it, and Drafts shows it once, without the line. Again,
      but come back to the app instead of tapping Refresh. Reopen a draft
      from Drafts, turn Wi-Fi off, change it, Save Draft: it is listed
      once, at the top, and the old copy is not beside it; with Wi-Fi on,
      one copy, the new one. Write a letter, wait five seconds, and swipe the
      app away in the app switcher; open it again: the letter is at the
      top of Drafts with every word, and shortly after in Gmail's Drafts
      on the web. The same with two photos attached before the swipe: both
      come back, open in the composer, and go up with it. Write a letter
      and swipe its sheet down: it is in Drafts. Send a letter, Save one
      with Wi-Fi on, and Delete one: nothing "On this iPad only" is left.
      Lock the iPad in the middle of a letter and unlock it: the letter is
      still in the sheet as it was. With Wi-Fi off, Save Draft on a letter
      with two photos; Wi-Fi on, open another folder: the connection log
      shows no APPEND; go to the Home Screen: it shows one, and Drafts has
      the letter once. In Drafts, Edit, tick a kept letter, Delete: it goes,
      and does not come back at the next Refresh. Search Drafts, open a
      draft from the hits, change it, Save Draft: the hit is the new copy,
      and opens.
- [ ] **B-049, new mail on its own.** With the Inbox open and the list at
      the top, send a letter to himself from the phone: within about half a
      minute it is at the top of the list with no tap, and the Inbox's count
      goes up. The connection log should show a `NOOP` answered `* n
      EXISTS`, then `UID SEARCH UID …:*`, one `UID FETCH` of that letter,
      and `NEWS folder=INBOX arrived=1 gone=0`; with nothing arriving, one
      `NOOP` each half minute and nothing more. Scroll
      a few pages down and send another: nothing on the list moves; scroll
      back to the top and it goes on. The same with two rows ticked in Edit
      mode (it goes on at Done), and with a search showing (it is at the top
      within half a minute of Cancel). Archive a letter on the phone: it
      leaves the list. Open Sent and send one more: the Inbox's count goes
      up, the log shows `STATUS "INBOX" (UNSEEN)` each half minute and no
      Inbox FETCH, and Sent's line ages, "Updated 1 minute ago", "Updated 2
      minutes ago", on to "Updated at …" after an hour. Turn Wi-Fi off:
      within a minute the line reads the age over "No Connection"; turn it
      back on and the next check lists what came and the line reads "Updated
      Just Now". Lock the iPad for a few minutes: no commands in the log
      while it is locked. A letter opened, flagged or deleted just after a
      check behaves as before. Hold a finger on a row as a letter arrives:
      it goes on within half a minute of lifting it.
- [ ] **B-052, the Outbox.** None of it seen on the iPad yet. Turn Wi-Fi
      off in Control Center, write a letter to himself, Send: "Sending…",
      then the sheet closes with "Message is in the Outbox. It will be sent
      when the iPad is connected and Blackmail is open.", an Outbox row
      with 1 appears below the folders and nothing above it moves, and the
      line under the list reads "1 Unsent Message". Open the Outbox: the row shows whom it is to and
      the subject. Turn Wi-Fi on and wait up to half a minute, or tap
      Refresh: it goes, once (one `ENVELOPE` in the connection log), it
      arrives once, and the Outbox row disappears. Send a letter with
      several photos and press the lock button at once, unlock after a
      minute: it has arrived once, or it waits in the Outbox and then
      arrives once; never twice. If it waited as being sent, the log shows
      `UID SEARCH HEADER Message-ID` in Sent Mail before any second
      `ENVELOPE`. Either way, check in Gmail on the web ("Show original") that
      a letter the app sent is in Sent Mail under the Message-ID the app
      gave it, which is what the look depends on and has never been seen,
      and note how many seconds after Send it is there: the app gives Gmail
      ten minutes after a cut before it takes "not in Sent Mail" as final
      (`Outbox.settling`), a figure from RFC 5321, not from Gmail.
      Send a letter to an address with no domain, `nobody@`, which Gmail
      refuses at RCPT: the sheet stays with "Message was not sent." and the
      letter, as before. Reopen a draft from Drafts, Wi-Fi off,
      Send: it leaves Drafts' list, waits in the Outbox, and once sent its
      old copy is gone from Drafts on the web. Tap a letter in the Outbox,
      Cancel untouched: it is back in the Outbox. In two panes, the Outbox
      is in the Mailboxes' column and opens like any folder.
- [ ] **B-053, the copy kept on the iPad.** Seen 2026-09-30: the first
      frame with Wi-Fi on and off, an unread letter tapped in the first
      second (both vouching FETCHes, the dot staying off), the kept pages
      and their age offline, a folder never opened, and Refresh bringing a
      letter that came meanwhile. Still to see: the swap scrolled a little
      way down, with a finger resting on the list, and under two rows
      ticked in Edit, which needs a slower connection than the house Wi-Fi,
      the page landing about a second in; a flag from the pane in the first
      second staying on; a letter tapped with no connection showing its
      header, then the failure; the password saved again in Settings,
      force-quit and open: the Inbox empty for a moment, as before the
      copy, and the letters kept in Drafts ("On this iPad only") and the
      Outbox still there. Time the first frame if a screen recording can:
      the design asks under 500 ms.
- [ ] A folder count asked just before his read mark reaches the server
      puts the old count back for a second: at launch, a letter read while
      the STATUS sweep that follows the first page is out shows the Inbox
      as 1, then 2, then 1 when the sweep `adjustUnreadCounts` asks for
      lands. Seen on the iPad 2026-09-30; older than the kept copy, which
      only makes a tap that early likelier.
- [ ] The folder pane redraws only the Inbox's count after a read mark:
      `adjustUnreadCounts` patches the cell at `IndexPath(row: i, section:
      0)`, `i` an index into the flat list of folders, and the pane has had
      two sections since the Inbox got a block of its own, so All Mail,
      Important and Sent Mail keep their old number on screen until the
      next sweep, though the count under them is right (and kept so). Seen
      on the iPad 2026-09-30; older than the kept copy.
- [ ] Watch keepalive find a dead socket during the quiet: open a letter,
      restart the router (the iPad itself stays on Wi-Fi, so only the path
      dies), wait three minutes, then tap another letter. It should load
      after one reconnect, not after a 30 s stall.

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

Two ways to make an All Mailboxes search faster were weighed and left:
fetching the binned hits' summaries a page at a time, which needs their
dates, the merge key, from a second source before the first page can be
cut (see `IMAPMailRepository.startSearch`), and pipelining its SELECT and
SEARCH pairs (see `IMAPClient.search(_:across:)`).
