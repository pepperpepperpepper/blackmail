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
      the six-task test with him. Look at Settings > Apps > Mail > Mail
      Accounts on his iPad: whether his Gmail account lists his second
      address under Email, and whether that address is an account of its
      own. Then add his second address in Blackmail's Settings with "Add
      Another Email…", and Save (B-076).

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
      back".* *Changed 2026-10-06 by the owner's ruling, "copy apple
      mail": Reply All has the sender alone in To and everyone else in
      Cc, his addresses are matched as written in any letter case, and his
      second address is his once it is listed in Settings. See B-076.*
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
      the 25 MB; its own bytes read back before they go, and made a JPEG
      if they still say where. The checks left are the numbered list at
      the end of "Blocked on the iPad coming back".* *Changed again
      2026-10-05, not yet seen on the iPad: Send makes the letter from
      the staged files as it goes, never whole, so the memory at Send no
      longer shrinks a photo; videos are asked for, up to five, and one
      left out is said (B-070).*
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
- [ ] Attach documents from Files, and video. *The app's picker is
      unchanged by B-070: photos only, made a JPEG at 0.85. The share
      sheet takes videos since B-070; Send streams them from the disk.*
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
      `PaneArrangementTests`; see B-048 for what he could notice. Seen on
      the iPad 2026-09-29 (B-048); what is left is below.*
- [x] **B-066. The view button's switch moves.** Asked for by the owner
      on 2026-10-03: "We need better transition animation between the
      three-panel view and the two-panel view." Calm, nothing wobbling,
      nothing moving up or down, nothing reflowing while it moves.
      *Done: pictures of the panes slide sideways for 0.4 s and settle for
      0.2 s over the panes already laid out beneath them, and with Reduce
      Motion the screen fades for 0.3 s (`PaneMove`, `PaneMotion`).
      "< Mailboxes" and a folder tap stay instant, and so does a switch
      tapped while a list or the letter bounces past an end. Checked in
      `PaneMoveTests` and `PaneArrangementTests`; see B-066. Seen on the
      iPad frame by frame 2026-10-03, then replaced by B-077's motion, the
      next item. What to look at on the iPad is below.*
- [x] **B-077. The panes move as Mail's.** The owner's ruling on B-066's
      questions, 2026-10-06: "copy apple mail for these".
      *Done, seen on the iPad 2026-10-07, VoiceOver's place too under
      B-079 (2026-10-20): one half-second motion on UIKit's spring for the
      view button, the list over the folders at half speed and the folders
      darkening, no settle; "< Mailboxes" and a folder tap as a pop and a
      push; Reduce Motion and Prefer Cross-Fade Transitions as Mail has
      them (`PaneMove`, `PaneMotion`). Seen and measured in the iPadOS 18
      simulator.*
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

- [x] See B-037 rendered at all: now B-048, below. *Seen on the iPad
      2026-09-29: three panes and two, the view button, "< Mailboxes" and
      the choice kept across a relaunch (B-048).*
- [ ] Confirm the signature's white sheet **in the reading pane**, in a
      conversation's stack (`ConversationDocument`'s `.bm-signature` rule).
      *Seen in passing on the iPad 2026-10-07 (B-074): in a stack, a
      reply's signature and what it quotes on a white sheet with dark
      words.* The outgoing half is verified by tests and Chromium renders.
      Every HTML letter the app sends with a signature carries the marker
      (`AppleMailHTML.signatureOpen`), so no send is needed. A letter shown
      alone is drawn by `PanePage.letter`, which has no such rule, so its
      signature shows white on the dark pane (seen in passing in B-074,
      not yet looked into); that is what is left of this item.
- [ ] Register and test the share extension. *Registered and seen
      2026-09-30 through TrollStore's installd path: a Safari link shares,
      sends and arrives; see B-036. Still to try is below.* It is installed
      through TrollStore's helper. (B-036 blocker 2) The IPA
      is `tools/build-share-ipa.sh` → `ios/Blackmail-share.ipa`, installed
      through installd, not the copy-based deploy. Open the app once, then
      share from Safari and from YouTube: that Blackmail is in the row, that
      Safari's page title is the subject (the YouTube app hands over the
      link alone, so a share from it has no subject; B-036), that his
      second address is offered in To once a letter of it is typed
      (B-073), that it sends and arrives with the link tappable, that five
      full-size photos shared at once arrive, and that the app's own
      password still works after the extension build's keychain groups
      (copy-deploy that build to the dev iPad first). Then take
      `BLACKMAIL_SHARE_EXT` out of `package.sh`. *Safari seen 2026-09-30;
      what is left is "The share sheet's checks", further down this
      section.*
      *Seen on the test iPad 2026-10-21: from the YouTube app too,
      Blackmail in the row, the link alone with no subject, and the link a
      link in the letter that arrived (share check 11, B-036). What is left
      is still "The share sheet's checks".*
- [x] Anything else touching the send path. Batch 6 of the lag fixes
      (B-044) went in before the iPad was back; its checks below come
      first. *Done 2026-09-29: B-044's checks were made on the iPad; what
      is left of them is under B-044 below.*
- [x] Send one letter to confirm the send path still works now that
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
      465), and `TLSConnection`'s `NWConnection` glue only runs on the
      device. *Seen on the iPad 2026-09-29, five pictures sent over it
      (B-044), and 2026-10-05, a 19 MB video with one `WIRE-OUT`,
      `LETTER-LATCH ok`, one `WIRE-ACK` and the 250, and `DEADLINE write
      bound=30s` when the line was cut (B-070). The ten-minute wait for the
      reply was not seen, Gmail answering in seconds; the host tests stand
      for it (`SMTPReplyWaitTests`, `LinkTransportTests`).*
      *Seen on the test iPad 2026-10-20 again: five photos sent from the
      composer, one `WIRE-OUT`, `LETTER-LATCH ok`, one `WIRE-ACK
      err=none`, then the 250, twice (B-044, B-070).*
- [x] Time an All Mailboxes search on the device, and a letter tapped
      while it runs, from the connection log. The one-hold search and the
      interactive line are checked on the scripted server, which knows
      nothing of Gmail's own SEARCH time on Trash and Spam, and that time
      decides what the binned half of a search still costs.
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa): a word with 291 hits in Trash took 0.81 s from
      Trash's SELECT to the page's answer. Trash's SELECT 66 ms, its SEARCH
      132 ms and the FETCH of its 200 binned hits 201 ms; Spam's SELECT and
      SEARCH 56 and 51 ms; All Mail's 70 and 56 ms; the page 78 ms; 0.1 s
      between them. A letter tapped during a search went once the mailbox
      the search was in was done, as the hold gives way between mailboxes
      and never inside one: answered 0.51 s after the tap, 2.56 s with
      Gmail slow that minute, and 0.29 s when the search was over first.
      The page's FETCH is the list's own, after the hold, and the tapped
      letter can go before it.*
- [x] Watch a cold launch in the connection log: LOGIN, one LIST, the
      Inbox's SELECT, SEARCH and FETCH, and only then the sweep of the
      counts, a LIST of its own and a STATUS per folder. Then mark a
      letter unread in Edit mode (opening it marks it read) and
      move it out of the Inbox from the reading pane, and check both
      folders' counts come right, which they must within one
      sweep of the MOVE (B-040). The order and the counts are checked on the
      scripted server; since the kept copy (D-016, B-053) the folders are
      drawn with their last counts in the first frame, and names alone show
      only when nothing is kept.
      The host suite checks the rules, not the UIKit wiring that applies
      them, which it cannot compile, so on glass also check: the counts do
      appear after launch (the folder pane holds them until
      `onFirstLoadFinished` lets them go, and nothing else would), and after
      a launch with Wi-Fi off the kept counts show and no STATUS goes;
      tapping the newest unread letter the moment the Inbox appears leaves
      the Inbox's count right once the counts have settled
      (`adjustUnreadCounts` asking for one more); and the Move sheet opens
      with its folders at once.
      *Seen on the test iPad 2026-10-20, a build of the `shot-share`
      worktree: a letter marked unread in Edit mode and moved from the
      reading pane to All Mail, its row gone as the folder was chosen, the
      `UID MOVE` alone, then one LIST and a STATUS per folder, the Inbox's
      count down by one and All Mail's right; moved back and deleted from
      the pane, the same, and Trash's count up by one with them (B-040).
      The Move sheet had its folders in its first frame, 0.2 s after the
      tap, with nothing sent for it. Not seen with these: the launch's own
      checks.*
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa): the launch's checks passed (B-040). A cold launch
      sent LOGIN, one LIST, the Inbox's SELECT, SEARCH and page FETCH, and
      only then the sweep, whose own LIST comes before its eight STATUS:
      the check had the STATUS alone, and now names that LIST. 45 s on,
      every folder had Gmail's count. Launched with Airplane Mode on, the
      kept counts were in the first frame with one "Can't connect", and
      nothing went while offline; back on, the watch's first check, the
      kept page fetched afresh and one sweep. The newest unread letter
      tapped as the Inbox appears was seen on 2026-10-01, under B-059.*
- [ ] **B-041, the reading pane at the tap.** Tap from letter to letter
      in the Inbox: the header must change at the tap to the new sender,
      subject and date with "Loading…" under it, and the previous letter
      must never be on screen beside the new selection, not even for a
      frame. Delete a letter, then tap the next: the binned one must not
      appear at all. Tap four letters about a third of a second apart,
      one of them large: the connection log should show two
      `BODY.PEEK[]` fetches, the first and the last (for letters of 5 MB or
      less, `largeLetterBytes`; a larger one is fetched in parts, its
      BODYSTRUCTURE first), and the pane should end on the last. Tap Reply
      while a large letter is loading: the Reply, Reply All and Forward
      sheet does not open until it is there. The web view's first paint of
      "Loading…" and of the letter after it is the part the host cannot
      see: look for a white flash or a blank frame between them. The
      header's height must not change when a letter with files lands
      (B-042).
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa), the taps recorded: every part but the first frame
      passed (B-041). The new header came in the frame the selection
      moved, but for one frame, some 17 ms, it stood over the previous
      letter's body, or for two over an empty pane for the first letter
      after a launch, before "Loading…" came: in 5 taps of 7, and at every
      first letter after a launch. The header is UIKit, and the web view
      paints "Loading…" a frame or two after it; seen and not changed. No
      white or blank frame came between "Loading…" and the letter. The
      binned letter never showed again. The taps, some half a second
      apart, were three, not four: the first and the last fetched, none
      between, the pane on the last. Reply did nothing while "Loading…"
      showed, and the header kept its height as a letter with a file
      landed. Left: that first frame, which needs a change to the app.*
- [ ] **B-041, Delete, Move and Flag from the pane.** In a folder scrolled
      down a few pages, with previews filled: Delete a read letter. The
      pane empties and the row goes at the tap, nothing else on the list
      moves or blanks, and the connection log shows `UID MOVE` and after it
      only the watch's check every 30 s: a NOOP, and after the first NOOP
      following the MOVE one `UID SEARCH UID n:*` with
      `NEWS folder=INBOX arrived=0 gone=N` (the MOVE's own EXPUNGE is news
      to the watch), then NOOPs alone; no summary FETCH, LIST, STATUS or
      page FETCH. Delete stays grey until it lands.
      Mark a letter unread in Edit mode (opening it marks it read) and
      Delete it from the pane: its counts drop when the MOVE lands, and the
      log shows one LIST and a STATUS per folder after the MOVE; Trash's
      count comes right with them. With an All Mailboxes search showing,
      open a hit that is also in the Inbox's first page, Delete it, then
      cancel the search: it must not be in the Inbox, and the search's
      text, results and scroll must have stayed until the cancel. With the
      Inbox's first page only loaded, search the Current Mailbox for a
      letter a few pages down, Delete it from the pane,
      cancel the search and scroll to the bottom: the list must go on to the
      oldest letter, not stop at the page the binned one was in. In All
      Mail, Move a letter to Inbox: the row stays. Flag an All Mailboxes hit
      that is also in the Inbox's first page and cancel the search: the
      Inbox row is flagged. Flag one letter with Wi-Fi off: the flag goes
      back with "Can't connect" at once, so quickly that it may never be
      drawn (B-091). OK, open another, which says it could not be
      downloaded, and Flag it: refused the same way. With Edit on and three
      rows ticked, open a letter inside the conversation still in the pane,
      and Flag from the pane: the three ticks stay, and no other row is
      ticked. Flag, and the row's flag appears at once; flag with Wi-Fi
      turned off, within a minute and a half of the last thing he did: the
      flag goes back and "Can't connect" is said (at once: nothing is
      written onto a connection the iPad says has no network, B-091; only a
      command already on the wire as the network went waits, for the stack
      to drop the connection or the 30 s read deadline, as on a socket left
      half open). In a conversation, open an unread letter that arrived
      while the stack was open and was then closed by its line (since B-074
      every unread letter opens with the stack): the dot goes at the tap,
      and one count when its STORE is answered (a fraction of a second
      later, never before, so a refused STORE cannot leave the count too
      low), and the list does not reload. The host suite checks the rules;
      the table view's reaction to them, row removal, highlight and empty
      state, is only visible here.
      *Seen on the test iPad 2026-10-20, Airplane Mode for Wi-Fi off: every
      part but two passed (B-041). Scrolled three screens down, the Delete's
      pane was empty in the first frame and nothing on the list moved; with
      the row in view, it was gone in the first frame after the tap, the
      rows under it one place up with their previews, and so for a Move.
      After each MOVE the watch's one SEARCH, as the check has it now. The
      Inbox held 67 letters, so the one FETCH below the first page took the
      rest and the list went on to the oldest: a page made up with one more
      FETCH needs over a hundred. The search hit's Delete left "No results"
      up until the Cancel, with nothing to scroll. The reopened letter's dot
      went at the tap and its count 0.4 s later, as its STORE was answered.
      The Flag with Wi-Fi off stayed 19 s on the build before, B-091, and
      was refused within 0.2 s on its fix; on the build before, the second
      letter's Flag, the connection then gone, was refused at once and never
      drawn, so the check no longer asks to see both flags. Still to do:
      Delete grey while its MOVE is out, and a Flag on a socket left half
      open, both made by taking the iPad's Wi-Fi interface down under the
      connection, which waits to be agreed.*
- [x] **B-041, coming back.** With the Inbox showing, scrolled down, a
      letter open and Edit on, leave the app for more than fifteen minutes
      (or shorten `Sitting.awayBeforeReturningToInbox` for the test, as
      B-003 was checked): the list must be at the top, out of Edit, with its
      old rows and previews on screen until the new page lands, never
      black, the letter still in the reading pane, and the counts' LIST
      and STATUS after the page's SEARCH and FETCH in the log. From another
      folder, the Inbox opens as before. Lock the iPad for two minutes
      after reading a letter, unlock, and before touching anything read the
      log: one NOOP, which finds the old connection gone, and a LOGIN on a
      new one at once after it: iPadOS shuts the sockets of an app it
      suspends, so this is so after any lock, not only a night away. After
      a night away the first letter opened then costs its FETCH alone,
      since the Inbox's refresh after more than fifteen minutes away has
      already selected the Inbox. After a night away, unlock and Delete the
      letter in the pane at once: the log should show the NOOP, a LOGIN and
      the MOVE, once, with a second NOOP before the MOVE only if the Delete
      came while the first was still out, and the row must not come back.
      Lock for thirty seconds straight after tapping a letter: nothing
      should be sent on the way out or back until the watch's first check,
      about 30 s after the return.
      *Seen on the test iPad 2026-10-20 and 2026-10-21, a lock of 45 minutes
      for the night away: every step passed (B-041). The iPad locked itself
      during the fifteen minutes away; at the return the page came in 0.6 s,
      before the app's first frame, so the rows kept could not be told from
      the new, and the list was never black. Every lock lost the connection,
      three minutes, 45 minutes and 30 seconds alike: the first command at
      the return had no answer and a new connection was made at once, some
      0.06 s later. The check had a new connection only after a night away,
      and now says what was seen. After the long lock the Delete came once
      the new connection had been made, so it went with no NOOP of its own,
      once; the check now says when a second one goes. After thirty seconds
      the watch's first check found the connection gone, and made a new
      one.*
