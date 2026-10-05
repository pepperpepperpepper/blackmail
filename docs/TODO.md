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
      - [x] "Password needs updating" on a read, not "Can't connect to mail
            server." for every failure (`MessageListViewController` :504,
            :580, :1167 and the pane's handlers flatten it)
            *Done 2026-09-30, not yet seen on the iPad: Mail's "Cannot Get
            Mail" with Settings, a third state for any other refusal with
            Google's ALERT text, and a new password used at once. B-056.*
      - [x] setup and Settings check sending (SMTP) too, so Gmail's
            wrong-account trap cannot pass setup
            *Done 2026-09-30, not yet seen on the iPad. B-056.*
      - [x] take out the B-033 `PAIR` probe, which logs subject lines
            (done 2026-09-30, D-016 phase 0, with the sender in
            `SESSION-IDENT`)
      - [ ] a build number he or a helper can read out
      - [x] a safe start after launches that never finished, and the
            Outbox and Drafts giving up on a letter after three tries the
            app did not live through
            *Done 2026-10-01, seen in part on the iPad: the copy of his
            mail and the view settings left behind after two, no automatic
            pass after three, the letters kept on the iPad set aside, never
            deleted, after five, and brought back from Settings; a launch
            that ended in a letter's try charged to the letter. B-057, and
            its check under "Blocked on the iPad coming back".*
      - [x] a guard so the signature cannot be wiped by accident
            *Done 2026-09-30, not yet seen on the iPad: setup keeps it,
            plain text and an empty one are asked about, Restore Original
            Signature, and the password item written before anything is
            deleted. B-056.*
      - [x] Go to Date bounded by when a letter arrived, so one dated wrong
            into the future cannot take every jump
            *Done 2026-10-01, seen on the iPad. B-058.* And on 2026-10-03,
            seen on the iPad: one copied in with a wrong arrival cannot
            either, and a jump lands on his day, not the evening before.
      - [ ] `provision-ipad.sh`: the TrollStore iOS range is wrong (:132 takes
            all of 16.7.x)
      - [x] the reading pane runs no letter's script and goes nowhere by
            itself. *Done 2026-09-30, not yet seen on the iPad: script off,
            the pane's own in the app's content world, only its own pages
            loaded, WebKit's data in memory; pictures from the web still
            load. See B-055, and its check under "Blocked on the iPad
            coming back".*
- [ ] On the day: Smart Invert off, what to do about Apple Mail's badges,
      the six-task test with him.

**Ways a letter is lost** (all confirmed in the code):

- [x] Save Draft with no connection throws the letter away silently
      (`ComposeActions.saveAndClose`; a test pins the silence). Mail keeps
      the draft on the iPad.
      *Done 2026-09-30, not yet seen on the iPad: kept on the iPad before
      the sheet goes, listed in Drafts as "On this iPad only", taken to
      Gmail once when the connection works, never twice. See B-051.*
- [x] Delete inside Trash erases for good with no confirmation, which the
      spec asks for (`IMAPMailRepository` :1169).
      *Done 2026-10-03, the question seen on the iPad the same day: the
      reading pane's Delete and Edit mode's ask first in Trash, "Delete
      Message?", "This message will be deleted immediately. You can't undo
      this action.", Cancel and a red Delete, and Cancel leaves everything
      as it was; not in Spam, where Delete moves to Trash. The erase after
      it, a `UID EXPUNGE` after the `\Deleted`, came after the check and
      was seen the same day. B-062, and its check under "Blocked on the
      iPad coming back".*
- [x] Delete and Move of several letters in Edit mode fail silently
      (`MessageListViewController` :1070, :1133); Delete shows no progress.
      *Done 2026-10-03, seen on the iPad: every ticked row goes at
      the tap and Edit mode ends, "Deleting…" or "Moving…" on the line
      until the server has answered for each, a letter it did not take
      back on the list with the ones after it unsent and the app's alert
      saying why, and the counts moved for the letters that went. B-062.*
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

