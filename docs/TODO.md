# TODO

One ordered list of what is actually left. Detail lives in
`KNOWN_ISSUES.md` (B-nnn) and `PERFORMANCE.md`; this is the running order.

Last revised 2026-09-22, with the iPad offline.

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
- [ ] **P5. Fix the send path's CPU.** `SMTPClient.dotStuffed:390` (rewrite
      over an unsafe buffer into a preallocated `[UInt8]`, 40-70x) and
      `RFC5322Builder.uniqueBoundary:658` (stop substring-scanning base64
      payloads — `_` is not in the base64 alphabet, so the scan is provably
      vacuous). Both verified byte-identical. Takes a five-photo send from
      ~3.5 s of local CPU to under 50 ms. (B-038 #4a/4b)
- [ ] **P6. Give Send some feedback.** `ComposeViewController.sendTapped:539`
      — today there is no spinner, no disabled button, and the sheet stays
      live and re-pressable through a multi-second upload. (B-038 #4c)
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

- [ ] See B-037 rendered at all: now B-048, below.
- [ ] Confirm the signature's white sheet **in the reading pane** — the
      outgoing half is verified by tests and Chromium renders, but the in-app
      half only applies to letters carrying the new marker, so it needs one
      send.
- [ ] Register and test the share extension — also needs `ideviceinstaller`,
      which is on neither machine. (B-036 blocker 2)
- [ ] Anything else touching the send path.
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
- [ ] **B-046, the signature's logo in a reopened draft.** A new letter,
      Cancel, Save Draft; open Drafts and tap the draft: no attachment row.
      Send it: it arrives with no paperclip in the list and no file row in
      the header, and with the logo in the signature; the connection log's
      `WIRE-PAYLOAD raw=` for it should be about what the same letter sent
      fresh gives, not ten kilobytes more. Then a draft with a photo he
      attached: Save Draft, reopen it, the photo's row is there once; send
      it: it arrives with the photo once, and the logo in the signature.
- [ ] **B-047, "Inbox".** The sidebar's first row and the list's title read
      "Inbox" at launch and after tapping it. The Move sheet says "Inbox"
      too. With VoiceOver on, the first row reads "Inbox, N unread", or
      "Inbox" with nothing unread.
- [ ] **B-048, two panes or three.** Switch the Layout button on in the
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