- [x] **B-042, where the list is.** In the Inbox, scroll down three pages
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
      view stay where they were. Scroll past the first page and do the
      same: since B-062 the rows are taken off in place, and the list is not
      fetched again and stays where it was. With
      Wi-Fi off, search from far down: "Could not search. Check the
      connection." is on screen, not above it.
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), Airplane Mode for Wi-Fi off: every step passed (B-042).
      From three screens down the first hit was the first row under the
      search band by 3 s, the keyboard up, and two more letters started
      the hits at the top again. Cancel put the noted row back at the
      same height by 0.9 s, the two previews missing fetched at once.
      Refresh went to the top as the page landed, 1.1 s on. Two rows
      ticked a screen down went at the tap, "Deleting…" until both MOVEs
      were answered, and nothing else in view moved; past the first page
      the same with one row, the only letter there that would do, and the
      list neither fetched again nor sent to the top. Offline, "Could not
      search. Check the connection." under the search band.*
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
      *Go to the day from part-way down the list, not from a list at its
      top: from the top the page above comes as the day lands, before any
      scroll, and there is nothing left for the scroll to bring (B-094,
      recorded, not changed). So it should, by the sums (not seen),
      wherever the jump is made from, for a day with a page of older mail
      below it, which lands at row 10 or higher; in the test account's All
      Mail the day lands at row 20.*
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), All Mail at a day sixteen days back, 43 letters newer
      than it: every part but the Delete passed (B-042). Scrolled up
      slowly with a letter open, the page above was asked for 0.8 s into
      the swipe and put on by 1.1 s, the rows moving only with the finger
      and the highlight staying on the letter; a conversation in the
      window with newer replies went up alone to the newest's place. With
      Edit on, the same three stayed ticked. Organize by Thread off and on
      again kept the top row at the top both times. The Delete in the pane
      of a letter whose row was just above the top of the list moved every
      row in view up by one: fixed as B-093, not yet seen there fixed. Go
      to Date from a list at its top fetched the page above as the day
      landed, nothing touched, so the scroll up was made after jumps from
      part-way down: recorded as B-094, not changed. Seen in passing: a
      letter open before a jump stays in the pane, its row no longer
      highlighted until tapped again. Left: the Delete, on B-093's build.*
- [ ] **B-042, Go to Date and Move.** Tap Go: "Going to <day>…" must be on
      the status line while the sheet is still sliding away, then
      "Showing <day>". From the Inbox, go to a day in All Mailboxes: All
      Mail opens during the slide, saying "Going to <day>…". Double-tap Go
      quickly: one jump in the connection log. With Airplane Mode on, Go:
      "Can't connect to mail server." must appear, once the sheet has gone
      if the failure came during the slide (the log's timestamps say so
      only when a connection was up; a failed connect writes no line), and the
      status line goes back to what it said. Move a letter from the
      reading pane: "Moving…" until the MOVE is answered; with Wi-Fi off,
      the row comes back and the alert appears after the sheet has gone.
      Double-tap a folder in the Move sheet: one MOVE in the log. Edit,
      tick two, Move: "Moving…" until the server has answered for both; the
      list is not fetched again (B-062). Start to
      swipe the Go to Date sheet down and tap Go before letting go, with
      Wi-Fi off: the alert may be lost with the sheet, but alerts after it,
      a second later, must still appear (tap a letter: "Can't connect").
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), Airplane Mode for Wi-Fi off: every part but two passed
      (B-042). "Going to October 3…" at 0.42 s as the sheet's last edge
      slid off, "Showing October 3" at 0.53 s; from the Inbox with All
      Mailboxes, All Mail open behind the sheet at 0.21 s and "Going to
      October 4…". Go tapped twice 0.1 s apart: one dated
      `UID SEARCH RETURN (MIN)`. Go offline: the line back to what it
      said once the sheet had gone, at 0.61 s, and the alert from 0.82 s.
      A letter drawn, then moved offline: `NO-PATH UID MOVE nothing-sent`,
      the row back and one alert as the sheet went. All Mail tapped twice
      in the Move sheet: one MOVE. Edit, two ticked and Move, was seen
      under B-062's check on 2026-10-03. Left: "Moving…" for a Move from
      the pane, not possible on this iPad's network, the MOVE answered
      0.27 s after the tap while the sheet still covered the line; and
      the sheet swiped with Go tapped before letting go, offline, not
      tried.*
- [ ] **B-042, the header's files.** Open a letter with two PDFs: both file
      rows are in the header at the tap, grey, and turn blue when the
      letter lands; nothing under the header moves then. Open a
      conversation whose newest letter has files: the stack must not shift
      when its body lands. A letter whose only picture is a signature logo
      shows no file row before or after. Open a letter with a
      message/rfc822 part (the app's own Forward quotes inline, B-050; such
      a letter comes from another client): the rows before and after must be
      the same; if they are not, the BODYSTRUCTURE and the downloaded letter
      disagree about its parts, which the host cannot see with Gmail's own
      structures. Tap a large PDF in one letter, and at once another letter
      with a file: when the first download ends, the second letter's rows
      stay grey until it lands, and a download of its own keeps its
      spinner.
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): every part but the last passed (B-042). A letter's two
      PDFs were in the header at 0.27 s, grey, over "Loading…", and blue
      at 0.41 s, nothing else moving. A reply with a picture to a letter
      of four files: the newest's file row grey from the first frame,
      then blue, and the stack's lines unmoved as its body landed. A
      letter with the signature's logo alone: no file row. A
      message/rfc822 part, made by sharing an `.eml` from Files: one row,
      the same before and after. A large PDF tapped, then the two-PDF
      letter, and again with a large photo: its rows grey after the
      download had ended, until it landed. Left: a download of the
      second letter's own as the first ends, which cannot be made: the
      app's one connection fetches in turn, so the second letter lands,
      and its rows can be tapped, only once the first download is over.
      Seen in passing: each time the first letter's file then opened in
      Quick Look over the second letter.*
- [x] **B-042, Drafts.** Use drafts that have reached Gmail: a row "On
      this iPad only" opens at once, with no spinner. Tap a draft: its row
      stays highlighted with a spinner in the left gutter, the text beside
      it unmoved, until the composer opens. Tap it again while it spins: one
      FETCH in the connection log. Tap a second draft while the first spins:
      only the second opens. With Wi-Fi off: the spinner stops, the
      highlight goes, and "Can't connect to mail server." appears.
      *Seen on the test iPad 2026-10-20, Airplane Mode for Wi-Fi off:
      every step passed (B-042); a row "On this iPad only" opening at once
      was seen under B-087 the same day. The highlight and spinner held
      until the draft had come, 2.9 s for one of 4.9 MB, and the plain row
      showed for one frame before the sheet. Only the second opened when
      the first was large; a first of 18 KB came before the second tap.
      Offline the alert came 34 to 44 s after the tap, its FETCH written
      onto the connection open from before Airplane Mode, as in B-091, on
      the build before it.*
- [ ] **B-042, WebKit's content process.** Force it out while a letter is
      showing: on a device with a shell, `kill -9` of Blackmail's own
      `com.apple.WebKit.WebContent`, never `killall`, which ends every
      app's; otherwise leave for Safari and Photos,
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
      Open the largest letter in the
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
      a send, Send with the Cancel sheet open.* Write a
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
      once with all five. Turn Wi-Fi off and Send: the sheet closes
      with "Message is in the Outbox. It will be sent when the iPad is
      connected and Blackmail is open." (B-052). Send a photo letter and lock
      the iPad at once; unlock after a minute: either the letter went, once,
      and the sheet is gone, or it waits in the Outbox and goes once. A
      letter that went must not be reported as failed, and none may arrive
      twice. Then Save Draft on a photo letter and lock at once: the draft
      is in Drafts when he comes back.
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
      *Seen on the test iPad 2026-10-20: the first four still to see
      passed, Look Up chosen from the menu (B-044). The picker takes every
      touch until about 0.9 s after Add, and by then the five photos were
      in, so a Send with a photo still coming in could not be made on this
      iPad. Send with the Cancel sheet open did not go as written: four
      taps on Send with that sheet up, two after a fresh launch, each only
      closed the sheet, and a second tap sent the letter once; nothing was
      saved, deleted or lost. The code meant one tap and does not give
      it: the sheet, an action sheet in a popover, lets no tap through to
      Send's bar (B-044). Still to see: this step, sent with one tap.*
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
- [x] **B-046, the signature's logo in a reopened draft.** *First half
      seen 2026-09-29; the draft with a photo is still to try.* A new letter,
      Cancel, Save Draft; open Drafts and tap the draft: no attachment row.
      Send it: it arrives with no paperclip in the list and no file row in
      the header, and with the logo in the signature; the connection log's
      `WIRE-PAYLOAD raw=` for it should be about what the same letter sent
      fresh gives, not ten kilobytes more. Then a draft with a photo he
      attached: Save Draft, reopen it, the photo's row is there once; send
      it: it arrives with the photo once, and the logo in the signature.
      *Seen on the test iPad 2026-10-20, a draft with two photos: reopened,
      a row for each photo once and none for the logo; sent, each photo
      once, the logo once, inline, and no other file, its `raw=` the
      photos' base64 and some 18.8 KB, a plain letter's 18.2 KB (B-046).*
- [ ] **B-047, "Inbox".** *Sidebar and title seen 2026-09-29; the Move
      sheet and VoiceOver still to look at.* The sidebar's first row and the list's title read
      "Inbox" at launch and after tapping it. The Move sheet, opened on a
      letter in another folder (it leaves out the letter's own folder),
      says "Inbox" too. With VoiceOver on, the first row reads
      "Inbox, N unread", or "Inbox" with nothing unread.
      *Seen on the test iPad 2026-10-20: the Move sheet, opened on a letter
      in All Mail, said "Inbox" and left out All Mail (B-047); VoiceOver
      read the first row "Inbox, 12 unread" on 2026-10-07, in B-079's
      check. Left: "Inbox" alone with nothing unread, not tried, the test
      account's Inbox having thirteen unread; `MailboxNameTests` holds
      it.*
- [ ] **B-048, two panes or three.** *Partly seen 2026-09-29: both ways
      with a letter open and a search up, "< Mailboxes" and the open
      folder, the choice kept across a relaunch; see B-048. Still to see:
      Edit mode across a switch, the scrolled list with the log quiet, the
      open folder from "< Mailboxes" in the log, a long folder name ending
      in "…" in two panes, and the thumb resting on the list, which needs
      two touches at once. Another folder, VoiceOver and the layout lines
      were seen in B-077 and B-079.* Switch the Layout button on in the
      connection log first. Open a letter, scroll the list a few pages
      down, and tap the view button both ways: the letter stays drawn with
      no "Loading…" and nothing in the connection log but the watch's check
      every 30 s, the list keeps
      its rows and the selected one where they were on screen, and the
      folder keeps its highlight. Again with a search active and the
      keyboard up (text, scope, results and keyboard all stay), and with
      Edit mode on and two rows ticked (still in Edit, ticks and Done
      kept). Pane widths: 250 / 330 / 613 in three and 375 / 818.5 in two
      on the 11-inch; the button in the same spot in both. `< Mailboxes`
      shows the folders with the open one highlighted; the open folder
      tapped shows its list where he left it, with nothing in the log but
      the watch's check every 30 s; another folder loads as it does in three
      panes. With the folders in front, the view button puts the list back
      in the middle. Nothing truncates in the list's bar in two panes but a
      long folder name, which ends in "…"; "Sent Mail" should fit, and
      `< Mailboxes` is never shortened. Relaunch in two panes: it opens in
      two, on the Inbox's list. VoiceOver reads "Hide Mailboxes" and "Show
      Mailboxes", and lands on the button after a switch. A tap on the
      button with a thumb resting on the list does nothing. The connection
      log shows `layout: three panes`, `layout: two panes, …` and no
      finding after either.
- [ ] **B-050, Reply and Forward as the original looked.** *Partly seen
      2026-09-30: a newsletter forwarded, and a one-word reply to his own
      letter with a link; see B-050.* Read what
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), read in the raw letters as they arrived: every part but
      the look and the reply to his own shared link passed (B-050). A
      newsletter forwarded: "Begin forwarded message:", then From, Date,
      To and Subject with bold labels, in the text part too; its nine
      pictures and sixteen links as they were, its tables kept, its style
      blocks, head and comments dropped, and `WIRE-PAYLOAD raw=` 1.39
      times its markup. A reply to it saved as a draft and reopened: no
      rows; sent, the attribution, then the original's markup in a cite
      blockquote, In-Reply-To and References, and no `bm-quote` comment.
      A quote with a word changed and a line cut went as plain text with
      the word, without the line, its https address a link; a quote
      deleted, nothing of it. A forward of a letter with a picture in its
      body and a PDF, which had a Cc: the composer listed both with their
      weights, and it went with the picture inline under a Content-ID of
      its own, the PDF a file, his signature's logo once beside them, and
      Cc under To in both header blocks. A reply to it: the letter as it
      looked but for the picture, and no file. Left: how each looks in
      Mail and on Gmail's web page, which needs a person, the seven
      letters being in Trash until about 2026-11-20; the reply to his own
      shared link was not part of it.*
- [x] **B-051, letters kept on the iPad.** *Partly seen 2026-09-30: the
      offline Save Draft and Refresh, a reopened draft changed offline, and
      a letter kept across the app's end; see B-051.*
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
      come back and open in the composer; at a megabyte or more of files
      the letter goes up only as he leaves the app (`LocalDraft.goes(by:)`).
      Write a letter and swipe its sheet down: it asks Save Draft or Delete
      Draft and does not close (B-069). Send a letter, Save one
      with Wi-Fi on, and Delete one: nothing "On this iPad only" is left.
      Lock the iPad in the middle of a letter and unlock it: the letter is
      still in the sheet as it was. With Wi-Fi off, Save Draft on a letter
      with two photos; Wi-Fi on, open another folder: the connection log
      shows no APPEND; go to the Home Screen: it shows one, and Drafts has
      the letter once. In Drafts, Edit, tick a kept letter, Delete: it goes,
      and does not come back at the next Refresh. Search Drafts, open a
      draft from the hits, change it, Save Draft: the hit is the new copy,
      and opens.
      *Seen on the test iPad 2026-10-20, Airplane Mode for Wi-Fi off:
      every step not seen before passed (B-051). With a return to the app
      in place of Refresh, the letter went up at the watch's first check,
      35 s after the return. With the two photos, 3.6 MB as kept, the app
      was ended by a kill, not a swipe in the app switcher: every word and
      both photos came back, with no APPEND in nearly two minutes in the
      app and one as it was left. Nothing read "On this iPad only" after
      the day's sends, saves and Deletes.*
- [ ] **B-049, new mail on its own.** *Partly seen 2026-09-30: a letter
      from Blackmail at the top by itself, the Inbox's count up; see
      B-049.* With the Inbox open and the list at
      the top, send a letter to himself from Blackmail: within about half a
      minute it is at the top of the list with no tap, and the Inbox's count
      goes up. The connection log should show a `NOOP` answered `* n
      EXISTS`, then `UID SEARCH UID …:*`, one `UID FETCH` of that letter,
      and `NEWS folder=INBOX arrived=1 gone=0`, or `gone=` as many letters
      as were deleted from the list before: it still holds them, out of
      sight, for paging, and the watch counts them gone again whenever
      something else changes. With nothing arriving, one `NOOP` each half
      minute and nothing more. Scroll
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
      *Seen on the test iPad 2026-10-20, the lock: three minutes, and
      nothing in the log from the lock to the wake but the watch's check
      already on the wire as it locked, answered (B-049). The watch's first
      check came 32 s after the return.*
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa), Airplane Mode for Wi-Fi off: every part but three
      passed (B-049). At the top each letter went on by itself at the next
      check, the checks 30 to 33 s apart. Scrolled down, under two ticks
      and under a resting finger nothing on the list moved; the letter went
      on as the list came to rest at the top, at Done, and 3.6 s after the
      lift. With Sent Mail in front, the Inbox's count rose at the next
      check, one STATUS a check and no Inbox FETCH, and Sent's line aged to
      "Updated 6 minutes ago". A letter opened, flagged and deleted 0.7 s
      after a check each went as before. With Airplane Mode on, the age
      over "No Connection" from 37 s; back on, the first check, on a new
      connection, listed the letter, and the line read "Updated Just Now".
      The NEWS lines said `gone=3` and `gone=1`, letters deleted before: by
      design, as the check now says. After a search's Cancel the letter
      came 32.2 s later, and 31.7 s at a second try: Cancel starts no
      check, so what came during the search waits for the next one; seen
      and not changed. Left: that half minute, which needs a change to the
      app; the archive on the phone, which needs a person; and
      "Updated at …" after an hour, which needs Auto-Lock at Never and
      waits on a yes.*