- [x] Links in plain-text letters cannot be tapped (`PanePage` escapes and
      nothing links them; WebKit's data detectors are off). About a third of
      his own shared links are plain text. *Done 2026-09-30, not yet seen
      on the iPad: `http://`, `https://`, `www.` and `mailto:` made links as
      the page is built, the sentence's punctuation left out as Mail leaves
      it, and in HTML letters' text too. See B-055.*
- [x] Sent and Drafts rows show his own name, not the recipient's.
      *Done 2026-10-03, seen on the iPad: in Sent Mail, Drafts and
      the Outbox the row names whom the letter is to, To, Cc and Bcc, each
      person once, the name or the address where there is none; a
      conversation everyone he wrote to in it; "No Recipients" for a draft
      to nobody; the drafts "On this iPad only" too, the kept copy and
      VoiceOver with them. His letters found by an All Mailboxes search
      still name him, as in All Mail. See B-060, and its check under
      "Blocked on the iPad coming back".*
- [x] The reading pane never shows Cc, nor any bare address. *Done
      2026-09-30, not yet seen on the iPad: Cc under To, names, and the
      address where there is none, To the same; a name with a comma in it
      is one recipient; and since 2026-10-01 there from the tap, from the
      row's ENVELOPE. See B-055.*
- [x] Reply ignores Reply-To; replying to his own letter addresses it to
      himself; Reply All misses his second address. *Done 2026-10-03, seen
      on the iPad: Reply goes to the Reply-To, his own letter to
      whom it went, a letter from several to them all, and Reply All keeps
      the To in To and the Cc in Cc, names and all, each once and each on
      one line, and leaves out his address in every spelling Gmail
      delivers to him. His second address, on another domain, is his only
      once the owner says how the app is to know it (under "Blocked on the
      owner"). See B-061, and its check under "Blocked on the iPad coming
      back".*
- [x] A reply finished from Drafts went with no In-Reply-To and no
      References, and began a conversation of its own (found on the iPad
      in B-061's check). *Done 2026-10-03, seen on the iPad: a
      reply reopened from Drafts, from a search, from the iPad or from the
      Outbox still answers its letter, with that letter once in
      References, and whatever another client wrote in a draft's
      In-Reply-To goes as its ids alone, on one line. See B-064, and its
      check under "Blocked on the iPad coming back".*
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
      until the rest of its checks.* *Changed 2026-10-04, not yet seen on
      the iPad: a shared photo is made a JPEG of at most 4096 px by
      ImageIO, from its file, asked for a size the decoder reaches by
      halving, so a 48-megapixel one is decoded at a half, 49 MB, not
      whole at 195 MB, which made the sheet vanish on the iPad the same
      day. Its location does not go; a small GIF or PNG goes as it is; a
      photo that could not be attached is said.* *Changed again
      2026-10-05, not yet seen on the iPad: as Apple Mail does, by the
      owner's ruling. A JPEG that fits goes as its own bytes, never
      decoded, under its file's name ("IMG_0776.JPG"), its metadata
      replaced by the date and the orientation alone, so still no
      location; a GIF or PNG whole at any size that fits; "image0.jpeg"
      for a picture with no name; shrunk only when it does not fit or
      cannot go as itself, at a factor the memory left allows, or left
      out and said (B-036, "2026-10-05: as Apple Mail does"). Fits: in
      the 25 MB, and in the memory Send builds the letter in, at five
      times its files; its own bytes read back before they go, and made
      a JPEG if they still say where. The checks left are the numbered
      list at the end of "Blocked on the iPad coming back".*
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

- [x] Saving a received photo may crash: no Photos usage description in
      Info.plist. Needs a device check. *Done 2026-10-04, seen on the
      iPad: it did end the app, from "Save to Photos" on a picture in a
      letter; both keys are in, iOS asks, and "Save Image" is offered.
      B-067.*
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
- [x] **B-066. The view button's switch moves.** Asked for by the owner
      on 2026-10-03: "We need better transition animation between the
      three-panel view and the two-panel view." Calm, nothing wobbling,
      nothing moving up or down, nothing reflowing while it moves.
      *Done, not yet seen on the iPad: pictures of the panes slide
      sideways for 0.4 s and settle for 0.2 s over the panes already laid
      out beneath them, and with Reduce Motion the screen fades for 0.3 s
      (`PaneMove`, `PaneMotion`). "< Mailboxes" and a folder tap stay
      instant, and so does a switch tapped while a list or the letter
      bounces past an end. Checked in `PaneMoveTests` and `PaneArrangementTests`; see
      B-066. What to look at on the iPad is below.*
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
      `package.sh`. *Safari seen 2026-09-30; what is left is "The share
      sheet's checks", the last item of this section.*
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
- [ ] **B-051, what a kept letter names, by its Gmail id.** Cases 1 to 3
      seen on the iPad 2026-09-30 (B-051); case 4 is for an iPad that had
      letters from before the ids, which his fresh install will not. A draft
      in Gmail cannot be opened with no connection: in case 1, open it, then
      cut the Wi-Fi, then change it. Each case is made by hand in the store, with the
      app ended (swiped away in the app switcher, so nothing writes a letter
      under the edit). The store is `Library/Application Support/Local
      Drafts/` in the app's data container; over SSH, `find
      /var/mobile/Containers/Data/Application -maxdepth 5 -type d -name
      'Local Drafts'`. One directory per letter, named by a UUID, holding
      `letter.json`: one line of JSON, its keys in no fixed order and its
      slashes written `\/`, so a UID reads `"messageID":"1\/2345"`. `grep -l
      '"subject":"Test two"' */letter.json` finds the letter. Copy it aside
      first (`cp letter.json /var/tmp/`) and put it back after; an edit that
      breaks the JSON only drops that letter from the lists. `password-saves`
      beside the directories is the count of passwords saved, once one has
      been.
      1. The copy a draft was reopened from. Write "Test one" to himself,
      Save Draft; open it from Drafts, then Wi-Fi off, change the subject to
      "Test two", Cancel, Save Draft: "On this iPad only". End the app. In
      its `letter.json`, `grep -o '"savedLetter":[0-9]*'` gives Gmail's id
      for "Test one"; write it one higher (`sed -i` with the two numbers
      spelled out; BSD sed wants `-i ''`). Open the app with Wi-Fi off and
      go to Drafts: "Test two" at the top, "On this iPad only", and "Test
      one" listed below it, since the row under its UID names another letter
      than the one the letter now names; before the edit only "Test two" was
      listed. End the app. Wi-Fi on, open the app: the pass after the
      Inbox's first page takes it. The connection log: the `APPEND` of "Test
      two" (after a `UID SEARCH HEADER Message-ID` if the offline save
      reached its APPEND), then `UID FETCH n (UID X-GM-MSGID)` in Drafts,
      not yet listed in this launch, and no `UID STORE` or `UID EXPUNGE`;
      the notes `KEPT-UNVOUCHED folder=[Gmail]/Drafts nothing-sent` and
      `DRAFT-SUPERSEDED folder=[Gmail]/Drafts not-that-letter left`. Drafts
      on the web has both; delete them there. Again with no edit: one copy,
      "Test two", the `UID STORE` and `UID EXPUNGE` after that FETCH as Save
      Draft always sent them.
      2. A forward's file found in All Mail. Forward to himself an Inbox
      letter that carries a PDF, Wi-Fi off, Send: the Outbox. End the app.
      In its `letter.json`, the file's `"messageID":"1\/U"`: write U one
      lower, which is another letter's UID or none. Wi-Fi on, open the app:
      it goes by itself, and the log shows no `BODY.PEEK[2]` in the Inbox,
      `CARRIED-PART folder=INBOX reason=another-letter` (or `reason=gone`),
      `UID SEARCH X-GM-MSGID …` in All Mail, the part fetched there, and
      `CARRIED-PART found folder=[Gmail]/All Mail`. The letter arrives with
      the PDF that was forwarded, under its own name. Before, it went with
      the file of whatever letter had that UID, or failed.
      3. A file nowhere. As 2, but write the file's `"letter":` number one
      higher instead, an id no letter has: the letter stays in the Outbox,
      its row reading "Attachment could not be downloaded.", nothing is
      sent, and the log ends `CARRIED-PART not-found nothing-sent`; a letter
      sent offline after it goes. Open it and Send: the sheet stays with the
      same words. Take the file off and Send: it goes. The same with Save
      Draft in place of Send: its row in Drafts reads "On this iPad only",
      then the words on the line under it. A forward whose quote shows a
      picture (a letter from Mail with a photo in its words) the same, by
      its entry under `"pictures"`, which has its own `"messageID"` and
      `"letter"`.
      4. A letter kept before the ids were, and a password saved. Make one:
      a draft reopened from Drafts and saved offline, as in 1, then take its
      ids out, `sed -i -E 's/,"(savedLetter|letter)":[0-9]+//g;
      s/"(savedLetter|letter)":[0-9]+,//g' letter.json`. Open the app with
      Wi-Fi on: it goes as before, its old copy removed. Then the save,
      which has to come before the letter it is to hold: Settings checks a
      new password with Gmail, so the app is open with Wi-Fi on, and a
      letter already kept without its ids would go up at the Inbox's first
      page before Settings could be reached. Wi-Fi on, Settings, type the
      same app password into the password field and tap Save (a blank field
      keeps the password and counts nothing); `password-saves` now reads one
      more. In the same launch, Wi-Fi off, reopen a draft, change it, Save
      Draft: it is stamped with the count this launch found, from before the
      save. End the app, take its ids out with the same `sed`, and open the
      app with Wi-Fi on: the letter stays "On this iPad only", no APPEND for
      it, its old copy listed beside it; opened and saved, it goes up as a
      new copy and the old one stays. A letter written in this launch goes
      up by itself. (Or leave Settings alone: make the letter and take its
      ids out, then, the app still ended, raise `password-saves` by one by
      hand, `echo 1 > password-saves` where there is none, and open the
      app.)
      5. A letter cut off after its DATA before a password save (B-052,
      "Across a password save"). Wi-Fi off, Send a letter to himself: the
      Outbox. End the app. In its `letter.json`, write its Message-ID down
      as an attempt that went, `sed -i 's/"outbox":"\([^"]*\)"/&,"unsettled":["\1"]/'
      letter.json`; with no stamp beside it, the attempt reads as made
      before any save. Make sure `password-saves` reads 1 or more (4 leaves
      it so; else `echo 1 > password-saves`). Wi-Fi on, open the app:
      nothing goes for it, no `UID SEARCH HEADER Message-ID` and no
      `ENVELOPE`, and its row in the Outbox reads "May already have been
      sent.", with "1 Unsent Message" under the list. Tap it, Send: the log
      shows the look in Sent Mail, then one `ENVELOPE`, and the letter
      arrives once. With no `password-saves` file at all, the same edit
      makes the pass look in Sent Mail and send it by itself.
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
- [ ] **B-056, signing in again, and the signature.** Seen 2026-09-30: the
      two confirmations, a wrong password refused with the old one kept,
      and the refusal shown under the password field (B-056). Still to see,
      on the test account, with the app open on the Inbox: revoke
      its app password at myaccount.google.com/apppasswords and make a new
      one. Once Gmail refuses the old one, at the next connection the app
      makes (lock the iPad for a few minutes and come back, if the open
      session carries on), the line says "Password Needs Updating"; tap a
      letter: "Cannot Get Mail", "The user name or password for “Gmail” is
      incorrect.", Settings and OK. Tap Settings: Settings opens with the
      keyboard in the password field, the line under it naming the account's
      address. Type the new password, Save: "Checking the new password with
      Gmail…", and the sheet closes with no relaunch. The Inbox is empty a
      moment, then "Checking for Mail…", then "Updated Just Now"; the log
      shows the check (a LOGIN, LIST and LOGOUT, then `SIGN-IN CHECK
      host=smtp.gmail.com:465` and an AUTH), `PASSWORD-SAVED signed in
      afresh`, the old connection's LOGOUT and a new LOGIN, and a letter sent
      then goes. Put a letter in the Outbox (Wi-Fi off, Send) before revoking:
      after the save it goes by itself, once. Then make an app password while
      signed in to another Google account, and type it into Settings, and into
      setup with the stored password removed by hand as for a clean install
      (B-031): both refuse it with "Gmail took that password for reading mail
      but refused it for sending. Make the app password while signed in to
      Google as <address>. If you are sure it was made as <address>, wait an
      hour and try again.", the address the account's and the whole of it
      readable under the button, Settings adding that the old password is
      still in place, and nothing is sent. Gmail's 534 at the check cannot
      be asked for; if one comes (Google wanting a sign-in on the web after
      sign-ins it found odd): Save closes Settings, the new screens come
      up, and "Cannot Send Mail" is put up over them at once while the
      Inbox fills behind it, "Gmail accepted the password for reading mail
      but is refusing to send for now. The server returned the error:
      Please log in via your web browser…" with OK, Gmail's words whole
      and no piece of its accounts.google.com sign-in address among them,
      the log showing `smtp=sign-in-refused` then `PASSWORD-SAVED signed
      in afresh`; a letter sent then keeps its sheet with "Gmail refused
      the sign-in.", and goes once Google has been satisfied on the web.
      The password item is now written before older ones are deleted, and
      they are deleted by persistent reference, which has not run on a
      device: once the new password is saved, a Keychain dump on the
      jailbroken iPad should show one item for the account, as B-033's
      probe did. A refusal that is not the password,
      if one can be had (a normal Google password in Settings gets Gmail's
      "Application-specific password required"): the sentence with Google's
      words under Save. Last, with the signature set: tap "Send my signature
      as plain text instead" and Cancel, then Use Plain Text and Save; open
      Settings again, "Restore Original Signature", Restore, Save; write a
      letter to the account: the formatted signature and its logo are back.
      Without leaving the app, open a letter's attachment, share it from the
      preview to Blackmail (or, if Blackmail is not offered there, a link
      from Safari in Slide Over) and send it to the account: the logo is on
      that letter too (the share extension handed the pictures at the save,
      not at the next trip to the background). Empty the box and Save:
      "Remove Signature?", Cancel keeps it.
- [ ] **B-053, every write and every open naming its letter.** Seen
      2026-09-30: the everyday wire after the page (open, Flag, Edit's
      Mark), and a copy made another mailbox's by hand refused under held
      ticks with nothing sent (B-053). Still to see, with Wi-Fi on and
      after "Updated Just Now": move a letter and delete another: the
      connection log shows each as it did, the `UID MOVE` with no `(UID
      X-GM-MSGID)` FETCH before it, and no `KEPT-` line. The same for a row on a page scrolled down to, a day jumped
      to, a search hit, a letter opened inside a conversation, a draft
      reopened, and Edit mode's Mark, Move and Delete. Then open Sent Mail,
      opened before, and before its page lands, if it can be caught, open a
      row and flag it from the pane: the letter's own FETCH with
      `X-GM-MSGID` beside `BODY.PEEK[]`, where it used to be the plain one
      once the Inbox had been listed, then the `UID STORE` alone, the FETCH
      having asked. For the question before a STORE, tap an unread row the
      same way, before its page lands, in a folder opened before that has
      unread mail: the read mark's `UID FETCH n (UID X-GM-MSGID)` before its
      `UID STORE`, beside the letter's FETCH with the id, and its dot stays
      off. Sent Mail's rows are his own letters, read, so a tap there sends
      no read mark; on the slower connection the swap under ticks needs,
      Edit, a tick on a Sent Mail row and Mark as Unread can all be made
      before its page lands: `UID FETCH n (UID X-GM-MSGID)` before
      `UID STORE n -FLAGS.SILENT (\Seen)`, then Mark as Read to put it back.
      On that connection too: send the account two letters, force-quit, open
      it, and before the page lands tick, in Edit, the last row of the kept
      Inbox, a read one (read it on an earlier launch if it is not), and a
      read one near the top. Once the page has come and waits for the ticks,
      the last row is one the new letters pushed off it: Mark as Unread
      sends `UID FETCH n (UID X-GM-MSGID)` before that row's `UID STORE`,
      where it used to go unasked, and the STORE alone for the other. The
      Mark ends Edit mode and lets the fresh page on, so the row pushed off
      leaves the list; scroll down until the page below brings it back, then
      tick it and the row near the top in Edit and Mark as Read: the two
      STOREs alone, the page below having named it. Another mailbox's copy
      is made by hand by giving kept rows ids of no letter there, with the
      app ended (B-053); a letter opened from one needs the slower
      connection too.
- [ ] **B-055, the reading pane locked down, links in plain letters, Cc.**
      Seen 2026-09-30: letters and their web pictures drawn, a conversation's
      letter opened and closed, a plain letter's links asking before they
      open, and Cc in the first frame (B-055). Still to see, the rest: send the test account the letters
      below from another account; not his mailbox.
      Every letter, notice and conversation still draws at all: the pane
      now loads only `about:blank` from `loadHTMLString`, and if WebKit
      named the pane's own page otherwise, nothing would.
      *A conversation.* Three letters or more: the newest open, the rest
      lines. Tap a closed line: it opens, its body comes, the header and
      Reply move to it, its dot and one count go, and the line greys under
      the finger as it did. Tap it again: it closes. Open two in quick
      succession; leave the pane fifteen seconds and open another, whose
      body goes in after WebKit's pause. With letters open, `killall -9
      com.apple.WebKit.WebContent`: the stack comes back with them open and
      their bodies in (B-042).
      *Links in plain letters.* A plain-text letter, from a client set to
      send plain text, with a YouTube link, a Wikipedia link ending
      `_(film)`, `www.example.com.`, `(https://example.com/a),` and a
      `mailto:` in it: each is a link, whole, the full stop and brackets
      not in it. A tap
      asks "Open this link?" with the site's name and Open goes to Safari;
      the `mailto:` opens the composer with its address. The same in a
      conversation, and an address written in an HTML letter's text.
      Hold a finger on one: WebKit's own menu and its preview, left as
      Mail has them (decided 2026-10-01); note only that nothing else
      happens, and that letting go leaves the letter as it was.
      *Cc.* A letter with a named Cc, an unnamed one, and one named
      `"Example, Pat"`: "Cc: …" under To in To's grey, the rule under it,
      Pat once; Reply All puts Pat in once. A letter with no Cc: the header
      as it was. The Cc line is there at the tap, under "Loading…", and
      nothing in the header moves as the letter lands (since 2026-10-01).
      Open a conversation whose newest letter has the Cc: the stack does not
      move as its body comes. Force-quit and open, and tap the same letter
      on the kept Inbox before the page lands: the line at the tap again,
      once a page of this build has been kept; on the first launch of it the
      kept page is the last build's, and the line comes with the letter.
      *A letter that tries to go somewhere.* HTML with `<meta
      http-equiv="refresh" content="0;url=https://example.com">`, an
      `<iframe src="https://example.com">`, a `<form
      action="https://example.com">` with a field and a button, a
      `<script>` that rewrites the page, and `<img src=x onerror=…>`: the
      letter stays as written, the frame is empty, the button does
      nothing, no script's change shows, and the connection log holds
      nothing of the letter. The same letter inside a conversation.
      *Pictures from the web.* A newsletter's pictures still load, as
      before.
- [x] A folder count asked just before his read mark reaches the server
      puts the old count back for a second: at launch, a letter read while
      the STATUS sweep that follows the first page is out shows the Inbox
      as 1, then 2, then 1 when the sweep `adjustUnreadCounts` asks for
      lands. Seen on the iPad 2026-09-30; older than the kept copy, which
      only makes a tap that early likelier.
      *Done 2026-10-01, seen on the iPad: a folder marked since a
      sweep left keeps the pane's count when it lands. B-059.*
- [ ] Save Draft with no connection, with Drafts open: the list keeps the
      Gmail copy's row, and the new "On this iPad only" row takes its place
      only some eight seconds later, once the save's upload has failed.
      Seen on the iPad 2026-09-30. Nothing is lost; the row should come at
      once, as the letter is kept before the sheet goes.
- [ ] A forward with several files found in All Mail searches for the
      original once per file (`UID SEARCH X-GM-MSGID` before each part);
      once would do. Seen on the iPad 2026-09-30.
- [ ] A letter read from its All Mailboxes hit leaves the Inbox's row for
      the same letter with its unread dot until the list is fetched again,
      though the Inbox's count goes down. Seen on the iPad 2026-10-03.
- [x] The folder pane redraws only the Inbox's count after a read mark:
      `adjustUnreadCounts` patches the cell at `IndexPath(row: i, section:
      0)`, `i` an index into the flat list of folders, and the pane has had
      two sections since the Inbox got a block of its own, so All Mail,
      Important and Sent Mail keep their old number on screen until the
      next sweep, though the count under them is right (and kept so). Seen
      on the iPad 2026-09-30; older than the kept copy.
      *Done 2026-10-01, seen on the iPad: each folder found in its
      block. B-059.*
- [x] The folder pane draws Important blank while the Outbox's block is
      under the folders, and its middle takes no tap: the gap's footer,
      painted, left where the keyboard pinned it. Seen on the iPad
      2026-10-03. *Done the same day, seen on the iPad: the footer is
      clear and lets taps through. B-065.*
- [ ] Watch keepalive find a dead socket during the quiet: open a letter,
      restart the router (the iPad itself stays on Wi-Fi, so only the path
      dies), wait three minutes, then tap another letter. It should load
      after one reconnect, not after a 30 s stall.
- [ ] **B-054, a letter too large to fetch whole.** Seen 2026-09-30: a
      15 MB letter of photographs shown from its structure, its parts cut at
      2 MB and a photograph fetched alone when tapped (B-054). Still to see:
      from another account, send the test account a letter of
      three full-size photographs shown in its body, as Mail on an iPhone
      sends them, and a PDF: 8 MB or more. Open it: the connection log shows
      `UID FETCH n (UID BODYSTRUCTURE BODY.PEEK[HEADER])`, then its text's
      and its HTML's FETCHes cut at `<0.2097152>`, and no `BODY.PEEK[]`; the
      words come at once and the photographs one after another, each one
      `UID FETCH n (UID BODY.PEEK[k])` and no more; the PDF's row opens the
      PDF. Open it again and tap the next letter while the photographs are
      still coming: the next letter comes after at most the one photograph
      on the wire, and the log shows no FETCH for the others. Forward it to
      the second address with a Cc: the photographs and the PDF arrive.
      Reply to it: the quote is there. Open a conversation with it in: the
      same FETCHes for it, the others' as ever. On a slow connection,
      force-quit and tap it on the kept Inbox before the page lands: the
      first FETCH carries `X-GM-MSGID`. And with the Inbox open, the
      connection log shows the SEARCH as `* SEARCH {N uids}` and its screen
      scrolls without a stall. A letter whose HTML is over 2 MB, if one can
      be had, shows "Only the beginning of this message is shown." above
      it; Reply to it and Forward it to the second address: the composer's
      quote ends with the same words under a blank line, and the letter
      received ends its quote with them in grey, in Mail and on Gmail's web
      page, once (since 2026-10-01). Save the reply as a draft, reopen it
      and send it: the line still once.
- [ ] **B-057, a safe start, and the Outbox giving up after three tries.**
      Seen 2026-10-01 (B-057): steps 1 and 2's first launches, the fifth
      with Bring Back, the leftover, and three tries after a DATA that may
      have gone, and, on the build after, step 4's letter in the Outbox
      coming back held, its notice, and going only by his Send. Still to
      see: the swipe in the app switcher, a launch
      charged to a letter (step 8), and a held draft's row.
      Seen in part on the iPad on 2026-10-01, on the build before Bring Back
      and the charge to a letter: step 1 but for the swipe, its third launch
      taking the second stage, and step 6's Outbox letter. Step 2's own
      checks, and what is left, are seen on the build with both. Every stage
      is made by hand in the app's files with the app ended, swiped away in
      the app switcher. Every step begins, with the app ended, with `rm -f
      Launches/trying`: a mark left by an app ended mid-try
      would have the step's first launch charged to a letter, a stage short
      of the one the step writes. Whether the swipe finishes the launch is
      step 1's to show, so until it has, every step that does not write the
      count itself begins with `echo 0 > Launches/unfinished` as well:
      otherwise a count left standing could hold the pass, or set the
      letters aside, for a reason that is not the step's. The files are in
      `Library/Application Support/` in the app's
      data container; over SSH, `cd "$(dirname "$(find
      /var/mobile/Containers/Data/Application -maxdepth 5 -type d -name
      Launches)")"` once the app has been opened once. `Launches/unfinished`
      is the count, one number; `Launches/safe-starts.json` the steps taken;
      `Launches/trying`, while the pass has a letter on its way, that
      letter's key, and nothing else; each letter is `Local Drafts/<UUID>/letter.json`
      (B-051's case list says how to find one). The notes are in the
      connection log (five taps on the line under the list).
      1. *A look, and a crash.* Open the app and go to the Home Screen
      within two seconds: `cat Launches/unfinished` reads 0. Open it and
      swipe it away in the app switcher within two seconds: 0 again. Open
      it and stay on the Inbox: it reads 1 until half a minute after the
      Inbox's page has come, and any letter the pass takes has gone, then
      0. Open it and, within ten seconds, `killall -9 Blackmail`, which ends
      it as a crash does, without the background: 1. Open it again and,
      before killing it, open the connection log, which lives only in
      memory and goes with the app: it begins `SAFE-START unfinished=1`.
      Kill it: 2. Open it a third time: the next stage.
      *Seen 2026-10-01: the stay read 1, then 0 half a minute after the
      first page; the quick look read 0; two kills left 2, and the third
      launch took stage 2. The swipe is still to see.*
      2. *After two.* Choose two panes, turn Organize by Thread off, and
      pick All Mailboxes and a day last year in Go to Date. End the app,
      `echo 2 > Launches/unfinished`, open it: no kept rows in the first
      frame, the Inbox empty under "Checking for Mail…" until its page
      comes, three panes, conversations grouped, Go to Date on Current
      Mailbox and at today; the log starts `SAFE-START unfinished=2`,
      `SAFE-START kept-copy=wiped`, `SAFE-START view-settings=reset`, and
      `cat Launches/safe-starts.json` names both steps. Letters "On this iPad
      only" in Drafts, and the Outbox, are still there. Leave: the count
      reads 0. Open it again: the kept Inbox is back in the first frame; the
      count reads 1, and 0 again half a minute after the page.
      3. *After three.* Wi-Fi off, Send a letter to himself: the Outbox.
      End the app, Wi-Fi on, `echo 3 > Launches/unfinished`, open it: the
      Inbox's page comes, and the letter stays in the Outbox, no `ENVELOPE`
      in the log, which has `SAFE-START automatic-pass=held`. Go to the Home
      Screen and back, and wait a minute: still nothing goes. Send another
      letter from the composer: it goes at once. End the app and open it:
      the waiting letter goes by itself, once.
      4. *After five, and Bring Back.* Wi-Fi off. Save Draft two letters to
      himself, one with a photo, and Send a third: the Outbox. End the app.
      `(cd "Local Drafts" && find . -type f -exec shasum {} + | sort -k2)
      > /var/tmp/before.sum`, `echo 5 > Launches/unfinished`, open it:
      Drafts has no "On this iPad only" and there is no Outbox, and the log
      ends its safe start with `SAFE-START local-drafts=set-aside
      folder="Local Drafts set aside <date> <time>"`. `ls` shows that
      folder beside `Local Drafts`; in it, the same `find … shasum` matches
      `/var/tmp/before.sum` line for line. Stay in the app, Wi-Fi still off,
      until `cat Launches/unfinished` reads 0, half a minute after the
      page. Open Settings: under Organize by Thread, in blue, "Bring Back
      Set-Aside Letters". Tap it: an alert, "Bring Back Set-Aside
      Letters?", "Letters on this iPad that were set aside when Blackmail
      could not start will go back to Drafts and the Outbox.", Cancel and
      Bring Back, neither red. Cancel: nothing changes, and the row is
      still there. Tap it again, then Bring Back: the row goes. Close
      Settings: Drafts has the two letters under "On this iPad only", the
      Outbox has the third, its row reading "Not sent automatically. Open
      it and tap Send.", and the line under the list "1 Unsent Message";
      the log has `SAFE-START brought-back=3`, `safe-starts.json` ends with
      `letters-brought-back` and `"broughtBack":3`, `Launches/unfinished`
      still reads 0, and `ls` shows no folder set aside. In `Local Drafts`
      the same `find … shasum` matches `/var/tmp/before.sum` line for line
      but for the Outbox letter's `letter.json`, which now holds
      `"autoAttempts":3` (since 2026-10-01). Open Settings again: no row.
      Open the letter in the Outbox and tap Send, Wi-Fi still off: the
      sheet closes with "Message is in the Outbox. It will not be sent
      automatically. When the iPad is connected, open it and tap Send.",
      and the letter is still in the Outbox, its row as before.
      Wi-Fi on, Refresh: nothing goes, since this launch, after five, holds
      the pass. End the app and open it: the draft without the photo goes
      up by itself, once, and the draft with the photo with it if its photo
      is under a megabyte. At a megabyte or more, as a photo from the
      camera is, it goes up by itself only as he leaves (B-051): go to the
      Home Screen, and it goes up, once. The letter does not go: the log
      says `OUTBOX-HELD unfinished-tries=3`, and it is still in the Outbox
      after a minute. Open it and tap Send: it goes, once. One copy of each
      draft on the web, and the letter arriving once.
      5. *A leftover.* With the app ended, `mkdir "Local Drafts/leftover"`
      and copy any photo into it; `mkdir "Local Drafts/damaged"` and `echo
      '{' > "Local Drafts/damaged/letter.json"`. Open the app: `leftover`
      is gone, `damaged` is still there and lists nowhere, and the log says
      `DRAFTS-LEFTOVERS removed=1`. Remove `damaged` by hand.
      6. *Three tries.* Wi-Fi off, Send a letter to himself, and Save Draft
      another. End the app. In each `letter.json` write three tries the app
      did not live through: `sed -i 's/"format":1/"format":1,"autoAttempts":3/'
      letter.json` (BSD sed wants `-i ''`). Wi-Fi on, open the app: neither
      goes, no `ENVELOPE` and no `APPEND`; the Outbox row's first line is
      "Not sent automatically. Open it and tap Send.", the line under "On
      this iPad only" in Drafts "Not saved to Gmail automatically. Open it,
      tap Cancel, then Save Draft.", the line under the list "1 Unsent
      Message", and the log has `OUTBOX-HELD unfinished-tries=3` and
      `DRAFT-HELD unfinished-tries=3`, once each however often the pass
      runs. Tap the Outbox letter, Send: one `ENVELOPE`, and it arrives
      once. Open the draft, Cancel, Save Draft: one `APPEND`, one copy in
      Drafts on the web. Again with `"autoAttempts":2`: both go by
      themselves.
      *Seen 2026-10-01 for the Outbox letter: held, its row's first line
      "Not sent automatically. Open it and tap Send.", and his Send sent
      it once. The draft's row, with its new words, is still to see.*
      7. *Three tries after a DATA that may have gone.* As 6 for the Outbox
      letter, and also write its Message-ID down as an attempt whose DATA
      went, stamped with the count of passwords saved as the pass stamps
      it. Unstamped, as in B-051's case 5, the attempt reads as made before
      a password save, which setup itself counts, and the letter is passed
      over for that reason whatever its tries, so the step would prove
      nothing. From `Application Support`: `n=$(cat "Local
      Drafts/password-saves" 2>/dev/null || echo 0)`, then in the letter's
      folder `sed -i "s/\"outbox\":\"\([^\"]*\)\"/&,\"unsettled\":[\"\1\"],\"unsettledSaves\":$n/"
      letter.json`. Open the app: no `UID SEARCH HEADER Message-ID` and no
      `ENVELOPE` for it; its row's first line is "May already have been
      sent.", alone, not step 6's, since its DATA may have reached them; the
      log has `OUTBOX-HELD unfinished-tries=3`. Tap it, Send: the look in
      Sent Mail first, then, Gmail not having it, one `ENVELOPE`, and it
      arrives once. The control: the same edits with `"autoAttempts":2`,
      and the pass itself makes the look in Sent Mail and sends it, once.
      8. *A try the app does not live through, charged to the letter, and
      one the background cuts short.* Wi-Fi off, Send a letter with four or
      five full-size photos to himself, end the app, Wi-Fi on. Over SSH,
      watch its file and the mark: `while sleep 0.2; do grep -ho
      '"autoAttempts":[0-9]*' "Local Drafts"/*/letter.json; cat
      Launches/trying 2>/dev/null; echo; done`. Open the app:
      `"autoAttempts":1`, and the letter's key in `trying`, while the pass
      sends it. Before it arrives, `killall -9 Blackmail`: both stay with
      the app gone, and `Launches/unfinished` reads 1. Open the app: the
      count still reads 1, not 2, `trying` is
      gone until the pass takes the letter again, a second or so after the
      page, and holds its key from then until the try ends, and the log
      begins `SAFE-START charged-to-letter`, with no `SAFE-START
      unfinished`; the letter goes, or is found in Sent Mail, once, and
      `trying` goes with the try. Half a minute later the count reads 0. The same again, but go to the Home Screen while it sends
      instead of killing it: the count and the mark go at once, as the app
      leaves, while the letter is still on its way, and it arrives once.
      And again, swiping the app away in the app switcher while it sends:
      the count and the mark go as the app goes, whichever way the swipe
      ends it, and the letter arrives once, or at the next launch once.
      Still 1 with the app gone, and the swipe ends a running app as a
      crash does, with neither the background nor
      `applicationWillTerminate`: write that into B-057, with what step 1's
      swipe left in `Launches/unfinished`.
- [x] **B-060, Sent Mail and Drafts name whom each letter is to.** Only
      letters the test account sends to itself. Gmail delivers mail for its
      address with `+jane` or `+sam` put before the `@` to the same
      mailbox, so below, "Jane's address" is that with `+jane`, typed into
      the field as `Jane <` the address `>`, "Sam's address" that with
      `+sam`, typed as `Sam <` the address `>`, and "Sam's bare address" the
      same typed alone, with no name. The names are short because the
      row's top line is: some 168 points of 17-point semibold in three
      panes, the default, and some 213 in two, cut off with "…" where the
      names run past its end. "Sam, Jane (2)" fits; "Jane Example, Sam
      Example (2)" does not, nor, most likely, a whole address. So the
      screen is checked below for what fits on it, and step 8 hears the
      rest with VoiceOver, which reads the whole line. Organize by Thread
      on.
      1. *The first launch of this build.* Before installing it, open Sent
      Mail once on the build before, so its page is kept. Install, Wi-Fi
      off, open the app, open Sent Mail: its kept rows draw at once, each
      naming the test account as before, and none says "No Recipients".
      Wi-Fi on.
      2. *Sent Mail.* Write a letter To Jane's address, Subject "B-060
      one", and Send. Write another To Sam's bare address, Cc Jane's, Bcc
      the test account's own address, Subject "B-060 two", and Send. Open
      Sent Mail: the top line of "B-060 one" reads "Jane", and that of
      "B-060 two" begins with Sam's bare address, as much of it as fits
      before the "…", which may stop short of the `+sam`. Neither reads the
      test account's name. What follows on that line, "Jane" and the Bcc
      if Gmail kept it, is past its end or cut short; step 8 hears it. Tap
      "B-060 two": the reading pane's header is as before, From the test
      account, To Sam's bare address, Cc "Jane".
      3. *A conversation.* In Sent Mail open "B-060 one" and tap Reply. Its
      To is the test account itself (the open item about replying to his
      own letter); put Sam's address there in its place and Send. Sent Mail:
      the conversation's row reads "Sam, Jane (2)", the newer letter's
      person first, all of it on the line.
      4. *Drafts.* Write a letter with nothing in To, Subject "B-060
      nobody", tap Cancel, then Save Draft. Drafts: its row reads "No
      Recipients". Wi-Fi off, write a letter To Jane's address, Subject
      "B-060 kept", Cancel, Save Draft: under "On this iPad only" its top
      line reads "Jane", not the test account's name. Wi-Fi on, and once it
      has gone to Gmail its row still reads "Jane".
      5. *The Outbox.* Wi-Fi off, write a letter To Jane's address, Cc
      Jane's address again typed alone, Subject "B-060 outbox", and Send:
      the Outbox's row reads "Jane" and nothing after it, where Jane named
      twice would go on ", " and her address. Wi-Fi on: it goes.
      6. *Search.* In Sent Mail search "B-060" with Current Mailbox. A
      search's rows are never gathered into conversations, so each letter
      has a row of its own, with no count: "B-060 outbox" reads "Jane";
      the reply of step 3 reads "Sam" alone, not "Sam, Jane (2)"; "B-060
      two" begins with Sam's bare address, as in 2; and "B-060 one" reads
      "Jane". Tap All Mailboxes: the same letters, found in All Mail, read
      the test account's name, as they do in All Mail itself; open All
      Mail and see that they do.
      7. *The kept copy.* Force-quit, Wi-Fi off, open the app and open Sent
      Mail: the rows read as in 2 and 3 at once, and "B-060 outbox"
      "Jane"; Drafts reads as in 4. Wi-Fi on.
      8. *VoiceOver,* which reads the whole line the screen cuts short,
      after "Unread" where a row is. With VoiceOver on, in Sent Mail touch
      the row of "B-060 two": it reads Sam's bare address whole, with its
      `+sam`, then "Jane", then, if Gmail keeps the Bcc on its copy in Sent
      Mail, the test account's address, then the subject and the time, and
      no "To". Write down in B-060, under "Not known", whether the Bcc was
      read. Touch the conversation of step 3: "Sam, Jane, 2 messages", then
      the subject and the time. In Drafts touch "B-060 nobody": "No
      Recipients", then the subject. Then VoiceOver off, and delete the
      B-060 letters and drafts.
      *Seen on the iPad 2026-10-03, on carlo's mailbox: steps 1 to 7 as
      written. Step 8's VoiceOver was not tried; Gmail's ENVELOPE for
      "B-060 two" in Sent Mail has the Bcc, so Gmail keeps it (B-060).*
- [x] **B-061, Reply and Reply All addressed as Mail addresses them.**
      Every letter here goes from the test account to itself; A stands for
      its address, `name@gmail.com` say. A letter from someone else with a
      Reply-To, one from several, and one whose names are broken over
      lines cannot be made that way, and are the suite's
      (`ReplyAddressingRepositoryTests`).
      1. *His address in other spellings.* In the app, write a letter To A,
      Cc A with a dot put in its name (`na.me@gmail.com`) and A with
      `+b061` before the @ and `googlemail.com` after it
      (`name+b061@googlemail.com`), subject "B-061 spellings", Send. It
      arrives in the Inbox. Open it there and Reply: To is A alone, and the
      Cc row is closed. Cancel, Delete Draft. Reply All: the same, To A
      alone and nothing in Cc, where the build before put the two other
      spellings in Cc. Cancel, Delete Draft.
      2. *A name with a comma.* Write a letter To `"Example, Test" <A>`,
      typed or pasted whole, quotes and all, subject "B-061 name", Send.
      Open it in Sent Mail and Reply: To reads `"Example, Test" <A>`, one
      recipient. Type a word and Send: the connection log has one `RCPT
      TO:<A>` for it, the reply arrives in the Inbox once, and Show
      original on Gmail's web page has `To: "Example, Test" <A>`.
      3. *Through Drafts.* Open the letter of step 2 again, Reply All, type
      a word, Cancel, Save Draft. Open it from Drafts: To still reads
      `"Example, Test" <A>`, one recipient. Send: one `RCPT TO:<A>`, and
      it arrives once.
      4. *Forward.* Forward the letter of step 1: To and Cc are empty.
      Cancel, Delete Draft.
      *Seen on the iPad 2026-10-03, on carlo's mailbox, whose domain is
      not Gmail's: step 1 with A with capitals and A with `+b061`, the
      capitals left out and the tag kept, as on any domain but Gmail's.
      Steps 2 to 4 as written. The letter sent from the draft lost its
      In-Reply-To: B-064.*
- [x] **B-062, Delete inside Trash asks first; Edit mode's Delete and Move
      say what they are doing and what failed.** Seen on the iPad
      2026-10-03 but for the erase in Trash, changed after it (the note at
      the end). Use only letters the test account sends itself: from the
      app, eight with the subjects "B-062 1" to "B-062 8", and from the
      Gmail web, signed in as the test account, twenty-six more, "B-062 9"
      to "B-062 34", each to itself. Wait until all are in the Inbox,
      unread. Keep the connection log open beside each step.
      1. *Delete in the reading pane, in Trash.* In the Inbox, open "B-062
      1" and tap Delete: it goes to Trash, nothing asked. Open Trash and
      the same letter, and tap Delete: an alert, "Delete Message?", "This
      message will be deleted immediately. You can't undo this action.",
      Cancel on the left and Delete in red on the right. Tap Cancel: the
      letter is still in the pane and on the list, and the log has no `UID
      STORE` for it. Tap Delete again, then Delete in the alert: the pane
      empties and the row goes at once, the log has one `UID STORE …
      +FLAGS.SILENT (\Deleted)` in Trash and then `UID EXPUNGE` of the
      same UID, and the letter is not in Trash at its next open, nor found
      by an All Mailboxes search, nor on the Gmail web in Trash or All
      Mail. The test account has Auto-Expunge off, so this is the step
      that shows the erase.
      2. *Edit mode in Trash.* In the Inbox, tick "B-062 2" and then "B-062
      3", the lower row first, in Edit mode and tap Delete: both go at
      once, Edit mode ends, nothing is asked, and the line under the list
      says "Deleting…" until both `UID MOVE`s are answered, then "Updated
      …" again (on a good connection perhaps too quickly to read; the log
      has the two). The log's first `UID MOVE` is for the higher UID, "B-062
      3", the upper row: the list's order, not the order ticked. The
      Inbox's count in the folder pane goes down by two, and the log has
      one sweep of the counts after the two, a `LIST` and its `STATUS`es,
      and no fetch of the Inbox's page. Open Trash, Edit, tick both, and
      tap Delete: "Delete 2 Messages?", "These messages will be deleted
      immediately. You can't undo this action." Cancel: both still ticked,
      Edit mode still on. Delete, then Delete in the alert: both rows go,
      "Deleting…" until two `UID STORE`s and their two `UID EXPUNGE`s are
      answered, and neither is in Trash at its next open or on the web.
      3. *Spam asks nothing.* Open "B-062 4", Move it to Spam, open Spam and
      tap Delete on it: nothing is asked, and it is in Trash after a
      Refresh of Trash.
      4. *A search that mixes Trash with other folders.* Delete "B-062 5"
      from the Inbox so that it is in Trash. Search "B-062" in All
      Mailboxes, tap Edit, tick the hit for "B-062 5" (from Trash) and the
      hit for "B-062 6", and tap Delete: "Delete 2 Messages?", "1 of them
      is in the Trash and will be deleted immediately. You can't undo this
      action." Delete: the log has a `UID EXPUNGE` in Trash for "B-062 5",
      which is gone from Trash at its next open, from the search and from
      the web altogether, and "B-062 6" is in Trash.
      5. *The reading pane is left alone.* Open "B-062 7" in the pane,
      tap Edit, tick "B-062 8" and Delete: "B-062 7" stays in the pane.
      Edit again, tick "B-062 7" and Delete: the pane empties. Then the
      same letter under two ids: open "B-062 33" from the Inbox, and with
      it in the pane search "B-062 33" in All Mailboxes, tap Edit, tick its
      hit and Delete: the pane empties, and after Cancel the Inbox has no
      "B-062 33". The other way about: search "B-062 34" in All Mailboxes,
      open its hit, Cancel the search, tap Edit, tick "B-062 34" in the
      Inbox and Delete: the pane empties. Before, it kept the letter in
      both, with Delete live.
      6. *A failure part-way.* In the Inbox, search "B-062" in this
      mailbox: "B-062 9" to "B-062 32". Tap Edit, Select All, Move, All
      Mail, and the moment the sheet has gone turn on Airplane Mode from
      Control Center, while the line says "Moving…". Every row went at the
      tap; those whose `UID MOVE` was answered stay off, the one it failed
      on and those after it come back in their places, not ticked, and the
      alert says "Can't connect to mail server." with OK; the log has no
      `UID MOVE` after the failed one. If all of them went before the
      switch, move them back to the Inbox from All Mail and try again
      sooner. Airplane Mode off, Refresh: the letters that came back are
      still in the Inbox, and the ones that went are archived, in All Mail
      and not the Inbox, each once. The same with Delete in place of Move:
      the ones that came back are in the Inbox and the others in Trash.
      7. *Nothing reaches the server.* Airplane Mode on, tick two of the
      letters left in the Inbox, Delete: both go, "Deleting…", then both
      come back with the alert, and neither is in Trash on the web.
      8. *A refusal after he has moved on.* Airplane Mode still on, tick
      the same two, Delete, and while the line still says "Deleting…" open
      Sent in the folder pane. When the refusal comes, the alert "Can't
      connect to mail server." is put up over the reading pane though the
      Inbox's list has gone, and OK takes it away. If it came before Sent
      was open, try again, tapping sooner. Airplane Mode off, open the
      Inbox: both letters are there.
      *Seen 2026-10-03, on carlo's mailbox: 1 to 8 as written but for the
      erase. In Trash the questions, Cancel and Delete were as written, but
      the log had the `\Deleted` STORE and no EXPUNGE, and each letter
      deleted there was back at Trash's next open and found by an All
      Mailboxes search: the test account has Auto-Expunge off. Changed
      since, not yet seen: a `UID EXPUNGE` of the letter after the STORE
      (B-062). Step 6 also showed the lost answer twice: the move cut off
      at 30 s had been carried out by Gmail all the same. Step 8 was made
      by taking the Wi-Fi interface down from a shell, since Airplane Mode
      refuses at once. Left to see, on a build with the change: step 1's
      Trash half, step 2's Trash half and step 4's Trash hit again, the log
      with `UID EXPUNGE` after each STORE, and the letter not in Trash at
      its next open nor in a search. "B-062 1", "B-062 2", "B-062 3" and
      "B-062 5", still in Trash and marked, will do, and show besides that
      a letter left marked goes when deleted again.*
      *Seen the same day on a build with the change: steps 1, 2 and 4's
      Trash halves on those four, and a letter never marked, each with its
      STORE and its own `UID EXPUNGE`, and none in Trash or a search
      after a Refresh (B-062).*
- [x] **B-063, his mailbox's size.** On
      the test account, with the connection log open between steps:
      1. *Folders.* Open Inbox, Sent Mail and All Mail, and Refresh each:
         each lists as before, with `UID SEARCH ALL` answered `* SEARCH
         {N uids}`. Write down every `SLOW <VERB> ms=<n> quiet=<n>` note,
         with the folder. `quiet` is the longest single silence in the
         answer, Gmail's own, and the number the 90-second bound has to
         stay well clear of; `ms` adds the answer's coming over the line.
         There should be none on the test account; a `DEADLINE read
         serverWork bound=90s` is a failure.
      2. *Go to Date before 2016*, in a folder and in All Mailboxes (All
         Mail): the dated SEARCH goes as `UID SEARCH RETURN (MIN) SENTSINCE
         "…" SINCE "…" BEFORE "…"`, the line after it is `* ESEARCH (TAG
         "a0nn") UID MIN <n>`, then `UID SEARCH ALL`, and the list lands as
         before, "Showing <day>" for the first day with mail. A day after
         the newest mail: the ESEARCH line has no MIN, and "No mail on or
         after" the day. If Gmail answers the RETURN with NO or BAD
         instead, or with an ESEARCH line that gives no MIN but gives
         something (`COUNT 37`), a plain `UID SEARCH SENTSINCE …` follows
         at once; if with a plain `* SEARCH {N uids}`, nothing follows.
         Either way the jump lands the same: write which into B-063, with
         the answer's words.
      3. *An All Mailboxes search* for a common word: found as before, and
         any SLOW note written down.
      4. *Send a test letter to the test account itself*, with two or three
         photos attached: it arrives once, photos and all.
      5. *Files.* Over SSH, in the app's container, `ls tmp/Attachments`
         after each of these. Open an attachment: one directory while the
         preview is up, and still one once it is closed. Open it again,
         and then another, closing each: never more than one, the last
         opened. With a printer to hand, Print a PDF from the preview's
         share button and tap Done as soon as the print panel has gone:
         the printout is whole, not blank. Attach photos to a
         letter: one directory each while the sheet is up; Send, and once
         the sheet has gone and the letter has arrived, none. Again with
         Save Draft and no connection: the letter is in Drafts "On this
         iPad only" with its photos, `tmp/Attachments` is empty, and the
         photos open from the reopened letter and go up with it when the
         connection is back.
      *Seen on the iPad 2026-10-03, on carlo's mailbox: 1 to 5 as written,
      with no SLOW note; Gmail answers RETURN (MIN) with `* ESEARCH (TAG
      …) UID MIN <n>`, and with no MIN where nothing matches, so neither
      fallback ran. The kept photo draft went up at the next going to the
      background, not when the connection came back, being large. Print
      not tried, for want of a printer (B-063).*
- [x] **B-064, a reply finished from Drafts answers its letter.** On the
      test account, A standing for its address. Reply to a letter from A
      to itself, type a word, Cancel, Save Draft. Open it from Drafts and
      Send. In the connection log, the ENVELOPE for the sent letter has
      the letter's Message-ID as its in-reply-to, where the build before
      had NIL, and its X-GM-THRID is the letter's; the Inbox shows it in
      the letter's conversation, not as one of its own.
      *Seen on the iPad 2026-10-03, as written. B-064.*
- [ ] **B-066, the view button's switch slides.** Switch the Layout
      button on in the connection log first.
      1. *Frame by frame.* A scratch build with the window's `layer.speed`
      at 0.1, so the slide takes 4 s and the settle 2 s; the deadline
      stretches with it. Each of the three switches at 1194 (three to
      two; two with the list in front to three; two with the folders in
      front to three), with a long newsletter scrolled down, with a short
      letter, and with the pane empty, a screenshot about every half
      second. The corner glyph and Flag to Compose are the same in every
      frame. A divider line is at every column's edge. No picture is
      stretched. Every row is at the same height in every frame. The
      letter's picture is not blank. The first frame is the screen before
      the tap, but for the glyph no longer dimmed. A letter's header and
      left margin are where they end up in the last frame of the slide.
      With the pane empty, "No message selected" is in the middle of the
      pane in every frame, never twice, and does not move at the settle.
      The list's bar, frame by frame: the calendar goes under the corner
      glyph near the end of the slide from three to two and fades in right
      of "< Mailboxes" at the settle; from two to three it moves about
      150 pt left at the settle; the title and Edit likewise only at the
      settle. *Seen 2026-10-03 at `layer.speed` 0.05 with the pane empty,
      the three switches as written (B-066); with a letter, not yet.*
      2. *At speed.* A 60 fps recording from Control Centre, stepped
      through frame by frame: about 0.6 s in all, no flash at the tap, no
      shimmer in the corner at the settle, and the last frame the same as
      a screenshot taken a second later (a heavy newsletter WebKit is
      still drawing apart).
      3. *Coasting and bouncing.* Flick the list and, while it still
      coasts, tap the button: the rows stop where they were and do not
      jump at the settle. Then pull the list down past its top, let go, and
      tap the button while it springs back: the switch is instant, the
      rows finish springing back to the top, and the log has
      `pane motion: bouncing; switched at once`. The same flicked past
      the bottom of the list, with the Mailboxes pulled down, and with a
      long letter flicked past its end. A tap a second after any of them
      slides as usual.
      4. *Fast taps.* A quick double tap makes one switch; a row tapped
      while it moves opens nothing; the first tap after it works.
      5. *Interrupted.* Turn the iPad over, swipe Home, pull down Control
      Centre, each in the middle of a switch: back in the app the screen
      is final, with no picture left on it, and taps work. Then thirty
      switches a second apart, both ways in turn.
      6. *Search and Edit.* A search with the keyboard up, letters typed
      while it moves: the words, scope, results and keyboard stay, and
      the letters are in the field. Edit mode keeps its two ticks.
      7. *Reduce Motion*, then *Prefer Cross-Fade Transitions* in
      Settings, Accessibility, Motion: a 0.3 s fade each time, nothing
      travelling.
      8. *VoiceOver* reads "Hide Mailboxes" and "Show Mailboxes", and
      lands on the button after a switch.
      9. *The log*: nothing on the wire, the `layout: …` lines, no new
      finding, and no `pane motion:` line, a fallback or the deadline,
      but the bouncing ones step 3 asked for.
      10. "< Mailboxes" and a folder tapped in two panes are still
      instant.
      11. On a 1366 or 1376 pt iPad, if one can be had: 1 and 2 again,
      with the 2 to 5 pt gaps beside the list.
      12. *A conversation* of three letters or more, each switch at speed
      and frame by frame: the names and the open letter land where they
      end up; the dates at the rows' right ends ride with them and are put
      at the right end at the settle (B-066, Not covered). Whether that
      catches the eye, and a newsletter's centred column the same way.
- [ ] **The share sheet's checks** (B-036, with the shrinking of
      2026-10-04 and Apple Mail's way of 2026-10-05). Install the IPA from
      `tools/build-share-ipa.sh` through TrollStore's helper
      (`trollstorehelper install installd force <ipa>`, the IPA path
      last), never by the deploy that copies files into the bundle:
      copied, the share extension does not start at all. Then end any
      BlackmailShare still running (`killall BlackmailShare` on the
      iPad): iOS keeps an extension's process from one share to the
      next, across a reinstall too, and one left from the install before
      says "Open Blackmail once, then share this again." (2026-10-05).
      Open the app once. **2026-10-05, on the test iPad:** 1 (IMG_0776
      and IMG_0774), 2 (all five within the room), 3 (the JPEG and the
      panorama; no 48-megapixel HEIC at hand), 4 in part (the panorama,
      too large for the letter, shrunk at a quarter; none past the room
      Send has), 6 (the PNG only) and 8 passed, and a Wikipedia page
      from Safari went as before; the rest not tried (B-036, "Seen on
      the iPad, 2026-10-05"). Checks 1 to 10 are the photos'; 11
      onward are the rest of B-036 not yet tried. Only when all pass, take `BLACKMAIL_SHARE_EXT`
      out of `package.sh`; until then it stays opt-in, as it is.
      Every photo check reads the log as well as the letter. Send each
      letter to the account itself; then read the newest
      `blackmail-send-*.txt` in the share extension's own tmp from its
      last `SHARE-BEGIN` on, and nothing above it: iOS may keep the
      extension running from one share to the next, and the log is not
      cleared between them, so the lines of a share before can be there
      too. After it, one `SHARE-PICTURE` line for each picture, in the
      order shared, and at Send three `SHARE-SEND` lines. Copy the
      `offered=` of each down: what Photos offers, and in what order, has
      never been seen. A name in a line is as it is only when a device
      made it, IMG_ and digits or image and digits; any other shows as
      `{N chars}.ext`, and is read from the letter that arrived. Read a
      photo that arrived on the host, not in Gmail's Show original, where
      it is base64: open the attachment in the letter, save it from its
      share button in the app with Save to Files, which keeps its bytes as
      they came (Save Image puts it through Photos), and bring it over.
      With Python's Pillow, `from PIL import Image, ExifTags`,
      `im = Image.open(f)`, `raw = Image.Exif()`,
      `raw.load(im.info.get('exif', b''))`, then:
      - the orientation tag: `raw.get(0x0112)`, the EXIF alone. Not
        `im.getexif()`, which takes it from the XMP when the EXIF has none.
      - GPS: `raw.get_ifd(0x8825)`; the date and its zone: 36867
        (DateTimeOriginal) and 36881 (OffsetTimeOriginal) in
        `raw.get_ifd(0x8769)`; a maker's note: 37500 in that IFD.
      - the XMP: `im.info.get('xmp')`, searched for GPS, City, State,
        Country and Location.
      - every segment: `[(m, d[:16]) for m, d in im.applist]`. No APP13
        and no COM; list any APPn but APP0 JFIF, APP1 Exif or XMP, APP2
        ICC_PROFILE or MPF, and APP14 Adobe.
      - other pictures in it: `im.format`, `getattr(im, 'n_frames', 1)`,
        and any APP2 beginning `b'MPF\0'`; list each one's EXIF and XMP.
      - the thumbnail's IFD: `raw.get_ifd(ExifTags.IFD.IFD1)`.
      - the colour profile: `im.info.get('icc_profile')`.
      Or `exiftool -a -G1 -ee -u`, where it is installed. "No GPS
      anywhere" below is none in any of these: the EXIF, the XMP, an
      APP13, the thumbnail's IFD, another picture.
      1. *One camera photo from Photos, as its own bytes:* the test
      iPad's IMG_0776, then one taken with its camera. The sheet lists it
      under its library name, IMG_ and four digits, and the letter brings
      it so. Its line: `read=public.jpeg`, `name=file "IMG_NNNN.JPG"` (or
      `.jpg`, Photos' JPEG of a HEIC), `way=own bytes, metadata replaced`,
      and `bytes=` the size the attachment arrives at. If IMG_0776's says
      `(not as its own bytes: more than Send could build, room for R MB)`
      instead, its file is more than the memory left lets Send build: note
      R and its `bytes=`, see it as in 4, and make this check with the
      camera photo. On the host: the size it was taken at, the original's
      in DCIM (8064 by 6048 for IMG_0776, 4032 by 3024 for one from the
      camera), never a half of it; the same pixels as the original where
      that is a JPEG (`im.tobytes()` equal for both); no GPS anywhere; no
      maker's note; the date and its zone; the orientation tag in the
      EXIF the original's (8 for IMG_0776), one in the XMP alone failing,
      and the photo upright in Gmail on the web, which turns a photo by
      its EXIF alone; the colour profile byte for byte the original's.
      Any EXIF beyond those few is ImageIO's writing; list it.
      2. *Five full-size photos at once.* The sheet stays, lists all five
      by their names, has no line saying a photo could not be attached,
      and all five arrive. Five `SHARE-PICTURE` lines. Those that fit the
      room Send has go as in 1; the first that does not says `(not as its
      own bytes: more than Send could build, room for R MB)` and goes as
      in 4. Note R, line by line, and how many went as their own bytes.
      3. *The 48-megapixel JPEG alone* (IMG_0776: 8064 by 6048, EXIF
      orientation 8, a GPS tag), which made the sheet vanish on
      2026-10-04: the sheet stays. Its line says own bytes and it arrives
      at 8064 by 6048, orientation 8, no GPS anywhere; or, where its
      `bytes=` are more than the room Send has, it says so, as in 1, and
      it arrives as in 4. Then the 64-megapixel panorama alone, and a
      48-megapixel HEIC, an iPhone's HEIF Max, where one can be had: its
      line says what Photos offered for it and which way it went.
      4. *A photo too large for the room, shrunk.* Share the camera photos
      and the 48-megapixel JPEG last, five at once. Those that fit go as
      their own bytes. The first that does not says why, `(not as its own
      bytes: more than Send could build, room for R MB)`, then `way=JPEG
      at factor F, N MB available`, and arrives as a .jpg, IMG_NNNN.jpg,
      at the size F gives (for the 48-megapixel JPEG a quarter, 1512 by
      2016, upright, stored 8064 by 6048 with orientation 8, with less
      than 264 MB left), upright in its pixels, no orientation tag, no GPS
      anywhere, the date. Then a video of 15 to 24 MB and the
      48-megapixel JPEG after it, if Photos offers Blackmail for the two
      together: the JPEG's line says `more than the letter's room, N MB
      left`. The sheet says nothing of one left out unless one is.
      5. *A letter near the limit, sent.* Share a video of 20 to 24 MB
      alone, which is weighed against the 25 MB and not against the memory
      at Send, and Send it. The sheet must close at the 250, and the
      letter arrive. Copy down its three `SHARE-SEND` lines: the memory
      left with the files read, once the letter is built, and once it has
      gone, and `M MB at the least`, how near the building came to the
      limit. Then the same three lines for the letter of 2. An extension
      killed at Send leaves no log: the sheet goes at "Sending…" and
      nothing arrives; note that, and the size shared. A pass on the test
      iPad, allowed 180 MB, says nothing of his, perhaps 120 MB: make it
      again there when his can be had.
      6. *A screenshot, and a GIF.* The screenshot's line: `name=file
      "IMG_NNNN.PNG"`, `way=copied whole`; it arrives as the .PNG it was,
      its name's case kept. A moving GIF arrives as the .gif it was, still
      moving, whatever its size up to the room Send has; the old 5 MB
      bound is gone. If either's `read=` is `public.jpeg`, note it: Photos
      then offers a JPEG ahead of it.
      7. *A picture with no name.* Take a screenshot, tap its thumbnail,
      and share from that screen; then two the same way at once, if it
      allows. Its line says `name=none "image0.png"` (or `.jpeg`), the
      next `image1`. If it says `name=file "{N chars}.png"`, iOS made a
      name up: read it from the letter that arrived and note it; it
      decides whether such names count as none.
      8. *The memory guard's line.* In every line with `way=JPEG`, `N MB
      available` is a number, not "memory unknown": the extension is told
      what it has left. Note N on the test iPad, and on his when there is
      one. A 12-megapixel HEIC made a JPEG is read whole only with 118 MB
      or more. A line left out for the memory reads `left out, N MB needed
      at the least, M MB available`, N always more than M.
      9. *A JPEG with a GPS tag and neither a date nor an orientation*,
      made on the host with Pillow, a GPS IFD of made-up figures and
      nothing else, and saved to Photos from Safari. Its copy is given an
      empty metadata. Its line says own bytes and it arrives with no GPS
      anywhere; or `(not as its own bytes: the file written still says
      more than was kept)`, and it arrives as a JPEG made here, no GPS
      anywhere. Either passes; note which, since it is how ImageIO takes
      an empty metadata. One that arrives with its GPS fails.
      10. *A PNG carrying a GPS tag* (an eXIf chunk, made on the host the
      same way and saved to Photos the same way). Where Photos keeps it,
      its line says `(not as its own bytes: it says where it was)` and
      `way=JPEG at factor F`, and it arrives as IMG_NNNN.jpg, no GPS
      anywhere. Where its line says `copied whole`, Photos took the
      location off on saving: read the PNG that arrived for GPS all the
      same, and note that the check could not be made.
      11. *A link from the YouTube app*: in the row, the video's title as
      the subject, the link tappable in the letter that arrives.
      12. *After these, the app's own password still works* after the
      Keychain groups change: the app signs in and sends.
      13. *Cancel with words in it.* Type a word above the signature and
      tap Cancel: it asks, Delete Draft ends the share, and Cancel in the
      question goes back to the letter with the word still there.
      14. *A failed send.* With Wi-Fi off, Send: the reason is shown, the
      letter is left as it was, and Send works once Wi-Fi is back.
      15. *A `mailto:` link* tapped in a letter opens the app's composer
      with its address in To and his signature under the body. Whether
      one tapped in another app comes here is only noted.
      16. *A video over 25 MB*, shared from Photos: the sheet comes up
      without it, and the letter goes without it.
      17. *A signature changed in Settings* reaches the next share: the
      sheet's letter has the new one under the body.
      *Seen 2026-10-04, before the change of 2026-10-05, on a build
      installed through the helper: one photo (the 48-megapixel JPEG, at
      3024 by 4032, upright, no GPS, the date kept); five at once (five
      camera photos, each with its location, each 4032 by 3024, no GPS, the
      date and its zone and the Display P3 profile kept); a 64-megapixel
      panorama (at 4000 by 1000), no 24-megapixel photo or HEIC at hand;
      11, but with no subject: the YouTube app hands over the link alone;
      12. Every photo check is to be made again on the new build; 13 to 17
      not yet tried (B-036).*
- [x] **B-068, a plain letter is his words.** The test iPad's signature
      has a logo, so a letter there goes plain only with the signature
      taken out of it. A new letter to the test account itself, the
      signature deleted from the body, two lines typed with an `=` in
      them, Send: the row's preview and the pane begin with the first
      line, with no Content-Type above it, and so does Show original in
      Gmail on the web, under the header. Then the same letter, Cancel,
      Save Draft; open it from Drafts, add a word, Cancel, Save Draft;
      open it again: his lines and the word, nothing above them. Delete
      any test draft still beginning with the two lines.
      *Seen 2026-10-05, all as written, the draft's copy in Gmail one
      plain part too (B-068).*
- [ ] **B-071, a file's preview and the text size.** Seen on the
      simulator only. On the iPad, with a letter open that has two files:
      1. *The highlights.* Tap a file, then Done: the letter's row and the
      folder are still highlighted. The same in two panes, and
      "< Mailboxes" after it shows the folder highlighted.
      2. *The text size.* Settings, Accessibility, Display & Text Size,
      Larger Text, at the largest size; then two steps above the default
      with Larger Accessibility Sizes off. Back in the app each time,
      nothing has moved: the reading pane's buttons, the calendar, the
      folders' icons and names, a file's rows in the letter's header at
      44 pt, and in Edit mode the circles at their size and the rows'
      words where they were. At the largest size the circles sit a
      little lower (B-071, Not covered). Then the text size back as it
      was.
      3. *Settings.* With VoiceOver on, each field and the switch is read
      by its caption, and "Organize by Thread" is one stop, the switch,
      not the words and then the switch. With it off, tap the name, the
      signature and the app password: no "Passwords" over any of them.
      4. *The search field*, with VoiceOver on: "Search", a search field.

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
- [ ] **Pictures from the web in letters** — they load, as they always
      have, and a tracking pixel tells its sender the letter was opened; the
      spec asks for them blocked by default if feasible (B-055)
- [x] **A long press on a link** — WebKit's own menu, whose preview loads
      the page without "Open this link?"; every address in a plain letter
      is a link now. Leave it, or `allowsLinkPreview` off (B-055)
      *Decided 2026-10-01: left as it is, as Mail has it.*
- [x] **The Cc line arriving with the letter** — a conversation's stack
      moves down a line under him, against B-042's header of its final
      height from the tap. Let it stand and write it into B-042, or carry
      the Cc on the list's rows from the ENVELOPE, which holds it (B-055)
      *Decided 2026-10-01 and built, not yet seen on the iPad: the rows
      carry it, and the header has its line from the tap.*
- [ ] **A conversation's count in Sent Mail** — the row's top line holds
      some 168 points in three panes and 213 in two, and is cut at its
      end, so naming To, Cc and Bcc pushes a conversation's "(2)" past it:
      "Jane Example, Sam Exam…". Accept it, as the Inbox already does with
      a long list of who wrote (built); name To alone, which shortens
      the line; or put the count
      first, or fit the names to leave it room, either of which changes
      the frozen row (B-060, which puts four more questions about these
      rows)
- [ ] **Reply's addressing** (B-061) — built as Mail is believed to do it,
      none of it checked against Mail on an iPad. Reply All to a letter
      with a Reply-To goes to the Reply-To in place of the From, or to
      both; the composer's To shows "Jane Example <jane@example.com>", or
      the address alone as before; Reply All keeps the letter's To in To
      and its Cc in Cc, or puts everyone in Cc as before; a Cc left alone
      moves up to To, or the reply goes with no To; his own letter's
      Reply-To is not followed, or it is.
- [ ] **The view button's motion** (B-066) — built as pictures of the
      columns sliding 0.4 s and settling 0.2 s, the list sliding over
      the folders from three to two and off them from two to three. Keep
      it; another timing; or later Mail's way, where the folders slide off
      to the left. From two panes with the folders in front, their column
      draws in and the list is there in the middle, which Mail never did;
      keep it, or a plain 0.3 s fade for that switch alone.
- [ ] **"< Mailboxes" and a folder tap in two panes** (B-066) — instant,
      as they have always been, and as built. Or a slide, as Mail's
      navigation pushes and pops, about 0.35 s.
- [ ] **His second address** (B-061) — Gmail sends as it and delivers it
      to him, and the app cannot tell it is his, so a Reply All to a
      letter that names it sends it a copy, which comes back to his Inbox.
      Leave it; or a line in Settings where his other addresses are
      written once, as Mail's account has them under its Email; or the
      From addresses of Sent Mail taken as his at sign-in, which would
      take a stranger for him if a letter of theirs were ever moved into
      Sent Mail.
- [ ] **Reply to his own letter sent by Bcc alone** (B-061) — its copy
      in Sent Mail keeps its Bcc header, and Reply answers it to himself,
      as built. Or to its Bcc recipients, in Bcc,
      or in To. Gmail keeps the Bcc on its copy of a letter sent from
      Blackmail too (seen 2026-10-03, B-060), so this is any letter he
      sent to Bcc alone.

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