- [x] **B-052, the Outbox.** *Partly seen 2026-09-30: the notice, the
      Outbox row and its line, going once, the lock at once, and Gmail's 553
      for `nobody`; see B-052. A waiting letter looked for in Sent Mail
      before it went again was seen under B-070, and one going by itself
      once the connection was back under B-083.* Turn Wi-Fi
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
      gave it, which is what the look depends on (seen 2026-09-30, B-052),
      and note how many seconds after Send it is there: the app gives Gmail
      ten minutes after a cut before it takes "not in Sent Mail" as final
      (`Outbox.settling`), a figure from RFC 5321, not from Gmail.
      Send a letter to an address with no domain, `nobody@`, which Gmail
      refuses at RCPT (seen 2026-09-30): the sheet stays with "Message was
      not sent." and the letter, as before. Reopen a draft from Drafts,
      Wi-Fi off, Send: it leaves Drafts' list, waits in the Outbox, and once
      sent its old copy is gone from Drafts on the web. Tap a letter in the
      Outbox, Cancel untouched: it is back in the Outbox. In two panes, the
      Outbox is in the Mailboxes' column and opens like any folder.
      *Seen on the test iPad 2026-10-20, Airplane Mode for Wi-Fi off:
      every step not seen before passed (B-052). The folder rows above
      the Outbox's were the same to the pixel. Back online with nothing
      tapped, it went at the watch's first good check, 10 s after
      Airplane Mode went off. Sent Mail had it under the app's Message-ID
      within a second of its 250, found by `UID SEARCH HEADER Message-ID`
      polled each second, three times of three. Deleted from the Outbox
      offline, a letter never went.*
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
      ticked in Edit, made by a launch with no connection, then Airplane
      Mode off, which lands the fresh page over the kept one at the watch's
      next check; a flag from the pane before the fresh page lands
      staying on; a letter tapped with no connection showing its header,
      then the failure; the password saved again in Settings: the
      Inbox empty for a moment right after Save (the copy is wiped at the
      save, B-056), and after a force-quit the kept Inbox in the first frame
      again, and the letters kept in Drafts ("On this iPad only") and the
      Outbox still there. Time the first frame if a screen recording can:
      the design asks under 500 ms.
      *Seen on the test iPad 2026-10-20, a build of the `fix-087-089`
      worktree, Organize by Thread on: the three swaps and the letter
      tapped offline passed (B-053). Scrolled six rows down, the rows on
      screen kept their height to the pixel, the new letter went on above
      the top out of sight, and the open letter kept its highlight. Under a
      resting finger the listing came and nothing moved; the fresh page
      went on within 0.3 s of the lift. Under two ticks the page waited
      until Mark ended Edit. A letter tapped offline had its header and the
      failure in the first frame, 0.33 s, too soon for "Loading…" to be
      caught. A flag from the pane in the first second stayed on, but the
      launch's page had come 0.4 s before its STORE went, so a flag before
      the page lands was not caught. Not yet tried: the password saved
      again, which waits to be agreed, as editing the store and typing
      the password do, and the first frame timed.*
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa), a screen recording: the first frame timed, the kept
      rows and counts 167 ms after the first frame of the launch's zoom,
      and the screen settled at 300 ms, under the 500 ms asked (B-053).
      Left: a flag from the pane before the fresh page lands, not yet
      caught, and the password saved again, as above.*
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
      words under the password field. Last, with the signature set: tap
      "Send my signature as plain text instead" and Cancel, then Use Plain
      Text and Save; open Settings again, "Restore Original Signature",
      Restore, Save; write a letter to the account: the formatted signature
      and its logo are back. Without leaving the app, open a letter's
      attachment, share it from the preview to Blackmail (or, if Blackmail
      is not offered there, a link from Safari in Slide Over) and send it to
      the account: the logo is on that letter too (the share extension
      handed the pictures at the save, not at the next trip to the
      background). Empty the box and Save: "Remove Signature?", Cancel keeps
      it.
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa): the signature's part passed (B-056). "Send my
      signature as plain text instead", then Cancel, changed nothing; Use
      Plain Text and Save, then Restore Original Signature, Restore and
      Save, put back the thirteen lines, the formatted twin and the logo,
      each byte for byte as found. A letter's PDF shared from its preview,
      where Blackmail was offered, went with that logo and the formatted
      signature, the share extension's last copy before the restore's save
      having been the plain one. The box emptied and saved asked "Remove
      Signature?", and Cancel kept it. A letter written after a restore
      had its formatted signature and logo back on 2026-10-19, in B-082's
      check. Left: everything before the signature, the app password
      revoked and made again first, which needs the account's Google
      settings.*
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
      no read mark; after a launch with no connection, Sent Mail opened
      while there is still none, and then Airplane Mode off, as for the
      swap under ticks, Edit, a tick on a Sent Mail row and Mark as Unread
      can all be made before its page lands at the watch's next check:
      `UID FETCH n (UID X-GM-MSGID)` before
      `UID STORE n -FLAGS.SILENT (\Seen)`, then Mark as Read to put it back.
      After such a launch too: send the account two letters, force-quit, open
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
      app ended (B-053); a letter opened from one needs such a launch
      too.
      *Seen on the test iPad 2026-10-20: every part but the last passed
      (B-053). Online, every write and open listed went alone, with no
      `(UID X-GM-MSGID)` FETCH and no `KEPT-` line, the draft fetched whole
      without the id. In Sent Mail before its page landed: the Flag at the
      second try, the first having met the watch's check; the unread row a
      letter sent to the account itself, unread in Sent Mail as in the
      Inbox; and Edit's Mark, each with the FETCH before its STORE. The row
      pushed off had to be a letter alone in its conversation on the kept
      page: with Organize by Thread on, a conversation with a newer letter
      there keeps its row. Not tried: a letter opened from another
      mailbox's copy, which needs the store edited with the app ended, and
      that waits to be agreed.*
- [ ] **B-055, the reading pane locked down, links in plain letters, Cc.**
      Seen 2026-09-30: letters and their web pictures drawn, a conversation's
      letter opened and closed, a plain letter's links asking before they
      open, and Cc in the first frame (B-055). Still to see, the rest: send the test account the letters
      below from another account; not his mailbox.
      Every letter, notice and conversation still draws at all: the pane
      now loads only `about:blank` from `loadHTMLString`, and if WebKit
      named the pane's own page otherwise, nothing would.
      *A conversation.* Three letters or more: since B-074 oldest at the
      top, the newest and the unread letters open and the read ones lines,
      opening at the oldest unread letter, or at the newest when he has read
      the rest. Tap a closed line: it opens, its body comes, the header and
      Reply move to it (a read letter, so no dot goes and no count changes),
      and the line greys under the finger as it did. Tap it again: it
      closes. Open two in quick succession; leave the pane fifteen seconds
      and open another, whose body goes in after WebKit's pause. With
      letters open, `kill -9` of Blackmail's own
      `com.apple.WebKit.WebContent`: the stack comes back with them open and
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
- [x] Save Draft with no connection, with Drafts open: the list keeps the
      Gmail copy's row, and the new "On this iPad only" row takes its place
      only some eight seconds later, once the save's upload has failed.
      Seen on the iPad 2026-09-30. Nothing is lost; the row should come at
      once, as the letter is kept before the sheet goes.
      *Done 2026-10-20, seen on the iPad 2026-10-20: the row comes as the
      sheet goes, in place of the copy's, with a connection or without.
      B-087.*
- [x] A forward with several files found in All Mail searches for the
      original once per file (`UID SEARCH X-GM-MSGID` before each part);
      once would do. Seen on the iPad 2026-09-30.
      *Done 2026-10-20, seen on the iPad 2026-10-20 but for another letter
      under the original's UID: looked for once, and every part after it
      fetched from the UID that search gave, before its own folder and UID
      are asked again, so that with the original archived each costs its
      two FETCHes, no SELECT. B-088.*
- [x] A letter read from its All Mailboxes hit leaves the Inbox's row for
      the same letter with its unread dot until the list is fetched again,
      though the Inbox's count goes down. Seen on the iPad 2026-10-03.
      *Done 2026-10-20, seen on the iPad 2026-10-20: the mark goes on every
      row of the letter by its Gmail id, and on its kept rows. B-089.*
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
- [ ] Watch a dead socket found (by the watch's 30 s check, or by
      keepalive when no check runs): open a letter,
      restart the router (the iPad itself stays on Wi-Fi, so only the path
      dies), wait three minutes, then tap another letter. It should load
      after one reconnect, not after a 30 s stall.
      *Not seen on the test iPad 2026-10-20 and 2026-10-21: the router
      restart needs a person, and its stand-in there, a route to nowhere for
      the mail server for three minutes, waits to be agreed, as taking the
      Wi-Fi interface down does, and this iPad has no `route` command to
      make it. Seen in passing: a socket iPadOS shut under a 30-second lock
      was found by the watch's first check after the return and replaced at
      once; such a socket fails at once, where a router's leaves it silent.*
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
      connection log shows the SEARCH as `* SEARCH {N uids}` (seen
      2026-09-30) and its screen scrolls without a stall. A letter whose
      HTML is over 2 MB, if one can be had, shows "Only the beginning of
      this message is shown." above it; Reply to it and Forward it to the
      second address: the composer's quote ends with the same words under a
      blank line, and the letter received ends its quote with them in grey,
      in Mail and on Gmail's web page, once (since 2026-10-01). Save the
      reply as a draft, reopen it and send it: the line still once.
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): every part but the letters Blackmail cannot make passed
      (B-054). In their place a letter of 17 MB shared from Files, three
      camera photos and a PDF, all four as files. Opened: its structure
      and header, its text and HTML cut at `<0.2097152>`, its logo alone,
      no `BODY.PEEK[]`, and the four rows at once; the PDF and a photo
      each one `UID FETCH n (UID BODY.PEEK[k])` alone at the tap.
      Forwarded To and Cc: one copy, the PDF and photos at the original's
      sizes, fetched part by part behind "Sending…". Replied to with a
      picture: the quote there; its conversation opened, the large letter
      in parts again, its logo from the reply's copy, and the reply whole,
      being 5 MB or less. With Airplane Mode standing in for the slow
      connection: ended, opened offline, and tapped on the kept Inbox as
      Wi-Fi came back, before the page, the first FETCH carried
      `X-GM-MSGID`, the kept row's, and it opened in parts. The log said
      `* SEARCH {73 uids}` and its screen scrolled with no stall. Left:
      the photographs shown in the body, the next letter tapped while
      they come, and the HTML over 2 MB with its Reply, Forward and
      draft, which need letters from another account and wait on a yes.*
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
      `trying` goes with the try. Half a minute later the count reads 0.
      Killed once its DATA had begun, it is not in Sent Mail at that look,
      and by design waits out the ten minutes of `Outbox.settling` before
      it goes. The same again, but go to the Home Screen while it sends
      instead of killing it: the count and the mark go at once, as the app
      leaves, while the letter is still on its way, and it arrives once.
      And again, swiping the app away in the app switcher while it sends:
      the count and the mark go as the app goes, whichever way the swipe
      ends it, and the letter arrives once, or at the next launch once.
      Still 1 with the app gone, and the swipe ends a running app as a
      crash does, with neither the background nor
      `applicationWillTerminate`: write that into B-057, with what step 1's
      swipe left in `Launches/unfinished`.
      *Seen on the test iPad 2026-10-20: 8's first two parts, the kill and
      the Home Screen, passed (B-057). The kill came as the DATA began, so
      the letter was held, not in Sent Mail, and went once at a Refresh
      after the ten minutes; the check now says so. The relaunch's own
      try, some 0.13 s, fell between the watch's looks; `trying` held its
      key through the try at that Refresh. At the Home Screen the letter's
      own count of tries went back down too. Still to see: the swipe in
      the app switcher, in 1 and in 8's third part, which needs a person
      at the iPad, and a held draft's row, which needs the store edited
      and waits to be agreed.*
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
      button on in the connection log first. *Since B-077 the motion is
      one half second with no settle, the folders move and darken, Reduce
      Motion changes nothing, and "< Mailboxes" and a folder tap slide:
      steps 1, 2, 7 and 10 are B-077's checks below; 3 to 6, 8 and 9
      stand; in 11 the gap beside the list comes only at the tap from
      three to two, where the list narrows to 375 pt, and closes as it
      moves; in 12, "at the settle" is now "as the pictures go". Step 8
      was seen under B-077 on 2026-10-07.*
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
      7. *Reduce Motion*, then *Prefer Cross-Fade Transitions*: now B-077's
      step 5; since B-077 the view button slides with both on.
      8. *VoiceOver* reads "Hide Mailboxes" and "Show Mailboxes", and
      lands on the button after a switch.
      9. *The log*: nothing on the wire but the watch's check every 30 s,
      the `layout: …` lines, no new
      finding, and no `pane motion:` line, a fallback or the deadline,
      but the bouncing ones step 3 asked for.
      10. "< Mailboxes" and a folder tapped in two panes slide (B-077).
      11. On a 1366 or 1376 pt iPad, if one can be had: 1 and 2 again,
      with the 2 to 5 pt gaps beside the list.
      12. *A conversation* of three letters or more, each switch at speed
      and frame by frame: the names and the open letter land where they
      end up; the dates at the rows' right ends ride with them and are put
      at the right end at the settle (B-066, Not covered). Whether that
      catches the eye, and a newsletter's centred column the same way.
- [x] **B-077, the panes move as Mail's.** On the 11-inch, with the Layout
      button on in the connection log.
      1. *At speed.* A 60 fps recording from Control Centre, stepped
      through frame by frame, and if it can be had a slow-motion film of
      the glass: each of the five moves, three to two, two to three from
      the list and from the folders, a folder tapped and "< Mailboxes".
      One motion of about half a second, no settle. In the first frames
      after the tap, never the screen as it was again once the first frame
      of the motion has shown: the simulator's recorder showed that, and
      the app cannot draw it. The corner's glyph still, Flag to Compose
      still in the view button's switches. The last frame the same as a
      screenshot a second later, but for a letter's line ends and, from
      two panes with the folders in front, the folders' title and counts.
      2. *The curve.* Half the way in about a tenth of a second and still
      to the eye by 0.4 s, as on 18.6. If it crawls, a third of the way at
      a quarter of a second, iPadOS 16 runs the spring otherwise: say so.
      3. *Three to two, frame by frame*, a scratch build with the window's
      `layer.speed` at 0.1. At the tap the list is wider on its left, over
      the folders, with "< Mailboxes" in its bar; it slides to the edge;
      the folders go left half as far and darken a little; the letter's
      left edge goes with the list. *Two to three*: the reverse, the
      folders showing at the list's left at the tap. *The folders in front,
      to three*: their column draws in and the list is there between.
      4. *A folder tap and "< Mailboxes"*, frame by frame: the list slides
      in from the column's right edge over the folders, which go 30%
      of the column left and darken; "Mailboxes" goes left and fades as
      "< Mailboxes" and the folder's name come from the right; the letter
      never moves and nothing goes over it. "< Mailboxes": the reverse,
      the open folder highlighted at the end.
      5. *Reduce Motion*: all five slide as before. Then *Prefer
      Cross-Fade Transitions*: the view button still slides; "< Mailboxes"
      and a folder tap fade for half a second and nothing moves.
      6. *Taps and bounces* on "< Mailboxes" and a folder: a double tap on
      a folder opens it once; a row tapped while the list slides in opens
      nothing; a flick of the folders and a folder tapped while they
      spring back opens it at once, with `pane motion: bouncing; switched
      at once` in the log. Then pull the list down past its top, tap
      "< Mailboxes" as it is let go, and tap the open folder straight
      after: both changes are made at once, the log has two bouncing
      lines, and the rows spring back to the top with no jump. The same
      with the folders pulled down in three panes, the view button, then
      "< Mailboxes".
      7. *A letter and a conversation*, three to two and back: the letter's
      lines wrap again as the motion ends. Whether that catches his eye.
      8. *VoiceOver*: after "< Mailboxes" it is on the folders, after a
      folder tap on the list, and it reads nothing of the pictures.
      9. *A search with the keyboard up*, then "< Mailboxes": the keyboard
      goes, the search is there when he taps the folder again.
      10. *The log*: no `pane motion:` line but the bouncing ones.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: all it can show passed (B-077).*
      *Seen on the test iPad 2026-10-07: 1 to 7, 9 and 10 passed, 3 and 4
      at `layer.speed` 0.05; in 6 the folder opened from a tap at the top
      of the bounce, not as they sprang back. 8 did not: with a letter
      open, "< Mailboxes" and a folder tap leave VoiceOver on the letter's
      Flag (B-079). 8 seen under B-079 on 2026-10-20, every step passing;
      the glass was not filmed in slow motion, and the 60 fps recording
      never showed the old screen after the first frame that moved; 7's
      question, whether the lines wrapping again late catch his eye, is
      still the owner's to say (B-077).*
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
      - every segment: `[(m, d[:16]) for m, d in im.applist]`. No COM,
        and no APP13 but ImageIO's empty one (an IPTC record with nothing
        in it, and its digest); list any APPn but APP0 JFIF, APP1 Exif or
        XMP, APP2 ICC_PROFILE or MPF, and APP14 Adobe.
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
      and `bytes=` the size the attachment arrives at. Since B-070 no line
      says "more than Send could build": the memory at Send no longer
      shrinks a photo. On the host: the size it was taken at, the original's
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
      and all five arrive. Five `SHARE-PICTURE` lines, each as in 1, own
      bytes, while they fit the 25 MB together; one past it says `(not as
      its own bytes: more than the letter's room, N MB left)` and goes as
      in 4. Note how many went as their own bytes.
      3. *The 48-megapixel JPEG alone* (IMG_0776: 8064 by 6048, EXIF
      orientation 8, a GPS tag), which made the sheet vanish on
      2026-10-04: the sheet stays. Its line says own bytes and it arrives
      at 8064 by 6048, orientation 8, no GPS anywhere. Then the
      64-megapixel panorama alone, and a 48-megapixel HEIC, an iPhone's
      HEIF Max, where one can be had: its line says what Photos offered
      for it and which way it went.
      4. *A photo too large for the room, shrunk.* Share the camera photos
      and the 48-megapixel JPEG last, five at once. Photos hands them
      over in the library's order, by date, not in the order picked: the
      JPEG is last only behind older ones. Those that fit the
      letter's 25 MB go as their own bytes. A photo is shrunk only past
      that room (B-070): no line says "more than Send could build". The
      first that does not fit says why, `(not as its own bytes: more than
      the letter's room, N MB left)`, then `way=JPEG at factor F, N MB
      available`, and arrives as a .jpg, IMG_NNNN.jpg, at the size F
      gives (for the 48-megapixel JPEG a quarter, 1512 by
      2016, upright, stored 8064 by 6048 with orientation 8, with less
      than 264 MB left), upright in its pixels, no orientation tag, no GPS
      anywhere, the date. Then a video of 15 to 24 MB older than the
      48-megapixel JPEG, and the JPEG, if Photos offers Blackmail for the
      two together: the JPEG's line says `more than the letter's room, N
      MB left`. The sheet says nothing of one left out unless one is.
      5. *A letter near the limit, sent.* Share a video of 20 to 24 MB
      alone, weighed against the 25 MB alone, and Send it. The sheet must
      close at the 250, and the letter arrive. Copy down its lines: its
      `SHARE-FILE`; `LETTER-PLAN` with `raw=`, `payload=` and `ms=`; its
      `LETTER-FILE 1 bytes= crc=`; `MAIL FROM … SIZE=` the `raw=`;
      `LETTER-LATCH ok`; one `WIRE-OUT` and one `WIRE-ACK`; and the three
      `SHARE-SEND` lines: the memory left with the files read, in the
      rehearsal, before DATA, and once it has gone, `M MB at the least`
      since the extension started, and `W MB at the least while it went`
      (B-070). Then the same lines for the letter of 2. An extension killed
      at Send leaves no log: the sheet goes at "Sending…" and nothing
      arrives; note that, and the size shared. A pass on the test iPad,
      allowed 180 MB, says nothing of his, perhaps 120 MB: make it again
      there when his can be had.
      6. *A screenshot, and a GIF.* The screenshot's line: `name=file
      "IMG_NNNN.PNG"`, `way=copied whole`; it arrives as the .PNG it was,
      its name's case kept. A moving GIF arrives as the .gif it was, still
      moving, whatever its size up to the letter's room; the old 5 MB
      bound is gone. If either's `read=` is `public.jpeg`, note it: Photos
      then offers a JPEG ahead of it.
      7. *A picture with no name.* Take a screenshot, tap its thumbnail,
      and share from that screen; then two the same way at once, if it
      allows. Its line says `name=none "image0.png"` (or `.jpeg`), the
      next `image1`. If it says `name=suggested` or `name=file "{N
      chars}.png"`, iOS gave it a name: read it from the letter that
      arrived and note it; it decides whether such names count as none.
      *Tried on the test iPad 2026-10-20, three times of three: the sheet
      said "The photo could not be attached." in place of the letter,
      "The photos could not be attached." for two, and no line could be
      read, none being written without a Send (B-090). Since B-090 the
      picture is read as every picture type the provider offers, then as
      the `UIImage` it gives, made a PNG or a JPEG here, and the log is
      written when something is left out. Made again as B-090's check at
      the end of this section; its `read=` may then end `,object` or
      `,item`, and its way `PNG made of the object`.*
      *Seen on the test iPad 2026-10-20 on B-090's build, one picture and
      two at once: attached, and sent (B-090). Each line said
      `read=public.image,item name=suggested "{18 chars}.png" way=PNG made
      of the object`, and each arrived as "View recent photos.png",
      image/png, some 10.2 MB, with no location: iOS's name for a screenshot
      taken over a video open in Photos, two under the same name. The check
      looked for image0.png first; the editor named each screenshot it was
      given, so `name=suggested` is now in it. Whether such names count as
      none is not yet decided.*
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
      11. *A link from the YouTube app*: in the row, the link in the body
      (the YouTube app hands over no title, seen 2026-10-04, so the subject
      is empty), the link tappable in the letter that arrives.
      12. *After these, the app's own password still works* after the
      Keychain groups change: the app signs in and sends.
      13. *Cancel with words in it.* Type a word above the signature and
      tap Cancel: it asks, Delete Draft ends the share, and a tap elsewhere
      on the sheet closes the question with the word still there (on the
      iPad it is a popover with Delete Draft alone).
      14. *A failed send.* With Wi-Fi off, Send: the reason is shown, the
      letter is left as it was, and Send works once Wi-Fi is back.
      15. *A `mailto:` link* tapped in a letter opens the app's composer
      with its address in To and his signature under the body. Whether
      one tapped in another app comes here is only noted.
      16. *A video over 25 MB*, shared from Photos alone: the sheet says
      "The video could not be attached." in place of the letter, and no
      letter goes (B-070; the words approved by the owner). Its
      `SHARE-FILE` line says
      `went=left out, more than the letter's room, N MB left`.
      17. *A signature changed in Settings* reaches the next share: the
      sheet's letter has the new one under the body.
      *Seen 2026-10-04, before the change of 2026-10-05, on a build
      installed through the helper: one photo (the 48-megapixel JPEG, at
      3024 by 4032, upright, no GPS, the date kept); five at once (five
      camera photos, each with its location, each 4032 by 3024, no GPS, the
      date and its zone and the Display P3 profile kept); a 64-megapixel
      panorama (at 4000 by 1000), no 24-megapixel photo or HEIC at hand;
      11, with no subject: the YouTube app hands over the link alone;
      12. Every photo check is to be made again on the new build; 13 to 17
      not yet tried (B-036).*
      *Seen on the test iPad 2026-10-20, a build of master with B-087 to
      B-089 (daccd64): 2, 4, 5, 6's GIF, 9 and 10 passed (B-036). Photos
      offered a GIF as `com.compuserve.gif`, the rest as on 2026-10-05, and
      handed the items over in the library's order, not the order picked. In
      2 all five went as their own bytes. In 4 IMG_0776 went at a quarter
      behind three older PNGs of 24.2 MB, its N 170. 4's video and JPEG were
      not made: a video picked first, but newer than the JPEG, came after it
      and was left out, "1 video could not be attached.", and 4 now says the
      order is the library's. In 5 a 21.0 MB video went, Photos' H.264 copy
      of a 22.2 MB camera video, raw 1.37 times the file; the sheet closed
      at the 250. In 9 the JPEG went as its own bytes and arrived with no
      EXIF and an empty XMP. The pictures of 9 and 10 were saved to Photos
      from Files, not Safari. The JPEGs made here carry an empty APP13, an
      IPTC record with nothing in it, ImageIO's, holding no place, and the
      list of segments now allows it. 7 failed on that build and became
      B-090, seen fixed on B-090's build, as 7 says. Still to do of 1 to 10:
      3's 48-megapixel HEIC, none at hand; 4's video, which needs one older
      than the JPEG; 5 and 8 on his iPad; and 7's name, not yet decided.*
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa): 11, 13, 14, 16 and 17 passed (B-036). In 11 the
      YouTube app's link came alone on the body's first line, above the
      signature, the subject empty as on 2026-10-04, and arrived a link. In
      13 the popover was dark, Delete Draft alone. In 14, with Airplane
      Mode on, "Can't connect to mail server." over the sheet, the letter
      as it was and Send blue again; with Wi-Fi back it went, once. In 16,
      the 44 MB camera video, which Photos handed over as 48.5 MB: "The
      video could not be attached." with Cancel alone, and its `SHARE-FILE`
      line in the log kept for a share with something left out (B-090).
      In 17 "Seventeen", added in Settings, was in the next share's letter
      under the link. 15, the `mailto:` link, was not part of it.*
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
- [ ] **B-069, the composer and the share sheet as Mail's.** On the test
      account, letters only to it, subjects beginning "B-069", put in
      Trash after. No keyboard attached unless a step says so.
      1. *The keyboard.* Write a letter until the lines reach the
      keyboard: the line typed on stays above it, and the caret with it.
      In landscape, the same on a Forward of a letter with three or more
      files, and on a new letter with Cc/Bcc open: the fields go up out
      of the way, the caret's line stays in sight, and the fields scroll
      back down with the keyboard still up. The same in the share
      sheet, shared from Safari and with several photos from Photos.
      With a hardware keyboard attached, the body reaches the sheet's
      bottom as before. Forward a long letter, a newsletter, and type at
      the top of the body: the keys keep up, and the sheet opens without
      a pause.
      2. *Suggestions.* In To type the first letter of his second
      address and pick it: the list closes. Type a letter of a name: it
      comes back, without the one picked. The same in the share sheet.
      (Going into To offers nothing since B-073; it offered his most
      used when this was written.)
      3. *Tapped or swiped away.* A tap outside the composer does
      nothing, with words in it or not. A swipe down with a word typed
      asks Save Draft or Delete Draft; on an untouched letter it closes
      the sheet. In the share sheet a swipe with a word typed asks Delete
      Draft. Note what a tap outside the share sheet does: on the
      simulator Safari closes it.
      4. *Cancel.* A new letter untouched, and an untouched Reply and
      Forward: each closes with nothing asked, and Drafts has nothing
      new. A word typed, left a few seconds, taken out, Cancel: the same.
      The Outbox: with Airplane Mode on, Send a letter, which goes to
      the Outbox. Still in Airplane Mode, open it there, type a word,
      wait a few seconds, take it out, Cancel: nothing asked, and the
      letter is in the Outbox, not in Drafts. Airplane Mode off: it goes,
      once.
      5. *Return in Subject*: the caret at the top of the body, above
      the signature, and in a Reply above the quote too. Tab from Subject
      with a hardware keyboard, the same. In the share sheet, shared from
      Safari: an empty line above the link, and words typed there stay
      on their own line, the link under them. Cancel on a share left as
      it came closes with nothing asked.
      6. *Send* grey as a new letter opens, blue once To holds an
      address, grey again when it is emptied. The same in the share
      sheet.
      7. *The title* follows the subject as it is typed, "New Message"
      when it is emptied.
      8. *Colours.* The body black, as the sheet is; the share sheet's
      Cancel question dark.
      9. *VoiceOver* reads "To", "Cc", "Bcc", "Subject" and "Message",
      in the composer and in the share sheet.
      10. *The paperclip.* Settings, Accessibility, Display & Text Size,
      Larger Text, Larger Accessibility Sizes on, at its largest: the
      paperclip stays
      the size of "Attach Photo". Put the text size back.
      *Seen on the simulator, 2026-10-05, on 18.6, and 1 and 3 on
      17.5 (B-069); the review's changes to 1, 4 and 5 on 18.6 as well,
      all but the Outbox in 4. Not yet on the iPad.*
      *Seen 2026-10-05 on the test iPad (B-069): 1 in the composer,
      2, 3 (the tap; the swipe not tried), 4 for a new letter and the
      Outbox (it went once), 5, 6, 7 and 8, and the share sheet from
      Safari for 2, 5 and 6. Not yet: 1 in the share sheet, a reply and
      a forward left untouched, the swipe, 9 and 10.*
      *Seen on the test iPad 2026-10-21, a build of master with B-090 and
      B-091 (cba64fa): 1 in the share sheet and in landscape, the swipe of
      3 and 4's Reply and Forward passed (B-069). Ten lines in the share
      sheet from Safari, and eight under four photos from Photos: the
      fields went up, the photos' rows with them, and the caret's line
      stayed just above the keyboard; from Safari, swiped back down with
      the keyboard up, the fields came back, and the next key brought the
      caret into sight. The same in landscape on a Forward with six files
      and on a new letter with Cc/Bcc open. A long newsletter forwarded:
      the sheet began to show 0.67 s after the tap on Forward and was in
      place at 1.06 s, 0.1 s behind a short letter's, the rest being
      UIKit's menu fading and its sheet sliding, with no pause of the
      app's own; typed at the top, the keys kept up. Swiped down, a letter
      with a word asked Save Draft or Delete Draft, one untouched closed,
      and the share sheet with a word asked Delete Draft. A tap outside
      the share sheet, on Safari's dimmed page, closed it at once with
      nothing asked, the word typed lost with it, as on the simulator. An
      untouched Reply and Forward each closed with nothing asked, and
      Drafts had nothing new. Not yet: 9 and 10.*
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
      *Seen 2026-10-05 on the test iPad (B-071): 1, and 3 without
      VoiceOver. Not yet: 2, VoiceOver in 3, and 4.*

- [ ] **B-070, Send streams the letter from its files.** On the test
      iPad, the test account only, on a build of master, where it is merged.
      For every check copy down the
      `LETTER-`, `SHARE-` and `WIRE-` lines. To check a file that arrived,
      fetch it over IMAP on the host from the test account and compute
      `zlib.crc32` and its sha256.
      1. *A 19 MB IMG_NNNN.MOV, alone, from Photos.* Blackmail is offered,
      and its line reads `SHARE-FILE read=com.apple.quicktime-movie …
      mime=video/quicktime … went=staged`. Send: the percentage rises and
      the sheet closes at the 250. The lines: `LETTER-PLAN raw=R
      payload=R+3`; `MAIL FROM … SIZE=R`; `LETTER-LATCH ok`; one
      `WIRE-OUT` and one `WIRE-ACK`; 250. No `LETTER-FILE` line says
      `not checked`. The file's CRC is its `LETTER-FILE` line's, and it
      plays. Note `ms=`, under 2 s, and how
      long the upload took. Memory passes when "while it went" is no more
      than 15 MB below the available figure on the "files read" line.
      2. *A video of about 5 MB.* Its fall to "while it went" is within
      5 MB of that of check 1's video sent with the iPad left unlocked:
      the memory does not grow with the file. A lock right after Send, as
      in 3, took some 7 MB more by itself on 2026-10-20, so a locked send
      is no baseline.
      3. *Lock the iPad right after Send in check 1, and wait 5 minutes.*
      Either it arrives once, or "Message was not sent." shows and Sent
      Mail has nothing. No `LETTER-LATCH withheld … errno`. "Not sent" for
      a letter that arrived is a fail.
      4. *Five full-size camera photos.* Every `SHARE-PICTURE` line says
      own bytes and none "Send could build". They arrive at their own
      pixel size, with no GPS, each CRC its `LETTER-FILE` line's.
      5. *Mixed:* a video and two photos; videos of 19 MB and 8 MB, the
      second left out with "1 video could not be attached."; six items,
      Blackmail not offered; a video over 25 MB alone (seen with a 44 MB
      one), the words in place of the letter and nothing sent. The video
      words, and "The photo and the video could not be attached." for one of
      each, are the owner's, approved 2026-10-05.
      6. *The app's composer.* Five photos: `LETTER-PLAN` and five
      `LETTER-FILE` lines, none `not checked`, and they arrive. Forward check 1's letter: the
      video goes from memory, its CRC the same.
      7. *A draft.* Three photos, Cancel, Save Draft: the APPEND as before,
      no `LETTER-` lines. Reopen it and send it: it arrives, and the draft
      is gone.
      8. *The Outbox.* Wi-Fi off before Send: it waits, and goes once when
      Wi-Fi is back. Wi-Fi off at about 40% of check 6's five photos:
      `WIRE-ACK err=…`, `OUTBOX-WAITING` `connectionLost`, then
      `OUTBOX-UNSETTLED` for 10 minutes, then a new `LETTER-PLAN` under the
      same Message-ID. Exactly one copy at the recipient and in Sent Mail:
      the evidence that Gmail throws away a DATA that never ended, which
      the latch rests on.
      9. *As before:* a link from Safari; a plain letter, the signature
      taken out (one part, `WIRE-PAYLOAD bytes=` raw+5, B-068's check); a
      reply that threads; a share with Wi-Fi off, the reason shown, sent
      once it is back.
      10. *His iPad, when it can be had:* checks 1 and 2, and the memory
      lines.
      *Check 1's path seen in the iPadOS 18 simulator, 2026-10-05: a
      19,284,661-byte IMG_7001.MOV from Photos, Blackmail offered, the
      lines as written, `ms=101`, and the file that arrived the original's
      to the byte (B-070, "Seen in the simulator"). The simulator says
      nothing of memory; every check is still for the iPad.*
      *Seen 2026-10-05 on the test iPad (B-070): 1, 5 in part (too
      large alone, 19 + 8 MB, a video and two pictures), 6 (a Forward of
      the video), 7 and 8 (cut at 10 MB for 60 s: one copy, same
      Message-ID). Not yet: 2, 3, 4 on this build, six items, 9, and 10.*
      *Seen on the test iPad 2026-10-20, a build of master: the rest of 6,
      five photos from the app's composer, `LETTER-PLAN files=5` and five
      `LETTER-FILE` lines, none `not checked`, and each arrived with its
      line's CRC (B-070, under B-044's checks). Still not: 2, 3, 4 on this
      build, six items, 9, and 10.*
      *Seen on the test iPad 2026-10-20, a build of master with B-087 to
      B-089 (daccd64), shared from Photos: 1 again, 2, 3, 4 and 5's six
      items passed (B-070). In 3 the 18.7 MB video arrived once, its CRC its
      line's, the upload ending with the screen off; the test iPad has no
      passcode. 2 was first measured against 3's locked send, which fell
      9 MB where every unlocked one fell 2 MB, whatever its files. Against
      the 18.7 MB video sent again unlocked, the 7.9 MB one fell the same
      2 MB, so 2 now names an unlocked send as its baseline. Still not: 9,
      not yet tried, and 10, which needs his iPad.*
- [x] **B-072, Refresh sends what waits in the Outbox.** On the test iPad,
      the test account only, every letter to the account itself, built
      from the `refresh-outbox` worktree; merge only after a pass. Copy
      down the `OUTBOX-`, `LETTER-` and `WIRE-` lines.
      1. *The check.* Open a letter with a file over 1 MB (B-070's 19 MB
      video letter does). Airplane Mode on. Forward it: the sheet closes
      with "Message is in the Outbox…", and the Outbox has it. Airplane Mode
      off. Stay in the Inbox a minute: it is still in the Outbox (a page
      and the watch's check leave it). Tap Refresh: the list and the
      folder counts come first, then "1 Unsent Message" under the list
      goes away and the Outbox leaves the Mailboxes, and the log says
      `OUTBOX-REFRESH large=1`, then `LETTER-PLAN`, one `WIRE-OUT`,
      `LETTER-LATCH ok` and the 250. It goes once: one copy in the Inbox
      and one in Sent Mail, and the Outbox empty.
      2. *From the Outbox itself.* The same, but tap Refresh with the
      Outbox open: its row says "Sending…" while it goes, and it goes,
      once.
      3. *A draft still waits.* Airplane Mode on, a new letter with a
      photo over 1 MB, Cancel, Save Draft. Airplane Mode off, Refresh: it
      stays in Drafts "On this iPad only". Go to the Home Screen: it goes
      up, once.
      4. *Leaving while it goes.* Airplane Mode on, the Forward of 1 and
      the draft of 3 again. Airplane Mode off, tap Refresh, and go to the
      Home Screen once the log says `OUTBOX-REFRESH large=1`. The log
      says `OUTBOX-LEAVING owed`. Come back after a minute, and wait for
      the Outbox to empty if it has not: the forward went once (one copy
      in Sent Mail), and the draft is in Gmail's Drafts once, no longer
      "On this iPad only".
      *Seen 2026-10-05 (B-072): 1, one copy. 2 to 4 not tried on the
      iPad; the host suite holds them.*
- [x] **B-073, the list only as he types.** On the test iPad, the test
      account only. Send nothing; Cancel each letter.
      1. *The composer.* A new letter. Tap the empty To: no list. Type
      one letter: the list. Delete it: the list closes. Tap Cc/Bcc, then
      the empty Cc: no list.
      2. *The share sheet,* from Safari. It opens in To: no list. Type
      one letter: the list. Delete it: the list closes.
      *Seen 2026-10-06, as written, in both (B-073).*
- [x] **B-074, a conversation in Mail's order.** On the test iPad, the test
      account only, every letter to the account itself, subjects beginning
      "B-074", built from the `conversation-order` worktree; merge only
      after a pass.
      1. *The order.* Send a letter, and from the pane Reply to it twice,
      without opening the replies. Open the conversation: the first
      letter's line at the top of the pane, the first reply open under it,
      the newest open under that. The row's dot goes, and two come off the
      Inbox's count.
      2. *Read.* Open it again: the first reply's line at the top of the
      pane, the first letter's line above it and out of sight, the newest
      open under it, black below it. Tap that line: it opens under its
      line, which does not move.
      3. *Where it opens.* Reply with thirty lines or more. Open the
      conversation once it has come: the line of the letter before it at
      the top of the pane, the long one open under it from its first line,
      and nothing moves as its body comes in.
      4. *New mail.* With the conversation open and the Inbox at the top,
      send another reply. Within half a minute it is at the bottom of the
      stack, open, and nothing above it moves. Its row has its dot.
      5. *The header.* A reply with the account in Cc as well. Open the
      conversation, and tap the line above the newest: when its body comes
      the header loses its Cc line, and the line tapped stays where it was.
      6. *The view button.* Down a long letter in the stack, switch from
      three panes to two and back: that letter stays the one at the top of
      the pane. Its lines wrap again, and other words of it can be at the
      top, as B-066 has it for a letter alone.
      7. *Closing the newest.* Open the three letters of 1 again, tap the
      first reply's line, then the newest's line: the newest closes, and
      the first reply stays where it is, black under the newest's line.
      8. *The status bar.* Open them again and, without touching the pane,
      tap the status bar: the pane goes to its top. Then the view button,
      three panes to two: the letter at the top stays there.
      9. *A letter already read.* With the three letters open, turn Wi-Fi
      off on the iPad. From another device on the test account, reply to
      them, and open the reply there. Wi-Fi on, and Refresh: the reply goes
      in at the bottom as a closed line, nothing above it moves, and its
      row has no dot.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: all steps passed (B-074).*
      *Seen on the test iPad 2026-10-07: all nine steps passed. In 9 the
      reply was put into the mailbox already read, the iPad not taken
      offline. In 3 the long letter's body had come before it was opened,
      so there was no load to watch (B-074).*
- [x] **B-075, Sent Mail's rows as Mail's.** On the test iPad, three
      panes, Organize by Thread on, the test account only, every letter
      to the account itself: "Jane's address" is its address with `+jane`
      before the `@`, typed `Jane Example <` the address `>`, and "Sam's"
      the same with `+sam` and `Sam Example`. Send nothing else.
      1. *Two people.* A letter To Jane's and Sam's addresses, Cc the
      account's own address, Subject "B-075 one". Send. Sent Mail: its
      row reads "Jane & Sam", not the Cc, with no count and no mark, the
      time at the right edge where every row's is.
      2. *A conversation.* Open "B-075 one", Reply, Send. Sent Mail: the
      row reads "Jane & Sam", then the time, then a blue chevron in a
      circle at the right edge, and no "(2)". The names and the subject
      are where the row below has them. Tap the row: the conversation
      opens in the reading pane, as before. Edit: the mark stays after
      the time. Done.
      3. *A long name.* To `Jane Wolfeschlegelsteinhausen Example <`
      Jane's address `>`, Subject "B-075 long", Send, then Reply to it
      and Send. Its row: the name cut with "…", then the time, then the
      mark, all on the line.
      4. *Him.* To the account's own address typed alone, then Jane's,
      Subject "B-075 him": the account's address before its "@", then
      "& Jane", as Mail keeps the first. Another, To Jane's, then the
      account's: "Jane Example", whole, him left out.
      5. *Nobody in To.* A new letter, Sam's address in Cc only, Subject
      "B-075 nobody", Cancel, Save Draft. Drafts: "No Recipients".
      Another, To Jane's address with ";" typed after it, which makes
      her bubble at once (B-081), Subject "B-075 semicolon", Cancel, Save
      Draft: Drafts reads "Jane Example", not "No Recipients".
      6. *Elsewhere.* The Inbox: the letters of 2 and 3, each the
      account's name, then the time and the blue chevron in a circle,
      with no "(2)" (B-080). Sent Mail searched "B-075",
      Current Mailbox: a row for each letter, no mark, no count; All
      Mailboxes: each the account's name.
      7. *VoiceOver* on, in Sent Mail, touch the row of 2: "Jane & Sam,
      2 messages", the subject, the time. VoiceOver off.
      Then delete the B-075 letters and the draft.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: all steps passed (B-075).*
      *Seen on the test iPad 2026-10-07: 1 to 6 passed; in 7 the taps went
      to the app, not to VoiceOver.*
      *Seen on the test iPad 2026-10-19: 7 passed, VoiceOver put on the
      row by B-079's move, a touch still going to the app: "selected,
      Unread, Jane & Sam, 2 messages", the subject, the time (B-075).*
- [x] **B-076, Reply as Mail's: bubbles and his addresses.** On the test
      iPad, the test account only; A stands for its address. Letters only
      to A with a `+` tag before the @, subjects beginning "B-076".
      1. *Bubbles.* A new letter. In To type A with `+jane` and a comma: it
      becomes a bubble with the address on it. Tap Cc/Bcc, then Cc; type A
      with `+sam`, then tap Subject: a bubble too. Subject "B-076 bubbles",
      Send. It arrives once; Gmail's Show original has To and Cc as typed.
      2. *A pick.* A new letter. In To type one letter and pick a row with
      a name: a bubble with the name, no list, Send blue. Type the same
      letter again: the one picked is not offered.
      3. *Backspace and a tap.* With the caret after the bubbles, Delete
      once: the last bubble turns bright blue. Delete again: it is gone,
      and Send is grey if it was the only one. Tap a bubble: a small menu
      with its address and Remove. Tap outside: the menu goes, the bubble
      plain again. Tap it again and Remove: gone. Cancel, Delete Draft.
      3a. *A bubble's whole line.* A new letter. In To type `Al
      <al@example.com>` and a comma: a bubble "Al", as wide as a finger.
      Tap just above it, inside the To row: its menu. Tap outside; tap
      just below it: the menu again. With the menu up, type "sa" and
      Return: "sa" a bubble after it, "Al" still bright, the menu still on
      "Al", and still on it as the keyboard moves. Delete: "Al" goes, and
      its menu with it. Cancel, Delete Draft. Nothing is sent.
      4. *Reply All.* Open the letter of step 1 in the Inbox, Reply All: To
      `+jane`, Cc `+sam`, each a bubble (his own letter, answered as B-061
      answered it). Cancel. Type a word, Save Draft, open it from Drafts:
      the same bubbles. Cancel, Delete Draft.
      5. *His addresses.* Settings: under the address, "Email", the address
      alone, and "Add Another Email…". Add A with `+jane` in capitals:
      listed, with Remove. Add "owner": "That is not an email address."
      Save. Reply All to the letter of step 1 again: To `+sam` alone, `+jane`
      left out as his. Cancel. Settings: Remove `+jane`, Save; Settings
      again: only the address.
      6. *The share sheet,* from Safari. It opens in To. Type one letter,
      pick `+sam`: a bubble. Delete twice: picked out, then gone. Pick it
      again, Subject "B-076 share", Send. It arrives once, To `+sam`.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: all steps passed, two faults fixed (B-076).*
      *Seen on the test iPad 2026-10-07, the on-screen keyboard up: all
      steps passed, 3a's menu under the bubble once B-078 was in. Under
      the address, Settings reads "Email —" and what the addresses do, as
      built. B-073's check in both halves, and B-069's Send grey and its
      Cancel at once on a new letter, passed too (B-076).*
- [x] **B-078, a bubble's menu with the keyboard up.** On the test iPad,
      the test account only, landscape, built from the `bubble-menu`
      worktree; merge only after a pass. The on-screen keyboard up
      throughout but in 6: if a keyboard bar shows instead, its keyboard
      key, then Show Keyboard. Send nothing.
      1. *The menu.* A new letter. In To type `Al <al@example.com>` and a
      comma: a bubble "Al". Tap it: its menu (Al, the address, Remove)
      opens under "Al", its arrow on the bubble, not to the right of it.
      2. *A bubble after it.* With the menu up, type "sa" and Return:
      "sa" a bubble after "Al", in sight, not under the menu. "Al" stays
      bright, and the menu stays on it.
      3. *Delete.* With the menu still up, Delete: "Al" goes, and its
      menu with it. "sa" is left plain. Cancel, Delete Draft.
      4. *Cc and Bcc.* A new letter. In To `Al <al@example.com>` and a
      comma, then Cc/Bcc. In Cc `Jo <jo@example.com>` and a comma, and in
      Bcc `Bo <bo@example.com>` and a comma. Tap "Jo": its menu under
      "Jo" or over it, its arrow on it, never beside it. The Cc line
      stays in sight. Tap outside, then tap "Bo": the same, the Bcc line
      in sight. Remove: "Bo" gone. Cancel, Delete Draft.
      5. *The share sheet,* from Safari. It opens in To. Steps 1 to 3
      again: the menu under "Al", "sa" in sight after it, Delete taking
      "Al" and its menu. Cancel, Delete Draft.
      6. *The keyboard down.* A new letter, the bubble of step 1, then
      hide the keyboard with its key. Tap "Al": its menu under it, its
      arrow on it, as before. Remove: gone. Cancel.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: in each step the menu under its bubble, its arrow on it, in Cc and Bcc as in To; the fault does not show there (B-078).*
      *Seen on the test iPad 2026-10-07: all six steps passed, the menu
      under its bubble in each, never beside it.*
- [x] **B-079, VoiceOver's place after a pane move.** On the test iPad,
      landscape, the test account only, built from the `vo-focus-4`
      worktree; merge only after a pass. Turn VoiceOver and its Caption
      Panel on in Settings > Accessibility > VoiceOver. A tap goes
      straight to the control, as on 2026-10-07, and a VoiceOver double
      tap does the same. The caption names where VoiceOver is, and its box
      is round it. Nothing is sent, read or flagged.
      1. *"< Mailboxes".* Two panes, the list in front, a letter open in
      the pane. "< Mailboxes": VoiceOver is on the open folder's row, the
      highlighted one, and the caption names that folder, not "Flag,
      Button". If the folders end with a label, open it and a letter in it
      already read, tap "< Mailboxes", and as soon as VoiceOver is on the
      label's row swipe right once: VoiceOver goes into the reading pane,
      and stays there.
      2. *The open folder.* Tap it: the list comes back and VoiceOver is on
      the letter's row, the highlighted one, not Flag, and stays there to
      8 s. If VoiceOver goes by itself to Flag or to the view button, about
      a second after it got to the row, the app puts it back at once, and
      VoiceOver is on the row again within about a second, its own time
      to move, and stays. The list does not move.
      3. *A new folder.* "< Mailboxes", then a folder not open, such as
      Sent Mail: VoiceOver goes into its list, on its first row, or, while
      it has none, at its top, the search field. Not the view button in
      the corner. If VoiceOver touches the view button or another row on
      the way, it is on the row within a second after. The folder's newest
      page comes within a second or so and its rows are drawn again:
      VoiceOver stays on that row's letter, its box and its words the same
      row's, for 5 s. The same for Important and for the Inbox, each opened
      anew. The pane is now empty.
      4. *The pane empty.* "< Mailboxes": VoiceOver is on that folder's row,
      not on the view button. Tap it again: on the list's first row. The
      list does not move.
      5. *The list scrolled.* Scroll it so its top row is half under the
      search field, the pane empty or the letter's row out of sight.
      "< Mailboxes", then the open folder: VoiceOver is on the first row
      wholly below the search field. As VoiceOver lands the list may go back
      to its top, by the part of the first row that was under the search
      field: that is VoiceOver's own. It moves no further. Then open a
      letter, put its row half under the search field, and do the same: as
      the list slides in, the letter's row is already whole, just below the
      search field, the list moved down by the part that was under it and
      no more. VoiceOver goes to that row and the list does not move again:
      not to the middle, not to the top. The same with the letter's row
      half under the toolbar at the bottom: the list comes in moved up to
      show it whole, a third of a row clear of the toolbar, not on it.
      VoiceOver goes to the row and the list does not move again. The same
      with the letter's row whole but ending just above the toolbar: the
      list comes in moved up those few points, and then stays. Then
      VoiceOver off, the letter's row half under the search field again,
      "< Mailboxes" and the open folder: the list does not move at all.
      6. *The view button*, as before: two panes to three, VoiceOver on it,
      "Hide Mailboxes, Button"; three to two, "Show Mailboxes, Button".
      7. During and after every move nothing of the pictures is read: the
      caption names only real controls.
      8. *The rows drawn again under VoiceOver.* Two panes, the Inbox's
      list in front at its top, a letter open, VoiceOver on the letter's
      row as after 2. Tap Refresh, which leaves VoiceOver where it is: once
      the list has come again, VoiceOver is still on that letter's row, its
      box and its words that row's, not on Flag or the view button, for
      5 s. Then wait 40 s, through a check for new mail: still there.
      9. *From a fresh launch.* With VoiceOver on as the app starts, iPadOS
      moves VoiceOver once in the launch, about 0.9 s after it gets to the
      row: to Flag, or to the view button. Quit Blackmail from the app
      switcher and open it again, VoiceOver on. Two panes, the Inbox at its
      top, a letter open, VoiceOver on the letter's row. "< Mailboxes",
      then the Inbox: VoiceOver is on the letter's row at about 1.05 s. If
      at about 1.9 s it goes to Flag, it is back on the row within a few
      tenths of a second, and stays there to 8 s. Do it in three launches.
      Quit and open it again, the pane empty this time: the Inbox's first
      row, and if it goes to "Show Mailboxes, Button", back on the row; in
      three launches too. Quit and open it again with
      VoiceOver off, then turn VoiceOver on, open a letter and tap
      "< Mailboxes": VoiceOver is on the Inbox's row, and if it goes to
      Flag, back on that row, and it stays. If a letter is waiting in the
      Outbox from another check, quit and open Blackmail again, VoiceOver
      on, and tap "< Mailboxes", then the Outbox: VoiceOver is on its
      first row, and if it goes to "Show Mailboxes, Button", it is back on
      the row within about a second. Leave the letter where it is.
      Then VoiceOver and the Caption Panel off, and the panes as they were.
      *Seen on the test iPad 2026-10-07, the first change: steps 1, 4, 6
      and 7 passed; 2 failed once in three, 3 in each folder with letters,
      and 5 as the list moved. Changed again for 2 and 3, and 5 rewritten
      for VoiceOver's own scroll (B-079).*
      *Seen on the test iPad 2026-10-19, the second change: steps 1, 3, 4,
      5a, 6, 7 and 8 passed; 2 failed once in 15, VoiceOver leaving the row
      by itself once in each launch, and 5b as VoiceOver put a half-hidden
      row in the middle of the list or took the list to its top. Changed a
      third time for both: 2 and 5 rewritten, 9 added, a line in 1 for the
      last folder (B-079); not yet seen there.*
      *Seen on the test iPad 2026-10-19, the third change: steps 1, 2 (11
      in 11), 3, 4, 5a, 5b under the search field, 5 with VoiceOver off,
      6, 7, 8 and 9c passed; 9a and 9b failed, iPadOS moving VoiceOver off
      the row once in each launch and the app never seeing it, and 5b
      under the toolbar, VoiceOver putting the row in the middle of the
      list. The last folder's line in 1 and the Outbox in 9 could not be
      done. Changed a fourth time for both: 5 and 9 rewritten (B-079).*
      *Seen on the test iPad 2026-10-20, the fourth change: every step
      passed. VoiceOver left the row by itself 15 times, each after iPadOS
      moved it about 0.9 s into the move, in each fresh launch and in the
      first move of a session; each time the app put it back 8 to 30 ms
      later and VoiceOver was on the row again within about a second, and
      stayed. 2 held 6 times in a session, 9a in 7 launches, 9b in 4, 9c
      twice. 5b under the search field and under the toolbar, twice each:
      the row came in whole and nothing moved after. The last folder's
      line in 1 and the Outbox in 9 could not be done: no label and no
      letter waiting on this account (B-079).*
- [x] **B-080, every folder's conversation rows as Mail's.** On the test
      iPad, three panes, Organize by Thread on, the test account only,
      every letter to the account itself: "Jane's address" is its
      address with `+jane` before the `@`, typed `Jane Example <` the
      address `>`. Subjects beginning "B-080". Send nothing else.
      1. *A single letter.* A new letter To Jane's address, Subject
      "B-080 one", Send, Refresh. The Inbox: its row reads the account's
      name, then the time at the right edge, with no mark and no count.
      2. *A conversation.* Open "B-080 one", Reply, Send. Open the
      conversation again, Reply, Send. Refresh. The Inbox: the row reads
      the account's name, then the time, then a blue chevron in a circle
      at the right edge, and no "(3)". The names and the subject are
      where the row below has them, and the mark ends where a plain
      row's time ends. Tap the row: the conversation opens in the
      reading pane, as before.
      3. *Other folders.* Sent Mail: "Jane Example", the time, the mark,
      no count, as B-075 has it. All Mail: as the Inbox. Trash, Spam,
      Important, Starred or a folder of his: any conversation there has
      the mark after the time and no count, and a single letter neither.
      4. *Edit.* In the Inbox, Edit: the mark stays after the time, the
      names a little shorter. Done.
      5. *A search.* Search "B-080", Current Mailbox, then All Mailboxes:
      a row for each letter, the account's name, no mark, no count.
      Cancel.
      6. *VoiceOver* on, in the Inbox, touch the row of 3: the account's
      name, "3 messages", "Re: B-080 one", the time. VoiceOver off.
      7. *A long name.* Settings: the name "Carlo Wolfeschlegelsteinhausen
      Example" in place of the account's, Save. Quit the app in the app
      switcher and open it again: in the simulator the next reply went
      out under the old name until then. Reply to "B-080 one" again,
      Send, Refresh. The Inbox: the names cut with "…" before the time,
      then the mark, all on the line. Edit: the same, cut shorter.
      Done. Settings: the account's own name back, Save.
      8. *A Wednesday*, on a Friday to a Tuesday, so on another day if
      need be. In any folder, Trash too, a conversation whose newest
      letter came on the Wednesday before: the row reads "Wednesday",
      then the mark. Edit: the whole word "Wednesday" before the mark,
      never "Wednes…", the names a few points shorter than on a single
      letter's row. Done.
      Then move the B-080 letters to Trash.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator, every letter to the
      account's own address with a tag, not Jane's: each step as above,
      VoiceOver read from the accessibility tree; Spam, Important and
      Starred not opened. Step 8 with the app's clock moved two days
      ahead, to a Friday: in Trash, in Edit, "Wednesday" whole before the
      mark (B-080).*
      *Seen on the test iPad 2026-10-19: 1 to 7 passed (B-080). In 6 a
      touch went to the app, so VoiceOver was put on the row by B-079's
      move; in 7 the app was ended and opened again, as the swipe into the
      app switcher could not be sent. 8 could not be done: no letter in
      any folder had come on the Wednesday before. The suite holds it.
      Seen in passing: in Trash a conversation's row stood for its oldest
      letter, now B-084.*
- [x] **B-081, a To ending in ";".** On the test iPad, the test account
      only, landscape, the on-screen keyboard, built from the
      `stray-semicolon` worktree. It is the send path: merge only after a
      pass. A stands for the account's address; letters only to A with a
      `+` tag before the @, subjects beginning "B-081". The ";" is on the
      keyboard's .?123 side.
      0. *Before installing,* on the iPad's build as it is. A new letter,
      To A with `+jane`, then ";" and ",", then A with `+sam` and ",";
      Subject "B-081 old book", Send: it goes to `+sam` alone. Type
      `+ja` in a new letter's To: two rows for `+jane`, one with ";".
      Cancel, Delete Draft. Another, To "undisclosed-recipients:;" and
      ",", Bcc A with `+sam`, Subject "B-081 empty group", Cancel, Save
      Draft. Then install.
      1. *Typed.* A new letter. In To type A with `+jane`, then ";": a
      bubble at once, with the address on it, and nothing typed after it.
      Type ";", a space, ";": nothing. Subject "B-081 semicolon", Send. The
      sheet closes, with no "Message was not sent." It arrives once;
      Gmail's Show original has `To:` the address alone, no ";".
      2. *Two.* A new letter. In To type A with `+jane`, ";", A with
      `+sam`, ";": two bubbles. Subject "B-081 two", Send. It arrives
      once, To both, joined by a comma.
      3. *A ";" alone.* A new letter. In To type ";": nothing, and Send
      stays grey. Cancel.
      4. *A draft.* A new letter, To A with `+jane` and ";", Subject "B-081
      draft", Cancel, Save Draft. Drafts: its row names the address. Open
      it: one bubble. Send: it arrives once, and Drafts no longer has it.
      5. *Reply All.* Open "B-081 two" in the Inbox, Reply All: To `+jane`
      and `+sam`, a bubble each (his own letter, answered to its To).
      Cancel.
      6. *The share sheet,* from Safari. In To type A with `+sam` and ";":
      a bubble. Subject "B-081 share", Send. It arrives once, To `+sam`.
      7. *The old book.* A new letter, `+ja` in To: one row for `+jane`,
      no ";". Tap it: a bubble. Type `+ja` again: no rows. Cancel, Delete
      Draft. The same in the share sheet from Safari, then Cancel.
      8. *The empty group.* Drafts, open "B-081 empty group": one bubble,
      "undisclosed-recipients:;", whole. Send: it arrives once at `+sam`;
      Show original has `To: undisclosed-recipients:;`; the connection log
      has one RCPT TO, `+sam`'s, and none for the group.
      Then move the B-081 letters to Trash.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: steps 1 to 6 passed,
      with a hardware keyboard and `+sim18` in 1, 4 and 6; 0, 7 and 8
      passed on a simulated iPad built from master, then given this build
      (B-081).*
      *Seen on the test iPad 2026-10-19, the on-screen keyboard: 1 to 8
      passed. 0 was not run: this build was already installed, and the
      book had no entry with a ";". So 7 ran on a clean book, and 8 on a
      draft this build made: one RCPT TO, `+sam`'s, none for the group
      (B-081).*
- [x] **B-082, a name changed in Settings, at once.** On the test iPad,
      the test account only, landscape, built from the `account-name`
      worktree. It is the send path: merge only after a pass. A stands for
      the account's address; letters only to A with a `+` tag before the
      @, subjects beginning "B-082". Note the account's name in Settings
      first: it goes back at the end. Do not quit the app at any step.
      1. *Before.* A new letter To A with `+sim18`, Subject "B-082
      before", Send. Show original in Gmail: From the account's name.
      2. *Save.* Settings, the name "Carlo Wolfeschlegelsteinhausen
      Example" in place of the account's, Save. The list stays where it
      was.
      3. *Reply.* Refresh, open "B-082 before", Reply, a line, Send. Show
      original: From "Carlo Wolfeschlegelsteinhausen Example".
      4. *A new letter,* To A with `+sim18`, Subject "B-082 new after",
      Send: From the new name.
      5. *A draft.* A new letter, To A with `+sim18`, Subject "B-082 draft
      after", Cancel, Save Draft. Gmail's Drafts, Show original: From the
      new name. Then in Blackmail open it from Drafts and Send: From the
      new name.
      6. *The book.* A new letter, type the first letters of A in To: A
      is offered as "Carlo Wolfeschlegelsteinhausen Example". Cancel,
      Delete Draft.
      7. *The signature,* only where Settings shows both "Send my
      signature as plain text instead" and "Restore Original Signature":
      without the second, the formatted one would not come back. Restore
      puts back the signature first kept on this iPad, not the one in
      use, and a formatted one lost so cannot be put back from Settings.
      So first: Settings, "Restore Original Signature", Restore, look at
      the box, then Cancel. If its words changed, or a formatted
      signature has been put on this iPad from outside since, skip 7.
      Otherwise: Settings, "Send my signature as plain text instead",
      Save. A new letter To A with `+sim18`, Subject "B-082 plain", Send:
      Show original has no text/html part. Settings, "Restore Original
      Signature", Save. Another, "B-082 restored", Send: the formatted
      signature is back.
      8. *The share sheet,* from Safari. To A with `+sim18`, Subject "B-082
      share", Send: From the new name.
      9. *Put back.* Settings, the account's own name as noted, Save. A new
      letter To A with `+sim18`, Subject "B-082 name back", Send: From the
      account's own name. A offered under it again.
      Then move the B-082 letters to Trash.
      *Seen 2026-10-07 on the iPadOS 18.6 simulator: steps 1 to 6, 8 and
      9 passed, the account named "Carlo" and with no signature, so 7 was
      not tried (B-082).*
      *Seen on the test iPad 2026-10-19, with `+ipad` for `+sim18`: all
      nine steps passed, 7 included, the formatted signature gone from
      the plain letter and back, byte for byte, in the restored one. The
      app was never quit (B-082).*
- [x] **B-083, an Outbox letter goes as it was sent.** On the test iPad,
      the test account only, landscape, built from the `outbox-name`
      worktree. It is the send path: merge only after a pass. A stands
      for the account's address; letters only to A with `+jane` before
      the @, subjects beginning "B-083". *Steps for a person at the iPad:*
      the iPad is reached for checks over its Wi-Fi, and Airplane Mode
      cuts that, so these are done by hand, and the iPad's Wi-Fi is on
      again before anyone reaches it from elsewhere. They can also be done
      with the iPad on its cable, which Airplane Mode does not cut, as on
      2026-10-19; then too its Wi-Fi is on again at the end. Note the
      account's name in Blackmail's Settings first: it goes back at the
      end.
      1. *Queued.* The iPad's Settings, Airplane Mode on, and Wi-Fi off
      if it stays on. Blackmail, a new letter To A with `+jane`, Subject
      "B-083 queued", Send. Note the time on the iPad's clock. The sheet
      closes at once: "Message is in the Outbox. It will be sent when the
      iPad is connected and Blackmail is open." The Outbox lists it.
      2. *Renamed.* Blackmail's Settings, the name "Carlo Renamed
      Example", Save.
      3. *Back.* Wait two minutes. Airplane Mode off, Wi-Fi on, and wait
      for its mark in the status bar. Blackmail, Refresh: the Outbox
      empties.
      4. *Show original* of "B-083 queued" in Gmail: From the account's
      name as noted, not "Carlo Renamed Example"; Date the time noted in
      1, minutes before the time Gmail received it. One copy.
      5. *After.* A new letter To A with `+jane`, "B-083 after", Send:
      From "Carlo Renamed Example", Date its own Send.
      6. *Opened and sent again.* Airplane Mode on. A new letter, "B-083
      reopen", Send: in the Outbox. Settings, the account's own name as
      noted, Save. The Outbox, open "B-083 reopen", Send again, and note
      the time: in the Outbox once more. Airplane Mode off, Wi-Fi on,
      Refresh. Show original: From "Carlo Renamed Example", its name when
      it was first sent; Date the second Send. One copy.
      7. *The signature,* only where Settings shows both "Send my
      signature as plain text instead" and "Restore Original Signature",
      and only after the check B-082's step 7 asks for first. Airplane
      Mode on. A new letter, "B-083 signed", Send: in the Outbox.
      Settings, "Send my signature as plain text instead", Save. Airplane
      Mode off, Wi-Fi on, Refresh. Show original: a text/html part with
      the formatted signature, as when it was sent. Settings, "Restore
      Original Signature", Save.
      8. *Put back.* The account's name is as noted (6). The iPad's Wi-Fi
      is on. Move the B-083 letters to Trash.
      *Seen 2026-10-09 on the iPadOS 18.6 simulator, the line cut by
      blocking the mail ports: steps 1 to 6 passed, with `+sim18`; the
      account has no signature there, so 7 was not tried (B-083).*
      *Seen on the test iPad 2026-10-19, the iPad on its cable, Airplane
      Mode from Control Centre: all eight steps passed, 7 included
      (B-083). The waiting letter went by itself once the connection was
      back, before Refresh in 3 and 6. Airplane Mode turned Wi-Fi off and
      on with it, and offline each Save in Settings was followed by "Can't
      connect to mail server.", now B-085.*
- [x] **B-084, a conversation's row from its newest letter, wherever its letters came from.**
      On the test iPad, three panes, Organize by Thread on, the test
      account only, landscape, built from the `trash-order` worktree. A
      stands for the account's address; letters only to A with `+jane`
      before the @, subjects beginning "B-084". Wait a minute between
      sends, so each letter has a time of its own.
      1. *A conversation.* A new letter To A with `+jane`, Subject "B-084
      one", the line "The first letter.", Send. Refresh, open it, Reply,
      "The second letter.", Send. Refresh, open the conversation, Reply,
      "The third letter, the newest.", Send. Refresh. The Inbox: the row
      reads the account's name, the third letter's time, the mark, "Re:
      B-084 one", "The third letter, the newest."
      2. *Delete in Edit mode.* Edit, tick that row only, Delete. Trash: the
      row reads the same, the third letter's time, the mark, "Re: B-084
      one", "The third letter, the newest." Tap it: the header "Re: B-084
      one" and the third letter's time. Scroll up: the first letter at the
      top, then the second, then the third, open, at the bottom. On the
      build before, the row read the first letter's time and "B-084 one",
      and the stack ran the third at the top.
      3. *Over IMAP,* if it can be read from another computer: in Trash the
      first letter has the lowest UID of the three and the third the
      highest, and each keeps the INTERNALDATE it had in the Inbox.
      4. *A reply deleted first.* A new letter, "B-084 two", "The letter,
      before its reply.", Send. Refresh, open it, Reply, "The reply,
      deleted first.", Send. Refresh. Tap the conversation's row and, with
      the reply in the pane, tap Delete in the pane: the reply alone goes,
      and the row is "B-084 two" alone. Then Edit, tick it, Delete. Trash:
      its row reads the reply's time, the mark, "Re: B-084 two", "The
      reply, deleted first." Tap it: the letter at the top, the reply at
      the bottom, open.
      5. *After a launch.* Quit the app in the app switcher, open it, and
      tap Trash at once: both rows as in 2 and 4.
      6. *VoiceOver* on, in Trash, touch the "B-084 one" row: the account's
      name, "3 messages", "Re: B-084 one", the third letter's time.
      VoiceOver off.
      The B-084 letters are in Trash already: nothing else to move.
      *Seen 2026-10-19 on the iPadOS 18.6 simulator, with `+sim18`: steps
      1, 2, 4 and 5 passed; 3 was not read, and 6 not tried, as the
      simulator has no VoiceOver (B-084).*
      *Seen on the test iPad 2026-10-19: 1 to 6 passed (B-084). In 5 the
      app was ended and opened again, as the swipe into the app switcher
      could not be sent; in 6 a touch went to the app, so VoiceOver was
      put on the row by B-079's move. Move out of the Inbox in Edit mode
      did the same as Delete: the UIDs in Trash in the order the letters
      came, the row from the newest. B-074's 1, 2, 4 and 7 (7 in Trash,
      on a second try) and B-080's 1 to 4 passed again with it in.*
- [x] **B-085, a save while offline, quietly.** On the test iPad, the
      test account only, landscape, built from the `quiet-save` worktree.
      *Steps for a person at the iPad:* the iPad is reached for checks over
      its Wi-Fi, and Airplane Mode cuts that, so these are done by hand,
      and the iPad's Wi-Fi is on again before anyone reaches it from
      elsewhere. Note the account's name in Blackmail's Settings first: it
      goes back at the end. Leave the signature as it is.
      1. *Offline.* The iPad's Settings, Airplane Mode on, and Wi-Fi off
      if it stays on.
      2. *Nothing changed.* Blackmail's Settings, change nothing, Save.
      Settings closes, and nothing more is said: no alert.
      3. *The name.* Settings, the name "Carlo Renamed Example", Save: no
      alert. Settings again: the new name is there. The name as noted,
      Save: no alert.
      4. *Refresh,* still offline: "Can't connect to mail server.", as
      before, and the line under the list says "No Connection". OK.
      5. *Back.* Airplane Mode off, Wi-Fi on, and wait for its mark in
      the status bar. Refresh: the list comes, with no alert.
      *Not seen on the simulator: its line was not cut for this (B-085).*
      *Seen on the test iPad 2026-10-19, the iPad on its cable, Airplane
      Mode from Control Centre: 1 to 5 passed (B-085). No Save put up an
      alert, with nothing changed, with the new name or with the name put
      back. Refresh offline still said "Can't connect to mail server.",
      and back online the list came. The connection log has nothing from
      Save. Airplane Mode turned Wi-Fi off and on with it.*

- [x] **B-086, the folder he tapped stays highlighted at launch.** On the
      test iPad, three panes, the test account only, built from the
      `sidebar-highlight` worktree. Nothing is sent.
      1. *Early.* Quit Blackmail and open it again. As soon as the folders
      show, before the line under the list says "Updated Just Now", tap
      Trash: Trash's letters come, Trash is highlighted, and it stays
      highlighted when the folders' counts come and after, beside Trash's
      letters. The Inbox is not highlighted.
      2. *The same* with Sent Mail and with All Mail.
      3. *Late.* Quit and open again, wait for "Updated Just Now", tap
      Sent Mail: highlighted, as before.
      4. *Untouched.* Quit and open again and tap nothing: the Inbox is
      highlighted beside its letters, as before.
      *Not seen on the simulator: the iPad's own timing reproduced it
      (B-086).*
      *Seen on the test iPad 2026-10-20: step 1 three times, Trash tapped
      0.4 s after the launch, highlighted to the end each time (B-086).*
- [x] **B-087, Save Draft's row as the sheet goes.** On the test iPad,
      the test account only, landscape, built from the `fix-087-089`
      worktree. A stands for the account's address; drafts only, To A with
      `+jane` before the @, subjects beginning "B-087". Nothing is sent.
      1. *A new letter.* Drafts open in the list. A new letter To A with
      `+jane`, Subject "B-087 one", the line "A new letter.", Cancel, Save
      Draft. As the sheet slides away, "B-087 one" is the top row of
      Drafts, with "On this iPad only" on it; about a second later the
      mark goes, and one row "B-087 one" stays. Refresh: one row.
      2. *A photo.* Tap "B-087 one", Attach Photo, pick one photo, and as
      soon as the picker closes, Cancel, Save Draft. Once the photo is in,
      the row is at the top with its paperclip, one row, and so after the
      save. Refresh: one row, with the paperclip.
      3. *Opened again as it goes.* Tap "B-087 one", add the line "Changed
      at once.", Cancel, Save Draft, and tap its row as soon as the sheet
      has gone. It opens at once, with the new line and no spinner on the
      row; with a spinner the save had landed first: Cancel, and do this
      step again. Add the line "And again.", Cancel, Save Draft. As the
      sheet slides away, "B-087 one" is the top row with "On this iPad
      only", and no second "B-087 one" row without the mark beside it;
      about a second later the mark goes. Refresh: one row, with both
      lines.
      4. *Offline.* Blackmail, Drafts: tap "B-087 one" with the line up,
      as a draft only on Gmail is fetched to be opened. With it open,
      Airplane Mode on from Control Centre, and Wi-Fi off if it stays on.
      Add the line "Changed offline.", Cancel, Save Draft. As the sheet
      slides away the top row is "B-087 one" with "On this iPad only", and
      its old row, without the mark, has gone at once, not some eight
      seconds later. Wait fifteen seconds: still one row, and no alert.
      5. *Opened again at once.* Still offline: tap "B-087 one", add the
      line "Changed again.", Cancel, Save Draft, and tap its row again as
      soon as the sheet has gone. It opens with "Changed again." under
      "Changed offline.". Cancel: it closes without asking, and the row
      is there, one, "On this iPad only".
      6. *Back.* Airplane Mode off, Wi-Fi on, and wait for its mark in the
      status bar. Refresh: one row "B-087 one", without the mark, with
      every line added.
      7. *Put back.* Edit, tick "B-087 one", Delete.
      *On the build before, 4 left the old row for some eight seconds,
      in 1 there was no row until the save had landed, and in 3 the row
      tapped was the old copy's. On the first build of this fix, 3's
      second Save Draft listed two rows for about a second.*
      *Seen on the test iPad 2026-10-20, the iPad on its cable: 1 to 7
      passed (B-087), 4 in the order it has now, since a draft only on
      Gmail did not open offline. In 1 the mark went 1.8 s after the sheet;
      in 2 the photo was in before Cancel could be tapped, so a photo still
      coming in was not seen; in 3 the row was taken at 1.2 s, its save
      still out.*
- [ ] **B-088, a forward's original looked for in All Mail once, however
      many files it carries.** On the test iPad, the test account only,
      built from the `fix-087-089` worktree. A stands for the account's
      address; letters only to A with `+b088` before the @, subjects
      beginning "B-088". The store is edited as in B-051's check, with the
      app ended; Wi-Fi off cuts the line the iPad is reached by, so that
      step is done on its cable or by hand.
      1. *The original.* A new letter To A with `+b088`, Subject "B-088
      three", three photos from the iPad's library, Send. Refresh: it is in
      the Inbox with its three photos.
      2. *The forward, offline.* Open it, Forward, To A with `+b088fwd`.
      Wi-Fi off, Send: it waits in the Outbox. End the app.
      3. *Its UID another letter's.* In the forward's `letter.json`, every
      `"messageID":"1\/U"`, one for each photo and all the same U: write U
      one lower, which is another letter's UID or none.
      4. *Back.* Wi-Fi on, open the app: the forward goes by itself after
      the Inbox's first page. The connection log, before the first photo
      only: `CARRIED-PART folder=INBOX reason=another-letter` (or
      `reason=gone`), then one `UID SEARCH X-GM-MSGID …` in
      `[Gmail]/All Mail`. Then for each photo the FETCH that describes the
      letter and its `BODY.PEEK[n]`, both at the UID that search gave, and
      `CARRIED-PART found folder=[Gmail]/All Mail`. On the build before,
      the search went before each photo, three times.
      5. *Arrived.* Refresh: "Fwd: B-088 three" to `+b088fwd`, with the
      three photos as in the original.
      6. *The original archived instead.* Open "B-088 three" again,
      Forward, To A with `+b088fwd`, Wi-Fi off, Send: the Outbox. End the
      app, and open it with Wi-Fi still off: "Can't connect to mail
      server.", OK. Edit, tick "B-088 three". Wi-Fi on, and at once Move,
      All Mail: the app's Move to All Mail is Gmail's archive. Move lists
      the folders only with the line up, and with no page the forward waits
      for the watch's first check with the line up, within 30 s, so the
      archive goes first. No edit of the store.
      7. *Back.* The forward goes by itself. The log: one `UID FETCH` at
      the original's Inbox UID, answered with nothing, and
      `CARRIED-PART folder=INBOX reason=gone`, before the first photo only;
      one `UID SEARCH X-GM-MSGID …`; then for each photo the two FETCHes at
      the UID that search gave, and between the photos no `SELECT` unless
      the Inbox's previews came between them. On the build before, each
      photo had its own FETCH at that Inbox UID and its own search, and
      each after the first a `SELECT "INBOX"` and a
      `SELECT "[Gmail]/All Mail"` too.
      8. *Arrived.* A second "Fwd: B-088 three", with the three photos.
      9. *Put back.* Move the B-088 letters to Trash, the original from
      All Mail.
      *Not tried on the simulator: the host tests count the searches and
      the SELECTs over the scripted server (B-088).*
      *Seen on the test iPad 2026-10-20, the iPad on its cable: 1, 2 and 5
      to 9 passed (B-088), 6 with the app's Move to All Mail. Still to do:
      3, and with it 4's log, as editing the store waits to be agreed.
      Without the edit, 4 went from the original's own UID, no search. In 7
      one search, then the four parts, the quoted signature's picture and
      the three photos, from the UID it gave.*


- [x] **B-089, a letter read from its All Mailboxes hit is read in the
      Inbox.** On the test iPad, the test account only, built from the
      `fix-087-089` worktree; the `readdot` one has neither step 6 nor 7.
      A stands for the account's address; letters only to A with `+b089`
      before the @, subjects beginning "B-089".
      Do not open All Mail during these steps: a hit on its kept page
      was right before.
      1. *Two letters.* A new letter To A with `+b089`, Subject "B-089
      one", Send; another, Subject "B-089 two", Send. Refresh: both in
      the Inbox with the dot. One without it: Edit, tick it, Mark, Mark
      as Unread. Note the Inbox's count.
      2. *Read from a hit.* Search "B-089 one", All Mailboxes. Tap the
      hit: its dot goes, and the Inbox's count goes down by one. Cancel
      the search: the Inbox's "B-089 one" row has no dot. Tap it: the
      count stays where it is, not one lower again.
      3. *Mark from a hit.* Search "B-089 one", All Mailboxes, Edit, tick
      the hit, Mark, Mark as Unread: the dot on the hit, the count up by
      one. Cancel: the Inbox's row has its dot. Tap it: no dot, the count
      down by one, back where step 2 left it. Edit, tick it, Mark, Mark
      as Unread: the count up by one. Search again, Edit, tick the hit,
      Mark, Mark as Read, Cancel: no dot, and the count down by one, back
      where step 2 left it again.
      4. *Flag from a hit,* as before: search "B-089 one", All Mailboxes,
      tap the hit, Flag, Cancel: the Inbox's row flagged. Tap it, Flag
      again: not flagged.
      5. *The kept copy.* "B-089 two" still has its dot. Search "B-089
      two", All Mailboxes, tap the hit: its dot goes. Leave the search
      showing, go to the Home Screen, and end Blackmail from the app
      switcher. Airplane Mode on, from Control Centre. Open Blackmail:
      "Can't connect to mail server.", OK; the Inbox is the one kept on
      the iPad, and "B-089 two" has no dot. Airplane Mode off, Refresh:
      still no dot, and the count as after the tap.
      6. *News held.* Scroll the Inbox down a screen or more, and stay
      there. A new letter To A with `+b089`, Subject "B-089 three", Send.
      Wait a minute, still scrolled down. Search "B-089 three", All
      Mailboxes, tap the hit: its dot goes, the count down by one.
      Cancel, scroll to the top: "B-089 three" comes on at the top with
      no dot. Tap it: the count stays.
      7. *Binned from a hit.* Search "B-089 two", All Mailboxes, tap the
      hit, Delete. Cancel: no "B-089 two" row. Go to the Home Screen and
      end Blackmail from the app switcher. Airplane Mode on, open
      Blackmail: "Can't connect to mail server.", OK; the kept Inbox has
      no "B-089 two" row. Airplane Mode off.
      8. *Put back.* Edit, tick the B-089 rows left, Delete.
      *Seen on the test iPad 2026-10-20: 1 to 8 passed (B-089). In 5 and 7
      the app was ended once the Home Screen was up, the swipe into the app
      switcher not made. In 5 the Inbox's kept row was read with All Mail's
      kept page not holding the letter. Seen in passing: "B-089 three",
      come while scrolled down, was not on the Inbox's kept page, so 7's
      offline launch drew the Inbox without it until Refresh, as D-016 has
      it; and the reading pane's Flag looked the same flagged and not.*
- [x] **B-090, a screenshot shared from its editor is attached.** On the
      test iPad, the test account only. Build the IPA from the `shot-share`
      worktree with `tools/build-share-ipa.sh` and install it through
      TrollStore's helper, never by the deploy that copies files into the
      bundle; then `killall BlackmailShare` on the iPad, and open the app
      once, as the share sheet's checks say. A stands for the account's
      address; letters only to A with `+jane` before the @, subjects
      beginning "B-090".
      1. *One.* Take a screenshot, tap its floating thumbnail within a
      second, Share, Blackmail. The sheet shows the letter, "image0.png"
      (or "image0.jpeg") listed with its size, and no line saying a photo
      could not be attached. To A with `+jane`, Subject "B-090 one", Send:
      the sheet closes, and the letter arrives with image0.png, the screen
      as it was, upright. Listed under another name, the picture had one
      from iOS: send it all the same, and read its name in 3.
      2. *Two.* Take two screenshots, tap the second's thumbnail, so the
      editor holds both; Share, Blackmail: image0.png and image1.png
      listed, or iOS's names as in 1, and no line. To A with `+jane`,
      Subject "B-090 two", Send: both arrive, each the screen it was.
      3. *The log.* Read the two newest `blackmail-send-*.txt` in the share
      extension's own tmp, each from its last `SHARE-BEGIN` on. For each
      picture of 1 and 2 a `SHARE-PICTURE` line: copy down its `offered=`
      and its `read=`, which says the way the editor's picture came, a
      type after the first, `object` or `item`, which B-090 did not know;
      `item (public.png inside)` where the item was a file or bytes. Its
      `way=` is `copied whole`, `own bytes, metadata replaced`, `JPEG at
      factor F, N MB available`, or `PNG made of the object, N MB
      available` (or `JPEG`), N a number. Its `name=` is `none
      "image0.png"`, the next `image1`. If it says `name=suggested` or
      `name=file "{N chars}.png"`, iOS made a name up: read it from the
      letter that arrived and note it, as share check 7 does; it decides
      whether such names count as none. If either share still says a
      photo could not be attached, there is no Send: Cancel, and read
      `blackmail-send-<time>-left-out.txt` instead, written as its sheet
      came up, and copy its lines down: the last in each `read=` is the
      way that decided, and its `way=` says why it gave nothing.
      4. *From Photos, as before.* A full-size camera photo shared from
      Photos alone, To A with `+jane`, Subject "B-090 three", Send. Its
      line `read=public.jpeg`, with no type before it, `name=file
      "IMG_NNNN.JPG"`, `way=own bytes, metadata replaced`; it arrives
      under that name at the size it was taken, as in the share sheet's
      check 1.
      5. *Put back.* The B-090 letters to Trash.
      *Seen on the test iPad 2026-10-20, a build of the `shot-share`
      worktree (9780fe4): 1 to 5 passed (B-090), 4 with IMG_0776, the
      48-megapixel JPEG, the test iPad's camera photos being HEIC. The
      editor offered `public.image` alone, and its own item was the
      `UIImage`: `read=public.image,item`, `way=PNG made of the object`.
      The pictures went under the name iOS gave them, "View recent
      photos.png", two under the same name, not image0.png and image1.png;
      whether such a name counts as none is not yet decided. 1 and 2
      looked for image0.png: the editor named each screenshot, so 2 now
      takes iOS's names as 1 did. Each arrived as image/png, the screen as
      it was, upright, with no location.*

- [x] **B-091, Flag with Airplane Mode on.** On the test iPad, the test
      account only, built from the `no-path` worktree. A stands for the
      account's address; letters only to A with `+b091` before the @,
      subjects beginning "B-091". Airplane Mode from Control Centre; if it
      leaves Wi-Fi on, turn Wi-Fi off too. Times from the iPad's clock.
      1. *Two letters.* A new letter To A with `+b091`, Subject "B-091
      one", Send; another, Subject "B-091 two", Send. Refresh: both in
      the Inbox.
      2. *Flag, the connection open.* Open "B-091 one" in the reading
      pane, and within a minute Airplane Mode on. Five seconds later, Flag
      in the pane, and straight after it tap "B-091 two". Within about a
      second: the flag off again (it may never show at all), one "Can't
      connect to mail server.", and no "Loading…" waiting. A tap that lands
      before the alert opens "B-091 two", which says it could not be
      downloaded; the alert can come first, and then takes the tap, and
      nothing opens. On the build before, the flag stayed 19 s. OK.
      3. *A letter, the connection open.* Airplane Mode off, and wait for
      the connection to come back (the watch's LOGIN in the log, within
      half a minute). Open "B-091 one", and within a minute Airplane Mode
      on again. Five seconds later tap "B-091 two": at once, the pane
      says it could not be downloaded.
      4. *Back.* Airplane Mode off. Open "B-091 one", Flag in the pane:
      the flag stays, and after a Refresh too. Flag again: off.
      5. *The log.* Settings, the connection log. Only `LINK port=993`
      lines are the mail's connection; `port=465` is a Send's. For 2,
      `LINK port=993 viable=false` within a second or two of Airplane
      Mode going on, then at the Flag `NO-PATH UID STORE nothing-sent`,
      and nothing written, no `UID STORE` and no `UID FETCH`, until the
      LOGIN after Airplane Mode went off. For 3, `LINK port=993
      viable=false`, then `NO-PATH UID FETCH not-sent`. Either may have
      `NO-PATH NOOP not-sent` in its place, if the watch's check came
      first: then the tap found no connection, and was refused at once
      all the same. For 4, one LOGIN, then one `UID STORE …
      +FLAGS.SILENT (\Flagged)` and one `-FLAGS.SILENT`, each once and
      each answered OK. If the watch's NOOP was written just before `LINK
      port=993 viable=false`, the Flag waits behind it as before (B-091,
      Not covered): do 2 again. If there is no `LINK port=993
      viable=false` at all, iPadOS did not say the network had gone and
      the fix does nothing on this iPad: note how long 2 took, and stop
      there.
      6. *Put back.* Edit, tick the B-091 letters, Delete. Airplane Mode
      off, Wi-Fi on.
      *Not tried on the simulator: the host tests run it over the
      scripted server, its no-path model standing in for the iPad's
      (B-091).*
      *Seen on the test iPad 2026-10-20, a build of master with B-090 and
      B-091 (cba64fa), the iPad on its cable: 1 to 6 passed (B-091), 2
      twice, but for its tap on "B-091 two" landing before the alert,
      which could not be made here. iPadOS said the link had no network
      0.32 to 0.34 s after Airplane Mode went on, each of three times. The
      Flag was refused within about 0.2 s with one alert, drawn for a
      frame or not at all. In 2 the alert was up before the tap on
      "B-091 two" could land, a tap taking some 0.1 s here, and took it
      both times, so 2 now says so; a letter tapped offline said so at
      once in 3, at 0.19 s, the watch's check having gone first with
      `NO-PATH NOOP not-sent`. Back online, one STORE each way.*

- [x] **B-092, a MOVE Gmail answers OK for without moving the letter.**
      On the test iPad, the test account only, built from the
      `hollow-move` worktree. Gmail answered so once in about 116 MOVEs
      and it cannot be made to happen on demand, so the check is that
      normal Deletes and Moves still send one command each and the log
      has no `MOVE-HOLLOW` line; the hollow answer itself, and what the
      app does with it, is pinned by the host tests (B-092). A stands
      for the account's address; letters only to A with `+b092` before
      the @, subjects beginning "B-092".
      1. *Three letters.* Three new letters To A with `+b092`, Subjects
      "B-092 one", "B-092 two" and "B-092 three", Send each. Refresh:
      all three in the Inbox.
      2. *Edit mode.* Edit, tick the three, Delete: the rows go at the
      tap and stay gone, and after a Refresh too. Trash holds each once.
      3. *Move and the pane.* In Trash, open "B-092 one", Move, Inbox:
      its row goes. In the Inbox, open it, Delete in the pane: gone, and
      in Trash once.
      4. *Out of All Mail.* In Trash, open "B-092 two", Move, All Mail:
      its row goes. In All Mail, open it, Move, Inbox: its row stays,
      and a Refresh of the Inbox shows it there. In the Inbox, open it,
      Delete in the pane: gone, and in Trash once.
      5. *The log.* Settings, the connection log. Each Delete and Move
      is one `UID MOVE`, answered with an EXPUNGE and `OK [COPYUID …]`
      with no 0 among its numbers, and no `MOVE-HOLLOW` or
      `MOVE-CHECKED` line anywhere. The Move out of All Mail has no
      EXPUNGE, the letter staying there: note whether its answer has a
      COPYUID. One with none is a `MOVE-HOLLOW … copyuid=none
      no-expunge` line, then `UID FETCH n (X-GM-LABELS)` and
      `MOVE-CHECKED … labelled`, which is Gmail not saying, not a
      fault: copy it down. Any other `MOVE-HOLLOW` line is Gmail
      answering so again: copy it down, with the commands and
      `MOVE-CHECKED` lines after it (a NOOP, `UID SEARCH UID n`,
      perhaps the MOVE again), and whether the row stayed off with the
      letter once in Trash, or came back with "Can't connect to mail
      server." with the letter where it was.
      6. *Put back.* Nothing: the B-092 letters are in Trash.
      *Not tried on the simulator: the host tests run it over the
      scripted server, whose hollow answer is the iPad's (B-092).*
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): each Delete and Move was its one `UID MOVE`, answered
      `OK [COPYUID …]` with no 0, and no check after it (B-092). The
      letters went from the Inbox: one deleted in the pane, one moved to
      All Mail from the pane's Move sheet, one deleted in Edit mode, and
      the moved one sent from All Mail back to the Inbox, its row
      staying, and deleted there. Every other row went at the tap and
      stayed gone, and Trash held each letter once. The Move out of All
      Mail had no EXPUNGE and a COPYUID, as on 2026-10-20, so no
      `MOVE-HOLLOW` line. Letters moved out of the Trash that morning in
      B-042's checks were each in the Inbox once. In one of those checks
      the hollow answer came, to a Delete from All Mail:
      `OK [COPYUID 2 173 0]` with no EXPUNGE, then
      `MOVE-HOLLOW … copyuid=dest-0 no-expunge`, the NOOP and
      `UID SEARCH UID 173` finding the letter there,
      `MOVE-CHECKED … there sending-again`, the second MOVE answered with
      an EXPUNGE and a COPYUID, and `MOVE-CHECKED … moved`, 1.07 s from
      the first MOVE. The row stayed off with no alert, and Trash held
      one copy.*

- [ ] **B-093, a Delete in the pane with the letter's row just above the
      list.** On the test iPad, the test account only, built from the
      `list-place2` worktree. Three panes. W stands for a letter of the
      test account's, read, alone in its conversation, in the Inbox and so
      in All Mail. Times from the iPad's clock.
      1. *Just above the list.* All Mail, Go to Date, Current Mailbox, a
      day some weeks back with W a few rows below the day. Open W in the
      reading pane. Drag the list slowly upwards until W's row has gone
      just above the top of the list, hidden under the search field, with
      the row above it under the status and navigation bars, nothing of
      W's row showing below the search field, and the first row in view
      whole below it. With a point or more of W's row showing, W's row is
      the top row in view, and the rows below close up into it, as in
      step 2. A screenshot. Delete in the pane, with a burst of shots
      from the tap: in the first, at about a
      quarter of a second, and in every one after it, each row in view is
      where it was in the shot before, the same letters at the same
      heights. On the build before, every row in view went up one row at
      once (B-093). The log has one `UID MOVE` and no list FETCH.
      2. *The top row in view.* Put W back (step 4) and open it in All Mail
      again. Drag the list until its row is the top row in view, whole
      below the search field, nothing of the row above showing. A
      screenshot. Delete in the pane, with a burst: W's row goes, and the
      rows below it close up into its place, each up one row, as in Mail;
      the row that was above it stays out of sight under the search field,
      and the list does not scroll. Put W back, and again with a point or
      two of the row above showing below the search field: the same. On
      the build before, the rows below came up one as well.
      3. *Search and the page above.* The Inbox three screens down, Search,
      type a word that finds letters, scroll the results, Cancel: the
      Inbox back with the same rows at the same heights. Then All Mail, Go
      to Date to the same day, scroll up slowly until the page above
      comes: the rows move only with the finger, and the highlight stays
      on the letter open in the pane.
      4. *Put back.* After each Delete: Trash, open W, Move, Inbox.
      5. *Refused.* W the top row in view as in step 2, a screenshot.
      Airplane Mode on, Delete in the pane, with a burst, the list not
      touched: W's row goes and the rows below close up, as in step 2;
      with the alert, "Can't connect to mail server.", W's row is back
      where it was, the rows below it down one, every row as in the
      screenshot. OK. Then the same with W just above the list as in
      step 1: back out of sight, nothing in view moving either time.
      Airplane Mode off.
      *Not tried on the simulator: the host tests hold it, the list laid
      out as on the iPad (B-093).*

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
- [x] **Mail's conversation stack default** — thirty seconds on an iPhone;
      newest-first is currently a guess, not a copy
      *Decided 2026-10-06 by the owner: "copy apple mail for these". Built,
      seen in the simulator and on the iPad 2026-10-07: oldest at the top
      and newest at the bottom, the read letters closed, the unread ones
      open with the newest and marked read at the tap, the pane opening at
      the oldest letter he has not read, or at the newest when he has read
      the rest, and a letter that comes put in at the bottom (B-074).*
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
- [x] **A conversation's count in Sent Mail** — the row's top line holds
      some 168 points in three panes and 213 in two, and is cut at its
      end, so naming To, Cc and Bcc pushes a conversation's "(2)" past it:
      "Jane Example, Sam Exam…". Accept it, as the Inbox already does with
      a long list of who wrote (built); name To alone, which shortens
      the line; or put the count
      first, or fit the names to leave it room, either of which changes
      the frozen row (B-060, which puts four more questions about these
      rows)
      *Decided 2026-10-06: "copy apple mail for these", for this and
      B-060's other four. Built (B-075), seen in the simulator and on the
      iPad 2026-10-07, its VoiceOver 2026-10-19: in Sent Mail, Drafts and
      the Outbox the To alone, one person whole, two or more by short
      names joined "Jane & Sam", no count, and Mail's blue chevron in a
      circle after the date on a conversation. "No Recipients" kept. His
      addresses are the ones B-076's Settings list holds, as written, as
      Mail's are. The Inbox and the other folders keep their "(2)", to be
      asked about separately.*
- [x] **The count on the Inbox's rows** (B-075) — every folder but Sent
      Mail, Drafts and the Outbox ends a conversation's names with
      "(2)", cut off with them under a long list of who wrote. Mail has
      no count on any row: its blue chevron in a circle after the date
      marks a conversation everywhere. Keep the count (built), or the
      mark there too.
      *Decided 2026-10-07 by the owner: the mark there too, as Mail.
      Built as B-080, seen in the simulator and on the iPad 2026-10-19 but
      for a Wednesday: no count on any row, the blue chevron in a circle
      after the date on a conversation's row in every folder, and
      VoiceOver saying how many.*
- [x] **Reply's addressing** (B-061) — built as Mail is believed to do it,
      none of it checked against Mail on an iPad. Reply All to a letter
      with a Reply-To goes to the Reply-To in place of the From, or to
      both; the composer's To shows "Jane Example <jane@example.com>", or
      the address alone as before; Reply All keeps the letter's To in To
      and its Cc in Cc, or puts everyone in Cc as before; a Cc left alone
      moves up to To, or the reply goes with no To; his own letter's
      Reply-To is not followed, or it is.
      *Ruled 2026-10-06: "copy apple mail". Built (B-076): Reply All has
      the Reply-To, or the From, alone in To, and everyone else in Cc, the
      letter's To then its Cc; nobody moves up to To on anyone else's
      letter; the Reply-To in place of the From. To, Cc and Bcc show a
      bubble with each person's name, in the composer and the share sheet,
      and the header names them as before. His own letter: as built, its
      Reply-To not followed and its Reply All as before, since what Mail
      does there could not be found out.*
- [x] **The view button's motion** (B-066) — built as pictures of the
      columns sliding 0.4 s and settling 0.2 s, the list sliding over
      the folders from three to two and off them from two to three. Keep
      it; another timing; or later Mail's way, where the folders slide off
      to the left. From two panes with the folders in front, their column
      draws in and the list is there in the middle, which Mail never did;
      keep it, or a plain 0.3 s fade for that switch alone.
      *Decided 2026-10-06: "copy apple mail for these". Built, seen on the
      iPad 2026-10-07: one half-second motion on UIKit's spring, no
      settle; the list over the folders, which go at half its speed and
      darken; Reduce Motion changes nothing, as in Mail. The folders in
      front keep their drawing in, as Mail has no such switch. The three
      panes stay side by side. B-077.*
- [x] **"< Mailboxes" and a folder tap in two panes** (B-066) — instant,
      as they have always been, and as built. Or a slide, as Mail's
      navigation pushes and pops, about 0.35 s.
      *Decided 2026-10-06: "copy apple mail for these". Built, seen on the
      iPad 2026-10-07, and VoiceOver's place after them under B-079 on
      2026-10-20: a push and a pop, the panes on the same half-second
      spring, the bar's titles over 0.35 s; with Prefer Cross-Fade
      Transitions a half-second fade. B-077.*
- [x] **His second address** (B-061) — Gmail sends as it and delivers it
      to him, and the app cannot tell it is his, so a Reply All to a
      letter that names it sends it a copy, which comes back to his Inbox.
      Leave it; or a line in Settings where his other addresses are
      written once, as Mail's account has them under its Email; or the
      From addresses of Sent Mail taken as his at sign-in, which would
      take a stranger for him if a letter of theirs were ever moved into
      Sent Mail.
      *Ruled 2026-10-06: "copy apple mail". Built (B-076): Settings lists
      his addresses under his account, the account's own first, with "Add
      Another Email…" and a Remove for each added one, as Mail's account
      has them under Email. Reply All leaves every one out, and a letter
      from any is his own. Nothing is added by itself, as in Mail, so his
      second address is to be added on his iPad at the install.*
- [x] **Reply to his own letter sent by Bcc alone** (B-061) — its copy
      in Sent Mail keeps its Bcc header, and Reply answers it to himself,
      as built. Or to its Bcc recipients, in Bcc,
      or in To. Gmail keeps the Bcc on its copy of a letter sent from
      Blackmail too (seen 2026-10-03, B-060), so this is any letter he
      sent to Bcc alone.
      *Ruled 2026-10-06: "copy apple mail". What Mail does could not be
      found out: his mail has no such reply, and nothing published says.
      Kept as built: answered to himself (B-076).*

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

Seen on the test iPad on 2026-10-07, after B-076's check: a letter open
in the reading pane was moved to Trash from another device. Refresh took
its row from the Inbox, and the reading pane went on showing the letter.
That is as B-049 has it: a letter taken out elsewhere comes off the
list, and the pane keeps it. Whether Mail does the same was not looked
into.
