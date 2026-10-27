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
- [x] How updates reach him after install; today every fix is a visit.
      *Owner.* *Answered 2026-09-30 by the owner: the install is the last
      step and is never updated, so none reach him (D-004, set and
      forget).*
- [ ] A trial install on an ordinary, non-jailbroken iPad: every install so
      far was an SSH copy onto the jailbroken one. *Owner.*
- [x] Try it against a mailbox his size: Go to Date back to before 2016, an
      All Mailboxes search, ~1,900 Drafts. The test account had 24 letters.
      *Tried 2026-10-23: the test account filled with made-up letters
      APPENDed already read (Inbox 57,209, Sent Mail 24,026, Drafts 1,900,
      All Mail 83,503, 14 labels), and a round on the test iPad, a build of
      int12 (140df65). Launch, scrolling 17 Inbox pages, search in both
      scopes, Drafts, Sent Mail, Complete Threads, Refresh and the watch,
      and the kept copy passed, and Gmail answered every command in under
      5 s. Go to Date failed: every jump landed at the folder's foot, on
      the account's own first letter (B-115, fixed, seen fixed on the
      iPad the same day). Seen there too: Gmail's Important and Starred
      drawn indented among the labels, each as if inside the label above
      it (B-116, fixed, seen fixed the same day). Memory could not be read from the
      app's log. B-115, B-116 and B-117, found there, fixed and seen fixed
      the same day.*
- [ ] Buildable now, for the install-day build:
      - [x] the in-app warning before the 2027-09-18 expiry (D-004 item 3)
            *Done 2026-10-25, not yet seen on the iPad: the day read at
            launch from the app's own profile, the earlier of its expiry
            and its certificate's, never written into the code; in the
            last thirty days, once a day, an alert with OK, never over a
            letter he is writing; nothing with no profile or under
            TrollStore. Its words await the owner's approval ("The new
            words on his screen", below). B-137, and its check under
            "Blocked on the iPad coming back". On the test iPad the same
            day TrollStore was not recognised, the file it leaves beside
            the app hidden by the app's sandbox; fixed that day, TrollStore
            told by the entitlement it adds to the app's own signature,
            read in the shape its signer `ldid` writes as well as Apple's,
            and so read on the host from TrollStore installs pulled from
            the test iPad; not yet seen in the app there.*
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
      - [x] `provision-ipad.sh`: the TrollStore iOS range is wrong (:132 takes
            all of 16.7.x)
            *Done 2026-10-25, not yet run with an iPad on the cable: the
            build read too, and the rule in `tools/trollstore-range.sh`,
            pinned by a host test: 14.0 to 16.6.1, the 16.7 RC (20H18) and
            17.0 in range; 16.7.x, 17.0.1 on and later past; below 14.0
            older. An iOS older than the app's 16.0 stops the script before
            the iPad is registered. B-138, and its check under "Blocked on
            the iPad coming back".*
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
      Another Email…", and Save (B-076; until then a half name in search
      can ask for it, B-123).
- [ ] On the day: his iPad's Settings > Apps > Mail, Privacy Protection
      (Block All Remote Content, shown only with Protect Mail Activity off)
      and Ask Before Deleting, below Messages, matched in Blackmail's
      Settings, the rows B-167 shows (B-168). Off in both, Mail's factory
      value, until set; nothing to build.
- [ ] On the day, with him or his helper: Blackmail's New Message, one
      letter typed in To, and iOS's question about Contacts answered with
      Allow (on iPadOS 18, Continue, then share all of them); then Cancel
      and Delete Draft. Until then the share sheet offers none of his
      Contacts, and he would meet the question alone in the middle of a
      letter, where a Don't Allow is for good and nothing in the app says
      so (B-162).
- [ ] On the day, on his iPad: Settings, Accessibility, Per-App Settings.
      If Mail is listed there with a text size or Bold Text of its own
      (Control Center's Text Size used in Mail puts it there too), Add App,
      Blackmail, and the same values for it; then Blackmail's list, a
      letter and New Message (Cancel) looked at, nothing cut. Nothing else
      to set: Blackmail takes the iPad's own Text Size and Bold Text as
      Mail does (B-166).
- [ ] On the day, his iPad's Settings > Apps > Mail open beside Blackmail's
      Settings, its part called Mail (B-167): each live row set as his
      Mail's page shows it, two minutes. Mail Accounts > Gmail > Account (or
      Account Settings) > Advanced > Move Discarded Messages Into (Deleted
      Mailbox or Archive Mailbox); Message List > Swipe Options > Swipe Left
      and Swipe Right, and Delete or Move Message Action (if his iPad has no
      such row, View Next Message, as Mail before 18.4); Threading >
      Organize by Thread and Complete Threads. A greyed row whose value on
      his iPad differs from Blackmail's (Preview, Show To/Cc Labels,
      Collapse Read Messages, Most Recent Message on Top, and until B-168 is
      merged Ask Before Deleting and Privacy Protection's Block All Remote
      Content) written down for the owner: Blackmail does not have his
      value. Then Blackmail's Settings closed with Cancel, which leaves them
      set.

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
      other apps' links, which iOS may not send it. A letter's `mailto:`
      link was seen opening the composer on the test iPad 2026-10-21, and
      again 2026-10-25 (B-120's check, step 6).*

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
      back".* Phase 2, the last 300 letters he opened. *Done 2026-10-22,
      seen on the iPad the same day: the last 300 letters he opened, at
      most 64 MB and none over 5 MB, kept whole, shown from the iPad at
      once with a connection or without; never a draft or a letter
      Complete Threads brings from Sent Mail; nothing of them sent. B-111,
      and its check under "Blocked on the iPad coming back".*
- [x] Text size: fixed today; Dynamic Type and Bold Text are ignored.
      *Owner decision* (D-007).
      *Ruled 2026-10-26: copy Apple Mail. Built as B-166.*
- [ ] Replied and forwarded arrows on rows. *Shown 2026-10-22, seen on
      the iPad the same day: Mail's grey arrow in the gutter for a letter
      answered or forwarded, from the flags Gmail sends with the row.
      Writing the marks after a reply or forward goes waits for the owner.
      B-102, and its check under "Blocked on the iPad coming back".*
- [x] His own replies missing from Inbox conversations (Mail's Complete
      Threads). *Done 2026-10-22, seen on the iPad the same day; a drop
      under a finger found there fixed and seen fixed the same day: in an
      Inbox conversation of more than one letter, his letters of it that
      are only in Sent Mail come in closed, by date, "Found in Sent Mail"
      when opened, read only and never acted on; a Complete Threads switch
      under Organize by Thread. B-104, and its check under "Blocked on the
      iPad coming back".*
- [x] Search: several words may be searched as one phrase (not yet checked
      against Gmail); no suggestions or recent searches. *Done 2026-10-22,
      seen on the iPad the same day, two faults found there fixed and seen
      fixed the same day: checked against Gmail first (several words
      were already found anywhere, through BODY alone); now each word is
      asked for in From, To, Cc, Subject or the body, as Mail asks, a
      quoted phrase as one, curly quotes too; Mail's three recent searches
      under the field before he types, for 7 days. Suggestions as he types
      are left out: they need an index of the whole mailbox on the iPad,
      which D-016 does not keep. B-105, and its check under "Blocked on
      the iPad coming back".* *Changed 2026-10-24 to copy Apple Mail, not
      yet seen on the iPad: the last word, with no space typed after it
      and three letters or more, also finds the letters from, to or
      copied to up to four people the app already knows whose name or
      address starts with it, so "Marg" finds Margaret's, as Mail's search
      matches the start of words; still no suggestion list, and no
      subject or body found by the start of a word. B-123, and its check
      under "Blocked on the iPad coming back".* *Seen on the test iPad
      2026-10-25, and changed again that day to up to 30 people (B-123).*

**Probably used, smaller:**

- [x] Saving a received photo may crash: no Photos usage description in
      Info.plist. Needs a device check. *Done 2026-10-04, seen on the
      iPad: it did end the app, from "Save to Photos" on a picture in a
      letter; both keys are in, iOS asks, and "Save Image" is offered.
      B-067.*
- [x] Mark as Unread and Move to Junk from the Flag menu. *Mark as
      Unread done 2026-10-22, seen on the iPad the same day: the Flag
      button opens Flag or Unflag and Mark as Unread or Read, as Mail's
      did. Move to Junk ruled 2026-10-26, copy Apple Mail, and on the
      `copy-junk` branch, not yet seen on the iPad: Move to Junk at the
      end of the sheet, and Move to Inbox there inside Junk. B-106, and
      its checks under "Blocked on the iPad coming back".*
- [x] Reply with the original's attachments. *Done 2026-10-22, seen on
      the iPad the same day: a reply carries the original's files as rows
      when he adds someone the original did not go to (Mail's When Adding
      Recipients), shown before it can go; Forward asks Mail's Include or
      Don't Include. B-107, and its check under "Blocked on the iPad
      coming back".*
- [x] Attach documents from Files, and video. *The app's picker is
      unchanged by B-070: photos only, made a JPEG at 0.85. The share
      sheet takes videos since B-070; Send streams them from the disk.*
      *Done 2026-10-22, seen on the iPad the same day: 'Photo Library'
      (photos and videos) and 'Attach File' in the composer, through the
      share sheet's own intake; photos sent as Apple Mail sends them; a
      file that cannot be attached is said, and Send never goes without
      one he picked. B-108, and its check under "Blocked on the iPad
      coming back".*
- [x] Undo for Delete and Move; Contacts in address suggestions (B-017);
      app badge and notifications. *Owner decisions.*
      *Undo for Delete and Move ruled 2026-10-26: copy Apple Mail. Built
      as B-157, not yet seen on the iPad: a shake, three fingers or
      Command-Z undoes a Trash or a Move, from a drag, Edit mode or the
      pane, with UIKit's "Undo Trash" or "Undo Move", the letters moved
      back and their rows where they stood, and a Flag, "Undo Flag", as
      Mail is reported to; and its check under "Blocked on the iPad coming
      back".*
      *App badge and notifications ruled 2026-10-26: copy Apple Mail. Built
      as B-161, not yet seen on the iPad: the Inbox's unread count on the
      icon, and a banner for each new unread Inbox letter from a check iOS
      wakes the app for while the iPad is on charge and on Wi-Fi, as Mail
      fetches from the factory, after iOS's own question; its check under
      "Blocked on the iPad coming back".*
      *Contacts in address suggestions: ruled 2026-10-26: copy Apple Mail.
      Built as B-162, and its check under "Blocked on the iPad coming
      back".*
- [ ] Pull to refresh, the sent sound, blue bars on quoted text, tap the
      status bar to go to the top, Print. *The sent sound done 2026-10-22,
      seen on the iPad the same day, whether it is heard left for a
      person's ear: Mail's Swoosh once as the sheet closes after Send, for
      a letter that went or was put in the Outbox, from the composer and
      the share sheet. B-100, and its check under "Blocked on the iPad
      coming back".*
      *Blue bars on quoted text done 2026-10-22, seen on the iPad the same
      day: Mail's own rules, a 1 px bar and the words in violet, teal and
      green by level, in HTML letters; plain-text '>' quotes left to the
      owner. With it, a file sent inline, as Apple Mail sends a PDF, gets
      its row and its paperclip. B-101, and its check under "Blocked on
      the iPad coming back".*
      *Pull to refresh done
      2026-10-22: on the message list, by the Refresh button's own path,
      not in Edit mode, a search or a day's list; the status-bar tap
      pinned as it was. Seen on the iPad the same day: a gap left above
      the list and, with no connection, a pull left down, both fixed and
      seen fixed the same day. B-103, and its check under "Blocked on the
      iPad coming back", 11 left for a person's hand.*
      *Print done 2026-10-22, seen on the iPad; three faults found there
      fixed and seen fixed 2026-10-23, the time of a letter tapped after
      Print on 2026-10-25, missed once at a slow moment of the wire: Print
      in the Reply sheet under Forward, as Mail's Reply button had it,
      prints the letter the header shows, on white, with its header and
      pictures and the date in full, through AirPrint's panel. B-110, and
      its check under "Blocked on the iPad coming back".*

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
- [x] **Left from batch 4.** Opening another letter inside a conversation
      still changes the header to that letter once its body has come, so
      a letter with a different number of files moves the stack then. The
      header could change at the tap instead, with Reply held until the
      letter has come, as the single-letter pane does since P1. And a new
      result set as he types asks for every hit's preview again, where the
      previews already drawn for the same letters could be carried over by
      id, as Refresh does. Also left as it was: a letter reopened in the
      stack whose body is already kept takes the header at once, so a letter
      opened before it and still coming takes the header back when it lands.
      *The first and last parts done 2026-10-25 as B-129, seen on the test
      iPad 2026-10-25: a letter opened in the stack takes the header and the
      toolbar at the tap, from its row, Reply held until its body has
      come, and the last letter opened owns the header whatever lands
      after it (`StackFocus`). The search previews' part is B-135's.*
      *The search part done 2026-10-25 (B-135): a hit takes the preview
      already drawn for its letter, by its folder, id and Gmail id, from
      the folder's rows, the hits it replaces or the last 300 drawn, and
      only the rest are asked for; on the scripted mailbox "Margaret"
      typed a letter at a time asked 4 preview FETCHes where it asked 18.
      Checked in `SearchPreviewsTests`; the device check is below. The
      header's part and the letter reopened are B-129's.*
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
- [x] **B-025. Insert a photo at the cursor** (`NSTextAttachment` in the
      composer). Last, deliberately: exactly 1 of his 433 sent messages did it.
      *Done 2026-10-22 in its minimal form, seen on the iPad the same day:
      his photos sit in the letter under his words, above the signature,
      as all of his Apple Mail picture letters did. B-109, and its check
      under "Blocked on the iPad coming back".*
- [x] **The print's "This message has no text." only where the pane's.**
      From B-114 with B-110. `PrintPage.body` and `PrintPage.words` say
      "This message has no text." only where the pane would
      (`PanePage.isEmpty`), so a letter shown only in part prints with
      the pane's "Only the beginning…" line over whatever came, as B-114
      has the pane. ~~Not done yet: `PrintPage.words` says it for any letter
      whose text is empty, one shown only in part included, and
      `PrintPage.body` asks `MailText.hasNoVisibleContent` alone; nothing
      in the print calls `PanePage.isEmpty`.~~ With a test of each for a
      letter with nothing in it said to be short, beside `PanePageTests`'.
      *Done 2026-10-25, B-131: both ask `PanePage.isEmpty`; a letter that
      is only a picture, which the pane shows, is its header alone in
      words. `PrintPageTests`, two, the pane's five shapes of nothing.
      Its check is under "Blocked on the iPad coming back". Also: an HTML
      letter cut at 512 KiB has the line in words, as on its page, and the
      question is asked once for both (`PrintPage.made`); two tests more.*

## Blocked on the iPad coming back

*Owner, 2026-10-24: he does not use VoiceOver or anything read aloud;
his hearing is bad and he does not like it. Every VoiceOver step in the
checks below is left as not needed, not open, and none is worth a round.*

- [x] See B-037 rendered at all: now B-048, below. *Seen on the iPad
      2026-09-29: three panes and two, the view button, "< Mailboxes" and
      the choice kept across a relaunch (B-048).*
- [x] Confirm the signature's white sheet **in the reading pane**, in a
      conversation's stack (`ConversationDocument`'s `.bm-signature` rule).
      *Seen in passing on the iPad 2026-10-07 (B-074): in a stack, a
      reply's signature and what it quotes on a white sheet with dark
      words.* The outgoing half is verified by tests and Chromium renders.
      Every HTML letter the app sends with a signature carries the marker
      (`AppleMailHTML.signatureOpen`), so no send is needed. A letter shown
      alone is drawn by `PanePage.letter`, which had no such rule until
      B-130, so its signature showed white on the dark pane (seen in
      passing in B-074); that was what was left of this item.
      *Looked for on the test iPad 2026-10-21, a build of master with B-092
      (1233252): not possible. No conversation on the test account holds a
      letter with the signature: each of the 22 letters that carry it is
      alone in its thread, and the conversation chosen for it has none. A
      letter with the signature shown alone, for what it shows: no white
      sheet, the thirteen lines white on the black page, its links blue,
      and the logo as drawn, dark ink, a dark box hardly to be seen on the
      black. Left: what the letter alone should show, seen as above and
      not yet looked into; the stack again on purpose needs a conversation
      holding a reply sent from the app, and the check sent none.*
      *Built 2026-10-25 (B-130): a letter on its own has the stack's rules
      now, from the one string (`SignatureSheet`), on every HTML letter's
      page. Left: seeing both, which B-130's check below does with letters
      the host puts in a label, none sent.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), in B-130's
      check: the sheet in a stack and on a letter shown alone. Nothing
      left.*
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
      is still "The share sheet's checks".* *Decided 2026-10-21 by the
      owner: the share with no subject is left as it is, as the YouTube
      app hands over the link alone (share check 11).* *Reopened
      2026-10-24 (B-125): Mail does give a YouTube share a subject, the
      video's title, which the YouTube app hands to Mail and to no share
      extension. The subject is what the share hands over that names it,
      Safari's page title; the YouTube share's stays empty for want of
      one, and a fetch is left to the owner.* *Decided 2026-10-25 by the
      owner: the title is fetched from YouTube (B-126).*
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
      frame. Delete a letter, then tap the next (since B-158, under View
      Next Message, the next opens by itself): the binned one must not
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
      paints "Loading…" a frame or two after it; not changed (B-098). No
      white or blank frame came between "Loading…" and the letter. The
      binned letter never showed again. The taps, some half a second
      apart, were three, not four: the first and the last fetched, none
      between, the pane on the last. Reply did nothing while "Loading…"
      showed, and the header kept its height as a letter with a file
      landed. Left: that first frame, recorded as B-098 and left as it is.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), the first frame
      measured again from a screen recording at 60 frames a second, seven
      taps 1.5 s apart through letters the host put in the label Notes, each
      a block of one colour: the letter before stood beside the new
      selection in 3 taps of 7, against 5 of 7 on 2026-10-21, for two
      frames, 33 ms, once and for one, 17 ms, twice, not counting in those
      two a frame with both rows lit under the old header; in the other four
      the first frame with the new selection had the new header over
      "Loading…". No white or blank frame came between "Loading…" and a
      letter, which came 67 to 117 ms after it. The first letter after a
      launch: two frames of an empty pane under its header, as before
      (B-098). Left: that frame, B-098, whether to cover it being the
      owner's question ("One frame of the letter before", under "Blocked on
      the owner").*
- [ ] **B-041, Delete, Move and Flag from the pane.** In a folder scrolled
      down a few pages, with previews filled: Delete a read letter. The
      pane empties and the row goes at the tap, nothing else on the list
      moves or blanks, and the connection log shows `UID MOVE` and after it
      only the watch's check every 30 s: a NOOP, and after the first NOOP
      following the MOVE one `UID SEARCH UID n:*` with
      `NEWS folder=INBOX arrived=0 gone=N` (the MOVE's own EXPUNGE is news
      to the watch), then NOOPs alone; no summary FETCH, LIST, STATUS or
      page FETCH. Delete stays grey until it lands. (Since B-158, under
      View Next Message, Mail's factory setting and the app's, the next
      letter opens in the pane, highlighted, and Delete stays live: the
      empty pane and the grey Delete are Don't Select a Message's, which no
      Settings row sets yet, host-tested only. B-158's own check has the
      rest.)
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
      half open, or the 90 s one of a SELECT, SEARCH or STATUS, B-063, a
      Flag behind such a command waiting with it). In a conversation, open
      an unread letter that arrived while the stack was open and was then
      closed by its line (since B-074 every unread letter opens with the
      stack): the dot goes at the tap, and one count when its STORE is
      answered (a fraction of a second later, never before, so a refused
      STORE cannot leave the count too low), and the list does not reload.
      The host suite checks the rules; the table view's reaction to them,
      row removal, highlight and empty state, is only visible here.
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
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), the iPad's Wi-Fi
      interface taken down over its cable under the connection, a guard
      armed first to bring it back, on letters the host put in the label
      Notes: Delete grey while its MOVE is out passed, and the Flag on a
      socket left half open in part (B-041). Delete: its `UID MOVE` never
      answered, the row gone and the pane empty from the first frame, every
      pane button but Compose grey, with no letter in it; "Can't connect to
      mail server." 15 to 20 s on, the row back where it stood, as the
      connection was dropped; the interface up, Refresh, the letter where it
      was, nothing moved on the server. The Flag, four times, its own STORE
      never written: once its SELECT went into the silent socket and the
      flag went back with "Can't connect" about 20 s on, at the drop; once,
      behind a Refresh's STATUS on the wire as the network went, it waited
      for that command's 90 s bound and went back with "Can't connect" about
      100 s after the tap, where the step named the 30 s deadline alone: it
      now names both; once, behind the watch's STATUS, about 48 s on, after
      the drop and a reconnect's 30 s bound, as its log has it; and once,
      the row out of sight and the connection log's screen up as the 90 s
      ran out, the flag went back with no alert seen, not made again without
      that screen. Nothing was set on the server. Left: that missing alert,
      not looked into.*
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
- [x] **B-042, paging upward.** In All Mail, Go to Date a few months back,
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
      recorded, not changed). So it does too, by the sums (not seen),
      wherever the jump is made from, for a day with a page of older mail
      below it, which lands at row 10 or higher; in the test account's All
      Mail the day lands at row 20, where the check can still be made.*
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
      row in view up by one: fixed as B-093, seen fixed on B-093's build
      below. Go to Date from a list at its top fetched the page above as
      the day landed, nothing touched, so the scroll up was made after
      jumps from part-way down: recorded as B-094, not changed. Seen in
      passing: a letter open before a jump stays in the pane, its row no
      longer highlighted until tapped again.*
      *Seen on the test iPad 2026-10-21, a build of the `line-press`
      worktree (a6a6c7c), in B-093's check: the Delete passed (B-093),
      nothing in view moving in any frame, and the scroll up passed again,
      the rows moving only with the finger and the highlight kept.*
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
      *Since B-122 and B-141: the sighting above was of two letters of
      the list, on a build before B-122, whose `stillShows` (2026-10-24)
      has let the first letter's file go since, once another row is
      tapped. B-141 (2026-10-25) closes the same within a conversation,
      first seen in the round of 2026-10-25, where another letter's line
      leaves the pane on the same conversation and the first letter's file
      opened over the second's header, the second's own let go. Now the
      last tap wins: a file tapped before another file, or before another
      letter's line, is let go as it lands, its spinner cleared; the
      second letter's file keeps its spinner and opens as it comes; a file
      tapped again while it comes is not fetched again. B-141's check; the
      download of the second letter's own as the first ends still cannot
      be made.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), on a
      conversation the host put in the label Notes, both letters over 5 MB,
      the older with a PDF of 4.4 MB and the newest with one of 14.7 MB, the
      header on the newest: its file tapped, then the older letter's line,
      then that letter's own file, its words in from an earlier open, so
      that the download of its own as the first ends, which the notes above
      say cannot be made, was made. The older's row kept its spinner as the
      first download ended, as the step asks; then the first file opened in
      Quick Look over the older letter's header, and the older's file,
      landing 1.7 s later, never opened and nothing was said; made again by
      a second run from a fresh start. Found here, fixed as B-141, see its
      entry; B-141's check takes it (B-042).*
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
- [x] **B-042, WebKit's content process.** Force it out while a letter is
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), the pane's own process found each time in the system log,
      which names the app it serves, and ended with `kill -9`: every part
      but the long conversation passed (B-042). A letter alone: "webview:
      content process ended", the letter at its top again with its picture,
      the same to the pixel, and no FETCH. Three letters, two open and one
      a line: back the same way round, bodies and pictures in, and nothing
      fetched at all, the two having been fetched whole just before, their
      pictures with them. Ended with Settings in front: the log line,
      nothing until the return 20 s on, then the stack drawn again. Ended
      0.36 s after the tap on a letter of 26 MB, its FETCH out: the letter
      appeared as it landed. Ended again 1.4 s after the redraw: "This
      message could not be shown.", and its row tapped again drew it. The
      same on a letter with no text left the pane empty, as built for a
      notice lost twice, and its row drew it. Left: the conversation of
      twenty letters or more.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): the long
      conversation passed, 22 letters the host put in the label Notes, half
      HTML, half plain, threaded by References: opened five times on Wi-Fi
      from the list, another row first each time, the newest letter open
      with its body in the first frame, 0.44 s, every time, never
      "Loading…", only the first and fifth opens' first frames looked at a
      second time; fetched at the first open, then shown from the copy kept
      on the iPad (B-042). Every part has now passed.*
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): the newsletter, the body with backslashes and `</script>`,
      the kill, the PDF and the fill as frames can time it (B-043). The
      largest newsletter on the test account, 130 KB, tapped, and the list
      flicked up and down for 3 s at once: in five runs of six the flings
      went on with no frame standing still, four of them across the body's
      landing at 0.37 to 0.39 s, and the letter drew whole with its
      pictures. In the second run the first flick, its finger down 20 ms
      after the tap lifted, as in the four runs after it, was not taken:
      the list did not move from 0.14 to 0.71 s while the letter came, the
      touch reaching the app at its usual pace and no gesture beginning;
      the three runs after it made the same way did not make it again. A
      plain letter with quotes, backslashes and `</script><b>` in it read
      as sent, alone and in a conversation (B-055's check), and a
      conversation came back with its bodies after the pane's process was
      ended (B-042's). A PDF of 4.4 MB in a letter over 5 MB, opened twice:
      Quick Look 2.6 s after the tap, then 2.3 s, the whole part fetched
      again: recorded as B-097, not changed. The fill, from frames, an
      upper bound: a conversation's newest, 8 KB, in by 0.55 s after two
      minutes idle, a NOOP of 219 ms going first, and by 0.27 and 0.26 s
      after 13 s and 2 s. The memory could not be read, the iPad's process
      list giving 0 for every process; the system log had no WebContent
      ended and no jetsam line through the fill. Left: the one flick not
      taken, why not known; a newsletter of a few hundred KB, which the
      account does not have, a conversation of twenty letters, the time
      zone and the 24-hour clock, which wait on a yes, "Yesterday" after
      midnight, the fill timed in the app with a letter of a megabyte, and
      the memory.*
      *2026-10-25: the time zone and the 24-hour clock were tried in round
      r6-s6-dates-lists and failed, twice: what was on the screen kept its
      old form until it was drawn again (B-139). B-139 closes that
      leftover, and "Yesterday" after midnight with it: both are B-139's
      check now (below), and nothing of the zone, the clock or midnight is
      left to this item.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), on letters the
      host put in the label Notes: the newsletter of a few hundred KB and
      the conversation of twenty letters passed (B-043). A newsletter of 455
      KB, 420 KB of it HTML in coloured tables, tapped and the list flung
      down and up four times at once: its body in at 0.26 s and drawn by
      0.51 s, and every frame from 0.26 to 4.40 s had the list somewhere
      else, none standing still; six flings in the newsletter brought its
      last stories, drawn. 22 letters, half HTML, half plain: the newest
      filled in at each of five opens; letter 1, HTML, and letter 2, plain,
      opened by their lines, and letter 1 closed and opened again, its body
      back. Only two of the twenty fling frames were looked at a second
      time, and the shots of the conversation scrolled and of letter 1
      opened again were not. Not possible: the CPU, the iPad having no
      `top` and its process list giving none. The time zone and the 24-hour
      clock: found here, fixed as B-139, as the note above has it. Left: the
      one flick not taken, the fill timed in the app with a letter of a
      megabyte, and the memory.*
- [x] **B-044, sending.** *Seen 2026-09-29: plain, double tap, reopened
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
      letter with text, and with that sheet still open tap Send: the first
      tap only closes the Cancel sheet, as in Mail, and a second sends the
      letter once; nothing is saved or deleted.
      *Seen on the test iPad 2026-10-20: the first four still to see
      passed, Look Up chosen from the menu (B-044). The picker takes every
      touch until about 0.9 s after Add, and by then the five photos were
      in, so a Send with a photo still coming in could not be made on this
      iPad. Send with the Cancel sheet open took two taps: four taps on
      Send with that sheet up, two after a fresh launch, each only closed
      the sheet, and a second tap sent the letter once; nothing was saved,
      deleted or lost. The sheet, an action sheet in a popover, lets no
      tap through to Send's bar (B-044).*
      *Decided 2026-10-21 by the owner: "Leave the two-tap Send, the 'View
      recent photos.png' name, and the subjectless YouTube share as they
      are, since each matches what Mail or iOS would do." Left as it is,
      as Mail has it: the popover takes the tap outside it, Send's bar
      included. That was the last step left.* *The ruling's part on the
      YouTube share was reopened 2026-10-24 (B-125).* *Since 2026-10-25 the
      title is fetched from YouTube, by the owner's ruling (B-126).*
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
- [x] **B-047, "Inbox".** *Sidebar and title seen 2026-09-29; the Move
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
      it.* *Done: what is left is VoiceOver's alone, not needed since
      2026-10-24 (he does not use it).*
- [x] **B-048, two panes or three.** *Partly seen 2026-09-29: both ways
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), the Layout button on: Edit, the scrolled list and the open
      folder passed (B-048). A conversation open, the list three screens
      down, both ways: the conversation drawn in every frame, never
      "Loading…", the rows and the selected one at the same heights a pane
      over, the Inbox highlighted, and in the log
      `layout: two panes, the list in front` and `layout: three panes`, no
      finding after either, and the watch's NOOPs alone. Edit, two ticked,
      both ways: still in Edit, the same two, Done in the bar.
      "< Mailboxes", the open folder: its list where he left it, a NOOP
      alone; another: its SELECT, UID SEARCH and UID FETCH. Seen in
      passing: after Done the open letter's row is no longer highlighted,
      the letter still in the pane (B-133 since). Left: the long folder
      name, which needs a label made on the account and waits on a yes,
      and the thumb resting on the list.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): the long folder
      name passed, on two empty labels the size test made on the account: in
      two panes the list's bar read "< Mailboxes" whole, the calendar, then
      "Note to…" for "Note to Self: Letters to Himself" and "Unopene…" for
      "Unopened 4/17/17", close against Edit; "Sent Mail" whole, and
      "< Mailboxes" whole with it; the view button gave three panes back
      (B-048). Not possible: the thumb resting on the list, two touches at
      once, which touches from outside cannot make; left for a person's
      hand, which does not keep this item open, as with B-105's 9b.*
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), under B-055's check: in place of a shared link, a reply to
      a plain-text letter of his own with links in it. The quote's web
      addresses went as links, its `mailto:` as words, as built, and in the
      conversation one of the quote's links asked "Open this link?" over
      its site (B-050). Left: how each looks in Mail and on Gmail's web
      page.*
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
- [x] **B-049, new mail on its own.** *Partly seen 2026-09-30: a letter
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
      check, so what came during the search waits for the next one; not
      changed (B-099). Left: that half minute, recorded as B-099 and left
      as it is; the archive on the phone, which needs a person; and
      "Updated at …" after an hour, which needs Auto-Lock at Never and
      waits on a yes.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): the archive
      elsewhere and "Updated at …" passed (B-049). A letter the host put in
      the Inbox, read and dated three days back, went on at the top at the
      watch's next check; the host then took the Inbox label off it from All
      Mail, nothing tapped: at the next check, 4 s on, the NOOP answered
      `EXPUNGE` and `EXISTS`, then the SEARCH and `NEWS folder=INBOX
      arrived=0 gone=1`, no page FETCH, and the row was gone. The host's
      first try, the label taken off with the Inbox selected, was answered
      OK and changed nothing on Gmail, and the row rightly stayed. Sent Mail
      in front 62 minutes, nothing touched, Auto-Lock at Never for it and
      put back after: "Updated 59 minutes ago" at an hour, then "Updated at
      6:43 PM"; 118 `STATUS "INBOX" (UNSEEN)` about 32 s apart in the log
      and nothing else. At 15, 30 and 45 minutes "Updated 14, 29 and 44
      minutes ago", those shots not looked at a second time. Nothing left to
      check: the half minute after a search's Cancel is B-099, recorded and
      left as it is.*
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
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to writes into the app's containers: case 3 as Save
      Draft and case 5 up to his Send passed, nothing sent (B-051). Case
      3: with Airplane Mode on, a draft, a forward of a letter with a PDF,
      a forward of a letter whose photo shows in its words, and a second
      draft, each saved; the app ended, the PDF's `"letter":` and the
      quoted picture's written one higher. Airplane Mode off: the two
      drafts went up, one APPEND each, and the two forwards stayed "On
      this iPad only" with "Attachment could not be downloaded." under it,
      each by `CARRIED-PART folder=INBOX reason=another-letter`, the
      search in All Mail and in the Trash finding nothing, and
      `CARRIED-PART not-found nothing-sent`, no APPEND. Each opened, a
      letter typed and saved again: the same words, no APPEND. Each with
      its file or photo taken off and saved: one APPEND, Gmail's draft
      without it, the letter's folder gone. Case 5: a Send with Airplane
      Mode on put a letter in the Outbox; the app ended, its attempt
      written down unstamped, `password-saves` reading 1. Offline, then
      online for two minutes, its row read "May already have been sent."
      over "1 Unsent Message", and nothing went: no `UID SEARCH HEADER
      Message-ID`, no ENVELOPE, no copy in Gmail. It was then deleted in
      the composer offline, unsent. Not run, under the no-send rule: case
      3's Sends after its Outbox row (that row seen 2026-09-30): the letter
      sent after it going, the sheet staying with the same words, and the
      file taken off and sent; case 5's Send from its row, and its pass
      with no `password-saves`. Each "end the app" was a kill from the
      host, not the app switcher, which injected touches cannot open. Left:
      those Sends.*
- [x] **B-053, the copy kept on the iPad.** Seen 2026-09-30: the first
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
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): the flag before
      the fresh page lands, and the password saved again, passed but for the
      drafts (B-053). A letter of his in Sent Mail kept, the app ended and
      opened with Airplane Mode on, Sent Mail's kept page and the letter
      from its copy: a Flag offline was refused at once, as B-091 has it, so
      Airplane Mode went off and the Flag was tapped 1.7 s later, before the
      page: on the new connection the vouching FETCH, then its STORE,
      answered, then the page, its line for the letter flagged; the flag on
      the row 0.7 s after the tap, before the page, and still on almost a
      minute later; Unflag put it back. The test account's password typed
      into Settings, never on a screen kept, and Save: the Inbox empty under
      "Checking for Mail…" at 2.04 s, its rows at 2.20 s; ended and opened,
      the kept Inbox, the page listed since the save, in the app's first
      frame, 0.35 s, before its sign-in was answered. Not possible: the
      drafts "On this iPad only" and the Outbox through the save, there
      being none at the start and none to be made. Left: those, with a draft
      kept on the iPad first.*
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to writes into the app's containers: the drafts "On this
      iPad only" and the Outbox through the password saved again passed
      (B-053). A draft and a letter in the Outbox, made with Airplane Mode
      on in B-057's check, were held there by three tries written into
      each, so that no pass would take them. The test account's password
      typed into Settings, never on a screen kept, and Save: the Inbox
      empty under "Checking for Mail…" 2.1 s after the tap, its rows at
      2.6 s, the counts by 7.7 s; the kept letters wiped. Both letters
      stayed, their files byte for byte as before. Ended from the host and
      opened: the kept Inbox, the page listed since the save, with its
      previews and counts in the app's first frame, 0.41 s, before its
      sign-in was answered; the draft still "On this iPad only" and the
      letter in the Outbox over "1 Unsent Message", `OUTBOX-HELD` and
      `DRAFT-HELD` once each, no ENVELOPE and no APPEND. The two were then
      moved out of the store by hand with the app ended, unsent: Airplane
      Mode, to delete them in the app, would have cut the iPad's one way
      in that day, its Wi-Fi. A first try at this that morning was cut
      before the save by a lost connection to the iPad. Nothing left for
      the test iPad.*
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
- [x] **B-053, every write and every open naming its letter.** Seen
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
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to writes into the app's containers: a letter opened
      from another mailbox's copy passed (B-053). A letter the host put in
      the Inbox, opened online, so kept; with the app ended, its row on
      the kept Inbox page given a Gmail message id of no letter, the last
      digit changed. A launch with Airplane Mode on: the kept page, that
      row on top; tapped, its header and "This message could not be
      downloaded.", none of its words. Airplane Mode off and the row
      tapped 0.18 s later, before any listing: `UID FETCH n (UID
      X-GM-MSGID BODY.PEEK[])` answered with the letter's own id, then
      `KEPT-UNVOUCHED folder=INBOX nothing-shown`; the row gone from the
      list, the pane "No message selected", no STORE, MOVE, EXPUNGE or
      APPEND, no `KEPT-DISCARDED`. After Refresh the row was back under
      its own id, and tapped it opened from its copy, `KEPT-LETTER shown`,
      no FETCH. Nothing was sent. Nothing left for the test iPad.*
- [x] **B-055, the reading pane locked down, links in plain letters, Cc.**
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
      and the line lightens under the finger while it is held (B-095; it
      never did before, which B-095's check sees). Tap it again: it
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), five letters made in the app: every part passed but the
      hold, the kept Inbox and the letter that tries to go somewhere
      (B-055). A plain letter, the signature taken out, went as one
      text/plain part; its first line, with quotes, backslashes and
      `</script><b>bold?</b>`, read as typed, alone and in a conversation.
      Each link whole, in `#0A84FF`, `_(film)` kept and the full stop,
      comma and brackets not; each asked "Open this link?" over its site
      and opened, the YouTube one in its app; the `mailto:` opened the
      composer To its address, the signature under the body; and an address
      typed in a reply, an HTML letter, was a link asking the same. A link
      held: WebKit's menu and preview, nothing else. Cc, a named address,
      an unnamed one and `"Example, Pat"`: under To at the tap, under
      "Loading…", in To's grey, the rule under it, Pat once, and nothing in
      the header moved as it landed; Reply All put Pat in once; no Cc, no
      line. The conversation, its newest with the Cc: the stack still as
      the body came. Three letters: a tap opened a line, its body in by
      0.7 s, the header and Reply moved to it; a tap closed it; two 0.3 s
      apart both opened; one 15 s on had its body; with letters open, the
      pane's process ended: back as it was. Held 1 s on a line: no light,
      and WebKit's selection of a word at 0.7 s and its Copy menu at 1.4 s:
      fixed as B-095, seen fixed on B-095's build. The kept Inbox, offline:
      the conversation's row gives the header of its newest letter, which
      had no Cc, so none showed, rightly; its letter with a Cc, tapped
      offline, could not be downloaded, and so did not take the header
      (since B-129 it does, at the tap, from its row, Cc and all).
      Seen in passing: a header that gains a Cc line at a tap leaves the
      stack's first line half under it until the stack is scrolled (fixed
      as B-128, its check below); and an
      Edit Delete of two rows met Gmail's `* BYE System Error` at its first
      MOVE, nothing moved, and the rows stayed off the list until a
      Refresh (B-132 since: out of sight above it, before B-093). Left:
      the Cc from the kept Inbox, which needs it on the letter the header
      names, and the letter that tries to go somewhere, which needs a
      letter from another account and waits on a yes.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): the Cc from the
      kept Inbox and the letter that tries to go somewhere passed, on
      letters the host put in the label Notes and the Inbox (B-055). The
      letter, its refresh, frame, form, script and `onerror` each aimed at
      `https://example.com/`: at 2.5 s and 8 s as written, the frame an
      empty box, no script's change, the pane going nowhere, its button
      tapped doing nothing; one FETCH of it in the connection log,
      `example.com` there only in other letters' addresses, and no WebKit
      network line for the app in the system log. The same as the newest of
      a conversation of two, its line closed and opened again, the other
      letter opened above it. A letter with a Cc put in the Inbox three days
      back, listed once, the app ended and opened with Airplane Mode on, its
      row tapped: the Cc line in the header at the tap, from the kept row,
      over "This message could not be downloaded."; online, the same lines
      with its body. Every part has now passed.*
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
      *Since B-140 (2026-10-25): the round of 2026-10-25 made such a letter
      on the host, HTML over 2 MB and nearly all words, and its Reply froze
      the app. A quote now holds at most 64 KiB or 2,000 lines of the
      original's words, ended with the same line, and the letter received
      quotes them as words, not the original's markup, the grey line after
      them, once.
      B-140's check sees that letter's Reply and Forward in the composer,
      sending nothing; what is left here is the letter received, in Mail
      and on Gmail's web page, and the draft saved, reopened and sent,
      which send.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), on letters the
      host put in the label Notes: the photographs shown in the body, the
      next letter tapped while they come, and the HTML over 2 MB with its
      Reply, Forward and draft passed but for one Reply (B-054). A letter of
      13 MB as an iPhone sends it, three photographs of about 3 MB shown by
      `cid:` and a PDF: each photograph by its own `BODY.PEEK[1.2.k]`, about
      1.1 s each, no `BODY.PEEK[]`. After a relaunch, the next letter tapped
      1 s after it: the one photograph on the wire, then the next letter,
      whole 1.52 s after the first tap, no FETCH of the other two. Two
      letters with an HTML part of about 6 MB, "Only the beginning of this
      message is shown." over each. On the one that is mostly markup,
      Reply's and Forward's quotes ended with the line once, under a blank
      line, each closed by Cancel; the reply saved as a draft, reopened with
      the line once, then deleted. On the one whose words fill its 2 MB,
      Reply put the keyboard up but never drew the sheet, which, up unseen,
      took every touch but the keyboard's: found here, fixed as B-140, see
      its entry. Left, as above: the letter received, and the draft sent,
      which send.*
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
      *Seen 2026-10-26 for the draft, with a defect (round r6-g-store2,
      step 08, on int17 939ad5a): held, not taken up, its row's line as
      above; but opened and Cancelled untouched it closed at once with
      nothing asked, no Save Draft, and stayed held. Fixed as B-165, whose
      own check is below; the draft's Cancel, Save Draft here is that.*
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
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to writes into the app's containers: 6's draft half and
      its control passed, and the held draft's row failed (B-057). Two
      drafts and a letter in the Outbox made with Airplane Mode on, each
      given three tries, a third draft two. Opened with Airplane Mode
      still on: the held drafts under "On this iPad only" with "Not saved
      to Gmail automatically. Open…", cut by the row's width, the third
      without it; the Outbox row "Not sent automatically. Open it and tap
      Send." over "1 Unsent Message"; `OUTBOX-HELD unfinished-tries=3`
      once and `DRAFT-HELD unfinished-tries=3` once for each held draft,
      no ENVELOPE, no APPEND. Online, the draft of two tries went up by
      itself, once, and the held letters stayed as written. The held
      draft's row could not be followed as written: opened and Cancelled
      untouched, the composer closed with no sheet, so no Save Draft, and
      the draft stayed held; a second run made it again twice on the other
      held draft, the second time after the autosave's pause. Now B-165, on
      its own branch. With one letter typed, Cancel brought the sheet, and
      Save Draft sent one APPEND, one copy in Drafts. The Outbox letter's
      Send, seen 2026-10-01, was not tapped, under the no-send rule, nor
      its control with two tries. The kills were from the host, not the app
      switcher. Left: the swipe in 1 and in 8's third part, which needs a
      person at the iPad; the held draft's row once B-165 is in; 6's
      control for the Outbox letter, with two tries, a send, behind the
      no-send rule.*
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
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to paper, in B-110's check: 5's print from Quick Look
      (B-063). A one-page PDF of 1 MB in a letter the host put in Notes,
      opened in Quick Look; Share, Print: the panel's preview the whole
      page. Print, and Done about 0.9 s after it, as the panel had just
      gone. The iPad's print service took the job 1.4 s after the Print
      tap, 0.5 s after Done, as Quick Look closed, as one page;
      `tmp/Attachments` held the one PDF before and after, the same size
      and hash. An AirPrint laser printer on the home network listed it
      completed, one impression. The sheet is the owner's to look at.*
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), the Layout button on: 3 to 6, 9 and 12 passed but for the
      bounces and two points of 9 (B-066). In 3 a list flicked and tapped
      as it coasted stopped where it was and slid in one motion of about
      0.5 s. A pull past the top, Important flicked past its bottom and a
      long letter past its end each switched at once,
      `pane motion: bouncing; switched at once`, and the tap a second on
      slid; but against the same gesture with no tap, the bounce lost 26 to
      45 pt of a pull and 66 to 72 pt of the flick in the frame of the
      switch, the last 6 to 10 pt springing back after it with no jump:
      recorded as B-096, not changed. The long letter, at its rest at once
      in two panes, could not show it; the Mailboxes pulled down was seen
      under B-077 on 2026-10-07. In 4 two taps 0.1 s apart made one switch,
      a row 0.2 s after opened nothing and fetched nothing, and one 0.9 s
      after opened. In 5, with Control Centre and with Settings 0.2 s into
      a switch, the screen was final and taps worked; sixty switches all
      slid. In 6 the search's words, scope, results and keyboard stayed and
      three characters typed during the motion were in the field; Edit kept
      its ticks. In 9 each switch the saved logs reach has its `layout:`
      line, no finding after any, no deadline, the bounces' lines alone,
      and the watch's checks alone around the switches; but the
      three-minute sweep, ended before the first switch, had one finding, a
      label in iOS's share sheet, not a pane, which the sweep does not
      leave out, and the switch made to set up 6's search fell between two
      saved logs. In 12, at 60 frames a second, a newsletter's centred
      column rode with the letter's edge, landed 44 and 45 pt off its place
      and was laid out again 0.52 s on, a conversation's text wrapped again
      at 0.51 s, and the names and header landed where they end up; whether
      the end frames catch the eye is still 12's question. Left: 11, and
      in 5 the iPad turned over, and Home; 1 and 2 are B-077's checks,
      seen there on 2026-10-07.*
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
      arrived and note it; the picture goes under it, as decided below.
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
      given, so `name=suggested` is now in it.*
      *Decided 2026-10-21 by the owner: "Leave the two-tap Send, the 'View
      recent photos.png' name, and the subjectless YouTube share as they
      are, since each matches what Mail or iOS would do." The name iOS
      suggests stands, as iOS gives it; image0.png and image0.jpeg are for
      a picture that comes with no name at all.* *The ruling's part on
      the YouTube share was reopened 2026-10-24 (B-125); the name stands.*
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
      is empty), the link tappable in the letter that arrives. *Decided
      2026-10-21 by the owner, with 7's name: the empty subject is left as
      it is, as the YouTube app hands over the link alone.* *Reopened
      2026-10-24 (B-125): its ground, that Mail does the same, does not
      hold, Mail giving the video's title. The subject stays empty because
      the YouTube app hands an extension nothing that names it, not by the
      ruling; a fetch is an owner question.* *Decided 2026-10-25 by the
      owner: the title is fetched from YouTube; with B-126 the subject is
      the video's title a moment after the sheet comes up (B-126's
      check).*
      12. *After these, the app's own password still works* after the
      Keychain groups change: the app signs in and sends.
      13. *Cancel with words in it.* Type a word above the signature and
      tap Cancel: it asks, Delete Draft ends the share, and a tap elsewhere
      on the sheet closes the question with the word still there (on the
      iPad it is a popover with Delete Draft alone).
      14. *A failed send.* With Wi-Fi off, Send: the reason is shown, the
      letter is left as it was, and Send works once Wi-Fi is back. Since
      B-153 (2026-10-26) that is a share with a photo; a share with no
      files closes and waits in Blackmail's Outbox (B-153's check).
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
      than the JPEG; and 5 and 8 on his iPad. 7's name was decided by the
      owner on 2026-10-21, as 7 says.*
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): 15 passed (B-036). A `mailto:` link in a plain letter
      opened Blackmail's composer To its address, his signature under the
      body, with no alert, and Cancel closed it asking nothing. The address
      typed into Safari's address bar: Safari asked to open the page in
      "Blackmail", the iPad's handler for `mailto:`, and Open brought the
      same composer, closed with Cancel and nothing kept. Left: 12, not
      part of either, and of 1 to 10 what the note of 2026-10-20 says.*
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
      files, and on a new letter with Cc/Bcc open (since B-134, with
      someone in Cc, or they fold back as the caret goes into the body,
      as Mail's do): the fields go up out
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252), VoiceOver's Caption Panel read: 9 in the composer and 10
      passed (B-069). The app being among VoiceOver's Direct Touch apps
      here, a tap goes to the app, and VoiceOver goes to a field only as
      the keyboard comes up for it; so each field was tapped on a fresh
      letter, Cc/Bcc open: "To", "Cc", "Bcc" and "Subject", each a text
      field; the body, reached by Return in Subject, "Message", a text
      field. At the largest accessibility size and two stops above the
      default the paperclip was as tall as "Attach Photo", and the whole
      composer the same to the pixel as at the default, its type being
      fixed (D-007). Left: 9 in the share sheet, which needs the app and
      Safari taken off the Direct Touch apps and waits on a yes.*
- [x] **B-071, a file's preview and the text size.** Seen on the
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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): 1 in two panes again, 2, and 3 without VoiceOver passed
      (B-071). In two panes a PDF's preview and Done left the letter's row
      highlighted, and "< Mailboxes" showed the Inbox highlighted. At the
      largest accessibility size and two stops above the default nothing
      moved against the default, compared to the pixel: the folders' icons
      and names, the list and its chevrons, the calendar, the pane's
      buttons, the two 44 pt file rows. In Edit the circles kept their size
      and the rows' words stayed; the circles sat 12.5 pt lower at the
      largest size, and about 1 pt lower two stops above. The name field
      and the app password field, tapped with nothing typed: no "Passwords"
      over either. Left: VoiceOver in 3, and 4, which need the app taken
      off VoiceOver's Direct Touch apps and wait on a yes: with VoiceOver
      on, a tap on Settings' name field brought the keyboard and left
      VoiceOver where it was.* *Done: what is left is VoiceOver's alone,
      not needed since 2026-10-24 (he does not use it).*

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
      *Seen on the test iPad 2026-10-21, a build of master with B-092
      (1233252): 9 passed (B-070). A plain letter, the signature taken out:
      one text/plain part, its lines as typed,
      `WIRE-PAYLOAD bytes=555 raw=550`; a reply to it went in one
      conversation with it. A link from Safari shared with Airplane Mode
      on, the reason shown, and sent once with Wi-Fi back, was seen the
      same day as the share sheet's check 14, on a build of master with
      B-090 and B-091 (cba64fa). Still not: 10, which needs his iPad.*
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
      *Since B-128 the stack moves up with the header instead, the line
      tapped staying at the top of the pane, whole: B-128's check. Since
      B-129 the header changes at the tap: B-129's check.*
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
      its menu with it. Cancel, Delete Draft. Nothing is sent. *Since
      B-134, as in Mail, the "s" takes "Al"'s place and the menu goes with
      it; Return then makes "sa" the only bubble. B-134's check says what
      to see.*
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
      *Since B-134 steps 2 and 3 no longer hold as written: the "s" takes
      "Al"'s place, as in Mail, and the menu goes with it. B-134's check
      has the steps for now; the menu's place, under its bubble, is as
      here.*
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
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), a Sunday: 8
      passed, on a conversation of two the host put in the label Notes, its
      newest letter of Wednesday 21 October: the row "Wednesday", then the
      mark, no count; in Edit "Wednesday" whole before the mark, never
      "Wednes…", the names cut shorter; Done, the rows as before; in two
      panes the same (B-080).*
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
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to writes into the app's containers: 3 and 4 passed on
      the forward saved as a draft, and 5 was read from that draft
      (B-088). The original, "R6 B-088 three" with three photos of about
      66 KB, was put in the Inbox by the host, not sent. Opened, Forward,
      To A with `+b088fwd`, Airplane Mode on, then Cancel and Save Draft
      in place of 2's Send: "On this iPad only". The app ended, the three
      photos' `"messageID"` written one lower, another letter's UID there.
      Airplane Mode off and the app opened: after the Inbox's page,
      `CARRIED-PART folder=INBOX reason=another-letter` once, no FETCH at
      that UID before it; one `UID SEARCH X-GM-MSGID` in All Mail, giving
      one UID; for each photo the FETCH that describes the letter and its
      `BODY.PEEK[n]` at that UID, then `CARRIED-PART found
      folder=[Gmail]/All Mail`, no search or SELECT between them; then the
      draft's one APPEND. Gmail's draft held the three photos once each,
      byte for byte the original's. The draft was deleted in the app, the
      original put in the Trash by the host. Not run, under the no-send
      rule: the forward with 3's edit sent from the Outbox, so 4 as
      written and 5's arrival after it; 1, 2 and 5 were seen 2026-10-20
      without the edit. The kills were from the host, not the app
      switcher. Left: 3 and 4 on a forward sent from the Outbox, and its
      arrival.*


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
      letter that arrived and note it, as share check 7 does; the picture
      goes under it, as decided below. If either share still says a
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
      photos.png", two under the same name, not image0.png and image1.png.
      1 and 2 looked for image0.png: the editor named each screenshot, so 2
      now takes iOS's names as 1 did. Each arrived as image/png, the screen
      as it was, upright, with no location.*
      *Decided 2026-10-21 by the owner: "Leave the two-tap Send, the 'View
      recent photos.png' name, and the subjectless YouTube share as they
      are, since each matches what Mail or iOS would do." The name iOS
      suggests stands, as iOS gives it; image0.png is for a picture that
      comes with no name at all.* *The ruling's part on the YouTube share
      was reopened 2026-10-24 (B-125); the name stands.*

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

- [x] **B-093, a Delete in the pane with the letter's row just above the
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
      *Seen on the test iPad 2026-10-21, a build of the `line-press`
      worktree (a6a6c7c), master with B-092, B-093 and B-095: 1 to 5
      passed (B-093). In 1 no row in view moved, 0 pt in 80 frames to
      2.3 s. In 2 the rows below came up a row, 96 pt, the row above
      staying where it was, with none of it showing and with 1.5 pt, and
      the list did not scroll. Each Delete was of a W of its own, a letter
      put back from Trash coming under a new UID at the top of the list. In
      3 a jump from one fling below All Mail's top fetched the page above as
      it landed (B-094), so the scroll up was made from three flings down.
      In 5 the refusal came at 0.10 s, offline, and the row was back before
      the first frame that could show it gone: nothing moved in any frame,
      and the row gone with the rows closed up, before the alert, was not
      seen.*

- [x] **B-095, a finger held on a conversation's line.** On the test iPad,
      the test account only, built from the `line-press` worktree. Three
      panes. A conversation of three letters or more, every one read, each
      closed to its line, as in B-055's check. Each hold with one finger
      still at one point, and a burst of shots from the touch, the line's
      padding measured as there: about 20 lit, 0 not.
      1. *Held 0.3 s* on a closed line: lit from the first frame until the
      lift. At the lift it opens, its body comes and the header and Reply
      move to it, as at a quick tap. No loupe, no word selected, no menu.
      2. *Held 0.8 s* on another closed line: the same, lit until the lift,
      and it opens at the lift.
      3. *Held 1.5 s* on a closed line: lit until about 1.2 s, then not; no
      loupe, no word selected and no menu in any frame; nothing opens at
      the lift, and nothing else changes. On the build before, a word was
      selected at about 0.7 s and the Copy menu came at about 1.4 s.
      4. *An open letter's line*, held 0.8 s: it closes at the lift.
      5. *A held finger that scrolls.* A finger on a closed line, held half
      a second, then dragged up a screen and lifted: the line may light at
      the touch and goes as the stack moves; nothing opens. A flick of the
      stack, and a finger put on a line while it still moves: the stack
      stops, and nothing opens.
      6. *A quick tap* on a closed line: it opens, as before; again: it
      closes. Two lines 0.3 s apart: both open. Then two closed lines, the
      first a letter with a Cc and the second one without, or the other
      way, so the header changes height as the first one's body comes: a
      quick tap on the first, and at once a finger held 0.8 s on the
      second, past the moment the first one's body comes. Both open, or
      say which did not; the second, its press cut by the pane's scroll,
      is WebKit's own tap at the lift.
      7. *A letter's text.* A finger held on a word in an open letter's
      body: WebKit selects it and shows its menu, as before. Then, the
      word still selected and the menu up, a quick tap on a closed line:
      it opens, and the selection, its handles and the menu go.
      8. *VoiceOver*, if it is turned on for the check: a closed line found
      and double-tapped opens, once; again, it closes. VoiceOver off after.
      *Not tried on the simulator: the host tests read the script, and it
      was run outside WebKit (B-095). What WebKit does with a touch held a
      second, the line no longer selectable, is seen only here.*
      *Seen on the test iPad 2026-10-21, a build of the `line-press`
      worktree (a6a6c7c), master with B-092, B-093 and B-095: 1 to 7
      passed (B-095), but for 5's finger held half a second and then
      dragged, which cannot be made here in one touch; a drag from a line,
      a slow drift within 10 px for 0.3 s and a touch on a stack still
      moving stood in, each lit only while still and opening nothing. 8
      was not run, VoiceOver not being on for the check. The 1.5 s hold
      went dark between 1.23 and 1.32 s. In 6 the pair both ways: the line
      without a Cc tapped first, both opened, the second at the lift of
      its 0.85 s touch, never lit, by WebKit's own tap; the line with the
      Cc first, its body pushed the second line down before or as the
      finger landed, the finger ending on the signature's logo, a link,
      and WebKit put up the link's menu at about 1 s: the second did not
      open. In 7 the handles were gone by 0.20 s, the menu by 0.57 s.*

- [ ] **B-100, the sent sound.** On the test iPad, the test account only,
      built from the `feat-sentsound` worktree. A stands for the account's
      address; letters only to A with `+b100` before the @, subjects
      beginning "B-100".
      1. *Send.* In the composer, a letter to A with `+b100`, Send: the
      spinner, then one swoosh as the sheet closes. None before the sheet
      goes.
      2. *Silent and the volume.* Silent Mode on in Control Center, Send:
      no sound. Silent off, Settings, Sounds, the Ringer and Alerts slider
      low, Send: quiet. Then the volume buttons alone, the slider left as
      it was, Send: note whether they change it. Say which volume governs
      it.
      3. *Refused.* A letter Gmail refuses, over 25 MB: no sound, and the
      sheet stays with the alert.
      4. *The Outbox.* Airplane Mode on, Send: the sheet closes with one
      swoosh and the Outbox notice. Wi-Fi back, Refresh: the letter goes
      once, with no second sound.
      5. *The share sheet.* A page shared from Safari, Send: one whole
      swoosh as the sheet slides away (say if it is cut short), the share
      completes, and Safari is not held.
      6. *With music.* Music playing, Send: the two mix; the music does
      not stop.
      7. *VoiceOver.* VoiceOver on, Send: the swoosh and VoiceOver both
      heard, and focus lands where it did on the build before. VoiceOver
      off after.
      8. *Two quick taps* on Send: one sound.
      9. *The simulator.* The iOS 18.6 simulator on the Mac:
      /System/Library/Audio/UISounds/mail-sent.caf is in the runtime, and
      a Send plays it.
      10. *Headphones.* Wired headphones or a Bluetooth headset connected,
      Send: say where the swoosh plays, the headphones, the speaker or
      both. Informative, not blocking.
      11. *The share sheet offline.* Airplane Mode on, a page shared, Send:
      refused, no sound, the sheet stays. Since B-153 (2026-10-26) that is
      a share with a photo; a share with no files closes with one swoosh
      and waits in Blackmail's Outbox (B-153's check). Seen as first
      written, below.
      12. *Locked after Send.* A letter with a few photos, Send, and the
      iPad locked at once: say whether a swoosh comes from the locked
      iPad when the letter goes, and that the sheet has gone when it is
      unlocked. Informative, not blocking.
      *Not tried on the simulator but for step 9: the host tests hold the
      hook; the sound is the iPad's.*
      *Seen on the test iPad 2026-10-22, a build of `featA-int` (7eefcb4),
      the sound read from the iPad's system log: 1, 2's Silent Mode, 4, 5,
      6, 8, 11 and 12 passed (B-100). Each Send that went or was put in the
      Outbox asked for 1001 once, just after the 250 or the Outbox's word,
      and iOS played mail-sent.caf to the speaker for about 1.6 s, the
      share sheet's whole; none at a second tap, the Outbox's later send, a
      refusal, Delete Draft or a share's Cancel. In Silent Mode nothing
      played; the music played on; the locked iPad played it. The log gave
      each swoosh the system sounds' volume, 1.0, while the media volume
      was at nought; the level after the iPad's processing read silence
      for every swoosh, as for the music. Left for a person's ear: which
      volume governs it, the media volume included, 2's Ringer and Alerts
      slider and the volume buttons, 6's two heard together, 7, and
      whether any swoosh is heard at all; 10, no headphones being
      connected. 3 was not made on that build: its
      composer took photos alone, five at a time, which came in at 0.8 MB
      or less, and the share sheet left out a 114 MB video as past its
      25 MB room; 11's offline refusal was silent. Still to run on the
      test iPad: 3, as this tree can make it, a reply to a letter with
      large files, files picked to fill the composer's room before someone
      new is added, whose rows for that person the room does not count
      (B-108, Not covered), so Send refuses it. 9, the simulator, not
      run.*
- [x] **B-101, Mail's quote bars, and a file sent inline listed.** On the
      test iPad and the iOS 18.6 simulator, the test account only, built
      from the `bm-readpane` worktree (branch `feat-readpane`). The test
      letters are APPENDed to the test account or mailed to it from a host
      script (the test iPad has no Mail). Three panes unless a step says.
      1. *A reply from Mail,* its quote a bare `<blockquote type="cite">`:
      a violet bar down the quote's left, its words 5 pt from it, and the
      words violet. The attribution line in a quote of its own, as Mail
      writes it, has the same bar, joined to the quote's.
      2. *A reply from Gmail's web page:* Gmail's own grey bar gone, the
      same violet bar and violet words in its place, 5 pt in, not 0.8 ex.
      3. *Three deep:* a chain of three quotes, violet, then teal one level
      in, then green; a fourth level green.
      4. *In a conversation:* the same letters as one conversation's stack,
      the bars as in 1 to 3. Touch the stack as the bodies come: nothing
      moves once he has touched it.
      5. *A quote holding a signature's white sheet:* in the stack the
      sheet white with its own black words, not coloured, and the quote's
      bar beside it; on the letter's own page the sheet inverted as
      before (*white since B-130, as in the stack*). A quote inside the
      sheet, in the stack: Mail's light colour on the white.
      6. *Two panes and three:* 1 to 3 in each.
      7. *A PDF sent inline,* as Apple Mail sends one (multipart/mixed, the
      PDF `Content-Disposition: inline`, no `Content-ID`): its row in the
      header from the tap, grey, then blue as the letter lands; after a
      Refresh, a paperclip on its list row; the row tapped, the PDF in
      Quick Look. Then a letter of Apple Mail's other shape, its words
      going on after the PDF (multipart/alternative: the plain words, then
      multipart/mixed of HTML, the PDF, HTML): say whether the words after
      the PDF show. The host tests say they do not (B-101, Not covered);
      if so, record it under the next free number above B-114.
      8. *A signature's logo,* inline with a `Content-ID`, shown by `cid:`:
      the logo in the letter, no row in the header and no paperclip.
      9. *A forward sent inline as message/rfc822,* unnamed: its words in
      the pane as before, no row for the forwarded letter itself, and no
      paperclip unless it carries files of its own, which have their rows.
      If a real iPad with Mail is at hand, compare the bars with Mail's
      own: their colour, the 1 pt line and the 5 pt to the words.
      *Seen on the test iPad 2026-10-22, two rounds, three panes and two.
      The first, a build of `featA-int` (7eefcb4) with replies the app
      sent itself and no letter put in from the host: 1, 3, 4, 5's first
      half, 6 and 8 passed, and nothing new on the wire; 2, 5's second
      half, 7 and 9 were not possible, the account holding no letter of
      their shapes. The second, a build of `featAB-int` with letters the
      host made and APPENDed to the Inbox, never sent: 2 passed, Gmail's
      grey bar gone and the violet bar at the content's edge, the words 5
      pt from it; 5's second half passed, the quote inside a sheet in
      Mail's light violet and teal on the white; 7's first part passed,
      the PDF's row grey from the tap and blue at 0.89 s, the paperclip
      after Refresh, Quick Look on a tap; 9 passed, a forward's words with
      no row for itself, and a forwarded letter's own PDF with its row and
      the paperclip. 7's second part failed as the host tests said it
      would: the words after the PDF were nowhere, nor "Sent from my
      iPad" after the PDF in 7's first letter. Recorded as B-113, below.
      A shape beyond 9's, a note and then the letter it forwards inline,
      showed the note alone, the forwarded letter nowhere: B-114, below.
      Not yet tried: the iOS 18.6 simulator, and Mail's own bars beside
      these.*
      *Run again 2026-10-22, a build of int11 (e739d2c) with B-113 and
      B-114, the same letters under new headers: 7's second part passed,
      the words after the PDF and "Sent from my iPad" under its blue row,
      in three panes and two, and the shape beyond 9's drew the forwarded
      letter under the note with its header lines. Every step that can be
      made on the test iPad has passed. Left: the iOS 18.6 simulator, and
      Mail's own bars beside these, on a device with Mail.*
      *Seen 2026-10-25 on the Mac's iOS 18.6 simulator, an iPad (7th
      generation), on a simulator build of int16 (662d63d), the check's
      letters opened in the Trash: 1 to 3, 5 on the letter's own page, and 6
      to 9 passed (B-101). The bars and words violet, teal and green on
      black, the exact figures, their match with the host's and the 5 pt not
      read again from the full-size shots kept; a quote in a signature's
      sheet in Mail's light violet and teal on the white; the inline PDF's
      row grey under "Loading…", blue once landed, its paperclip, Quick
      Look, and the words after it. In 4 a conversation's stack drew the
      same bars, letter two's line above letter three in its first shot. Not
      done there: 4's touch as the bodies come and 5 in the stack, both
      passed on the test iPad 2026-10-22. Left: Mail's own bars beside
      these, on a device with Mail.*
- [x] **B-103, pull to refresh and the status-bar tap.** On the test iPad
      (16.5.1) and the iOS 18.6 simulator, the test account only, built
      from the `feat-pullrefresh` worktree, in three panes and in two. A
      stands for the account's address; letters only to A with `+b103`
      before the @, subjects beginning "B-103". The connection log is the
      five taps on the line under the list.
      1. *A pull.* The Inbox at its top. Pull the list down past its top
      and let go: a grey spinner turns above the first row, and the line
      says "Checking for Mail…". Mail a letter To A with `+b103`, Subject
      "B-103 one", from a host, and pull again: it lands at the top, the
      spinner goes, nothing jumps, and the line reads "Updated Just Now".
      Once with the finger held down past the top until the letter is
      there, then let go: the rows do not jump under the finger, and the
      list springs back to the top. Once, while the spinner turns, scroll
      down a little: the search field stays under the bar, with no gap
      above it. *Run again:* ten quick pulls, each about 0.3 s from the
      touch to the lift and far enough for the spinner, so that the page
      answers just after the lift, as the list springs back: each time
      the spinner stays at its rest until the list is still, then goes,
      and the list closes up to its top, with no band left above the
      search field. Then the view button: the panes move, and the log
      does not say "switched at once".
      2. *No connection.* Airplane Mode on, pull: the Refresh button's
      alert, "Can't connect to mail server.", the spinner goes, and no
      gap is left above the first row. OK. Airplane Mode off. *Run
      again,* with three quick pulls let go about 0.3 s after the touch
      and one slow pull held 1.5 s: the alert comes on only once the
      finger has lifted, the list springing back to its top under it, and
      after OK no spinner turns and nothing is left pulled down. In three
      panes, one alert only: none from the Mailboxes under the finger,
      and no second "Can't connect to mail server." after OK or at the
      next touch.
      3. *One page at a time.* Pull, and tap Refresh while the spinner
      turns: one page FETCH in the connection log. Then, after the page
      has come, tap Refresh: a second page FETCH, as before.
      4. *Edit mode.* Edit, tick two rows, pull: the list only bounces, no
      spinner, and the ticks stay. Done.
      5. *Search.* Tap the search field, pull: only a bounce, the keyboard
      and the field as they were. Type a word, pull: only a bounce, the
      words stay. With results showing, pull: only a bounce, the results
      stay. Cancel, pull: the spinner, as in 1.
      6. *A day.* Go to Date, a day some weeks back, then pull at the top
      of that day's list: nothing but the bounce; scrolling up loads the
      newer pages as before. Refresh: back at the newest, and a pull
      works again. *Run again, with the pull made at the top of the day's
      list,* which the first run never reached: the landing fetches the
      page above the day at once, and scrolling up fetches each next one
      before the top is in sight. So: in Trash, Go to Date a day with
      more than 120 letters newer than it, and let it land ("Showing" and
      the day on the line). Airplane Mode on, which stops the newer pages
      coming, silently. Scroll up to the very top of the list: its first
      row is not Trash's newest, and the line still says "Showing". Pull
      it down past its top as far as in 1 and let go: only the bounce, no
      spinner, no alert, no page in the log. A pull offered there would
      turn the spinner and put up "Can't connect to mail server.".
      Airplane Mode off; scrolling up loads the newer pages as before.
      7. *The spinner left.* Pull, and tap the view button while it
      turns; pull, then Home and back; pull, then another folder while it
      turns, and back to the Inbox: each time no spinner stays turning,
      and no gap is left above the first row. *Run again,* each once with
      the tap made at once after the lift and once while the spinner
      turns at its rest; Home or another app opened. Then, as the list
      springs back after a pull whose page has just answered, Edit and
      Done, and the search field and Cancel: no spinner stays turning,
      and a band, if one is left as the spinner goes, closes up to the
      top as the spring-back ends, with nothing touched; the next switch
      of the panes moves them. A band left until a touch is the risk
      B-103 records.
      8. *B-096.* Three panes, the Inbox at its top, pull and let go so
      that the spinner shows, and tap the view button as the list springs
      back: the switch is made, the bounce ends early as B-096 records,
      the spinner goes when the page answers, and no gap is left in two
      panes. *Run again,* the tap 0.1 to 0.3 s after the lift, and once
      0.25 s after: the spinner goes as the list comes to rest in two
      panes, no gap, and the next switch back to three moves the panes.
      9. *The Outbox.* As in B-072's check: open a letter with a file over
      1 MB, Airplane Mode on, Forward it To A with `+b103`, Subject
      "B-103 Outbox": "Message is in the Outbox…". Airplane Mode off; a
      minute in the Inbox leaves it waiting. Open the Outbox and pull: its
      row says "Sending…", the spinner goes without waiting for it, and it
      goes once: one copy in Sent Mail, the Outbox empty.
      10. *Held mail.* The Inbox scrolled down a screen, a letter mailed To
      A with `+b103` from a host, and the watch's check made (half a
      minute): not on the list yet. Scroll to the top, and pull as soon
      as the list is there: the letter is on the list, once.
      11. *VoiceOver*, if it is turned on for the check: at the top of the
      Inbox, a three-finger scroll down: the refresh is announced, and the
      connection log has one page FETCH. Once the page has answered, the
      spinner goes and no band is left above the search field; three
      times, and once with Airplane Mode on, one alert. By hand: from
      outside only one finger can be put on the screen. VoiceOver off
      after.
      12. *Thirty.* Thirty pulls in a row, each let go as the last one's
      spinner goes: one page FETCH each, never two out at once in the log,
      and Refresh still works after.
      13. *The status bar.* Tap it far down the Inbox, over the list: the
      list goes to its top, and mail held below the top goes on. Over the
      Mailboxes column: the folders go to their top. In two panes with the
      list in front: the list goes to its top. With search results
      showing: they go to their top and stay. In Edit mode with two ticks:
      the top, and the ticks stay. With the composer open: nothing behind
      it moves.
      *Seen on the test iPad 2026-10-22, a build of `feat-pullrefresh`
      (4093de3), three panes and two: 3, 4, 5, 9, 10, 12 and 13 passed,
      13's Mailboxes part not possible, every folder fitting the column;
      11 not possible, one finger being all that can be put on the screen
      from outside. 1, 7 and 8 failed: a page answered as the list sprang
      back left it 60 pt below its top with no spinner, 11 of 13 such
      pulls, in two panes too. 2 failed: offline, a quick pull's alert
      came on as the finger lifted, and after OK the list stayed 168 pt
      down with the spinner turning until touched, 2 of 2. 6's pass was
      not supported: the pull at the top of a day's list was never made.
      All four failures made again on a fresh launch. Both faults fixed
      since, as B-103 in KNOWN_ISSUES says; 1, 2, 6, 7 and 8 to run again
      as above, and 11 by hand.*
      *Run again 2026-10-22, a build of int9 (8607083): 1, 2, 6, 7 and 8
      passed, both faults gone. 1: ten quick pulls answered as the list
      sprang back, the spinner held at its rest, gone at 0.75 to 0.81 s,
      the list closed up by 1.06 s, no band; the view button then moved
      the panes. 2: offline, the alert 0.07 to 0.12 s after the lift,
      nothing left pulled down, one alert a pull. 6: at the top of a day's
      list in Trash, offline, two pulls only bounced, nothing in the log.
      7: the view button, another app, another folder and Edit, at once
      and at the spinner's rest: no spinner left, no band, the next switch
      moving the panes; its search field and Cancel cannot be made as the
      list springs back, the field taking no tap while the list moves, as
      with a finger. 8: the switch at once as B-096 records, the spinner
      gone at rest in two panes, no gap. Left: 11, VoiceOver's
      three-finger scroll, by a person's hand; 13's Mailboxes part, every
      folder fitting the column; the simulator.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 13's Mailboxes
      part passed, the size test's labels making the column scroll: scrolled
      to its end, a tap on the status bar over it took the folders to their
      top, Inbox first; again with the Inbox list scrolled down as well, the
      same tap moved the column alone, and one over the list then took the
      list to its top (B-103). Seen 2026-10-25 on the Mac's iOS 18.6
      simulator, an iPad (7th generation), on a simulator build of int16
      (662d63d): 1, 4, 5, 7, 8, 12 and 13 passed, no band and no spinner
      left, Refresh fetching a page after thirty pulls. Not looked at a
      second time there, though in the shots and the log kept: 1's ten quick
      pulls, 8's next switch back to three panes, and 12's 25 page FETCHes,
      never two out at once. Not shown there: 13's Mailboxes column and
      search results. Not settled there: 3, the touches coming some 0.4 s
      apart, so that the pull's page had answered before the Refresh, which
      fetched a second page; 3 passed on the test iPad 2026-10-22. Not
      possible there: 2 and 6's offline half, the simulator having no
      Airplane Mode, and 9 and 10, which need a send or a letter mailed; 6's
      first half not reported. 11, VoiceOver, is not needed.*
- [x] **B-102, the reply and forward arrows.** On the test iPad, the test
      account only, built from the `feat-arrows` worktree (part 2, when it
      is built, from its own). A stands for the account's address; letters
      only to A with `+b102` before the @, subjects beginning "B-102".
      Flags are set from a host over IMAP for part 1, on the test
      account's Inbox: `UID STORE n +FLAGS (\Answered)`, `+FLAGS
      ($Forwarded)`, and `-FLAGS` to take them off; the app shows them at
      its next Refresh. The letters can be put in the Inbox from the host
      by APPEND, so nothing is sent. Nothing in the app is answered or
      forwarded for this check.
      0. *Informative, not blocking*, on any Apple device with Mail (the
      owner's; the test iPad has none, B-028): add the test account, reply
      to one "B-102" letter and forward another, then from a host `UID
      FETCH n FLAGS` on both originals in INBOX and in All Mail. Expect
      `\Answered` on the first and `$Forwarded` (or `Forwarded`) on the
      second. This says whether the letters he answered in Apple Mail show
      arrows from the first launch.
      1. *The three marks.* Three read letters, "B-102 replied", "B-102
      forwarded" and "B-102 both", each its own conversation; `\Answered`
      on the first, `$Forwarded` on the second, both on the third.
      Refresh: a grey arrow turning left in the first row's gutter, where
      the unread dot goes; one turning right in the second's; the left one
      in the third's. Each about the dot's width, grey as the preview's
      words, centred on the name's line; the names, the dates and the
      previews where they were.
      2. *Beside a file, and unread.* A read letter with a photo, "B-102
      file", `\Answered`: the arrow in the gutter and the paperclip at the
      end of the subject's line. "B-102 unread", `\Answered`, marked unread
      in the app: the blue dot and no arrow. Opened and read: the dot goes
      and the arrow comes.
      3. *A conversation.* Two letters in one thread, "B-102 thread" and
      "Re: B-102 thread", both read, the second with In-Reply-To and
      References naming the first's Message-ID, and the two seen as one
      row before the flags are set. `\Answered` on the newer alone: the
      row has the arrow. Taken off it and put on the older alone: no arrow.
      Back on the newer alone, and the older made unread from the host
      (`-FLAGS (\Seen)`): the dot, and no arrow.
      4. *VoiceOver*, if it is turned on for the check: the rows of 1 read
      "Replied, …", "Forwarded, …" and "Replied, …" before the names; the
      unread row of 2 "Unread, …", with no "Replied"; the conversation of
      3, its older letter unread, "Unread, …", with no "Replied".
      VoiceOver off after.
      5. *Kept.* End the app, Airplane Mode on, open it: the rows of 1 to 3
      keep their arrows as the server last said, under "Updated …".
      Airplane Mode off.
      6. *Two panes and three*, and Edit mode: the arrow stays in the
      gutter beside the circles, where the dot goes. The look again on the
      iPadOS 18.6 simulator on the Mac, its grey set beside Mail's in
      Apple's picture (the guide's "Flag emails" page): Mail's is lighter
      than the preview's words, this one the preview's grey (D-020).
      7. *Put back.* Move the B-102 letters to Trash.
      *Seen on the test iPad 2026-10-22, a build of `featAB-int`
      (1b5d096), the letters made on the host and marked from it: 1, 2, 4,
      5, 6's iPad half and 7 passed (B-102). The arrows 10 to 11 pt wide in
      the dot's column, the preview's grey, nothing else on the row moved
      and no STORE; beside a file, the paperclip at the subject's end;
      unread, the dot and no arrow; offline after a relaunch, the marks as
      the server last said; VoiceOver "Replied", "Forwarded", and
      "Unread" with no "Replied" where the row shows the dot. 3 failed:
      the first Refresh after the host's STORE split the conversation and
      named the newer letter "(unknown sender)", "(no subject)", 31/12/69,
      B-112, an older fault. Run again on a build of int9 (8607083) with
      its fix: 3 passed, one whole row with the right mark at every
      Refresh. Left: 0, on a device with Mail; 6's look beside Mail's
      picture, on the simulator.*
      *Looked at 2026-10-25 on the Mac's iOS 18.6 simulator, on a simulator
      build of int16 (662d63d): 6's look beside Mail's picture was not
      possible, no letter on the test account having `\Answered`,
      `$Forwarded` or `Forwarded` and the run setting no flag, so no row
      drew an arrow; the preview's grey, the arrow's, read 142 on black
      there, as on the host (B-102). Left as before: 0, on a device with
      Mail; 6's look beside Mail's picture, with a letter marked from the
      host.*
- [ ] **B-104, his own letters in Inbox conversations.** On the test iPad,
      the test account only, built from the `bm-threads` worktree (branch
      `feat-threads`). A stands for the account's address; J is a second
      test address; letters only between them with `+b104`, subjects
      beginning "B-104". Three panes.
      1. *Between.* J writes to A; A reads it and replies; J writes
      again. In the Inbox, open the conversation: A's reply is between J's
      two letters, closed to its line, a moment after J's second letter has
      come. Opened, it reads "Found in Sent Mail" in grey over its body.
      J's second letter, the one open, does not move as A's line goes
      in: its first line stays where it is on the glass, and A's line takes
      the place of J's first line at the top. Once without touching the
      pane, a burst of shots from the tap; once with a finger dragging the
      pane slowly as A's line comes: J's second letter's first line moves
      with the finger alone, with no step of a line, and A's line goes in
      above it once the stack is still. Then open it again within ten
      minutes: the same picture from the first frame, A's line at the top
      and J's second letter under it.
      2. *Before and after.* A conversation A began, J answering twice: A's
      letter at the top. One A answered last: A's letter below the newest,
      and the pane still opens at the Inbox letter it opened at before.
      3. *The header stays.* Open A's line: its body comes, from Sent Mail
      in the log, and the header, Reply and Delete stay on J's letter.
      Delete: J's letter goes to Trash, A's stays in Sent Mail, and the
      Inbox's count is right.
      4. *To himself.* A letter from A to A inside a conversation shows
      once.
      5. *Airplane Mode.* On, then a conversation not opened in the last
      ten minutes: exactly the stack of the build before, no alert. Off.
      6. *The log.* One `SELECT "[Gmail]/Sent Mail"`, one `UID SEARCH
      X-GM-THRID` and two `UID FETCH`es for each conversation opened, all
      after the newest letter's own FETCH; none when it is opened again
      within ten minutes, and A's letters in the first frame; the second
      `UID FETCH`, the few words, not sent when a letter of the Inbox is
      opened while the search is out, and A's line then without its
      words; and the lookup called off when another row is tapped while it
      is out, nothing after the command on the wire.
      7. *A reply just sent.* Reply from the stack, send, open the
      conversation again: the new reply is there.
      8. *VoiceOver and the switch.* VoiceOver reads "Found in Sent Mail"
      with the letter. Settings, Complete Threads off, then a conversation
      opened: the stack of the build before, nothing looked up. On again.
      9. *The iOS 18 simulator*, for the layout of the line, the label and
      the switch.
      After the install on his iPad: read the SLOW notes for `SELECT
      "[Gmail]/Sent Mail"`.
      *Seen on the test iPad 2026-10-22, a build of B-104 as first built,
      with other work: 2 to 7 and 8's switch passed. 1 passed untouched
      and again within ten minutes, and failed with a finger on the pane:
      J's second letter dropped one line as A's line went in, and went on
      with the finger from there. 8's VoiceOver could not be tried, the
      app being on VoiceOver's Direct Touch list there, and 9 was not run.
      Changed the same day (B-104 in KNOWN_ISSUES): A's line is held while
      the stack moves under a finger, coasts or bounces back, as the pane's
      scroll view says and as the page hears, and goes in once it is
      still. To run again, from a build with both steps of the change: 1
      in full; 8's VoiceOver, once the app is off the Direct Touch list;
      and 9. 1 with a finger, as on 2026-10-22: before each run another row
      selected, Refresh, so nothing is remembered, and J's second letter
      made unread from the host; a burst of shots from the tap each time,
      A's line found when the log has the summary FETCH in Sent Mail
      (about 0.6 s that day). Each time J's second letter's first line
      moves with the finger alone, with no step of a line, and A's line
      goes in above it within about a third of a second of the stack
      coming to rest. (a) *The finger at the tap*, as that day: within
      0.05 s of the tap, drag the pane up some 100 to 120 px of the shots
      over 1.5 to 1.8 s; then the same with the finger held still a second
      in the middle as A's line is found, then dragged on. That finger
      lands on the page before the stack's, whose first frame came about
      0.2 s after the tap, so the stack's page hears none of its touches,
      and only the pane's word holds A's line. (b) *The finger on the
      stack*: put it down once the stack is drawn, 0.3 s or more after the
      tap, and the same drag; then with a pause of half a second, and one
      of six seconds, longer than the page's own five, in the middle as
      A's line is found, then dragged on; and a flick, A's line found while
      the stack coasts. (c) *A pull at the top*: the stack opens with J's
      first line at the top of the pane; once it is drawn, pull it down
      some 60 px and let go as A's line is found, so it bounces back. J's
      second letter does not step, and A's line goes in after the bounce.
      (d) *A finger on J's first line*, put down once the stack is drawn
      and lifted at about 1 s, A's line found meanwhile: the lift opens
      that letter, once, its line where it was, and A's line goes in
      after. Then the same with the finger put down within 0.05 s of the
      tap: J's first line stays under the finger while it is down, and A's
      line goes in after the lift; what the lift opens, if anything, is
      WebKit's, the touch having begun on the page before, so write down
      what it does. If J's first line moves from under that still finger,
      or J's second letter steps in (c), UIKit did not count the finger
      or the bounce as moving: write it down, it is a case KNOWN_ISSUES
      names as not covered.*
      *Run again 2026-10-22, a build of int9 (8607083): 1 passed in every
      case made but one at-the-tap hold, and 2 and 7 again; the drop is
      gone. Untouched, A's line in at 0.63 s and J's second letter still.
      (a) The finger at the tap, 100 px over 1.5 s, a slow short drag,
      and a pause of 1.2 s in the middle of a drag: J's second letter
      moved with the finger alone, no step, A's line in once the stack was
      still, 0.25 to 0.49 s after rest in the slow drag. (b) A flick, A's
      line found as the stack coasted: no step. (d) A finger on J's first
      line put down once the stack was drawn: the line stayed under it,
      the lift opened it once, A's line in after. Put down at the tap,
      three times: the line stayed under the finger and J's second letter
      still. Once A's line, found during the hold, went in 0.33 s after the
      lift, which opened nothing; once it was found only after the lift;
      and in one run of three WebKit missed the finger's lift, so A's line
      waited for the script's five-second bound for a lift it never hears
      before it went in, still out at 4.07 s. Within ten minutes, A's line
      from the first frame. Still to run on the test iPad: (b)'s drag from
      a finger put down once the stack is drawn, its half-second pause and
      its pause of six seconds, the drags and the pause of that day having
      all begun with the finger at the tap; and (c), the pull at the top.
      Left: 8's VoiceOver, the app being on the Direct Touch list; 9, the
      simulator.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): (c) passed, on a
      conversation the host put in the Inbox three and four days back, J's
      two letters and A's answer between them in Sent Mail alone. Untouched,
      A's line took J's first line's place at the top between 0.40 and 0.54
      s, J's second letter still. Twice the stack pulled down at its top,
      the finger 60 px, the stack some 25, and let go as A's line was found:
      it bounced back to rest by 1.23 s, J's second letter never stepping,
      and A's line went in within 0.15 s of the rest, the stack then as
      untouched. Seen 2026-10-25 on the Mac's iOS 18.6 simulator, on a
      simulator build of int16 (662d63d): 9 passed, on a conversation of the
      size test's: his line at the top of the stack, "Found in Sent Mail" in
      small grey between it and his words when opened, the header staying on
      the other's letter; Settings' Complete Threads on under Organize by
      Thread with its line; nothing cut or overlapping (B-104). Left: (b),
      the drag from a finger put down once the stack is drawn, with its
      pauses of half a second and of six seconds. 8's VoiceOver is not
      needed.*
- [x] **B-105, several words and recent searches.** On the test iPad, the
      test account only, built from the `feat-search` worktree. A stands
      for the account's address; letters only to A with `+b105` before
      the @, subjects beginning "B-105". Smart Punctuation on (Settings >
      General > Keyboard), as on his. Three panes unless a step says two.
      (A) Several words:
      1. *Two fields.* A letter to A, "B-105 one", its body holding a word
      found nowhere else in the mailbox, say "quillwort". All Mailboxes,
      the account's name as From shows it and quillwort: the letter is
      found. The same two the other way round: found. Quillwort and a word
      in no letter: "No results".
      2. *Typed on the iPad's keyboard.* "Plan B" in the keyboard's double
      quotes, which it makes “Plan B”: the letters with the phrase come
      among the hits, and letters with plan and b apart may come too, as
      Gmail's BODY matches all the words of a quoted part anywhere; which
      came, written down. Plan B with no quotes, and in single quotes,
      which it makes ‘Plan B’: every letter with "plan", as Mail. The
      keyboard's double quotes with nothing between them, “”, then Search:
      "No results", and a tap in the emptied field does not show “”
      among the recent searches. garden--party, which it makes
      garden—party: the letters with both words. A word with an accent,
      as Müller. A paragraph pasted from a letter: hits or "No results",
      never "Could not search. Check the connection."
      3. *Both scopes.* Each of 1 in Current Mailbox in the Inbox too. A
      "B-105" letter deleted to Trash, then found by two of its words in
      All Mailboxes: it comes among the hits in date order.
      4. *The log.* The connection log shows a two-word search as one UID
      SEARCH of two groups in parentheses side by side; a one-word
      search's line is as on the build before.
      5. *Time.* In All Mail, a three-word All Mailboxes search timed
      against a one-word one, from the last letter typed to the list.
      (B) Recent searches:
      6. *None yet.* After a password Save in Settings, which takes them
      away: a tap in the field shows Cancel and the scope bar, and nothing
      under them.
      7. *Four.* Four searches, each ended with Search on the keyboard,
      then Cancel, and a tap in the empty field: "Recent Searches" and the
      last three under the scope bar, newest first. A letter opened from a
      fifth search's results: that search is first.
      8. *A tap.* In Current Mailbox, a tap on the second: its words in
      the field, the keyboard down, and the results at once, the folder's;
      it is first next time.
      9. *The band.* A letter typed: the block goes and the band is the
      field and the scope bar again; deleted back to empty: the block is
      back. Nothing drawn over the first row with the keyboard up, in two
      panes and in three, after turning the iPad, and with VoiceOver on,
      which reads each row as "Recent search", its words, and "button";
      whether "heading" is said after it too, written down. With
      VoiceOver on and the recent searches showing, the first letter typed
      on the keys: the band shrinks and the cursor stays on the keys. A
      recent search double-tapped: the cursor goes to the field, which
      reads its words, and stays there as the results come; anywhere
      else, where, written down. VoiceOver off after.
      10. *Relaunch.* The app ended in the app switcher and opened: the
      searches are still there.
      11. *A week.* The iPad's date put 8 days forward, the app opened, a
      tap in the field: none. The date put back: they show again, as a
      read takes nothing out of the file.
      12. *Put back.* The "B-105" letters to Trash.
      *Seen on the test iPad 2026-10-22, a build of the integration
      branch with this one in it (1b5d096): 1, 3, 4, 5, 7, 8, 10, 11 and
      12 passed, 9d's band, and 2 but for its word with an accent; 6, 9b,
      9c and 9d's cursor could not be run. Two faults, fixed since
      (B-105): Müller read "Could not search. Check the connection." in
      both scopes, Gmail refusing 8-bit text in a quoted string; and the
      keyboard's delete back to an empty field put the block over the
      first rows, and Cancel left the Inbox 164 points down. To run again,
      on a build from the `feat-search` worktree, Smart Punctuation on:*
      - *2, the accented words, in All Mailboxes and in Current Mailbox:
        Müller, the ü from the u key's accent popover; "garden müller";
        don’t, the keyboard's apostrophe, with a "B-105" letter whose
        subject says "don’t"; and a paragraph with “ ” and ’ in it, typed
        in a "B-105" letter on the iPad, copied and pasted into the field.
        Hits, never "Could not search. Check the connection." The
        connection log has one UID SEARCH line for each mailbox, answered
        OK, each such word in it as `{7+} Müller`, its size and the word,
        and each ASCII word in its quotes as before.*
      - *9a, the Inbox at its top, three recent searches kept, in three
        panes and in two: Search, q, its hit, then each way of emptying
        the field in turn: the keyboard's delete; Select All and Cut; the
        undo on the keyboard's shortcut bar; a recent search tapped, the
        field tapped and its words deleted; the clear button. Each time
        the block comes back with the first row wholly below it, and stays
        so; Cancel leaves the Inbox at its top, and after five rounds
        still at its top. The same from part-way down the Inbox, scrolled
        by hand before Search: the block covers the list's top rows at the
        first tap in the field, as Mail's covers its list; the rows below
        it at that tap stay below it after each emptying, and Cancel
        leaves the Inbox where it was. With VoiceOver on, the delete key
        once, the same.*
      *Run again 2026-10-22, a build of int9 (8607083), Smart Punctuation
      on: 2 and 9a passed, both faults gone. Müller, "garden müller",
      don’t and the pasted paragraph with “ ” and ’ found their letters in
      both scopes, 30 SEARCHes all answered OK, each 8-bit word a `{n+}`
      literal. 9a: the five ways of emptying the field, from the top and
      from part-way down, in three panes and two, and with VoiceOver on:
      the block back with the rows below it that were below it at the
      focus, and Cancel leaving the Inbox where it was. From part-way
      down, the block covers the list's top rows at the first tap in the
      field, as Mail's covers its list: two rows in sight before Search
      were under it. 9a's mark for part-way down is worded so since
      2026-10-23; it had the rows in sight before Search stay in sight.
      Left: 6, which needs the password
      typed in Settings, its "none yet" seen without it before any search
      was kept; 9b, the iPad turned, by a person; 9c and 9d's cursor,
      VoiceOver past the field, the app being on the Direct Touch list,
      where the cursor stayed on the field throughout.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 6 passed: the
      test account's password typed into Settings and saved, then, before
      any search, a tap in the field showed Cancel and the scope bar and
      nothing under them, where "Recent Searches" and three had shown before
      the save; the three were made again after (B-105). Left: 9b, the iPad
      turned, by a person; 9c and 9d's cursor, VoiceOver, are not needed.*
- [x] **B-112, a mark set on another device, told inside the listing.** On
      the test iPad, the test account only, on a build of master, where it
      is merged. Organize by Thread on, three panes, the Inbox open at its
      top. A conversation of two letters at the top of the Inbox, sent from
      the host, the second a reply to the first (In-Reply-To and References
      naming it), on one row, as in B-102's check. Copy down, for every
      Refresh, its NOOP, the listing's `UID FETCH` and every line of its
      answer for the two UIDs, and its `SESSION-IDENT` line.
      1. *The news inside the listing.* From the host, over IMAP on the
      test account, `UID STORE <newer> +FLAGS (\Answered)`, and tap Refresh
      within a second of its OK; then `-FLAGS (\Answered)` and Refresh at
      once; then `-FLAGS (\Seen)`, `+FLAGS (\Seen)`, `+FLAGS (\Flagged)`
      and `-FLAGS (\Flagged)`, each with Refresh at once; then the same on
      the older letter; then once more on the newer with Refresh 2 s
      after the OK. Repeat until the news, `* n FETCH (UID u FLAGS (…))`,
      has come inside the listing's answer, after the letter's own line
      and before the tagged OK, at least three times, the log saying each
      time whether it came there or on the NOOP before it. Every time,
      whichever: one row for the conversation, its sender, subject and
      date the newer letter's, never "(unknown sender)", "(no subject)" or
      31 December 1969 (12/31/69 with a US region since B-119, 31/12/69
      before), the older letter not on a row of its own, and
      `SESSION-IDENT … msgid=` a number, never `-`. Where the news came
      inside the listing, the row shows the new mark at that Refresh: the
      dot with `\Seen` off, the flag with `\Flagged` on, and, on a build
      with B-102's arrows, the arrow with `\Answered` on and none with it
      off. No `FETCH-NO-ENVELOPE` line.
      2. *Every mark off.* The newer letter with `\Seen` alone, no arrow
      and no flag: `-FLAGS (\Seen)` from the host, Refresh at once,
      repeated until the news `FLAGS ()` comes inside the listing: the row
      whole and with the dot at that Refresh.
      3. *Put back.* Every mark as it was at the start, from the host, a
      Refresh to see the row as it was, and the conversation deleted from
      Edit mode, as at the end of B-102's check.
      *Not tried on the simulator: the host tests hold it, the scripted
      server telling of the mark where Gmail told the iPad (B-112).*
      *Seen on the test iPad 2026-10-22, a build of int9 (8607083), the
      marks set from the host: 1 to 3 passed but for `\Flagged` (B-112).
      Of 34 Refreshes made at once after a STORE, 13 had the news inside
      the listing, after the letter's own line and before the OK, three of
      them the old flags in the line and the new in the news, two
      `FLAGS ()`: every row whole, in its conversation, with the new mark
      at that Refresh, `SESSION-IDENT` naming a Gmail id each time, and no
      `FETCH-NO-ENVELOPE` line. `\Flagged` was not set from the host;
      `$Forwarded` stood in, its news the same line. B-102's step 3 passed
      with it. Still to run on the test iPad: 1's `+FLAGS (\Flagged)` and
      `-FLAGS (\Flagged)` from the host, Refresh at once, until the news
      has come inside the listing, the flag on the row at that Refresh and
      off at the next, then put back as in 3. It is a STORE on the test
      account, which B-106's run set `\Flagged` on.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): `\Flagged`
      passed, on a conversation of two the host put in the label Notes
      (B-112). Eleven pairs of `+FLAGS (\Flagged)` and `-FLAGS (\Flagged)`
      from the host on the newer letter, Refresh tapped within a second of
      each OK: of the 18 Refreshes in the logs the news came inside the
      listing 6 times, once for a `+FLAGS`, on the NOOP 11 times and nowhere
      once, the letter's own line in the listing carrying the new flags each
      time. Every row whole, the conversation one row, the newer letter's;
      the flag on at the Refresh after every `+FLAGS`, the one with its news
      inside the listing too, and off at the next; the log's id for the
      letter a number each time; no `FETCH-NO-ENVELOPE`. Put back: the flag
      off, the conversation in the Trash by the host. Every step has now
      passed.*
- [x] **B-106, the Flag button's sheet.** On the test iPad, the test
      account only, built from the `bm-flagmenu` worktree (branch
      `feat-flagmenu`) at the merged commit. A stands for the account's
      address; letters only to A with `+b106` before the @, subjects
      beginning "B-106". Three letters to A, two of them answered from
      Gmail's web so they make a conversation.
      1. *The sheet.* A letter opened, then Flag: the sheet opens under the
      Flag button, Flag and Mark as Unread. UIKit draws no Cancel in a
      popover, as for Reply's sheet; whether one shows, written down. A
      tap outside closes it and changes nothing.
      2. *Flag.* Flag, then Unflag from the sheet again: the flag on the
      row and in the header comes and goes as before, and the star on
      Gmail's web follows.
      3. *Mark as Unread.* The dot comes back at once, the Inbox's count
      goes up by one, the letter stays in the pane, and the sheet then
      offers Mark as Read. Mark as Read: the dot goes, the count down by
      one. Then Edit, its row ticked, Mark, Mark as Unread: the dot comes
      back, the letter stays in the pane, and the sheet offers Mark as
      Read, as the dot says.
      4. *Nothing reads it again.* Refresh, a letter sent to A arriving,
      and the view button switched both ways: the letter keeps its dot
      and the count stays. A tap on its row: read, the count down by one.
      5. *In a stack.* The conversation opened, an older letter's line
      opened, then Mark as Unread: the conversation's row has its dot, and
      on Gmail's web the older letter is unread and the newest is not. A
      tap on that line closes it, another opens it and marks it read.
      6. *No connection.* Wi-Fi off, then Mark as Unread: the dot comes
      and goes again, and the alert says so. Wi-Fi on.
      7. *VoiceOver* reads "Flag" or "Unflag", "Mark as Unread" or "Mark
      as Read", and the button for each, one swipe at a time.
      8. *Put back.* The "B-106" letters to Trash.
      Move to Junk, and Move to Inbox inside Junk, ruled 2026-10-26 and
      now on the `copy-junk` branch: their own check, "B-106, Move to
      Junk in the Flag sheet", at the end of this section.
      *Seen on the test iPad 2026-10-22, a build of int11 (e739d2c), the
      letters made on the host: 1 to 6 and 8 passed (B-106). The sheet a
      popover with no Cancel, a tap outside closing it with nothing
      written; the flag on the row only, the header drawing none, as
      before, and Starred following over IMAP; the dot 0.5 to 0.65 s after
      the tap, as the popover fades, the count at the server's OK. 6:
      offline the refusal is at once, so no frame shows the dot come and
      go; the alert says it, no dot is left and nothing is queued. Left: 7,
      VoiceOver past the sheet's first item, which it read, the app being
      on the Direct Touch list; the greyed item, its STORE answered in
      0.14 s, before the sheet could open; Move to Junk, the owner's.*
      *Seen 2026-10-25 on the Mac's iOS 18.6 simulator, an iPad (7th
      generation), on a simulator build of int16 (662d63d): 1 and the greyed
      item passed (B-106). The sheet a popover under the Flag button, Flag
      and Mark as Unread, no Cancel. An unread letter in the Trash tapped
      and Flag tapped just after: the sheet with Mark as Unread grey while
      the read mark's STORE was out, Flag blue. Put back: the two letters
      read made unread again from the sheet. Not shown: the tap outside and
      the times. With Flag about 0.4 s after the row the item was not grey,
      its shot not looked at a second time. Left: Move to Junk, the owner's;
      7, VoiceOver, is not needed.*
- [x] **B-111, the letters kept on the iPad.** On the test iPad (16.5.1)
      and the iOS 18.6 simulator, the test account only, built from the
      `feat-kept` worktree before it is merged (it changes one call in a
      forward's carried parts, `fetchCarried`). A stands for the account's
      address; letters only to A with `+b111` before the @, subjects
      beginning "B-111". Three panes. First mail A: P (plain), H (HTML with
      an inline photo), F (with a PDF), T (a conversation of three with J),
      L (two full photos, over 5 MB) and N, never opened.
      1. *Kept.* Open P, H, F, T's letters and L: one body FETCH each
      for P, H, F and T's letters in the log, each with a `KEPT-LETTER
      kept` note; L in parts, as B-054 opens it (a FETCH for its structure
      and header, then one for its text and one for its HTML, those it
      has), with
      `not-kept reason=size`. Open P, H and F again: no FETCH, each at
      once in a screen recording, H's photo shows, and F's PDF opens in
      Quick Look with nothing fetched.
      2. *Offline.* End the app in the app switcher, Airplane Mode on,
      launch: the kept Inbox. P, H with its photo, F with its PDF, and T
      open at once, with no alert. N and L: "This message could not be
      downloaded." and "Can't connect to mail server.", as today.
      3. *Nothing kept sent.* Still offline, Reply to P and Forward F: both
      go to the Outbox. Airplane Mode off: both go, the PDF's SHA-256 is
      unchanged, and the log shows its part's FETCHes naming X-GM-MSGID.
      4. *Gone.* Online, Delete P and move H to Spam; offline, relaunch:
      neither is in the Inbox or opens from it.
      5. *A password saved.* Save the password again in Settings, relaunch
      offline: nothing kept from before the save, no page of it and no
      letter; only what the sign-in after the save has listed since, the
      Inbox's page and any folder opened after, each under its age.
      6. *Not the server's word.* Mark F unread in Gmail's web, relaunch
      online, tap F before the page lands: shown at once, and the STORE
      follows a vouching `(UID X-GM-MSGID)` FETCH.
      7. *Complete Threads.* Open his line in an Inbox conversation. Then
      offline, within the launch and ten minutes, open the conversation
      again: his line from Sent Mail is there, and tapped says it could not
      be downloaded. Then end the app, relaunch offline, open the
      conversation: his line is not there, as nothing of his Sent Mail is
      kept (D-021).
      8. *Time.* A kept 3 MB letter against the same letter fetched (after
      a password save): from the tap to the letter drawn, and the shown
      note's ms. The kept note's ms for writing a 3 MB letter, with a list
      scrolled at the same moment, for the hitch, and its `free-ms`, the
      free-space reading's part of it. If `free-ms` is large, the floor
      is to be read once a launch, or every few minutes, instead.
      9. *The simulator.* The notes say `kept`, never `reason=space`.
      10. *The container*, where it can be read: `letters/` holds one
      `.eml` per letter kept, beside `letters.json`, and nothing else;
      `Kept/`, the account's directory and `letters/` carry the backup
      exclusion (xattr com.apple.metadata:com_apple_backup_excludeItem).
      The bounds, a full disk, a failed check, leftover files and the
      races are the host tests'.
      *Seen on the test iPad 2026-10-22, a build of int11 (e739d2c): 1, 2,
      3, 4, 6, 7 as it now reads, 8 and 10 passed (B-111). Kept at a first
      opening in 50 to 63 ms, L opened in parts and not kept; opened again
      from the copy by 0.27 s with nothing on the wire; offline after a
      relaunch, the kept Inbox and P, H, F and T at once, N and L as today;
      the reply sent by itself once online, the forward at Refresh (B-072),
      its PDF unchanged and fetched by F's Gmail id; P and H gone from the
      copy at their Delete and Move; F shown from the copy before the page
      landed, its STORE after the vouching FETCH; `letters/` and the backup
      exclusion as written. 7 as first written expected his line after the
      offline relaunch: it was not there, which is D-021's design, and the
      step now says so; within the launch it was there and said it could
      not be downloaded. 8: a 3 MB letter 1.25 to 1.37 s fetched, 0.27 s
      from the copy; a keep 62 to 85 ms, the free-space reading 44 to 58 ms
      of it, 70 to 90% of every keep; each 3 MB letter's first opening
      stood in for one fetched after a password save. Left: 5, which needs
      the password typed; 9, the simulator.* *8's last sentence done in
      B-136 (2026-10-25): the free space is read at a launch's first keep
      and held for five minutes, read again near the floor, and only a
      keep that read it gives `free-ms`; its own check is below.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), and 9 on the
      Mac's iOS 18.6 simulator, on a simulator build of int16 (662d63d): 5
      as it now reads and 9 passed (B-111). 5: the test account's password
      typed into Settings and saved, which wiped the copy, 15 pages and 90
      letters; the app ended and opened with Airplane Mode on: the Trash,
      kept before, opened with no rows and "Can't connect to mail server.";
      a letter of his kept before, tapped in Sent Mail, "This message could
      not be downloaded."; no letter left on the disk. What showed was what
      the sign-in after the save had listed since, the Inbox's page and Sent
      Mail's, under their age. 5 as first written, "no kept pages and no
      letters", cannot hold after any save, the sign-in keeping the Inbox's
      page at once, which B-053's check wants in the first frame; it now
      says what shows. 9: only `kept` and `shown` notes, `free-ms` only at
      keeps five minutes or more apart, each the first keep after five
      minutes (B-136), never `reason=space`,
      `cleared` or `not-kept`. Every step has now passed.*
- [x] **B-107, a reply's files and the Forward question.** On the test
      iPad, the test account only, built from the `feat-replyfiles`
      worktree before it is merged (it touches Send). A stands for the
      account's address; letters only to A with `+b107` before the @,
      subjects beginning "B-107"; each arrival's raw MIME read over IMAP
      from a host. A's second address is A with `+b107b`, added under the
      account in Settings for step 5 and taken out after. First mail A: P,
      a PDF and a photo shown in its body; L, a signature's logo alone.
      1. *Someone new.* Reply to P, a Cc of A with `+b107c` made a bubble
      with a comma: the photo's row and the PDF's appear under Subject
      with their weights. Send: at the Cc, and at the To, the PDF arrives
      as a file and the photo inline in the quote, under a `bmquote` id.
      2. *No one new.* Reply to P and Send: no rows, and nothing of P's in
      the raw MIME, as before.
      3. *Taken off.* Reply to P, the Cc added: the rows; the Cc taken
      off: they go. The Cc again, the PDF's row Removed, the Cc taken
      off: the photo's row stays, and goes in the quote.
      4. *Reply All* to a letter to A and A with `+b107c`: no rows.
      5. *His second address.* Reply to P with only the second address in
      Cc: the rows.
      6. *At Send.* Reply to P, a Cc typed WITHOUT a comma and Send tapped
      at once: nothing is sent, the rows appear, and VoiceOver, if on,
      goes to the first; Send again: it goes with the files. Reply again,
      a Cc typed and a tap into the body, which leaves the field: the
      rows appear at once. In landscape with the keyboard up, Reply All to
      a letter with P's files whose Cc runs to several lines (A with
      `+b107d` to `+b107k`), a Cc typed WITHOUT a comma and Send: the
      sheet scrolls to the first row. With VoiceOver on, Reply to P and a
      Cc made a bubble with a comma: the rows' names and weights are read
      out, and VoiceOver stays in the Cc.
      7. *Drafts.* Reply to P with the Cc and its rows, Save Draft,
      reopened from Drafts: the rows and the Cc are back. Send: one copy
      arrives, the photo inline and the PDF a file, and Drafts holds none.
      Again with the Cc typed WITHOUT a comma, then Cancel, Save Draft:
      reopened from Drafts, the Cc and the rows are there.
      8. *The Outbox.* Airplane Mode on, Reply to P with the Cc, Send: it
      goes to the Outbox. Off, Refresh: it leaves once, with its parts.
      Again, P deleted meanwhile in Gmail's web page and the app ended in
      the app switcher; Airplane Mode off, the app opened, Refresh: it
      leaves once with P's files, the log saying `CARRIED-PART found
      folder=[Gmail]/Trash`.
      9. *Forward.* Forward P: "Include attachments from original
      message?" at the Reply button, with Include, Don't Include and
      Cancel. Include: both rows. Don't Include: the photo's row alone,
      which goes in the quote. Cancel, and a tap outside: no letter.
      Forward L: no question, and its logo's row as before. Reply to L
      with the Cc: the logo's row, which goes in the quote.
      10. *Reference, not blocking.* On a real iOS 18 device with Mail (the
      owner's): when the files appear after a Cc is added, and whether
      they go when it is taken off; and what Mail's Don't Include does
      with a picture the body shows.
      11. *Put back.* The "B-107" letters to Trash, the second address out
      of Settings.
      *Seen on the test iPad 2026-10-22, a build of int11 (e739d2c), the
      originals made on the host: 1 to 9 and 11 passed (B-107), each
      arrival's parts byte for byte the original's. The Forward question a
      popover from the Reply button, its Cancel a tap outside. In 6's
      landscape case the sheet scrolled to the first row, the PDF's row
      staying under the keyboard, as built. A reply with a megabyte or more
      of the original's files waiting in the Outbox went as the app was
      left, as well as at Refresh. Left: 10, on a device with Mail.*
- [ ] **B-108, files and videos in the composer.** On the test iPad, the
      test account only, built from the `feat-composer` worktree before it
      is merged (it touches what Send carries). A stands for the account's
      address; letters only to A with `+b108` before the @, subjects
      beginning "B-108"; each arrival fetched over IMAP and its CRC
      compared with its LETTER-FILE line. Put on the iPad first, from a
      host: a PDF and a 30 MB file in On My iPad, a 19 MB video and a
      photo with a location in Photos, and a file named with a double
      quote.
      1. *The picker at all.* Attach File opens the document picker (the
      test iPad has the Files app now). A PDF from On My iPad arrives byte
      for byte, under its own name, and the log's `COMPOSE-PICK` line says
      `moves=true`, the copy in the app's Inbox.
      2. *A reply.* Reply to a letter from A with a PDF attached: the
      reply stays in the conversation.
      3. *Several.* Three files at once: three rows; Remove one; the two
      arrive.
      4. *Too large.* The 30 MB file: "The file could not be attached.",
      no row, and nothing is sent. *Since B-144, Mail's alert: "Unable
      to Attach", "One or more attachments failed to load."*
      5. *A video.* The 19 MB video through Photo Library: one
      `WIRE-OUT`, `LETTER-LATCH ok`, and the CRC matches the app's own
      H.264 copy, whose bytes its `SHARE-VIDEO made H.264` line gives
      (B-142): a 1080p HEVC video of 19 MB likely goes as its 720p copy
      (`made H.264 at 720p`), its copy at its own size being over the room
      by B-142's measure; one H.264 already goes as it came (`goes as it
      came, H.264 already`). Before B-142's second fix, Photos' compatible
      copy.
      6. *While it comes.* Send tapped while the video loads: the spinner,
      then it goes with it. Airplane Mode on while an iCloud original
      loads, Send: at three minutes "The photo could not be attached.",
      the sheet stays with Send, and nothing goes. Then several: five
      photos kept only in iCloud picked at once with Airplane Mode on,
      and Send tapped a minute after the pick: "Sending…" for three
      minutes from the tap at most, never fifteen, then one alert, "The
      photos could not be attached.", the sheet with Send, nothing gone,
      and the log's `COMPOSE-WAIT` line counting them out together.
      7. *A photo.* A composer photo arrives as a JPEG with no GPS, as
      "IMG_####.jpg": the picker's suggestion, which has no extension, and
      the one the intake gives a JPEG (B-108, Not covered). Since B-142's
      second fix, one of two, written down from its `SHARE-PICTURE` line:
      where Photos offers a JPEG beside the HEIC, as it did on the test
      iPad on 2026-10-26, that JPEG as its own bytes, its metadata replaced
      (`read=public.jpeg ... way=own bytes, metadata replaced`); a HEIC
      offered alone, made a JPEG in the app at its own size, its bytes the
      app's (`read=public.heic ... way=JPEG at factor 1 ... size=WxH`).
      Before B-142's second fix, Photos' compatible JPEG, as its own bytes.
      8. *Drafts.* Save Draft with the video, reopened from Drafts, Send:
      one copy arrives, and Drafts holds none.
      9. *Locked.* The iPad locked while the video uploads: it goes. And
      the iPad locked, or another app opened, for more than three minutes
      while a large video is still coming into the composer: back in the
      app, the video comes in, or has three minutes more, and is not
      counted out at once. *Reached on the test iPad 2026-10-25 (round
      r6-s6-marks-net, a build of int16), with its own 1.39 GB video,
      IMG_0712: locked 0.4 s after Add, iOS ended Blackmail 31 s after the
      lock, in both runs, for a file coordination claim held while Photos
      made its copy; the letter and the pick were gone and the wake showed
      the Home Screen. In front and not locked, the same pick came 4 min
      23 s after Add, after its bound. B-142, fixed 2026-10-26: 9's second
      half is run as B-142's check, below, not here, each step with a video
      not picked earlier in the round: the first pass's second pick of
      IMG_0712 came in 8.5 s, most likely from the copy Photos made for its
      first, and tested nothing. The fix also calls the read off at its
      count-out, so the first half's three minutes end with Photos' copy
      let go, where run 3 had it held 71 s more.*
      10. *Ended.* Pick a file and end the app in the app switcher at
      once: at the next launch `tmp/<bundle id>-Inbox` and
      `tmp/Attachments` are empty, where the container can be read.
      11. *A double quote.* The file named with one: the arrival's headers
      parse, and the name reads right on Gmail's web page, without the
      quote.
      12. *The share sheet again.* Its checks for a photo, a video and a
      Safari link, as before.
      13. *VoiceOver* reads "Photo Library" and "Attach File", and a row
      still coming by its name, or, with none, "Photo" or "Video".
      14. *Put back.* The "B-108" letters to Trash, the files and the
      video off the iPad.
      *Seen on the test iPad 2026-10-22, a build of int11 (e739d2c): 1 to
      5, 6's Send while the video loads, 7, 8, 9's first half, 10, 11's
      headers, 12 and 14 passed (B-108); 9's second half not reached. The
      test iPad has the Files app now: the picker opened, and its copy in
      the app's Inbox was moved out and purged. In 9's second half the
      video had come 1.9 s after the lock, so a video still coming on his
      return was not reached. Still to run on the test iPad: 9's second
      half, a video still coming through more than three minutes away,
      with a longer HEVC video or another app opened in place of the
      lock. Left: 6's iCloud original and five iCloud-only photos, the
      test iPad having no photo kept only in iCloud; 11's name on Gmail's
      web page; 13, VoiceOver, the app being on the Direct Touch list.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 9's second half
      failed (B-108). A video in Photos of over twelve minutes, 1.39 GB,
      picked in a new letter and the iPad locked at once: iOS ended the app
      within two minutes, and the letter and its pick were gone, no draft.
      In the round's second try the video came 7.5 s after the lock, likely
      ready from the first, and was left out for the letter's room. A second
      run from a fresh start, twice: the app ended 31 s after the lock, iOS
      ending it for a file claim held past its allowance while Photos made
      the video ready, no crash report; in front and not locked, the row
      still spun at 148 s, was counted out at three minutes, and the file
      came at 4 min 23 s, left out for the room. So a video still coming as
      he locks the iPad ends the app, and the letter is lost. Found here:
      fixed as B-142 on its branch, not yet seen on the iPad. Left: 9's
      second half, on a build with B-142; 6's iCloud original and five
      iCloud-only photos; 11's name on Gmail's web page. 13, VoiceOver, is
      not needed.*
      *Since B-142's second fix (2026-10-26): 5 and 7 no longer held as
      written, B-142 having changed them. Photo Library hands over what
      Photos keeps, so a video goes as the app's own H.264 copy, at its own
      size or at 720p, as it came where it is H.264 already, or is left
      out, never as Photos' compatible copy; and a HEIC photo goes as the
      JPEG Photos offers beside it, or, where none is offered, as the app's
      own JPEG of it. Their expected results above are corrected to what
      B-142 says now.*
- [x] **B-109, photos in the letter under his words.** On the test iPad,
      the test account only, built from the `feat-photos` worktree before
      it is merged (it changes what Send carries and how). A stands for the
      account's address; letters only to A with `+b109` before the @,
      subjects beginning "B-109"; each arrival's raw MIME read over IMAP.
      1. *Two photos* from Photo Library, with the signature on. The raw
      message has one related set with two inline parts whose Content-IDs
      match the `<img>` ids, and no attachment copies. In Gmail's web page
      and in Mail on another device, both pictures sit under the words,
      above the signature.
      2. *Drafts.* Save Draft, reopened from Drafts, Send: each picture
      arrives once, in the letter, and Drafts holds none.
      3. *The Outbox.* The same with Airplane Mode on: it goes to the
      Outbox; off, Refresh: it leaves once, each picture in the letter.
      Again, the app ended in the app switcher before Airplane Mode goes
      off, and opened again.
      4. *The share sheet.* A letter with one photo from Photos: the photo
      in the letter, above the signature.
      5. *A forward* of a letter from A with a PDF, a photo added from
      Photo Library: the PDF arrives as a file, the photo in the body.
      6. *The log.* The `LETTER-PLAN` line ends `in-body=2` for step 1, and
      each photo's `LETTER-FILE` line ends `in-body`, its CRC the
      arrival's.
      7. *Memory.* Five full-size photos through the share sheet: the
      `SHARE-SEND` lines' least memory stays where B-070 measured it.
      8. *Put back.* The "B-109" letters to Trash, the drafts deleted.
      *Seen on the test iPad 2026-10-22, a build of int11 (e739d2c): 1 to
      8 passed (B-109), the raw letters read in place of 1's look on
      Gmail's web page and in Mail on another device, which is left. Every
      photo inline in the related set under his words and before the
      signature, its Content-ID its `img` id; from Drafts, the Outbox and
      the Outbox after the app was ended offline, each once; five photos
      through the share sheet at 160 MB at the least, as B-070.*
- [ ] **B-110, Print.** On the test iPad and the iOS 18.6 simulator, the
      test account only, built from the `feat-print` worktree. A stands
      for the account's address; letters only to A with `+b110` before
      the @, subjects beginning "B-110": a plain letter, an HTML
      newsletter with remote pictures, a reply three quotes deep, a letter
      with an inline photo, a letter with a PDF, a three-letter
      conversation, an Apple Mail letter with the explicit-dark-mode head,
      a dark-background newsletter, and a plain letter over 128 KiB.
      First on the simulator on the Mac, then on the test iPad (16.5.1).
      1. *The sheet.* Reply, Reply All, Forward, Print, Cancel, under the
      Reply button. A tap outside closes it and nothing happens. VoiceOver
      reads "Print".
      2. *A plain letter.* The panel opens from the Reply button within
      about 2 s (the `PRINT ready` line's ms written down). Its preview is
      black on white: sender, To, Cc, subject, the date in full, files,
      then the words. No Local Network prompt.
      3. *The HTML newsletter.* Its pictures and its own colours, nothing
      inverted. The dark-background newsletter is legible (its white text
      grey). The explicit-dark-mode Apple Mail letter is light. On the
      test iPad, the time from the tap to the panel, written down.
      4. *The three-deep reply.* Violet, teal and green bars on white
      (B-101).
      5. *The inline photo.* The photo is there. With Airplane Mode on: for
      a letter neither the last opened nor kept on the iPad, the panel
      still comes within 10 s, the letter without its picture; for a
      letter kept on the iPad (B-111), with it.
      6. *The conversation.* Open the middle letter's line, then Print:
      only that letter, with its header; no lines from the stack.
      7. *Cancel and tap outside* each close the panel. Print 20 times in a
      row on the simulator: no slowdown; on the Mac, `ps` shows at most
      one WebContent process beyond the pane's own afterwards (WebKit may
      keep one ready), and the count does not grow over the 20; the app's
      footprint is steady.
      8. *A sheet meanwhile.* Print, then at once the Reply button again:
      the sheet shows Print greyed; close it: the panel comes from the
      Reply button within about half a second. Print, then at once Reply
      and Reply: the composer comes, and no panel ever comes over it
      (`PRINT ended why=covered`). With the panel up, the log says `PRINT
      panel over=true`; if it says false, record it as a finding (the
      panel is not a presentation over the pane, and Print must then also
      be greyed while a panel is up).
      9. *Leaving.* Home right after Print, before the panel: back in the
      app, no panel, the pane as it was, and Print works again. With the
      panel up, Home and back: no crash, and Print works again. Control
      Center pulled down right after Print, and put away: the panel comes
      once it has gone.
      10. *Moving on.* Tap another letter right after Print: no panel
      (`PRINT ended why=moved`, within half a second of the tap), and the
      letter tapped opens once the one picture of the print already on
      the wire, if one is, has come, and no other after it: within about
      a second and a half on a usual link, later at a slow moment of it;
      the same right after Print of the letter with the inline photo,
      neither the last opened nor kept on the iPad.
      11. *Big.* The plain letter over 128 KiB: the "Only the beginning…"
      line on top, about 60 pages, the panel within a few seconds (ms
      written down).
      12. *Five full-size photos* in one letter: the panel comes and the
      app is not ended.
      13. *The preview as a file.* On the simulator, save the panel's
      preview as a PDF (Share, Save to Files), copy it off the Mac, render
      its pages to pictures (pdftoppm) on the build machine, not the Mac,
      look at the header, colours, pictures and page breaks, and keep the
      pictures with the check's notes. If the Mac has Xcode's Printer
      Simulator (Additional Tools for Xcode), print to it from the
      simulator as well: its output is the AirPrint job itself, with no
      paper.
      14. *Paper,* only on the owner's yes: one sheet each of 2, 3 and 6 on
      the Brother the iMac has, if the iPad's Wi-Fi reaches it.
      15. *B-063's check,* on the same yes: a PDF attachment, QuickLook,
      Share, Print, and Done as soon as the panel has gone. The printout is
      whole. If it prints, a line in B-063's seen note: "Print tried
      2026-10-xx with B-110's check: …".
      *Seen on the test iPad 2026-10-23, a build holding this branch, each
      failure made again on a second run. Passed: 1a, 2, 3a, 3c, 4, 5a, 5b,
      6, 7a, 8a's Print greyed, 8b, 8c, 9a to 9c, 10b, 11, 12 and the log's
      counts. 8a's timing not met as measured then, the panel about 1.0 to
      1.3 s after the tap outside, 0.41 to 0.75 s after the sheet had gone;
      met on 2026-10-23 (below). NOT
      POSSIBLE: 1b, injected touches not moving VoiceOver's focus in the
      sheet. NOT RUN: 7b and 13, the simulator's and the Mac's (eight
      prints in a row and the panel's own PDFs on the iPad stood in), and
      14 and 15, paper, for the owner's yes. Failed: 3b, white words on a
      black block; 5c, the kept letter's photo printed blank at times; 10a,
      four more of the print's 3.3 MB pictures fetched after `PRINT ended
      why=moved`, the letter tapped waiting about 4.5 s. Changed the same
      day (B-110 in KNOWN_ISSUES): no backgrounds printed, the print's
      pictures decoded as drawn, its teardown stopping its own pictures,
      and the header's lines and the page's notices kept grey on paper,
      which with no backgrounds WebKit would have printed all but white.
      To run again, from a build with the change: 2, the header's To, Cc,
      date and file lines grey as on the first run, not near white; 3b,
      with 3a's newsletter, whose navy banner and boxes now print white
      and their words darkened, any grey small print written down as it
      prints; 4, the bars violet, teal and green and the violet words as
      on the first run, the teal and green words now lighter, WebKit's own
      on 16.5, written down with whether they can be read; 5c as on the
      second run, Airplane Mode on, the kept letter opened from its copy,
      about 8 s, three prints on that pane and one after opening it again,
      each with the photo; 10a with the five photos, a letter not kept
      tapped about 1 s after Print: after `PRINT ended why=moved` at most
      the one picture FETCH already on the wire, then the tapped letter's,
      its body within about a second and a half; and 12, its time to the
      panel written down again. Seen there too: on
      16.5.1 the panel is the centred Print Options sheet, not a popover
      from the Reply button; the iPad's sheet has no Cancel row, a tap
      outside being its cancel; each print of a letter opened in parts
      fetches its pictures again, 16.6 MB for the five photos.*
      *Run again 2026-10-23, a build of int12 (140df65): 2, 3a, 3b, 4, 5c,
      8a's timing, 12 and the log's counts passed; 3b and 5c did not fail
      again. 10a's wire order was right in both runs, and its mark met in
      one run of two. The header's lines `#8e8e8e` as before. The
      newsletters on white paper, their white words `#ababab`, their small
      print in `#999` printed `#ededed`, all but gone; the quotes' teal and
      green words `#00daff` and `#18ff13`, readable but faint. The kept
      letter's photo in all ten prints offline. The panel 0.33 to 0.41 s
      after the sheet had gone. After `PRINT ended why=moved` only the
      picture on the wire, then the tapped letter's STORE and FETCH, its
      body at 0.70 s once and 3.16 s once; in the slow run the log has the
      STORE answered in 1.31 s and the FETCH of 689 bytes in 1.03 s, read
      from when the app saw each answer, so not the server's delay apart
      from the app's. The five photos' print 7.95 s and 9.57 s, fetching
      them again, near the 10 s limit, which then draws what has come.
      Still to run on the test iPad: 10a a third time, its body within
      about a second and a half. Left: 1b, VoiceOver; 7b and 13, the
      simulator's and the Mac's; 14 and 15, paper, for the owner's yes.*
      *Seen 2026-10-25: 7b and 13 on the Mac's iOS 18.6 simulator, an iPad
      (7th generation), on a simulator build of int16 (662d63d), and 10a a
      third time on the test iPad on int16 (662d63d) (B-110). 7b passed: the
      letter with the inline photo printed 21 times, each Reply, Print, the
      panel, Cancel: `PRINT ready` 304 to 314 ms after the first's 349, one
      WebContent process throughout, about 190 MB, the app's footprint 100
      to 101 MB, and 100 MB 10 s after the last. 13 passed: the preview
      saved as a PDF from the panel's Share, one Letter page, drawn with
      Ghostscript on another machine, not the Mac, pdftoppm being on neither
      it nor the Mac: white paper, the sender blue, the To, date and file
      lines grey, two rules, the subject bold black, the words black, the
      photo in its colours, nothing inverted, no black box. 10a, on a letter
      of five 4.16 MB pictures opened in parts, a small letter tapped 1.1 s
      after Print, three times: no panel, `PRINT ended why=moved` 0.27 to
      0.37 s after the tap, the one picture on the wire finished and none
      after it, then the tapped letter, its body 0.79 s after the tap twice
      and 2.38 s once, that picture taking 2.67 s on the wire where 16
      others took 1.07 to 1.33 s. A second run from a fresh start, four
      times, once tapped 0.65 s after Print as its picture went out: 0.7 to
      1.2 s. So one slow moment of the wire, and the mark met in four more
      runs. The step had the letter open as quickly as with no print, 0.26
      to 0.38 s here, which no run did, the picture on the wire being let
      finish by design; it now says it waits for that picture. Left: 13's
      Printer Simulator, not looked for; 14 and 15, paper, for the owner's
      yes. 1b, VoiceOver, is not needed.*
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to four sheets: 14's three and 15's one printed, on an
      AirPrint laser printer on the home network, the one printer the
      panel offered (B-110). The letters were the host's, in Notes. Each
      panel: Copies 1, Letter, in colour, Double-sided off, on by default
      for that printer and kept off after the first print. 2's plain
      letter, `PRINT ready pages=1` in 169 ms: the preview white, the
      sender blue, To and Cc grey, two rules, the subject bold black, the
      date in full, the words. 3's newsletter, its three remote pictures
      in, the range set to page 1 of 2: the banner's words grey on white
      with no navy band, the red headline red, the green paragraph green,
      the first picture in its colours, the violet caption violet, nothing
      inverted, no black box. 6's middle letter, its line opened: its
      header and words alone, no stack line, nothing of the other two. 15,
      B-063's PDF from Quick Look: the preview the whole page, its frame,
      twenty lines and grey box. Each Print tapped once, `PRINT closed
      done=true` with no `PRINT ended` or `PRINT words` line for the three
      letters; the iPad's print service took each as one page, and the
      printer listed each job completed, one impression, within 35 s of its
      tap. No Local Network prompt. The sheets are the owner's to look at.
      Not on paper: the dark newsletter, the Apple Mail letter with the
      dark head and the rest, four sheets being the day's limit; their
      previews and PDFs were judged on 2026-10-23. Left: the sheets, for
      the owner; 13's Printer Simulator, not looked for.*

- [x] **B-113, the words after a file among them.** On the test iPad, the
      test account only, built from the `bm-readpane` worktree (branch
      `feat-readpane`). The host makes each letter and APPENDs it to the
      test account's Inbox; none is sent. Three panes, then two.
      1. *Apple Mail's shape:* multipart/alternative of the plain words
      and a multipart/mixed of an HTML part, a PDF sent inline with no
      `Content-ID`, and an HTML part after it with more words and "Sent
      from my iPad" (as `06-pdf-among.eml` of 2026-10-22). Tapped: the
      PDF's row in the header grey from the tap, then blue; in the body
      the words before it, the PDF's name and size in blue on a line of
      its own, then the words after it and "Sent from my iPad". The blue
      name tapped: the PDF in Quick Look; Done, the letter as it was. The
      header's row tapped: the same. A paperclip on its list row.
      2. *The plain mixed of the same:* multipart/mixed of an HTML part,
      a PDF of about 1 MB sent inline, and "Sent from my iPad" in an HTML
      part after it: as 1, "Sent from my iPad" under the PDF's name.
      3. *In a conversation:* a letter of 1's shape and a reply to it, as
      one conversation: in the stack, the PDF's name where it sat, blue,
      and a tap on it opens it, the letter's line open or not the last
      one opened.
      4. *Reply and Forward* of 1, opened and Cancelled with Delete
      Draft, never sent: the quote holds the words after the PDF and
      "Sent from my iPad"; the Forward lists the PDF.
      5. *A letter too large to fetch whole:* 1's shape with a PDF of 6 MB
      or more: the words before and after it shown, the row among them,
      and no "Only the beginning of this message is shown."
      6. *Nothing else moved:* a letter with a PDF attached after its
      words in Gmail's shape (multipart/mixed of a multipart/alternative
      and the PDF), and one with a signature's logo: as before, no row
      among the words. Apple Mail's own letter with a PDF at the end puts
      "Sent from my iPad" in an HTML part after it (as `05-pdf-one.eml`),
      so its PDF has a row among the words above the signature and its
      row in the header: say whether the two rows read as two files to
      him, for the owner, who decides whether one goes.
      7. *A bounce,* multipart/report of the explanation, the delivery
      status and the letter returned: the explanation alone, no "Begin
      forwarded message:".
      8. *More parts than a body holds:* a letter of a hundred parts of
      HTML: the first 64 and "Only the beginning of this message is
      shown." above them; a Reply's quote ends with the same line.
      9. *Moving on from a large one:* a letter over 5 MB of 300 parts of
      words and a PDF, tapped, and at once the letter below it: that
      letter shows in the time any letter takes, not after the first has
      come.
      *Seen on the test iPad 2026-10-22, a build of int11 (e739d2c): 1 to
      9 passed (B-113), and 1 and 5 again 2026-10-23 on a build of int12
      (140df65). 6: one PDF has its row in the header and its row among
      the words above "Sent from my iPad", the same name, size and blue,
      which read as one file shown twice; Mail shows the file among the
      words, and the header's row is the app's own: one row or two, the
      owner's (below). 7: a bounce lists its delivery status as
      "attachment-2.dat (214 bytes)" in the header with no paperclip on
      its row, an older rule, recorded under B-113. Nothing left for the
      test iPad.*

- [x] **B-114, a letter forwarded after a note.** On the test iPad, the
      test account only, built from the `bm-readpane` worktree. The host
      makes each letter and APPENDs it to the test account's Inbox; none
      is sent. Three panes, then two.
      1. *A note, then the forwarded letter inline,* multipart/mixed of a
      text/plain note and a message/rfc822 sent inline with no name,
      holding a plain letter (as `09-fwd-note.eml` of 2026-10-22): the
      note, then "Begin forwarded message:", a blank line, From, Date,
      To and Subject, the forwarded letter's Date in the iPad's zone,
      then its words. No row in the header, no paperclip on its list row.
      2. *The forwarded letter of HTML,* multipart/alternative: the same,
      the labels and the subject bold, the letter's own markup under them.
      3. *With a file of its own:* the forwarded letter carrying a PDF as
      an attachment: its row in the header, the paperclip, Quick Look.
      4. *Forwarded as a file:* the message/rfc822 named `forwarded.eml`
      and sent as an attachment: its row and paperclip as before, nothing
      of it in the body; the row tapped, Quick Look shows the letter or
      says it cannot, and say which.
      5. *A forward with nothing before it:* the forwarded letter's words
      alone, as before, no header lines.
      6. *A large one,* the note, the forwarded letter and a PDF of 6 MB or
      more: the header lines as in 1, drawn from the letter's structure.
      7. *Reply* of 1, opened and Cancelled with Delete Draft, never sent:
      the quote holds the note, the header lines and the forwarded words.
      8. *Forwarded under an encoding:* 1 with the message/rfc822 part sent
      `Content-Transfer-Encoding: base64`: as 1, its words and not the
      encoded lines.
      9. *Named and sent inline:* 1 with the message/rfc822 named
      `Earlier letter.eml` and `Content-Disposition: inline`: as 1, drawn
      under the note, no row and no paperclip.
      *Run 2026-10-22, three panes and two: 1 to 5 and 7 to 9 passed. 6
      failed, twice: the large one could not be opened at all, "This
      message could not be downloaded." and "Can't connect to mail
      server.", Gmail refusing BODY[2.1] of the forwarded letter's words,
      which it serves as BODY[2.TEXT]; and a row beside 5's lone forward
      lost its preview to the same refusal. Fixed since (KNOWN_ISSUES,
      B-114). To run again: 6, its note, header lines and forwarded words
      shown, the PDF's row there and Quick Look opening it, and no "Only
      the beginning of this message is shown."; 6 again with the
      forwarded letter itself forwarding a plain one (a message/rfc822
      whose body is a message/rfc822), over 5 MB with the PDF: say whether
      the inner letter's words show or the notice does, Gmail's answer to
      BODY[2.1.TEXT] in the app's log; and 5's list, the lone forward's
      row with its preview, and the rows beside it with theirs, in a
      folder where they share a page.*
      *Run again 2026-10-23, a build of int12 (140df65): 6 passed, the
      note, the header lines and the forwarded words, the PDF's row and
      Quick Look, no notice, Gmail answering `BODY.PEEK[2.TEXT]`; with the
      forwarded letter multipart, its 2.1 and 2.2 served. 5's list passed,
      every row with its preview, the lone forward's asked as 1.TEXT. The
      forward of a forward over 5 MB shows the notice and loses the
      innermost words: Gmail refuses `BODY[2.1.TEXT]` and serves them as
      `BODY[2.1]` (B-114, Not covered). In 4, Quick Look could not show
      `forwarded.eml`, saying it is data, 454 bytes.*
      *Where this is merged with B-104 (his Sent Mail's lines in a
      conversation):* done in this tree, 2026-10-23. B-104's
      `IMAPClient.fetchPartialBodiesWhileOpen` keeps what came under a
      NO, as `fetchPartialBodies` does since B-114 (its
      `guard result.status == .ok else { continue }` gone), and
      `RepositoryWireTests.testAPreviewWhileTheFolderIsOpenCostsOnlyItsOwnRow`
      is the twin of `testAPreviewTheServerWillNotGiveCostsOnlyItsOwnRow`
      for that path, one letter refused beside one given;
      `testNoPreviewFetchThrowsAwayWhatCameUnderANo` passes. *With
      B-110's print:* not done. It is an open item under "Doable now",
      the print's "This message has no text." only where the pane's.
      *Done since, 2026-10-25 (B-131).*

- [x] **B-115, Go to Date in a folder whose letters came out of order.** On
      the test iPad, the test account as filled for the size test (gap
      review, above), from a build with the fix; read only, nothing
      written to the mailbox. Current Mailbox unless said, three panes,
      the app's log read after each jump.
      1. *A day with mail:* Inbox, 10 March 2014: the list opens on the
      first of that day's five letters, 3:43 am, UID 3238, "Showing March
      10, 2014"; one dated `UID SEARCH SENTSINCE "10-Mar-2014" SENTBEFORE
      "12-Mar-2014" …`, answered `* SEARCH` with the UIDs of the 10th's
      letters and the 11th's to 8 pm, then `UID FETCH … (UID INTERNALDATE
      ENVELOPE)` of those, then `UID SEARCH ALL` and the window's FETCH,
      nothing between them.
      2. *Before the oldest:* 1 January 2011: the oldest letter, 4 January
      2012, "Showing January 4, 2012"; ten dated SEARCHes, the first for
      the 1st and 2nd with no FETCH after it, the last `SENTSINCE
      "02-Jan-2011" SENTBEFORE "27-May-2012"` answered MIN 578. The time
      from Go to the list, written down.
      3. *1 June 2012:* that day's first letter, at 9:26 am, one dated
      SEARCH and the FETCH of its letters' dates. *With Organize by Thread
      on it is in its conversation's row, answered on 5 June, and the row
      on top is that conversation's (B-117, its check below).*
      4. *The top of the Inbox:* 14 August 2026: its first letter, UID
      57710, one dated SEARCH and the FETCH; unless one of the account's
      own letters is dated that day after 8 pm, which the host did not
      look for: then that one, the day's lowest UID.
      5. *A day with no mail:* Sunday 25 May 2014: the first letter of the
      26th; two dated SEARCHes, the first for the 25th and 26th and the
      FETCH of its letters' dates after it, all the 26th's.
      6. *Sent Mail:* 15 May 2019: its first letter, UID 8324, "Showing
      May 15, 2019".
      7. *All Mailboxes* from the Inbox, 10 March 2014: All Mail opens on
      that day's first letter.
      8. *After the newest:* 20 October: "No mail on or after October 20";
      the day's SEARCH, with no FETCH after it, the spans that end before
      a week from today, then one dated SEARCH with no `SENTBEFORE`,
      `SENTSINCE "21-Oct-2026"`: five in all if run by 28 October.
      9. *The evening before:* if one of the account's own letters is
      dated after 8 pm (read only from the host, its UID and Date), the
      day after it: the list opens on that day's own letter if it has
      one, otherwise on the first letter after it, never on the evening's
      letter nor on one far above it; the evening's letter in the log's
      FETCH of the dates.
      10. *Two panes,* 1 again, then three panes back.
      11. *Put back:* the jump to 20 October last, so the day and scope
      remembered are as found.
      *Seen on the test iPad 2026-10-23 at the size test's mailbox: every
      jump on its day, 0.7 to 1.5 s (B-115).*
- [x] **B-116, the Mailboxes pane with labels.** On the test iPad, the
      test account only, whose labels are in the shapes of his (its LIST is
      `FolderTreeTests.testAccountsList`), built from the `bm-folders`
      worktree (branch `fix-folders`). Nothing is written to the mailbox:
      folders are opened only to look. Three panes, then two.
      1. *The order:* every row from top to bottom with its indent, shots
      from the top and the bottom of the pane: the Inbox; then one step
      in Drafts, Sent Mail, Spam, Trash, All Mail, Important, Sent
      Messages and Starred; then at the left edge "[Gmail]All Mail" with
      "Trip 2017" one step in under it, "[Gmail]Drafts", "[Gmail]Spam",
      "[Gmail]Trash", Bank to House, "Junk E-mail" with "Drafts" one step
      in under it, "Note to Self: Letters to Himself" to Travel 2017, and
      "Unopened 4/17/17" so named, at the left edge. No row for "[Gmail]",
      "Unopened 4" or "Unopened 4/17". Each count as the host's STATUS
      gives it.
      2. *Each tap opens its own folder:* "[Gmail]/Sent Messages", the
      label "Drafts", Junk E-mail's "Drafts", "[Gmail]Drafts", Starred and
      "Unopened 4/17/17": the list's title the row's name, the list as
      the host's count says (empty or not), and the app's log SELECTs that
      name and no other. Gmail's Drafts and Sent Mail open as before.
      3. *The first launch of the new build:* its first frame draws the
      pane kept by the build before, in the old order, and the new order
      comes with the sweep; the next launch's first frame is in the new
      order.
      4. *The Move sheet,* opened on a letter and Cancelled, no Move: the
      pane's order, without the indent.
      5. *Two panes:* the pane once more, as 1.
      *Seen on the test iPad 2026-10-23 with his labels' shapes: the order,
      the names and every tap as written (B-116).*
- [x] **B-117, Go to Date onto a letter that was answered.** On the test
      iPad, the test account as filled for the size test (gap review,
      above), from a build with the fix; read only, nothing written to the
      mailbox. Three panes, Organize by Thread on, Current Mailbox, the
      Inbox opened at its top before each jump, frames from Go as in the
      round that found it, and the app's log read after each.
      1. *The case found:* 1 June 2012. From the first frame with rows to
      5 s after Go, nothing touched, the top row is the conversation "Re:
      Watch and winter evening weather lunch", Harper Mock, 05/06/12, with
      the conversation mark, and under it the rows of 4 June to 1 June,
      then Hayden Lorem, 30/05/12 (761); "Showing June 1, 2012". No frame
      has 762 in a row of its own or 763 on top. A row under it whose
      letter was answered on the page asked as the day lands can leave
      for the top as it comes (B-117, Not covered): if one does, which,
      and the frames either side. The log: the dated
      SEARCH, the FETCH of its five letters' dates, `UID SEARCH ALL`, one
      window FETCH, `UID FETCH 723:822`, nothing between them; then the
      page above asked as the day lands, `UID FETCH 823:872` (B-094), and
      the top row the same after it is answered. A tap on the top row: the
      stack holds 762 and 773.
      2. *Moving the list after:* the same jump, then a slow drag up to the
      top of what is listed: the rows move with the finger only, and the
      page above, if one is asked, goes on with the rows in view where
      they were (B-042).
      3. *Organize by Thread off,* the same jump: the top row is 762,
      Harper Mock, 01/06/12, and stays; then the switch on again.
      4. *A reply further up,* if the host finds one, read only, by
      X-GM-THRID: a day whose first letter's reply is 61 to 110 letters
      above it. The top row is that letter's at first, and when the page
      above is answered it stays the top row as its conversation's; the
      frames either side written down.
      5. *A day whose first letter was not answered:* 10 March 2014, its
      first letter on top, as B-115's check 1, and nothing moving.
      6. *Two panes,* 1 again, then three panes back.
      7. *Put back:* the jump to 20 October last, so the day and scope
      remembered are as found.
      *Seen on the test iPad 2026-10-23: the conversation's row on top from
      the first frame and held; drags, Refresh and Organize by Thread off as
      written. Left for the owner: the rows in sight dated after the day
      (B-117).*
- [x] **B-118, Go to Date opens where Mail's list shows the day.** On the
      test iPad, the test account as filled for the size test (above),
      from a build with the change; read only, nothing written to the
      mailbox. Three panes, Organize by Thread on, Current Mailbox, the
      Inbox opened at its top before each jump, frames from Go as in
      B-117's check, and the app's log read after each. The rows expected
      are worked out from the size test's plan (`plan.jsonl`, its `thread`
      and `parent`), checked against the conversations the host read for
      four of the days; a row is dated by its newest letter. For each: the
      top row from the first frame with rows to 5 s after Go, nothing
      touched, the row under it, and "Showing".
      1. *1 June 2012:* Museum Members, 01/06/12, "Terrible great trip
      doctor listen train" (763, 11.02 am), no conversation mark; under it
      Hayden Lorem, 30/05/12 (761); above it Casey Dummy, 01/06/12 (764),
      then Reese Proxy and The Daily Brief, 02/06/12. "Showing June 1,
      2012". The conversation "Re: Watch and winter evening weather lunch",
      Harper Mock, 05/06/12, with the mark, is up the list among the rows of
      5 June, reached by scrolling up: 762 is in it. No frame has the
      conversation on top. The log as B-117's check 1: the dated SEARCH,
      the FETCH of its letters' dates, `UID SEARCH ALL`, one window FETCH,
      `UID FETCH 723:822`, then the page above, `UID FETCH 823:872`, which
      answers nothing in the row on top, and nothing moves as it comes.
      2. *12 January 2014:* Alex Surrogate, 12/01/14, "Large against"
      (2949, 5.06 am); under it Library Events, 11/01/14, "Coming up the
      garden" (2947); above it Concert Hall, 12/01/14 (2950). "Showing
      January 12, 2014". Morgan Lorem's conversation, 17/01/14, up the
      list.
      3. *21 March 2018:* Museum Members, 21/03/18, "Coming up the garden"
      (14733, 4.22 am); under it Noel Ipsum, 20/03/18, "Re: Autumn listen"
      (14730), Casey Dolor's letter of the 20th (14731) being up the list
      with its reply of the 24th; above it Garden Club News, 21/03/18,
      "Library during" (14735). "Showing March 21, 2018". The page above,
      14793 to 14842, joins Blair Notreal's conversation (14805, 28 March),
      which is out of sight up the list: nothing in sight moves.
      4. *23 April 2019, a reply on the page asked as the day lands:* in the
      first frame Ellis Ersatz, 23/04/19, "Weather friend send great"
      (18944, 4.59 am), its own row, no mark, over Hayden Pseudo, 22/04/19,
      "Student write" (18943). "Showing April 23, 2019". When the page
      above, 19005 to 19054, is answered, its reply 19024 joins the row,
      which goes up the list among the rows of 28 April as "Re: Weather
      friend send great", Ellis Ersatz, 28/04/19, with the mark, and Quinn
      Doe, 23/04/19, "Young listen long video" (18945, 6.39 am) comes into
      the top place, over 18943; "Showing April 23, 2019" still. Not the
      rows of 28 April on top (B-117's hold, which B-118's first build
      kept). The frames either side written down, and how long 18944 was
      on top.
      5. *27 March 2014, the day's first three letters each answered later
      in a conversation of its own:* Sam Testa, 27/03/14, "Know never trip"
      (3316, 9.46 am), no mark, on top; under it Photo Prints, 26/03/14,
      "Notes from the hall" (3312); above it Quinn Madeup, 27/03/14,
      "Forget dinner neighbor weekend terrible small" (3318). "Showing
      March 27, 2014". Reese Example's, Remy Testa's and Noel Notreal's
      conversations, 02/04/14, 31/03/14 and 29/03/14, with the mark, up the
      list; not Remy Testa's on top. The page above, 3374 to 3423, joins
      nothing in sight.
      6. *10 March 2014:* Kai Placeholder, 10/03/14, "Cousin library into
      drive" (3238, 3.43 am), over Jordan Imaginary, 09/03/14 (3237), as
      before: his reply of 13 March is in Sent Mail, not in the list.
      7. *Sunday 25 May 2014, no mail:* Harper Mock, 26/05/14, "Sister
      forget library perhaps" (3613, 6.07 am), over Alex Imaginary,
      24/05/14, "Picture think" (3612). "Showing May 26, 2014", as before.
      8. *Friday 8 June 2012, every letter of the day answered later:* its
      one letter, Peyton Standin's "From train read story" (777, 6.20 pm),
      was answered on the 10th (782). Blair Ipsum, 09/06/12, "By before
      fine around again" (778, 5.22 am) on top, under it Remy Lorem,
      07/06/12 (776). "Showing June 9, 2012", as for a day with no mail.
      Peyton Standin's conversation, 10/06/12, with the mark, up the list.
      9. *Sent Mail, 2 June 2012:* his one letter that day, to Harper Mock
      (533), was followed by his of 6 June (536): on top "Haydn — Aria",
      05/06/12 (534), to himself, over "Purcell — Concerto", 31/05/12
      (532). "Showing June 5, 2012". Then *15 May 2019:* the letter to
      Emery Pseudo, 15/05/19 (8324), on top as before.
      10. *All Mailboxes* from the Inbox, 10 March 2014: All Mail opens on
      his own "Opera house - Wikipedia", 10/03/14 (4416, 3.36 am), as
      before; Kai Placeholder's letter of 3.43 am is up the list in a
      conversation of 13/03/14 with his reply, which in All Mail is a
      letter of the list.
      11. *All Mailboxes, 8 April 2021, the row on top and the one under
      it both answered on the page asked as the day lands:* in the first
      frame Tatum Pseudo, 08/04/21, "Re: Book call to and lunch early"
      (40083, 1.30 am), its own row, over his reply to Parker Notreal,
      07/04/21, "Re: Evening very a picture list appointment" (40082),
      with the mark. "Showing April 8, 2021". When the page above, 40144 to
      40193, is answered, both rows go up the list, joined by 40158 and
      40153, and Library Events, 08/04/21, "On weather" (40084, 3.15 am)
      comes on top, over his "Re: City sister son send call yesterday" to
      Hayden Ipsum, 07/04/21 (40081), with the mark; Reese Standin,
      08/04/21 (40085), above it, not on top. The frames either side
      written down.
      12. *The ends:* 1 January 2011 opens on Garden Club News, 04/01/12
      (578), "Showing January 4, 2012"; 14 August 2026 on Wren Standin,
      14/08/26 (57710); as before.
      13. *Organize by Thread off,* 1 June 2012: Harper Mock, 01/06/12
      (762), on top, as before; then the switch on again.
      14. *Two panes,* 1, 4 and 8 again, then three panes back.
      15. *VoiceOver,* if it is to be run: 1 June 2012 once more, where
      VoiceOver is after Go written down; if on a row of the list, the row
      on top (763). Then VoiceOver off.
      16. *Put back:* the jump to 20 October last, "No mail on or after
      October 20", so the day and scope remembered are as found.
      *Seen on the test iPad 2026-10-23: every day as expected, three
      panes and two, Organize by Thread on and off; a row answered on the
      page above gave way to the day's next row in about 0.2 s. Left:
      step 15, VoiceOver (B-118).*
- [x] **B-119, every date the iPad's way.** On the test iPad, the test
      account as filled for the size test (B-118's check), from a build
      with the change; read only: nothing written to the mailbox, no
      letter sent and none saved. Three panes, Organize by Thread on.
      1. *The region:* Settings > General > Language & Region, the Region
      and the "Region Format Example" at the foot, its short date written
      down; Settings > General > Date & Time, 24-Hour Time on or off. The
      dates below are for a US region with 24-Hour Time off; with another,
      each in the form the example shows.
      2. *The rows:* the Inbox at its top: today's rows a time, such as
      "9:14 AM", yesterday's "Yesterday", this week's the weekday; down to a
      row older than a week, the short date month first, "10/3/26" for 3
      October, never "03/10/26". Shots of each.
      3. *Go to Date,* 1 June 2012: "Showing June 1, 2012"; Museum Members,
      "6/1/12" (763), on top, Hayden Lorem, "5/30/12" (761), under it;
      Harper Mock's conversation, "6/5/12", up the list.
      4. *The header:* 763 opened: "June 1, 2012 at 11:02 AM". A letter of
      today: "Today at" and its time; one of yesterday: "Yesterday at" and
      its time.
      5. *A conversation's stack:* Harper Mock's conversation opened: each
      closed letter's line dated month first, "6/1/12" and "6/5/12", and
      his own from Sent Mail "6/6/12" (B-104).
      6. *The composer, never sent:* on 763, Reply: the line above the
      quote reads "On Jun 1, 2012, at 11:02 AM, Museum Members <…>
      wrote:"; Cancel, then Delete Draft. Forward: its "Date: June 1, 2012
      at 11:02:… AM EDT"; Cancel, then Delete Draft. No Send, no Save
      Draft.
      7. *Paper, never printed:* on 763, Reply, then Print: the panel's
      preview has "June 1, 2012 at 11:02 AM" under the subject; Cancel.
      8. *The kept page:* Blackmail ended in the app switcher, Airplane
      Mode on, launched: the kept Inbox rows have the same dates from the
      first frame. Airplane Mode off.
      9. *Edit mode,* three panes, then two: rows older than a week, the
      widest dates, "12/28/25" and the like, whole beside the mark, never
      cut to "…".
      10. *Another region,* only with the owner's yes, as B-043's time zone
      and clock: Region United Kingdom, then back to the region of step 1:
      rows "01/06/2012", the header "1 June 2012 at 11:02", the reply line
      "On 1 Jun 2012, at 11:02" (Cancel, Delete Draft); in Edit mode in
      three panes a ten-character date whole.
      11. *Put back:* the jump to 20 October last, so the day and scope
      remembered are as found.
      *Seen on the test iPad 2026-10-25 on int15 (ac1b816), a US region
      with 24-Hour Time off: 1, 2's rows of this week and older, 3, 4's
      763, 5 to 9 and 11 passed, every date month first (B-119). Not
      possible: 2's rows of today and yesterday and 4's "Today at" and
      "Yesterday at", no letter in the mailbox being dated 23 or 24
      October and nothing to be sent or saved; those stay open, for a day
      the mailbox has such letters. Not run: 10, with no yes from the
      owner to change the region; open too.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), a US region with
      24-Hour Time off: 2's rows of today and yesterday and 4's "Today at"
      and "Yesterday at" passed, on two letters the host put in the label
      Notes, read, one dated two hours before and one the evening before:
      the rows "12:39 PM" and "Yesterday", the headers "Today at 12:39 PM"
      and "Yesterday at 8:15 PM" (B-119). Left: 10, another region, for the
      owner's yes.*
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to a region change: 10 and 11 passed (B-119). From the
      US region as found, Go to Date to 1 June 2012; then Region United
      Kingdom, English (US) kept when iOS asked, 24-Hour Time coming on
      with it. Back in Blackmail 66 s later, no relaunch: at once the rows
      "01/06/2012", "30/05/2012" and on, 763 still highlighted, its header
      "1 June 2012 at 11:02", no SELECT, SEARCH or FETCH from the change;
      the line under the list "Showing June 1, 2012" until the next jump
      (B-139). Rows scrolled into sight day first, the year whole. Reply's
      line "On 1 Jun 2012, at 11:02, Museum Members <…> wrote:", Cancel
      closing it with nothing asked. Edit in three panes: the
      ten-character dates whole beside the marks, the sender's name cut
      instead. Ended from the host and opened: the kept Inbox day first
      from about 1 s; Go to Date's weeks from Monday, "Showing 1 June
      2012", the header as before. Put back: Region United States, which
      iOS said would restart the iPad and did not; Language & Region and
      Date & Time as found; the rows month first again without a relaunch;
      the jump to 20 October, the day and scope remembered as found.
      Nothing was sent or saved.*
- [x] **B-124, no white at launch.** On the test iPad, the test account,
      from a build with the change; nothing written to the mailbox, no
      letter sent and none saved. Screen recordings at 60 frames a second,
      as B-053's of 2026-10-21.
      1. *A cold launch:* Blackmail ended in the app switcher, its icon
      tapped: no white frame from the icon's zoom to the rows; the launch
      screen black and the status bar's words light on it; the time from
      the zoom's first frame to the rows written down, beside B-053's
      167 ms. Three times in three panes, then once in two.
      2. *The app switcher:* Blackmail's card dark.
      3. *Dark as before* (D-010), each opened and closed, nothing sent:
      Reply on a letter, the keyboard up in its body: the keyboard dark; a
      word selected, the edit menu (Copy, Paste) and the loupe dark;
      the photo picker and Files opened from the composer and cancelled;
      then Cancel, then Delete Draft. Quick Look on a letter's PDF, then
      Done. Go to Date's calendar, then Cancel. A link in a letter tapped:
      "Open this link?" dark, then Cancel. Reply, then Print: the panel
      dark, its preview white paper, then Cancel. The connection log's
      share sheet opened and closed with nothing chosen.
      4. *The share sheet:* from Safari, a page shared to Blackmail: the
      sheet dark and filled; Cancel, then Delete Draft.
      5. *Smart Invert,* only if it is to be run: on, a cold launch: the
      launch screen and the rows inverted alike, no flash between; then
      off again.
      *Seen on the test iPad 2026-10-25 on int15 (ac1b816): 1, 3 and 4
      passed, no white frame in five cold launches, black from the zoom's
      first frame, 267 to 317 ms to the rows online and 167 ms offline
      (B-124). Not possible: 2, the app switcher, which the injected
      touches cannot open. Not run: 5, Smart Invert, not asked for. Left:
      those two.*
- [x] **B-120, a letter opens ready to type.** On the test iPad, the test
      account only, from a build with the change, the on-screen keyboard
      (no hardware keyboard attached). Nothing is sent: no Send anywhere,
      every letter closed with Cancel, a draft saved once and deleted
      again. A stands for the account's address. For each: where the caret
      is and whether the keyboard is up, from the sheet's first frame to
      2 s after it has arrived, nothing touched.
      1. *A new letter:* Compose: the keyboard up, the caret in To, no list
      under it. Cancel: the sheet closes without asking.
      2. *A reply:* a letter in the Inbox, Reply: the keyboard up, the
      caret on the empty first line, above the signature and the quote,
      the quote as it was. Cancel: it closes without asking. Reply All on
      a letter with a Cc, the same.
      3. *A forward:* a letter with no files (so no question), Forward:
      the caret in To. Cancel.
      4. *His caret kept:* Reply, then tap inside the quote and type one
      letter there. Photo Library, then Cancel in the picker: the caret
      still after that letter in the quote, not moved to the top. Cancel:
      the question; a tap outside it closes it, the caret still there.
      Cancel again, Delete Draft: the sheet closes, nothing saved.
      5. *A draft reopened:* Compose, A with `+b120` before the @ in To,
      Subject "B-120 draft", one word in the body; Cancel, Save Draft.
      Drafts, the draft tapped: the keyboard up, the caret at the top of
      the body, above the signature. One letter typed there, then Cancel,
      Delete Draft: Drafts is empty again.
      6. *Subject:* if a letter at hand has a `mailto:` link with an
      address and no subject, tap it: the composer opens with the caret in
      Subject. Cancel. Otherwise noted as not at hand.
      7. *The share sheet:* a Wikipedia page in Safari, Share, Blackmail:
      the keyboard up, the caret in To, no list. Cancel: it closes without
      asking. Nothing sent.
      8. *Two panes,* 1 and 2 again, then three panes back.
      *Seen on the test iPad 2026-10-25 on int15 (ac1b816): 1 to 7
      passed, each sheet in the field the rule picks, the caret about
      0.25 s after the sheet stopped and the keyboard up 0.3 to 0.4 s
      later (B-120). In 8, Compose and Reply All as in three panes. Left
      in 8: the caret in Reply, whose shot had the keyboard up and no
      caret in sight, and the three Cancels closing without a question,
      no shot kept of them.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 8's leftovers
      passed in two panes, on a letter with a Cc the host put in the label
      Notes, not the Inbox (B-120). Reply, nothing touched: the sheet at
      0.85 s with no caret, the caret on the empty first line above the
      signature at 1.12 s, the keyboard up by 1.58 s. Reply All: To the
      sender, Cc the Cc, the caret on the first line. Compose: the caret in
      To, no list. Cancel on each, untouched: the sheet down with no
      question, Reply's gone by 0.55 s, nothing more through 2.5 s. Every
      step has now passed.*
- [x] **B-121, typing as in Mail.** On the test iPad, the test account
      only, from a build with the change, the on-screen keyboard. Nothing
      is sent: no Send anywhere, a draft saved once and deleted again.
      First, Settings > General > Keyboard: Auto-Capitalization,
      Auto-Correction and Smart Punctuation written down as found (on is
      the factory's); the steps expect them on.
      1. *Subject:* Compose, then in Subject type `sunday lunch` and a
      space: it reads "Sunday lunch". Then ` teh` and a space: corrected to
      "the", as the keyboard corrects in Mail. Then ` don't` with the
      apostrophe key: the apostrophe curly, ’.
      2. *The body:* on its first line type `"yes" -- don't`: the quotes
      curly “ ”, the two hyphens one dash, the apostrophe curly.
      3. *To:* type `carlo` in To: no capital, nothing corrected; then
      take it out again.
      4. *Kept as typed:* A with `+b121` before the @ in To, Cancel, Save
      Draft. Drafts: the row's subject with its curly ’; the draft tapped,
      Subject and body as typed, quotes and dash as they were. One letter
      typed, then Cancel, Delete Draft: Drafts is empty again.
      5. *The share sheet:* a Wikipedia page in Safari, Share, Blackmail:
      at the end of Subject type ` don't`, and on the body's first line
      `"great"`: curly, as in the composer; in To, `carlo`, no capital.
      Cancel, Delete Draft. Nothing sent.
      *Seen on the test iPad 2026-10-25 on int15 (ac1b816), the three
      switches off as found, turned on for it and off again after: every
      step passed in both sheets, Subject capitalized and corrected,
      apostrophes and quotes curly and "--" one dash in Subject and body,
      read back from the server in UTF-8, To as typed (B-121).*
- [x] **B-125, a share's subject from what it hands over.** On the test
      iPad, the test account only, from a build with the change installed
      through TrollStore's helper as the share extension is (B-036). Nothing
      is sent: every share ends with Cancel.
      1. *Safari:* a Wikipedia page, Share, Blackmail: Subject is the
      page's title as Safari's tab shows it, "… - Wikipedia", and the
      sheet's title the same. Tap at the end of Subject and type ` x`:
      Subject and the title follow. Cancel: the question; Delete Draft.
      2. *The YouTube app:* a video, Share, Blackmail (under More if it is
      not in the row): Subject empty, "New Message" over the sheet, the
      link alone on the body's line under the empty first one. Cancel: it
      closes without asking. *From a build with B-126, Subject fills with
      the video's title a moment later: B-126's check.*
      3. *The share sheet's header:* in 2, before Blackmail is tapped,
      what the share sheet's header shows over its rows written down (the
      video's title or not): what iOS was given, which the extension is
      not.
      4. *Words beside a link,* if an app at hand shares them (Notes with
      a link in a note, or another): what Subject shows, written down.
      Cancel.
      *Seen on the test iPad 2026-10-25 on int15 (ac1b816), before B-126:
      1 to 3 passed. Safari's Wikipedia and YouTube pages gave their
      titles; the YouTube app's share an empty Subject; the share sheet's
      header the video's thumbnail and a name over the site's, not its
      whole title (B-125). Not possible: 4, Notes being offloaded on the
      test iPad and no other app at hand sharing words beside a link.*

- [x] **B-126, a YouTube share's subject, fetched.** On the test iPad,
      the test account only, from a build with the change installed
      through TrollStore's helper as the share extension is (B-036). Nothing
      is sent: every share ends with Cancel or Delete Draft. Screenshots at
      the sheet's first frame and a second after.
      1. *The YouTube app:* a video with a title of 75 characters or
      fewer, Share, Blackmail: the sheet comes up as before, To ready to
      type, and within a second or two Subject holds the video's title as
      the YouTube app shows it, and the sheet's title with it; written
      down, with how long it took. Cancel: it closes without asking.
      2. *A long title:* a video whose title is longer than 75 characters
      (search YouTube for "full concert live" or the like, and count):
      Subject is its first 72 characters and "...". Cancel.
      3. *Typed first:* share a video, tap Subject at once and type `x`
      before the title comes (or, where it comes too fast to beat, note
      that): Subject stays `x`. Cancel asks; Delete Draft.
      3b. *In Subject when it comes:* share a video, tap Subject at once
      and type nothing: the title comes into the field he is in, the caret
      at its end; type ` x`: it follows the title, and the sheet's title
      with it. Cancel asks; Delete Draft.
      4. *No connection:* Airplane Mode on (Wi-Fi off with it), share a
      video: the sheet as fast as before, Subject empty and staying so
      for 15 s. Cancel. Airplane Mode off, Wi-Fi back.
      5. *Safari:* the same video's page in Safari, Share, Blackmail:
      Subject "… - YouTube", Safari's title, as before; nothing asked.
      Cancel.
      6. *Not a video:* a channel's page shared from the YouTube app, if
      it offers Blackmail: Subject empty. Cancel.
      Send before the title comes is not tried: nothing is sent in these
      rounds, and the host's tests hold it (`ShareSheetTests`).
      *Seen on the test iPad 2026-10-25 on int15 (eaa68f5): 1, 2, 4, 5
      and 6 passed, the title in Subject from the sheet's first frame,
      YouTube answering 0.22 to 0.40 s after the tap; a 96-character
      title cut to its first 72 characters and "..."; offline, Subject
      empty for 21 s (B-126). Not possible: the race in 3 and 3b, the
      title always there before the sheet was in place, which the host's
      tests hold; their ` x`, Cancel and Delete Draft passed.*

- [x] **B-122, a photo in a letter, tapped.** On the test iPad, the test
      account only, built from the `bm-photo` worktree (branch
      `fix-photo-tap`) before it is merged. Nothing is sent, saved as a
      draft or APPENDed: one of the test accounts is signed in on the
      owner's phone and new mail rings it. The letters are ones already in
      the test account, found by the host read only (BODYSTRUCTURE and
      HTML, no flag set): a letter with a photo shown among its words by
      `cid:` (B-109's, in Trash since its check, or B-110's letter with an
      inline photo), a letter carrying the account's signature logo, an
      HTML newsletter with pictures from the web and one in a link (B-110's),
      and a conversation with a photo in one of its letters if there is
      one. A step whose letter is not there waits for the owner; none is
      made for it. Three panes, then two.
      1. *The photo:* tap it. Quick Look full screen, the photo whole, its
      name at the top, within a second or two for the letter just opened;
      the time written down. Done: the letter as it was, at the same place.
      Again, then the share button: Save Image and Save to Files are on the
      sheet. Save Image tapped: the photo in Photos (the test iPad's
      library may be used, B-067). Save to Files tapped: the Files sheet,
      then Cancel, nothing saved. Done.
      2. *The finger:* a short press, under about a quarter second, opens
      it as a tap does. From about 0.35 s, WebKit's menu (Share…, Save to
      Photos, Copy, Show Text), and no Quick Look under it or after it; a
      tap outside closes it. A drag that starts on the photo scrolls the
      letter and opens nothing; a pinch on it zooms the letter and opens
      nothing. Two quick taps: one Quick Look.
      3. *The signature's logo,* tapped: nothing opens. A picture from the
      web, tapped: nothing opens. A picture in a link, tapped: "Open this
      link?" and nothing else, Cancel; no Quick Look under it or after it.
      A photo in the signature or the quoted letter of a letter from
      Outlook, inside a bookmark (`<a name=...>` with no `href`, found by
      the host read of its HTML), if there is one: Quick Look, as 1.
      4. *In a conversation:* its line opened, the photo in that letter
      tapped: Quick Look, that letter's photo. Then another letter of the
      stack opened and the first photo tapped again: the time from the tap
      to Quick Look written down, and whether the app's log has a FETCH
      of the part (the server) or none (the copy kept on the iPad, B-111);
      nothing shows meanwhile (B-122, Not covered). His own letter from
      Sent Mail with a photo in the stack (B-104), if there is one, opened
      and its photo tapped: his photo. Then a photo of a letter not kept
      on the iPad, whose log has a FETCH of the part, tapped, and at once,
      before it comes, another row of the list tapped: that row's letter,
      and no Quick Look over it and no alert, then or in the half minute
      after; the app's log has the FETCH ending. The same with a file's
      row in the header, a PDF's if there is one, tapped and another row
      at once. Back on
      the first conversation, its photo tapped: Quick Look.
      5. *With no connection:* Airplane Mode on, the photo of 4 tapped
      again: from the copy kept on the iPad it opens; where 4's log had a
      FETCH, "Attachment could not be downloaded.", OK, and the letter as
      it was. Airplane Mode off.
      6. *Two panes,* 1 and 3 again, then three panes back.
      7. *Put back:* any letter where it was found (B-109's in Trash), the
      photo saved in 1 left in Photos or deleted, as the owner prefers.
      *Seen on the test iPad 2026-10-25 on int15 (ac1b816), on five letters
      the host put in the Inbox, read and dated days back, as none had a
      photo by `cid:`: every step passed but for what follows (B-122). 2
      as first written failed: holds of 0.35 and 0.5 s gave WebKit's menu,
      not Quick Look, and 0.2 s opened it as a tap. WebKit's menu starts at
      about 0.35 s on iPadOS 16.5.1 and the app opens a picture on the
      click alone, so the step was worded wrong; it now says so. Not
      possible: the pinch (one finger); his own Sent Mail letter with a
      photo (none, and none to send); the PDF row raced with another row,
      its 309 KB coming in 0.16 s.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 4's letter from
      Sent Mail passed, on letters the host put in the Inbox and in Sent
      Mail three days back, one conversation: his reply in Sent Mail alone,
      with a photo shown by `cid:`, between two of the other's in the Inbox,
      Complete Threads bringing his in only to an Inbox conversation of more
      than one letter. His line opened: "Found in Sent Mail", his words and
      the photo; the photo tapped, Quick Look on it (B-122). Done went back
      to the stack, its shot not looked at a second time. Left: the pinch
      and the PDF row's race, as before.*
- [x] **B-123, a half-typed name in search.** On the test iPad, the test
      account as filled for the size test (above), from a build of the
      `bm-halfname` worktree (branch `fix-halfname`). *Changed 2026-10-25
      after the first run of this check: up to 30 people, not four
      (KNOWN_ISSUES B-123, "Changed again"); steps 1, 4 and 10 are to be
      run again on a build with it.* Read only: nothing
      is composed, sent, moved, deleted or written to the mailbox, so no
      new mail reaches the phone the account is signed in on. Smart
      Punctuation on (Settings > General > Keyboard), as on his. Three
      panes unless a step says two; the app's connection log read after
      each step. The names below are the size test's own; where one is
      not listed, take another sender whose first name is no word of the
      subjects in sight, and write down which.
      1. *A name the app has seen.* The Inbox opened at its top and
      scrolled down two pages, so its senders are in the address book.
      All Mailboxes, the field tapped, "Pe" typed and a pause: as before,
      whatever "Pe" finds as a whole word, likely "No results". "y", so
      "Pey", and a pause: the letters, newest first, from, to and copied
      to each person in the book whose name or address starts "Pey", up
      to 30, and never "No results". Where more than 30 start so, as in
      the size test's book, the 30 are the first in the book's order:
      worked out beforehand from a read-only copy of the book in the
      prefs plist (a name's word before an address's, then most written
      to, then seen last, then by address), and written down. The log:
      one UID SEARCH each for the Trash, Spam and All Mail, the word in
      its five fields, then OR and FROM, TO and CC of each of those
      addresses in a tree of ORs in parentheses, answered OK.
      2. *Typing on:* "Peyt", "Peyto", "Peyton", each after a pause: the
      same person's letters each time.
      3. *A space:* "Peyton " with a space: the letters with Peyton as a
      whole word, as before, and the log's line has no address in it.
      Then "Pey " with a space: as before, likely "No results".
      4. *Two words:* a word from the subject of a letter of one of the
      people asked for in 1, a space, then "Pey": only letters with that
      word, that letter among them, each from, to or copied to one of
      those people or with "Pey" as a whole word. Then
      "Pey Sta": "Pey" asked whole, as before, likely "No results", and
      the log asking people for "Sta" alone.
      5. *Nobody:* "Qzx": "No results", and no address in the log's line.
      6. *Himself:* the first three letters of the test account's own
      name as Settings shows it: not every letter of the account; the
      log's line has neither the account's address nor any address the
      book has under that name.
      6a. *His other address:* Settings, "Add Another Email…" with
      Peyton Standin's address as one of Peyton's letters shows it, and
      Save; Settings and the app not otherwise touched. 1's "Pey": not
      Peyton's letters by the address, likely "No results", and the
      log's line has no address of Peyton's. The same for the first
      three letters of that address, if they are not "Pey". Settings:
      Remove it, Save; Settings again: its addresses as before 6a. "Pey"
      again: Peyton's letters as in 1.
      6b. *On someone's behalf,* if a sender in sight reads "… via …",
      a Google Group's: the first three letters of the name before
      "via": the log's line does not have the group's address. Write
      down which.
      7. *Pages:* the first three letters of a sender with more than 50
      letters, as Museum Members, "Mus": scrolled to the foot of the
      results and on, twice: no row twice, and one UID SEARCH per
      mailbox for those words in the log, none again as the pages come.
      8. *Current Mailbox,* in the Inbox: 1's "Pey": Peyton's Inbox
      letters, one UID SEARCH, the Inbox's.
      9. *Recent searches:* "Pey", Search on the keyboard, Cancel, a tap
      in the empty field: "Pey" first among Recent Searches. Tapped: the
      same letters as in 1. Cancel.
      10. *Time:* from the pause after "Pey" to the rows, and the same
      for "Peyton " with its space, in All Mailboxes, each written down.
      11. *An accent,* if a sender with an accent in the name is listed:
      the first three letters of the accented name typed without the
      accent, then with it from the letter's accent popover: that
      person's letters both times, never "Could not search. Check the
      connection.", the accented word a `{n+}` literal in the log.
      12. *Two panes:* 1 again, then three panes back.
      13. *Put back:* Cancel, and the Inbox at its top; Settings lists
      the addresses it did before 6a. Nothing else: nothing was written
      to the mailbox.
      *Seen on the test iPad 2026-10-25: 2, 3, 5 to 9, 12 and 13 passed on
      int15 (ac1b816), four people; 1 and 4 failed there, four of 36
      "Pey" people asked and "Picture Pey" missing a fifth's letter, and
      the change to 30 followed. On int15 (eaa68f5) 1, 4 and 10 passed:
      the book's first 30 "Pey" people asked in a tree of ORs, answered
      OK, "Picture Pey" finding that letter first, the rows 0.7 to 0.9 s
      after the pause (B-123). Not possible: 6b and 11, the size test's
      mailbox having no such sender.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 2, 3, 5 to 9, 12
      and 13 passed again, and 6b and 11, on letters the host put in the
      label Notes (B-123). 6b: "'Peyton Rand' via Rose Society" at a group's
      address, and the same via Garden Club writing to the group: "Pey"
      asked for the book's first 30 "Pey" people, neither group's address
      among them, where without the "via" rule the Rose Society's address
      came first. 11: "Zoe" found Zoë Müller's letter by her name; "Zoë",
      the ë from the e key's accent popover, the same letter, each word a
      `{4+}` literal, never "Could not search". Not run on int16: 1, 4, 6a
      and 10, passed on int15.*
- [x] **B-127, the header's To at the tap.** On the test iPad, the test
      account only, built from the `bm-paneheader` worktree (branch
      `fix-paneheader`) before it is merged. Nothing is sent, saved as a
      draft or composed: one of the test accounts is signed in on the
      owner's phone and new mail rings it. The host makes the letters and
      APPENDs them, read (`\Seen`), to a label of their own, "B-127", not
      the Inbox, each dated three days back: (a) from "Jane Example", To
      "Example, Pat" (a quoted name with its comma), a name in an encoded
      word and a bare address, Cc one more, and a PDF of about 3 MB, no
      more than 3.5, so its body takes a moment; (b) the same To, three
      lines of words; (c) a letter to Sam with a Cc and (d) Sam's reply to
      it, To Jane alone, one conversation (Gmail's thread, its References
      naming (c)). The PDF's size matters: in base64 a file comes to about
      1.37 times its size, so 3 MB is a letter of about 4.1 MB, under the
      5 MiB above which the app opens a letter without its files
      (`IMAPMailRepository.largeLetterBytes`), and it is fetched whole: a
      3 MB letter took about 1.3 s on the test iPad (B-111's check), this
      one a little longer. A 4 MB PDF is a letter of about 5.5 MB, opened
      in part, its text alone, as fast as a small letter. The host reads
      back (a)'s RFC822.SIZE before the run and finds it under 5,242,880.
      His own letter in Sent Mail to someone else is one already there,
      found by the host read only (B-060's "B-060 two", to Sam's bare
      address with Cc Jane, or another), and written down. Organize by
      Thread on, three panes, then two; a screen recording through each
      tap.
      1. *A letter alone:* the label opened, (a) tapped. In the first
      frame with "Loading…" the header's To line names the three, "To:
      Example, Pat, " then the encoded name decoded, then the bare
      address, as far as the line goes, the Cc under it, the PDF's row
      grey; when the body lands the To line's words do not change and
      nothing in the header moves. Never "To: me" in any frame.
      2. *Sent Mail:* his letter written down above, tapped: the header
      names whom it went to from the first frame, never "To: me".
      3. *No connection:* Airplane Mode on, (b) tapped, never opened on
      this iPad before, so not kept on it (B-111): "This message could
      not be downloaded." under a header whose To is the letter's, not
      "To: me". OK on the alert. Airplane Mode off.
      4. *A conversation:* the conversation of (c) and (d) opened from the
      label: its header has (d)'s To, "To: Jane Example", from the first
      frame, and nothing in the header changes as its body lands.
      5. *Two panes:* 1 and 2 again, then three panes back. (a) is likely
      kept on the iPad since 1 (B-111), its body then coming at once, with
      no frame of "Loading…"; the To line in the first frame is what is
      looked at.
      6. *Put back:* the label's letters and the label left for B-128's
      and B-129's checks, or moved to Trash by the host, as the owner
      prefers. Nothing was written to Sent Mail.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 6
      passed, never "To: me" in a frame: (a)'s To and Cc in the first
      frame with "Loading…", 0.27 s, unchanged as the body landed at
      1.53 s; Sent Mail's To at 0.14 s; offline, (b)'s To over "could
      not be downloaded"; the conversation's, (d)'s, from 0.14 s; two
      panes the same for (a), Sent Mail's there not looked at a second
      time (B-127). The letters were in the label Notes, the round's rules
      allowing no label of their own, and the host put them in the Trash;
      the Sent Mail letter was another, there being no "B-060 two". 1 seen
      again the same day on the iOS 18.6 simulator.*
- [ ] **B-128, the stack under a header that changes height.** On the
      test iPad, the test account only, built from the `bm-paneheader`
      worktree (branch `fix-paneheader`) before it is merged. Nothing is
      sent, saved as a draft or composed. The host APPENDs three letters,
      read (`\Seen`), to the label "B-127" (or one of their own, "B-128"),
      dated four, three and two days back, one conversation (Gmail's
      thread, each reply's References naming the one before): (a) plain,
      no Cc, no file, some forty lines of words, so that open it is
      taller than the pane; (b) a reply with a Cc and a PDF of about 100
      KB; (c) a reply, plain, no Cc, no file. Organize by Thread on, three
      panes, then two; a screen recording through each tap. A line tapped
      within a second of the stack moving with the header does nothing
      (B-128, item 5), and that second starts only once the stack has
      moved, after the tap; so each tap below comes about two seconds (1.5
      s at least) after the one before, but where a step says otherwise. A
      tap inside that second shows no light and does nothing.
      1. *Opened:* the conversation's row tapped. (c) open, (b)'s line at
      the top of the pane, whole, (a)'s above it out of sight; the header
      (c)'s, no Cc line, no file.
      2. *A header that grows, the line at the top:* (b)'s line tapped.
      When its body lands the header gains the Cc line and the PDF's row,
      and the whole stack moves down by as much: (b)'s line is still the
      top line of the pane, whole, its top at the header's bottom edge,
      not half under it. Written down: how far (b)'s line moved.
      3. *A header that shrinks, the stack's first line:* the status bar
      tapped: (a)'s line at the top, whole. (a)'s line tapped: when its
      body lands the header loses the Cc line and the PDF's row, the stack
      moves up with it, and (a)'s line is still the top line, whole.
      4. *A header that grows, the stack at its very top:* (a)'s line
      tapped to close it, and the status bar tapped again if the stack
      has moved: (a)'s line at the top, (b)'s under it. (b)'s line tapped
      twice, closed then opened: its body already in the stack, the
      header gains the Cc line and the row at once, and (a)'s line, the
      stack's first, is still the top line, whole, the case seen in
      B-055's check.
      5. *A line low in the pane,* the cost of the stack hanging from the
      header, for the owner to weigh (KNOWN_ISSUES, B-128, Not covered):
      (a)'s line tapped: it opens, its forty lines, the header (a)'s, with
      neither a Cc line nor a file, the stack moving up with it. The stack
      scrolled down to (b)'s line, below (a)'s words, and that line tapped
      to close it. Then the stack scrolled until (b)'s closed line sits
      within about 80 pt of the pane's bottom edge, (a)'s words above it,
      and a second's wait. (b)'s line tapped once: at the tap the header
      gains the Cc line and the PDF's row, about 64 pt, and the stack moves
      down by as much. Written down from the recording: where (b)'s line
      was before the tap and after it, whether it stayed in sight, whole,
      in part or not at all, and whether the first line of its words did.
      Its body is in the stack from 2, so there is no "Loading…"; a first
      opening has it there, where the words are.
      6. *A double tap on a line that grows the header:* the status bar
      tapped, (a)'s line tapped to close it, then (b)'s, now under it, and
      then (c)'s twice, closed and opened: the header (c)'s, no Cc line,
      no file. The status bar tapped again if the stack has moved: (a)'s
      line at the top, (b)'s under it. (b)'s line tapped twice quickly, as a
      double tap, in the middle of the line: at the first tap (b) opens,
      its words under it, and the header gains the Cc line and the PDF's
      row, the stack moving down by about 64 pt; the second tap, which by
      then lands on (a)'s line, does nothing: (a)'s line not lit, (a)
      still closed, (b) still open, the header (b)'s. Written down from the
      recording: what was under the second tap. Then, about two seconds
      later, (a)'s line tapped once: it opens, and the header is (a)'s.
      7. *Nothing else moved:* in 2 to 4 and 6, the letter opened grows
      below its own line, and no frame shows a line half under the header.
      8. *Two panes:* 1 to 3 again, then three panes back.
      9. *Put back:* the label's letters left for B-129's check, or moved
      to Trash by the host, as the owner prefers.
      *On a build with B-129, as this branch is, the header changes at
      the tap, not as the body lands; every step holds the same.*
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 6, 8
      and 9 passed: (b)'s line moved 64 pt with the header and stayed
      the top line, whole, (a)'s the same as the header shrank and at
      the stack's top, and the double tap's second tap did nothing. For
      5: (b)'s closed line went from about 70 pt above the pane's bottom
      edge to about 6 pt, in sight in part, none of its words in sight
      (B-128). The letters were in the label Notes, put in the Trash by
      the host. Not shown: 7 as written, the frames being stills 0.13 s
      apart, not a recording, and the header changing between two of
      them each time; none had a line half under the header. Left: 7,
      from a recording at 60 frames a second.*
- [x] **B-129, the conversation's header at the tap.** On the test iPad,
      the test account only, built from the `bm-paneheader` worktree
      (branch `fix-paneheader`) before it is merged. Nothing is sent: each
      composer opened is closed by Cancel, then Delete Draft. The host
      APPENDs five letters, read (`\Seen`), to a label of their own,
      "B-129", dated six to two days back, one conversation (Gmail's
      thread, each reply's References naming the one before), none of
      them opened on this iPad before, so none kept on it (B-111): (a) a
      PDF of about 3 MB, no Cc; (b) a Cc and a PDF of about 3 MB; (c)
      three lines, no Cc, no file; (d) a PDF of about 3 MB, no Cc; (e) the
      newest, three lines, no Cc, no file. The PDFs' size matters: in
      base64 a file comes to about 1.37 times its size, so 3 MB, and no
      more than 3.5, is a letter under the 5 MiB above which the app opens
      a letter without its files (`IMAPMailRepository.largeLetterBytes`),
      and it is fetched whole, `BODY.PEEK[]`: a 3 MB letter took about 1.3
      s on the test iPad (B-111's check), these a little longer. A 4 MB
      PDF is a letter of about 5.5 MB, opened in part, its text alone, as
      fast as a small letter, and the taps below that have to come before
      a body cannot. The host reads back (a)'s, (b)'s and (d)'s RFC822.SIZE
      before the run and finds each under 5,242,880. Organize by Thread
      on, three panes; a screen recording through each tap; the app's
      connection log read after each step. A line tapped within a second
      of the stack moving with the header does nothing (B-128, item 5), so
      the taps below come about two seconds apart (1.5 s at least), but
      where a step says at once.
      *A step that needs a body still coming,* Reply in 2, Flag in 3 and
      (b)'s two taps in 4, was run only if it came first: the log gives how
      long the letter's FETCH took, from its line to its tagged OK; the
      recording, how long after the letter's tap the other tap came, and
      "Loading…" still under the letter's line in that frame. Opening (b)
      again in 4 sends nothing, its body being in the stack, so its time is
      the recording's alone. If the tap came after the body, the step was
      not run: the letter is kept on the iPad by then (B-111) and would come
      at once, so the host APPENDs a copy of it, read (`\Seen`), to the
      label "B-129", a Message-ID of its own,
      its References naming the letter before it, dated an hour after it,
      the conversation is opened again from the label, and the step is done
      again on the copy.
      1. *Opened:* the conversation's row tapped: (e) open, (d)'s line at
      the top of the pane, (a) to (c) above it out of sight; the header
      (e)'s.
      2. *At the tap:* the stack scrolled up until (b)'s line is the top
      line of the pane, then (b)'s line tapped. In the first frame after
      the tap the header is (b)'s, its sender, To, Cc, subject and date,
      the PDF's row grey, "Loading…" under (b)'s line, and the stack moved
      down with the header, which gained the Cc line and the PDF's row,
      (b)'s line still the top line of the pane, whole (B-128). Reply
      tapped at once, before the body has come: nothing opens. Once it
      has: the PDF's row blue; Reply, then Reply in its sheet: a composer
      quoting (b), To (b)'s sender. Cancel, Delete Draft.
      3. *Flag at the tap:* the stack scrolled until (d)'s line is in
      sight, (d)'s line tapped and at once, before its body has come,
      Flag, then Flag in its sheet: the host, read only, finds `\Flagged`
      on (d) and on no other of the five. Flag again, Unflag: on none.
      4. *The race:* the stack scrolled up until (a)'s line is the top line
      of the pane; (a)'s line tapped and at once, before its body has come,
      (b)'s line, under (a)'s "Loading…", tapped twice, closed and opened
      again, its body kept from 2: the header (b)'s at once, its PDF's row
      blue. (a)'s header is (d)'s height, so nothing moved at (a)'s tap.
      When (a)'s body comes, in its section, the header stays (b)'s,
      through the half minute after. Reply, then Reply: a composer quoting
      (b). Cancel, Delete Draft. The log: (a) asked once, `BODY.PEEK[]`,
      with no `BODY.PEEK[HEADER]` for it, so fetched whole; and from
      (a)'s tap to (b)'s second tap shorter than (a)'s FETCH, as above.
      5. *No connection:* Airplane Mode on, (c)'s line tapped: the header
      (c)'s from the tap, and in its section "This message could not be
      downloaded. Tap the line above twice to try again."; Reply does
      nothing. Airplane Mode off, (c)'s line tapped twice: its words, the
      header the same, Reply answering (c); Cancel, Delete Draft.
      6. *A double tap on a line that grows the header:* (a)'s and (b)'s
      lines tapped to close them, the header still (c)'s, no Cc line, no
      file; the stack scrolled until (a)'s line is the top line of the
      pane, (b)'s under it. (b)'s line tapped twice quickly, as a double
      tap, in the middle of the line: at the first tap (b) opens, its words
      under it, and the header is (b)'s, gaining the Cc line and the PDF's
      row, the stack moving down by about 64 pt; the second tap, which by
      then lands on (a)'s line, does nothing: (a)'s line not lit, (a)
      still closed, the header and the toolbar (b)'s. Written down from the
      recording: what was under the second tap.
      7. *Two panes:* the conversation opened again: (e) open, (d)'s line
      at the top. The stack scrolled up until (a)'s line is the top line
      of the pane; (a)'s, (b)'s and (c)'s lines tapped one after another,
      each about two seconds after the last: the header follows each
      tap and ends on (c)'s, and (a)'s line is the top line, whole, after
      each. Three panes back.
      8. *Put back:* no flag on the five, no draft left in Drafts, and
      the label's letters, with any copies, left or moved to Trash by the
      host, as the owner prefers.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 8
      passed: the header the letter's at the tap, 0.22 s, the stack
      moving with it; Reply 0.79 s before the body opened nothing; Flag
      0.39 s before the body flagged (d) alone; in the race (b)'s second
      tap came 0.64 s into (a)'s 1.06 s FETCH and the header stayed
      (b)'s for 30 s after (a) landed, (a) fetched once, whole; offline,
      (c)'s header and its line; the double tap's second tap did
      nothing; two panes the same (B-129). Every early tap came before
      its body, so no copy was needed. The letters were in the label
      Notes, put in the Trash by the host. The header at the tap seen
      again the same day on the iOS 18.6 simulator.*
- [x] **B-130, the signature's white sheet for a letter shown alone.** On
      the test iPad, the test account, from a build of the
      `bm-signsheet` worktree (branch `fix-signsheet`). Nothing is
      composed, sent, moved or deleted in the app, so no new mail reaches
      the phone the account is signed in on. Four letters the host makes
      and APPENDs, read (`\Seen`), to a label of their own, "B-130", never
      the Inbox, dated three days back, each with a Message-ID of its own,
      new, and its own Date, and none naming any of the 22 letters below
      in a Message-ID, In-Reply-To or References: Gmail can take a letter
      APPENDed with a Message-ID it holds for the letter it holds, and
      only label that one. The host notes each APPEND's UID from its
      APPENDUID, and stops if one has none. (a) "B-130 alone", one of the
      22 letters on the account that carry the signature, its HTML body
      and its logo part copied, nothing else of it; (b) "B-130 stack", a
      letter from another address, and (a)'s body as a reply to it, "Re:
      B-130 stack", its In-Reply-To and References naming the first by
      its new Message-ID, a day later, so the two are one conversation;
      (c) "B-130 quoted", a reply that keeps the sheet's class, its
      `<blockquote type="cite">` holding (a)'s body as Apple Mail's reply
      and this app's quote it, alone in its thread. Before step 1, the
      host lists the label: the four UIDs it noted and nothing else, or
      stop. Three panes unless a step says two.
      1. *Alone:* "B-130", then "B-130 alone": the signature on a white
      sheet across the letter, its lines black, its links blue, the logo
      as on paper, dark ink on the white; the words above it white on the
      black. Then two panes: the same.
      2. *One of the 22, alone,* one already read, in whichever folder
      it is, nothing done to it: as 1.
      3. *In a stack:* "Re: B-130 stack", the reply's line tapped open if
      it is closed: its signature on the same white sheet as in 1, the
      words and the logo alike.
      4. *Quoted:* "B-130 quoted": the violet bar down the quote, and
      inside it the sheet white with its black words and the logo. (A
      reply from Gmail's web page renames the class, and its quoted
      signature looks as before: not a step.)
      5. *Print:* on 1's letter, Reply, then Print: the preview's paper
      white, the signature's words black and the logo as on paper, no
      black box; Cancel. No paper.
      6. *Put back:* the host moves the four UIDs it noted, and only
      them, from the label to the Trash (`UID MOVE`), deletes in the Trash
      only the UIDs that move answered (`COPYUID`), then deletes the
      label, empty. Never anything found by subject, Message-ID or label:
      if the label holds a UID not noted, it is left, and written down.
      Nothing else was written.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 6
      passed: the white sheet alone, in two panes, in the stack and in a
      quote, and no black box in Print's preview (B-130). (a) has no
      words above the signature; words above a sheet were white on the
      black in 4, and a link blue in 2. The letters were in the label
      Notes, listed and put in the Trash by Message-ID, the round's
      rules allowing no MOVE, delete or new label. 1 seen again the same
      day on the iOS 18.6 simulator, three panes.*
- [x] **B-131, Print's "This message has no text." only where the
      pane's.** On the test iPad, the test account, from a build of the
      `bm-signsheet` worktree (branch `fix-signsheet`). Nothing is
      composed, sent, moved or deleted in the app, and nothing is printed
      on paper: the Print panel's preview only. Two letters the host makes
      and APPENDs, read (`\Seen`), to a label of their own, "B-131", never
      the Inbox, dated three days back: (a) "B-131 only the beginning", over
      5 MB, multipart/mixed of an HTML part whose first 2.2 MB are a
      `<style>` holding only comments, then a paragraph of words, and a
      PDF of about 4 MB, so the pane fetches the HTML's first 2 MiB alone
      and they draw nothing; (b) "B-131 nothing", a small HTML letter of
      `<div><br></div>`. Each with a new Message-ID of its own; the host
      notes each APPEND's UID from its APPENDUID, and stops if one has
      none. Three panes.
      1. *Shown in part:* "B-131", then (a): the pane's grey "Only the
      beginning of this message is shown." and nothing under it, never
      "This message has no text." (B-114). If words show, the style was
      not long enough: write it down and stop.
      2. *Its print:* Reply, then Print: the preview has the header, then
      the same grey line and nothing under it, never "This message has no
      text."; Cancel.
      3. *Nothing in it, whole:* (b): the pane's grey "This message has no
      text."; Reply, Print: the preview the same words under the header;
      Cancel.
      4. *Put back:* the host moves the two UIDs it noted, and only them,
      from the label to the Trash (`UID MOVE`), deletes in the Trash only
      the UIDs that move answered (`COPYUID`), then deletes the label,
      empty. Never anything found by subject, Message-ID or label.
      Nothing else was written.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 4
      passed: (a)'s pane and its print's preview the grey "Only the
      beginning of this message is shown." over nothing, never "This
      message has no text."; (b)'s both "This message has no text."
      (B-131). The letters were in the label Notes, put in the Trash by
      Message-ID, the round's rules allowing no MOVE, delete or new
      label.*
- [ ] **B-132, a failed Edit mode Delete or Move puts its rows back
      where they stood.** On the test iPad, the test account, from a
      build of the `bm-editlist` worktree (branch `fix-editlist`).
      Nothing is sent and nothing comes to the Inbox: the letters are the
      host's, APPENDed read into a label "B-132" it makes, dated two days
      back and more, a Delete moves them to Trash, and a Move to a second
      label the host makes, "B-132 moved". Three panes; the connection
      log read after each step; Airplane Mode turned off after each step
      that turns it on.
      0. *The letters:* sixteen, read. Two conversations of two letters,
      "B-132 one" and "B-132 two", the reply's In-Reply-To and References
      naming the first, dated two days back; and twelve alone, "B-132
      single 1" to "12", three and four days back, below them. The label
      "B-132 moved" made empty beside "B-132".
      1. *Refused at the first letter, at the top:* B-132 opened at its
      top. Edit, the two conversations' rows ticked, Airplane Mode on,
      Delete. The two rows go at the tap and are back where they stood,
      the list at its top, every row as before the tap, not ticked, Edit
      mode over; "Can't connect to mail server.", OK. The log: one
      `NO-PATH UID MOVE nothing-sent`. Airplane Mode off, Refresh: the
      same rows.
      2. *In the middle of the list:* scrolled until a single's row is
      the first in view, a little way down; write down which. Edit, that
      row and the next two ticked, Airplane Mode on, Delete: the three go
      and come back where they stood, every row in view where it was
      before the tap, the list not scrolled; the alert as in 1.
      3. *Some moved, then a failure:* at the top, Edit, Select All,
      Delete, and Airplane Mode on about a second after the tap. The rows
      whose letters the log shows answered `OK [COPYUID …]` stay off, the
      rows below closing up; the rest come back where they stood, a
      conversation of which one letter went with the other alone; the
      alert. Airplane Mode off, Refresh: the same rows as before it, row
      for row. A row that came back but is gone at the Refresh, its MOVE
      on the wire as the network went, is B-092's lost answer (B-132,
      Not changed; in a label the watch does not look, so it waits for
      the Refresh): write it down, with its log lines. On a build with
      B-151 such a row goes by itself at the watch's next check, before
      the Refresh: B-151's check.
      4. *A Move:* 1 and 3 again on what 3 left, with Move in place of
      Delete: Edit, the top two rows for 1's and Select All for 3's, Move,
      "B-132 moved" chosen, Airplane Mode on before the Move for 1's, and
      about a second after the label is chosen for 3's. As in 1 and 3:
      every row back where it stood, nothing in the log but `NO-PATH UID
      MOVE nothing-sent`; then the rows of the letters answered `OK
      [COPYUID …]` off, the rest back where they stood, the alert each
      time. Airplane Mode off, Refresh, then "B-132 moved" opened from
      Mailboxes: the letters the log shows answered and any whose MOVE was
      on the wire as the network went, gone at the Refresh (B-092's lost
      answer, as in 3), and back to B-132. If the Move list does not
      offer the label with Airplane Mode on, write it down, and turn it
      on after the label is chosen instead, as fast as can be.
      5. *Two panes:* 1 again, then three panes back.
      6. *Put back:* the labels B-132 and "B-132 moved", with what is
      left in them, deleted by the host, and the letters in Trash left
      there.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 6
      passed on the screen. Refused, every row came back where it stood,
      not ticked, Edit mode over, with the alert; some moved, their rows
      stayed off and the rest came back, and one lost answer each time,
      single 3 and then single 9, went at the Refresh as B-092 has it
      (B-132). The letters were in the label Notes and the Move went to
      an empty label of the account's own, the round's rules allowing no
      label of their own; the rows were ticked by hand for Select All,
      Notes holding the account's 30 letters. 4 as first written wanted
      the label to hold exactly the letters answered; it held those and
      the lost one, and now says so. Not shown: the rows going at the
      tap, the first frame, 0.26 s after it, having them back; 5's
      Refresh, none made; and in 4 the log's line for the Move refused: it
      wrote none, where 1 has one `NO-PATH UID MOVE nothing-sent`, the
      Inbox's poll having found no path 4 s before, `NO-PATH STATUS
      not-sent`. A difference in the log alone: the screen was right and
      nothing was sent. Left: those three, the first from a recording at 60
      frames a second.*
- [ ] **B-133, the open letter's row stays highlighted.** On the test
      iPad, the test account, the same build, with B-132's sixteen letters
      in the label "B-132" (its step 0; made again by the host if B-132's
      check has put them away). Nothing is sent; step 6 moves two of them
      to Trash. Three panes; the connection log read after each step.
      1. *Done:* B-132 opened, a single tapped: its letter in the pane,
      its row highlighted. Edit: no row highlighted or ticked. Done: the
      row highlighted again, the letter still in the pane, the list where
      it was, and nothing in the log at Done.
      2. *Done after ticks:* Edit, two other rows ticked, Done: the ticks
      gone, the open letter's row highlighted.
      3. *Mark:* Edit, another row ticked, Mark, Mark as Unread: Edit mode
      ends, that row's dot on, the open letter's row highlighted. The same
      with Mark as Read, to put it back.
      4. *A conversation:* "B-132 one" tapped, its stack in the pane.
      Edit, Done: its row highlighted.
      5. *Go to Date:* the calendar, Current Mailbox, the open
      conversation's day, a conversation that is not its day's newest
      letter, a later one of that day above it, so that the day's list
      does not begin at its row: the list at the day as before, the
      conversation's row highlighted where it lands, the list not moved
      to it, and in the log nothing but the jump's own: its SEARCH, and
      the FETCHes of the day's page, envelopes and previews
      (`BODY.PEEK[1]<0.2048>`, or another part's first 2,048 bytes),
      which are expected. A FETCH of the open letter's whole body, or any
      STORE, at the highlight is a fail. Then,
      in All Mail, a read letter near its top opened and Go to Date to a
      day far enough back that the day's list does not reach it, if the
      account has one (write down which, or that it has none): no row
      highlighted, the letter in the pane; the list scrolled up until the
      pages bring its row: the row highlighted as it comes, no tap, and
      nothing fetched but the pages' own envelopes and previews, by the
      same rule.
      6. *A Delete of the open letter:* B-132, a single opened, Edit, its
      row and another ticked, Delete: the pane empty, both rows gone, no
      row highlighted.
      7. *Two panes:* 1 again, then three panes back.
      8. *Put back:* if the letters were made again for this check, the
      label B-132, with what is left in it, deleted by the host here, and
      the letters in Trash left there; otherwise nothing more, the label
      going with B-132's step 6.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), on B-132's
      letters in the label Notes: 1 to 4 and 6 to 8 passed, the open
      letter's row highlighted after Done, after ticks, after Mark and
      for a conversation, nothing in the log at Done; in 5 the row
      highlighted at the day, the log the jump's SEARCHes, envelopes and
      previews alone, and in All Mail highlighted as the pages brought
      it, no tap, no body fetched, no STORE (B-133). Not shown: 5's "the
      list not moved to it", the conversation being its day's newest
      letter, so the day's list began at its row either way; the step as
      first written took any conversation and now asks for one that is
      not. Left: that part of 5. Edit and Done seen again the same day
      on the iOS 18.6 simulator.*
- [ ] **B-134, letters over a bubble's menu, and Cc/Bcc as Mail's.** On the
      test iPad, the test account only, landscape, built from the
      `bm-bubblesugg` worktree (branch `fix-bubblesugg`); merge only after
      a pass. The on-screen keyboard up throughout but in 6: if a keyboard
      bar shows instead, its keyboard key, then Show Keyboard. Nothing is
      sent: every letter ends with Cancel, and Delete Draft if it is asked.
      1. *Letters over the menu.* A new letter. In To type `Al
      <al@example.com>` and a comma: a bubble "Al". Tap it: its menu under
      it, and no list. Type "s": "Al" and its menu go, "s" is on the line,
      and the list opens under To with every row in sight, nothing over
      it. Delete: the "s" goes and the list closes. Cancel.
      2. *Letters typed before the tap.* A new letter. In To `Al
      <al@example.com>` and a comma, then "s": the list. Tap "Al": the
      list closes, the menu opens under "Al". Return: "s" a bubble after
      "Al", "Al" still bright, the menu still on it, no list. Tap outside:
      the menu goes, "Al" plain. Cancel, Delete Draft.
      3. *Delete over the menu.* A new letter. In To `Al <al@example.com>`
      and a comma, then "sa". Tap "Al": its menu. Delete: "Al" and its
      menu go, "sa" stays on the line, and the list for "sa" opens, in
      sight. Cancel, Delete Draft.
      4. *Cc/Bcc.* A new letter. Tap "Cc/Bcc": Cc and Bcc, the caret in
      Cc, and no "Cc/Bcc" row under Bcc. Tap Subject: Cc and Bcc fold
      back into the "Cc/Bcc" row. Tap it again; in Bcc type `Bo
      <bo@example.com>` and a comma; tap the body: Cc and Bcc stay, no
      "Cc/Bcc" row. Tap "Bo", Remove; tap To: they fold back. Cancel,
      Delete Draft if asked.
      5. *Another field's bubble, and from the body.* A new letter. In To
      `Al <al@example.com>` and a comma; "Cc/Bcc"; in Cc `Jo
      <jo@example.com>` and a comma. Tap the body and type a word. Tap
      "Al": its menu under "Al", its arrow on it, never beside it, the
      caret now in To on the email keyboard. Type "s": "Al" goes, the list
      under To in sight. In landscape that list covers the Cc row, so type
      on, "qx", until no row matches and it closes; if it stays, Tab, and
      that written down. Tap "Jo": the letters in To become a bubble as
      the caret leaves To, as in Mail; its menu under "Jo", the caret in
      Cc. Type "s": "Jo" goes, the list under Cc in sight. Cancel,
      Delete Draft.
      6. *The keyboard put away.* A new letter. In To `Al
      <al@example.com>` and a comma, then hide the keyboard with its key.
      Tap "Al": its menu under it, its arrow on it, and the keyboard
      stays down. Tap outside. Cancel.
      7. *The share sheet,* from Safari on example.com. It opens in To.
      `Al <al@example.com>` and a comma; tap "Al": its menu under it, and
      Cancel and Send stay blue, as in the app's composer. Type "s": as
      in 1. Cancel: its question, Cancel and Send still blue; Delete
      Draft. Share again: step 4 there. Cancel, Delete Draft if asked.
      8. *The app's composer, colours.* A new letter, "Al" in To, its
      menu up: Cancel and Send stay blue, as before. Cancel, Delete Draft.
      9. *A space after letters.* A new letter. In To `Al
      <al@example.com>` and a comma, then "sa". Tap "Al": its menu, no
      list. Type a space: "Al" and its menu go, "sa" is on the line, and
      the list for "sa" opens under To, every row in sight. Cancel,
      Delete Draft.
      10. *A tap on the line after a Delete.* A new letter. In To `Al
      <al@example.com>` and a comma, `Bo <bo@example.com>` and a comma.
      Delete once: "Bo" bright. Tap the line after the bubbles: "Bo"
      plain, the caret on the line. Type "c": "c" on the line, "Al" and
      "Bo" both still there. Delete twice: "c" goes, then "Bo" bright.
      Type "d" with no tap: "Bo" goes and "d" is on the line, as in Mail.
      Cancel, Delete Draft.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d): 1 to 4 and 6 to
      10 passed: letters, Delete or a space over the menu took the bubble's
      place, the menu went and the list was in sight; Cc/Bcc went while they
      showed and folded back; the share sheet the same, Cancel and Send blue
      with the menu up and at Cancel's question, of which only the blue with
      the menu up was looked at a second time (B-134). In 5 the menu came
      under "Al" from the body, its arrow on it, the caret in To on the
      email keyboard; but To's list covered the Cc row, so "Jo" could not be
      tapped. To was left by Tab instead, the "s" becoming a bubble, then
      Jo's menu and the Cc list came, its fourth row cut by the keyboard's
      top. 5 as first written could not be followed there; it now says how
      to close the list first. Left: 5's tap on "Jo" with letters on To's
      line. 2 seen again the same day on the iOS 18.6 simulator, three
      panes, its link blue above the sheet; two panes not looked at there.*
- [ ] **B-135, search previews carried over.** On the test iPad, the test
      account as filled for the size test (above), from a build of the
      `bm-searchprev` worktree (branch `fix-searchprev`). Read only, as
      B-123's check: nothing is composed, sent, moved, deleted or written
      to the mailbox, so no new mail reaches the phone the account is
      signed in on. The Outbox empty before step 1: a pulled Refresh
      (step 8b) sends what waits there (B-072), so if it holds a letter,
      stop there. Three panes; the app's connection log read after each
      step, a preview's FETCH being `UID FETCH … (UID BODY.PEEK[…]<0.n>)`
      after the UID SEARCHes; a screen recording through steps 1 to 4.
      1. *A name typed slowly.* The Inbox at its top with its previews
      drawn. All Mailboxes, the field tapped, "Pey" and a pause: the rows,
      and their previews let come in full; the log has the UID SEARCHes,
      then the preview FETCHes. Then "t", so "Peyt", and a pause: every
      row of a letter "Pey" showed has its two lines in the first frame it
      is drawn, no grey lines on it, and the log has the UID SEARCHes and
      no preview FETCH after them but for UIDs "Pey" did not find, if any,
      written down. The same for "o" and "n", one at a time. The two empty
      drafts among the hits (UIDs 83185 and 83701 on that mailbox) are
      asked for at "Pey" alone, answered with two bytes each, and at no
      pause after; on int16 (662d63d) every pause asked for them again
      (B-135, "Found on the test iPad").
      2. *The right words.* Three rows of 1's "Peyton" that have no
      unread dot, tapped one by one: each letter begins with its row's
      words. Only rows already read, so that opening one marks nothing
      read on the server; if fewer than three are, as many as there are.
      3. *Back.* The delete key, a pause after each, back to "Pey": the
      rows with their lines at once, no preview FETCH.
      4. *Nothing, then the same again.* "x", so "Peyx", a pause: "No
      results". The delete key and a pause: "Pey"'s rows with their lines
      at once, no preview FETCH.
      5. *Typing on before the lines come.* Cancel, the field tapped,
      "Mus" (Museum Members, or another sender with more than 50 letters),
      and as soon as its rows appear, before their lines fill, "e" and a
      pause: "Muse"'s rows. In the log, no UID is asked for a preview
      after "Muse"'s UID SEARCHes whose preview FETCH was answered before
      them; write down whether one was on the wire as "Muse" was asked.
      6. *A page.* "Mus" again, a pause, its lines let come, then scrolled
      to the foot of the results: the next page's preview FETCH names only
      that page's UIDs. Then "e" and a pause: no preview FETCH for UIDs
      of either page that "Muse" finds.
      7. *The Inbox alone.* Cancel, the Inbox scrolled down two pages and
      back to its top, Current Mailbox, "Pey" and a pause: its rows with
      their lines at once, no preview FETCH for letters on those pages.
      7b. *The Inbox's rows after Cancel.* Cancel, Sent, then the Inbox,
      so that it opens afresh with only its first page loaded, and at
      once, before its lines fill, Current Mailbox, "Pey" and a pause, its
      rows' lines let come; write down whether the Inbox's lines were
      still coming as the search began. Cancel: every row of the Inbox
      has its two lines, a preview FETCH asking for any still grey at the
      Cancel, and none is left grey. Then scrolled down to the first row
      of a letter "Pey" found below that first page, if there is one: its
      two lines come, and the log has a preview FETCH naming its UID. On
      the fix's first form (B-135, "A fault in the fix's first form")
      those rows were left grey.
      8. *Two panes:* 1 again, then three panes back.
      8b. *Drafts refreshed.* Cancel, Drafts, its rows and their lines
      let come: one preview FETCH names the two empty drafts' UIDs there,
      answered with two bytes each. Then pulled down to Refresh, twice,
      the rows let come each time: no preview FETCH after either. No
      draft is tapped: one tapped opens in the composer.
      9. *Put back:* from Drafts, the Inbox, at its top; the search's
      scope left on All Mailboxes, as step 8 left it. Nothing else:
      nothing was written to the mailbox.
      *Since B-143 (2026-10-26): a row that comes into sight with its two
      lines empty after its preview's FETCH has answered, as round
      r6-s7-fixes saw once in ten tries on int17 (92f2cb9) over letters
      the host APPENDed to "Notes", is not this check's: the preview was
      in the list and the cell made ahead was not drawn again as it came
      in. Written down with its UID and the time its preview was answered,
      and B-143's check (below) runs it again.*
      *Seen on the test iPad 2026-10-26 on int17 (92f2cb9): 1 to 9 passed
      as written, frames about 0.3 s apart in place of a recording. The
      two empty drafts were asked for at "Pey" alone, two bytes each, and
      at no pause after; "Peyt" and "Peyto" asked for no preview, "Peyton"
      only for two hits in the Trash that "Pey" had not found; every row
      had its lines in every frame (B-135). In 5 the "e" came before
      "Mus"'s lines, but "Muse" was asked 0.1 s after "Mus"'s previews
      were answered, none on the wire. 7b counted at its second try, the
      first having left the scope on All Mailboxes: the Inbox, opened
      afresh, asked for no preview, its rows drawn at once, so its lines
      were not coming as the search began; the hit below its first page,
      scrolled to after Cancel, was asked for and drawn. In 8b 18 of
      Drafts' first page answered with two bytes, and neither Refresh
      asked for any. Nothing was written to the mailbox. Not shown: an
      answer landing after its list was replaced, which 5 and 7b ask to
      write down. Left: that, in either step.*
- [x] **B-136, the kept copy's free-space reading.** On the test iPad
      (16.5.1), the test account only, from a build of the `bm-searchprev`
      worktree (branch `fix-searchprev`). Eight letters of about 3 MB, a
      photo in each, made on the host and APPENDed by it, read (\Seen),
      into a label of their own, "B-136", none in the Inbox, dated three
      days back, subjects "B-136 1" to "B-136 8"; nothing is composed or
      sent. Three panes; the app's log read after each step, its
      `KEPT-LETTER` notes written down.
      1. *The free space.* Settings > General > iPad Storage: the space
      free written down. Steps 3, 4 and 6 need more than 2 GB: with less,
      every keep reads the free space by design (the 512 MB floor, a
      gigabyte to spare above it, and the letters), so every kept note
      has `free-ms`, as it should, and those steps' "none" is not to be
      looked for.
      2. *A launch's first keep.* The app ended in the app switcher and
      launched, the label opened, letter 1 opened: one `KEPT-LETTER kept
      bytes=… ms=… free-ms=…` note. Its ms and free-ms written down.
      3. *Held.* Within a minute, letters 2, 3 and 4, one after another:
      their kept notes have no `free-ms`, and their ms is about 1's less
      its free-ms. Letter 4 opened while the list beside it is dragged up
      and down in a screen recording: no stop in it longer than B-111's.
      4. *Five minutes on.* Six minutes with the app in front, the list
      dragged a little every minute or so, so the iPad does not lock and
      the app stays in front, then letter 5: its note has `free-ms` again;
      letter 6 at once after it: none. The log still has letters 1 to 4's
      notes above letter 5's: the log is the launch's own, so a relaunch
      between would have emptied it, and 5's `free-ms` would say nothing
      of the five minutes.
      5. *Opened again.* Letters 1 and 2: `KEPT-LETTER shown`, no kept
      note, as B-111.
      6. *A relaunch.* The app ended and launched, letter 7: `free-ms`
      again; letter 8 at once after it: none.
      7. *Put back:* the host takes the label and its eight letters away;
      nothing was sent.
      *Seen on the test iPad 2026-10-25 on int16 (662d63d), about 39 GB
      free: 1 to 7 passed. `free-ms` was 57 at a launch's first keep, 44
      at the first keep after six minutes and 58 after a relaunch, and
      none at the keeps between, which took 22 to 32 ms where the first
      took 87 (B-136). In 4 letter 6 had the first keep, 5's being let
      go as 6 was opened before 5's body came; 5 opened again had none.
      3's drag was frames 0.13 s apart, as B-111's, every one moving.
      The app was ended by a kill, not in the app switcher. The letters
      were in the label Notes, put in the Trash by the host.*

- [ ] **B-137, the warning before the app stops opening.** On the test
      iPad, the test account, from a build with the change. Nothing is
      sent and nothing is written to the mailbox: the one composer ends
      with Cancel, then Delete Draft. The iPad's clock is set by hand
      (Settings > General > Date & Time, Set Automatically off) and put
      back at the end. With the clock in 2027 Gmail's certificate may not
      be taken, so "Can't connect to mail server." may come at a launch
      and later: OK it each time and go on. "Kill and launch" is the app
      swiped away in the app switcher, then its icon. The connection log
      (five taps on the line under the list) keeps its last 500 lines, so
      it is read within a minute of a launch. Three panes unless a step
      says two. Screenshots of each alert. The app is installed by
      TrollStore's helper from the IPA of `tools/build-share-ipa.sh`
      (`trollstorehelper install installd force <ipa>`, the IPA path
      last), as for the round, and steps 2 and 11 need the gate for a
      write into the app's bundle container.
      The day last said is kept in the app's prefs,
      `blackmail.expiryWarningShown`, and a day there hides the warning
      on that day alone. The round of 2026-10-25 left it at 1 September
      2027, 16:02 UTC, which no step uses: it can stay. Before step 1
      the prefs plist (`Library/Preferences/wtf.uhoh.blackmail.plist` in
      the app's data container) is read over SSH. If the key holds a day
      a step uses, 18 to 24 August, 2 September or 18 September 2027, as
      a run of this check stopped part way, a step 1 or 3 that failed or
      a whole run (10's) leaves, it is taken out, a write into the data
      container behind its own gate: the app swiped away, the plist
      copied to the host, the key taken out there, copied back with its
      owner and mode, `killall cfprefsd` so its copy of the old one is
      dropped, and read again, the key gone. Step 1 is judged by its log
      line first, which no day in the prefs changes.
      1. *TrollStore:* the clock automatic; kill and launch: no warning,
      and the log's "EXPIRY none, TrollStore", no "EXPIRY entitlements
      unread" above it. The clock to 2 September 2027, 9:00 AM; kill and
      launch: no warning for a minute, the same log line.
      2. *A certificate's signature:* the same commit's build copied over
      TrollStore's, with `BLACKMAIL_SHARE_EXT=1
      TMPDIR=/mnt/temporary/<the run's folder> flock <the round's
      swift.lock> tools/deploy-to-ipad.sh --no-launch` from the repo's
      root, the folder made first (without `TMPDIR` the script's `mktemp
      -d` lands in the host's `/tmp`, and without the lock its `swift
      build` would not wait for the round's other builds), which signs it
      with `tools/sign-ipa.sh`, the profile and none of TrollStore's
      entitlements, copies it into the installed bundle and reads its
      md5 back (gated, a write into the bundle
      container; such a copy over TrollStore's install opened on its own
      mailbox on 2026-09-30, B-036). The clock automatic; kill
      and launch: the Inbox as before, no warning, the log's "EXPIRY
      stops 2027-09-18 10:22:36 +0000", or the instant of the profile the
      build was signed with, written down, and no "EXPIRY entitlements
      unread".
      3. *The day before the thirty:* the clock to 18 August 2027, 11:00
      PM; kill and launch: no warning for a minute.
      4. *The first day:* the clock to 19 August 2027, 9:00 AM; kill and
      launch: once the list is up, or within half a minute of the
      connection alert's OK if it came, an alert with no title, "This app
      will stop opening on September 18, 2027. After that, use Mail.",
      and OK alone. OK: the list and the pane as they were. The log:
      "EXPIRY-WARNING shown".
      5. *Once a day:* kill and launch: no warning for two minutes. Home,
      a minute away, back: none.
      6. *Not over a letter:* Compose, a word typed in the body. Home; the
      clock to 20 August 2027, 9:00 AM; back in Blackmail: the composer
      as it was left, and no alert over it for a minute. Cancel, Delete
      Draft: the warning within about half a minute. OK.
      7. *Two panes:* the view button to two panes; the clock to 21 August
      2027, 9:00 AM; kill and launch: the warning as in 4. OK; back to
      three panes.
      8. *Not under a finger:* the Inbox in front. Home; the clock to 22
      August 2027, 9:00 AM; back in Blackmail, and at once a finger on
      the list, pulled down past the spinner and held still for a full
      minute, two checks of the watch: no warning while it is held. Let
      go: the list springs back; a "Can't connect to mail server." that
      comes as the finger lifts is OKed. Within about half a minute of the
      list at rest, and of that OK, the warning, and the list not left
      pulled down. OK: the list at its top, no spinner turning.
      9. *Up across midnight:* Home; the clock to 23 August 2027, 11:55
      PM; back: the Inbox at its top, and at once Sent Mail tapped among
      the folders. The warning within about half a minute, over Sent
      Mail, before midnight. Left up, Home with it on the screen. The
      clock to 24 August 2027, 9:00 AM; back: the same warning, still up,
      and under it the Inbox in place of Sent Mail, at its top (B-003;
      before 2026-10-25 it stayed on Sent Mail). OK: the Inbox, and no
      warning again for two minutes.
      10. *The last morning:* the clock to 18 September 2027, an hour or
      more before the instant written down in 2, in the iPad's zone: for
      10:22:36 UTC, 5:00 AM in New York or 2:00 AM in Los Angeles, both on
      summer time then; the time set written down. Kill and launch: the
      warning, "September 18, 2027". OK. The clock is not taken past the
      instant: any app on the test iPad signed with that profile and not
      installed by TrollStore, Blackmail itself since 2, would stop
      opening while it was there, and the host tests hold that nothing is
      said after it.
      11. *Put back:* Set Automatically on; the IPA installed again by
      TrollStore's helper as before the check (gated, as 2); kill and
      launch: no warning, the log's "EXPIRY none, TrollStore";
      TrollStore lists Blackmail as before. The prefs keep the day of
      10's warning, 18 September 2027, which under TrollStore says
      nothing; a later run takes it out before its step 1, as above.
      *Seen on the test iPad 2026-10-26 on int17 (92f2cb9), installed by
      TrollStore's helper: 1 passed. The prefs held 1 September 2027, so
      nothing was taken out. The clock automatic: no warning for 30 s, the
      log's "EXPIRY none, TrollStore", no "EXPIRY entitlements unread".
      Set Automatically off brought back Los Angeles, the zone last set by
      hand; the clock set from the host over SSH went back to 2026 within
      a minute, twice, so 2 September 2027 was set with Settings' date
      picker, 9:31 AM. Kill and launch: "Can't connect to mail server.",
      OKed, no warning at 30 s or at 65 s, and "EXPIRY none, TrollStore",
      the one line of that launch's log kept. Set Automatically on at
      once; the day in the prefs unchanged (B-137). 2 to 11 gated, not
      run: 2 copies the build signed by the certificate over TrollStore's,
      a write into the bundle container the owner has not cleared, and 3
      to 10 need it, the app saying nothing in the thirty days under
      TrollStore; 11's reinstall is a write of the same kind, needless
      with the bundle untouched, and its other parts held: the clock
      automatic since 1, every launch "EXPIRY none, TrollStore". Nothing
      was sent. Left: 2 to 11, behind that gate.*
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a), with the
      owner's yes to writes into the app's containers: 1 to 7 and 9 to 11
      passed; 8 not done (B-137). Another try that day, just before,
      stopped at its start. The prefs held 1 September 2027 and stayed.
      Every clock was set with Settings' date picker, in Los Angeles;
      every kill and launch was from the host, not the app switcher and
      the icon. 1 as before, "EXPIRY none, TrollStore", on 2 September at
      9:12 AM too. 2 by a script of the round's copying the same commit's
      IPA, signed by the certificate, over TrollStore's install, no build:
      the Inbox, no warning, "EXPIRY stops 2027-09-18 10:22:36 +0000". 3,
      at 11:18 PM: none. 4: the warning 33 s after the launch, 14 s after
      the connection alert's OK, with no title, the words as written, OK
      alone; OK, the list and the pane as they were. 5: none. 6: the
      composer as left, no alert over it; the warning 21 s after Delete
      Draft. 7: over two panes. 9: over Sent Mail at 11:53 PM; on the 24th
      still up, over the Inbox at its top (B-003), the return's "Can't
      connect" after its OK, then none for two minutes. 10: at 1:02 AM in
      Los Angeles, 2 h 20 min before the instant, the warning with
      "September 18, 2027"; the clock on the 18th about two minutes. 11:
      TrollStore's install again, "EXPIRY none, TrollStore", TrollStore
      listing Blackmail as before, the share extension starting (B-036);
      the prefs keep 18 September 2027. 8 not done: on the 22nd "Can't
      connect to mail server." was up within 10 s of the return, before
      the slow pull standing in for a still hold, which injected touches
      cannot make, could take the list, and still up at a second pull, as
      an OK tapped after the first was stopped did not take; the warning
      came 29 s after its OK, the list at rest at its top. Once a day
      tapped took a time left on the picker's Time button from wheels left
      open, caught and set right before the app was opened. iOS moved its
      Wi-Fi private address's rotation date into 2027, left so. Nothing
      was sent. Left: 8, with a person at the iPad.*

- [ ] **B-138, provision-ipad.sh's TrollStore range.** On the laptop or
      the Mac, with the whole repo and the test iPad on the cable,
      unlocked and trusting it. Read only: nothing is registered, signed
      or installed, and nothing is sent. The script is not run without
      `--check`: past the iOS line it goes on to sign and install.
      1. `tools/provision-ipad.sh --check`: among the pre-flight's lines,
      "✓ trollstore-range.sh". Any ✗ line is the visit's own, written
      down, not mended here.
      2. `ideviceinfo -k ProductVersion` and `ideviceinfo -k BuildVersion`,
      both written down; then, from the repo's root, `.
      tools/trollstore-range.sh; trollstore_range "$(ideviceinfo -k
      ProductVersion)" "$(ideviceinfo -k BuildVersion)"`: "in" for the
      test iPad's 16.5.1. Then `ios_below "$(ideviceinfo -k
      ProductVersion)" 16.0; echo $?`: 1, not older than the app needs.
      *Seen 2026-10-25 at int16 (662d63d): 2 passed on the laptop, the
      test iPad on its cable: 16.5.1 (20F75), "in" with exit 0, and
      `ios_below` 1 (B-138). 1 ran on the host, where the whole repo is:
      "✓ trollstore-range.sh" among the pre-flight's lines; its ✗ lines,
      no ideviceinstaller and no IPA, are the host's, and the pre-flight
      failed there, exit 1. Nothing was registered, signed or installed.
      Left: 1 on the laptop or the Mac taken on the visit, with the
      whole repo, its ✗ lines the visit's own.*

- [x] **B-140, a Reply to a letter that fills its 2 MB.** On the test
      iPad, the test account, from a build with the change. Nothing is
      sent and nothing is saved: each composer has "x" typed in it, then
      Cancel, then Delete Draft. The letters are the host's, APPENDed read
      (`\Seen`) to the label "Notes" (made by the host if the account has
      none, and then deleted at the end), dated two days back, each with a
      new Message-ID of its own; the host notes each APPEND's UID from its
      APPENDUID, and stops if one has none. Three panes; the connection log
      read after each step; frames or a screen recording for the times.
      0. *The letters:* (a) "B-140 long", HTML alone, 28,000 paragraphs,
      each `<p>Paragraph 00001 of the long letter, words and more words to
      fill it.</p>` and a line break, numbered from 00001, about 2.1 MB, so
      the pane fetches its first 2 MiB; (b) "B-140 long plain", text/plain
      alone, 9,000 such lines numbered from 00001, about 620 KB, fetched
      whole; (c) "B-140 short", a small HTML letter of three paragraphs
      with a link and a bold word; (d) "B-140 short lines", text/plain
      alone, 30,000 lines, each a number of five figures from 00001, about
      180 KB; (e) "B-140 links", an HTML letter of two links,
      "Write the lines", `mailto:nobody@example.com?subject=B-140%20lines&body=`
      and the numbers 1 to 6000 joined by `%0D%0A`, and "Write the long
      one", `mailto:nobody@example.com?subject=B-140%20long&body=` and
      2,000 lines "Line 0001 of the long link, written to fill the
      composer to its bound and a little more.", numbered from 0001, their
      spaces `%20`, joined by `%0D%0A`, some 260 KB of address.
      1. *Shown in part:* "Notes", then (a): the grey "Only the beginning of
      this message is shown." above its paragraphs, and the app answering
      touches.
      2. *Reply:* Reply, then Reply in its sheet. The sheet up within two
      seconds of the tap, the time written down, the caret above the
      signature, the keyboard up with it; the sheet scrolls under a finger.
      Before 2026-10-25 the sheet never came and the app took no touch.
      Flick the sheet to its end: the last three lines "> Paragraph 00885
      of the long letter, words and more words to fill it.", "> " and "> Only
      the beginning of this message is shown.", the line nowhere else. If
      the number is not 00885, write it down. Type "x" at the top; Cancel,
      Delete Draft.
      3. *Reply All and Forward:* Reply All the same, the same end; Cancel
      as in 2. Then Forward: the sheet in To, up within two seconds; at the
      end "Paragraph 00936 of the long letter, …", a blank line, and "Only
      the beginning of this message is shown.", no "> ". "x" typed in the
      body, Cancel, Delete Draft.
      4. *A plain letter:* (b), Reply: the sheet up within two seconds, the
      quote ending with the whole line "> Paragraph 00923 of the long
      letter, words and more words to fill it.", then "> " and "> Only the
      beginning of this message is shown."; another number written down.
      Cancel as in 2.
      5. *Ordinary mail:* (c), Reply: its three paragraphs quoted whole, no
      "Only the beginning" line. Cancel as in 2.
      6. *Short lines:* (d), Reply: the sheet up within two seconds of the
      tap, the time written down; it scrolls under a finger. At its end
      "> 02000", "> " and "> Only the beginning of this message is shown.",
      the 2,000 lines a quote keeps however short. Cancel as in 2. Forward
      the same, up within two seconds: "02000", a blank line and the line,
      no "> ". Cancel as in 2.
      7. *The composer's own bounds:* (e), tap "Write the lines": the
      composer up within two seconds, To nobody@example.com, Subject
      "B-140 lines", the time written down; at the end of the body "3997",
      "3998", a blank line and "Only the beginning of this message is
      shown.", no signature under it: 4,000 lines. Cancel as in 2. Then
      "Write the long one": up within two seconds, its body ending "Line
      1472 of the long link, …", a blank line and the line: 128 KiB. Cancel
      as in 2. If either tap opens nothing, write it down: the address may
      be longer than WebKit hands over.
      8. *Nothing saved:* Drafts opened: no draft from these steps; the
      log shows no APPEND.
      9. *Put back:* the host moves the five UIDs it noted, and only them,
      from "Notes" to the Trash (`UID MOVE`), deletes in the Trash only the
      UIDs that move answered (`COPYUID`), and deletes "Notes" only if it
      made it. Never anything found by subject, Message-ID or label.
      Nothing else was written.
      *Seen on the test iPad 2026-10-26 on int17 (92f2cb9): 0 to 9 passed,
      each sheet up 1.43 to 1.9 s after its tap, the quotes and bodies
      ending as written, at 00885, 00936, 00923, "02000", "3998" and "Line
      1472" (B-140). (a) as written, 2,128,353 bytes, is under the 5 MiB
      above which a letter is opened in parts, so the pane fetched it
      whole, with no grey line, and its Reply ended at 00885 all the same;
      1 to 3 ran on (a2), its paragraphs on to 72,000, 5,472,365 bytes,
      added for them. Only the top and the end of each quote were read.
      The host put the six letters in the Trash by a STORE of its label,
      the round's rules allowing no MOVE or EXPUNGE. Nothing was sent or
      saved.*

- [ ] **B-141, the last file tapped opens.** On the test iPad, the
      test account, from a build with the change. Nothing is sent,
      composed or saved. The letters are the host's, APPENDed read
      (`\Seen`) to the label "Notes" (made by the host if the account has
      none, and then deleted at the end), each with a new Message-ID of its
      own; the host notes each APPEND's UID from its APPENDUID, and stops if
      one has none. Organize by Thread on; three panes; the connection log
      read after each step; Quick Look's Done closes each preview.
      0. *The letters:* a conversation of two, dated two days back. (A)
      "B-141 files", with two files: a PDF of about 14.7 MB, many pages,
      made by the host, sent among the letter's words as Mail on an iPad
      sends one (an HTML part, the PDF, an HTML part), so its row is among
      A's words (B-113) as well as in the header, and "note.txt" of a few
      hundred bytes, so the letter is over 5 MiB and opened in parts. On a
      build with B-148 the PDF has no row in the header: its one row is
      the one among A's words, which shows it coming, dimmed with
      "Loading…" after its name, where the header's row had its spinner.
      There, in 1 to 4, "the large PDF's row" is that row among A's words
      and "its spinner" its "Loading…", and in 1 A's header has one row,
      note.txt's. (B)
      "Re: B-141 files", an hour later, its In-Reply-To and References
      naming A, with a PDF of about 100 KB.
      1. *The round's race:* "Notes", the conversation's row: B open, the
      header on B. Tap B's line: it closes, the header stays. Tap A's line:
      A opens, the header on A, its two rows grey, then blue. Tap the large
      PDF's row: its spinner. Within two seconds tap B's line: B opens, its
      body already in the stack, the header on B with its file's row blue
      (B-129). Tap that row at once: its spinner. Wait for the log's
      FETCHes for both files to end: A's PDF never opens; B's opens in
      Quick Look over B's header, its spinner gone. Before 2026-10-25 A's
      opened and B's was let go. Done.
      2. *Tapped past, nothing more:* tap B's line: it closes. Tap A's line
      twice, closed and open again: the header on A. Tap the large PDF:
      its spinner. Within two seconds tap B's line: B opens, the header on
      B. Tap nothing else. When the log's FETCH for the PDF has ended:
      nothing opens and nothing is said, for a minute. Then tap B's line,
      then A's twice, the header on A, and the large PDF again: fetched
      again (B-097), it opens. Done.
      3. *Two files of one letter:* the header on A. Tap the large PDF's
      row, then at once "note.txt"'s: both spinners. The large PDF's FETCH
      first, then note.txt's: the large PDF never opens; note.txt opens as
      its FETCH ends. Before 2026-10-25 the PDF opened and note.txt was let
      go. Done.
      4. *The header's own line:* the header on A. Tap the large PDF: its
      spinner. Within two seconds tap A's line: it closes, the header stays
      on A; tap it again: A opens, the header on A. Tap nothing else. When
      the log's FETCH for the PDF ends, it opens in Quick Look. As first
      built, it was let go. Done.
      5. *One file tapped twice:* the header on A. Scroll to the large PDF's
      row among A's words, which has no spinner, and tap it; two seconds
      later tap it again, and a third time. The header's row has its
      spinner throughout; on a build with B-148, which has no such row,
      the row among A's words has its "Loading…" throughout. The log has
      the PDF's part fetched once, and Quick Look comes as that fetch
      ends, once. As first built, each tap
      fetched it again and Quick Look came after the last. Done. Tap it again: it opens
      again. Done.
      6. *Put back:* the host moves the two UIDs it noted, and only them,
      from "Notes" to the Trash (`UID MOVE`), deletes in the Trash only the
      UIDs that move answered (`COPYUID`), and deletes "Notes" only if it
      made it. Never anything found by subject, Message-ID or label.
      Nothing else was written.
      *Seen on the test iPad 2026-10-26 on int17 (92f2cb9): 2 to 6 passed,
      and 1 as far as it went. In 1 B's letter was kept whole on the iPad,
      so its file opened in Quick Look at once, with no FETCH, while A's
      PDF was still coming, and A's, 21.7 MB on the wire, in 5.7 s, never
      opened (B-141). With Quick Look up as A's landed, the code before
      B-141 would have let A's go as well, so 1 did not tell the fix; 2, 3
      and 5 did: nothing opened over B for a minute, note.txt opened and
      not the PDF, and three taps made one FETCH and one Quick Look. In 4
      the PDF opened, the header on A throughout. A was 21.4 MB with a PDF
      of 15.8 MB (16.3 MB on its row), B's PDF 127 KB and its subject
      without "Re:". The host put the two letters in the Trash by a STORE
      of its label. Nothing was sent. Not shown: 1's race, B's file
      fetched behind A's. Left: that, with a B over 5 MiB, which the app
      does not keep.*
- [ ] **B-139, the dates on screen after the clock's form changes.** On
      the test iPad, the test account only, from a build of the
      `bm-dateredraw` worktree (branch `fix-dateredraw`) or of the int it
      is merged into. Nothing is composed, sent, saved, moved or deleted
      in the app: one of the test accounts is signed in on the owner's
      phone and new mail rings it. A setting a step changes is put back in
      the same step, at once. The host makes twenty-three letters, each
      from another address, with a new Message-ID of its own and naming
      none on the account, and APPENDs them, read (`\Seen`), to the label
      "Notes", never the Inbox, each with its Date as its internal date;
      it notes each UID from its APPENDUID, and stops if one has none.
      (a) "B-139 one", dated an hour before the run; (b) "B-139 stack",
      three days back, and (c) "Re: B-139 stack", forty minutes before the
      run, its In-Reply-To and References naming (b)'s Message-ID, so the
      two are one conversation; (d) twenty more, "B-139 row 1" to "B-139
      row 20", each on its own, dated a minute apart from seventy minutes
      before the run back, so rows of today run on past the bottom of the
      list (a run started after 2 AM). Organize by Thread on, three panes
      unless a step says two; the app's connection log read after each
      step. Settings > General > Date & Time as found written down first:
      24-Hour Time, Set Automatically, the time zone.
      1. *Before:* "Notes" opened, (a) tapped: its row's date and the
      header's "Today at" give its time with AM or PM, as the status bar's
      clock does. A shot.
      2. *24-Hour Time:* Settings, 24-Hour Time on; back to Blackmail by
      the app switcher, nothing in it touched: in the first look, with no
      scroll and no tap, (a)'s row and the header give its time without
      AM or PM, "Today at 13:39" and the like, as the status bar does,
      and so does every row of today in sight, and the line under the
      list if it gives a time ("Updated at"). (a)'s row still highlighted,
      the list and the letter where they were; no FETCH and no SELECT in
      the log from the step. A shot. Then the list scrolled down slowly,
      by two or three rows: each row of (d) coming in at the bottom gives
      its time without AM or PM, the first one too (the table may have
      made it before the switch); a shot; the list back to the top.
      Settings, 24-Hour Time off at once; back: AM and PM again, nothing
      touched.
      3. *The time zone:* Settings, Set Automatically off, the time zone
      Los Angeles; back, nothing touched: (a)'s row, the header and the
      status bar give the time three hours earlier for an Eastern zone,
      the difference written down for another. A shot. Settings, Set
      Automatically and the zone as found, at once; back: the times of 1,
      nothing touched.
      4. *A conversation:* "B-139 stack" opened from the list: (c)'s line
      and the header give its time, (b)'s line its weekday. Settings,
      24-Hour Time on; back, nothing touched: (c)'s line and the header
      without AM or PM, (b)'s weekday as it was; no letter opened or
      closed, the stack where it was, no FETCH in the log. Settings,
      24-Hour Time off at once; back: as before, nothing touched.
      5. *Edit mode:* two panes, Edit, (a)'s row and one other ticked.
      Settings, 24-Hour Time on; back: the two ticks still there, the
      list where it was, the rows of today without AM or PM. Settings,
      24-Hour Time off at once; back, Done, three panes again.
      6. *Midnight,* if the round runs across it, or with the owner's yes
      to set the clock. The iPad awake (Auto-Lock Never for the step, put
      back after it), Blackmail in front. By the clock: Settings, Set
      Automatically off, the time set to 11:55 PM, back to Blackmail. The
      clock moved on by more than fifteen minutes is a long time away to
      the app, so it comes back to the Inbox (B-003: "Notes" is not the
      Inbox), with the Inbox's FETCH in the log: written down, not a
      failure. Either way, before 12:00 AM: "Notes" opened, at the top,
      and "B-139 stack" tapped, (a)'s row in sight; then nothing touched
      across 12:00 AM. Once midnight has passed, with nothing touched:
      (a)'s row and the stack's read "Yesterday", the header "Yesterday
      at" and (c)'s time, (c)'s line "Yesterday", (b)'s line its weekday
      as before; no letter opened or closed, the list and the stack where
      they were. A shot. Then the list scrolled down slowly, by two or
      three rows: each row of (d) coming in at the bottom reads
      "Yesterday", the first one too. By the clock only: Settings, Set
      Automatically as found, at once; back, with no return to the Inbox
      (the clock put back is no time away): "Today" and the times again
      where the day is today again, nothing touched.
      7. *Put back:* Date & Time as written down first, Auto-Lock as
      found. The host moves the twenty-three UIDs it noted, and only
      them, from "Notes" to the Trash (`UID MOVE`), and deletes in the
      Trash only the UIDs that move answered (`COPYUID`); "Notes" itself
      stays. Never anything found by subject or Message-ID: a UID not
      noted is left, and written down. Nothing else was written.
      *Seen on the test iPad 2026-10-26 on int17 (92f2cb9): 1 to 5 and 7
      passed; 6 not possible, the round running from about 9 to 10:40 PM,
      not across midnight, with no yes from the owner to set the clock.
      With 24-Hour Time on, in the first look, (a)'s row "20:39" and the
      header "Today at 20:39", every row of today in sight the same, (a)'s
      row still highlighted, no FETCH or SELECT; the rows of (d) scrolled
      in, the first too, without AM or PM. In Los Angeles three hours
      earlier, "Today at 5:39 PM". The stack's line and header "20:59",
      (b)'s "Thursday", nothing opened or closed; Edit's two ticks kept
      (B-139). The line under the list gave minutes, no time. Back to
      Blackmail by opening it from the host, not the app switcher. The
      letters were made twice, the first set out of order, the list going
      by UID, and both sets put in the Trash by a STORE of its label, the
      round's rules allowing no MOVE or EXPUNGE, nothing deleted there;
      (c)'s subject had no "Re:". Nothing was sent. Left: 6, across
      midnight or with the owner's yes.*
- [x] **B-142, a video coming into the composer as he locks the iPad or
      leaves the app, and Photo Library as Photos keeps it.** On the test
      iPad, the test account only, from a build of the `bm-videopick2`
      worktree (branch `fix-videopick2`) or of the int it is merged into.
      Nothing is sent: no recipient is typed in any step, so Send cannot
      go. Nothing is left on the account: step 7, optional, saves one draft
      there and deletes it in the same step. Every composer ends with
      Cancel, and Delete Draft if it asks (a letter left as it opened
      closes with nothing asked). The large videos are the test iPad's own
      in Photos, HEVC, over 25 MB. Two short HEVC clips: "the clip", for
      steps 4 to 7, of 5 to 12 MB, and "the measure", for step 4's second
      half, of 15 to 22 MB: the test iPad's own if it has them, else filmed
      with its Camera before step 4, a few seconds and some twenty, their
      sizes read from their `SHARE-FILE` lines (`bytes=M`) and filmed again
      if outside, and deleted, from Recently Deleted too, in step 12.
      Before the first step, over IMAP, the counts of Drafts and Sent Mail;
      the app's Local Drafts empty. A read-only syslog capture runs
      throughout; the app's log is read after each step. Write down any
      termination with 0x2182BAAD, with the step it fell in, and every
      "File Coordination Claim" on Blackmail with how long it was held.
      1. *Locked, a large video* (the round's case): a new letter, Photo
      Library, Videos, a large video, Add, and the lock within a second. In
      the syslog the claim, if one is taken, let go within a second or two
      of Add, "finished providing" without minutes of copying; no
      "Assertion warning event" near 26 s and no 0x2182BAAD near 31 s. In
      the log, either of two, both right: the read ended before the lock,
      `SHARE-FILE read=com.apple.quicktime-movie ... went=left out, more
      than the letter's room` within seconds of Add; or the lock first,
      `COMPOSE-ITEM set aside as the app went, called off` and `SHARE-FILE
      ... went=called off`, and on the wake the read again and then
      `went=left out, more than the letter's room`. Write down which. No
      `SHARE-VIDEO` line either way. Wake after three and a half minutes,
      nothing touched: Blackmail in front, the composer up, "The video could
      not be attached." up or said on the wake. A shot of the composer on
      the wake. Cancel. Before the third commit the app was ended 31 s after
      the lock, the wake showing the Home Screen (2026-10-25 and
      2026-10-26).
      2. *Another app:* as 1, another large video, Safari opened from the
      Dock in place of the lock, three and a half minutes there, then back
      to Blackmail by the app switcher. The same.
      3. *Several:* a new letter, two large videos and one HEIC photo, Add,
      the lock at once. Wake after three and a half minutes: no
      0x2182BAAD, the photo's row in, and one alert, "2 videos could not
      be attached.". Cancel, Delete Draft.
      4. *A clip that fits,* in front: a new letter, the clip, Add, and
      wait. In the log `SHARE-FILE ... went=staged`, then `SHARE-VIDEO made
      H.264, bytes=N from=M codec=avc1`, the time between them written
      down; the row "IMG_####.mov" with the weight of N. The codec is read
      back from the copy by the app (`codec=avc1` or `avc3` is H.264; any
      other, or `unread`, is a failure to write down). Over SSH, `stat` of
      the staged file in the app's `tmp/Attachments`: N bytes. No media
      tool is run on it anywhere: the app's line is the reading. Should the
      line say `its H.264 copy ... a 720p copy` for the clip, write down
      both lines; the clip was too large, film a shorter one. Cancel,
      Delete Draft; `tmp/Attachments` holds nothing of it. Then *the
      measure*, the same way, in a new letter: write down M, and every
      `SHARE-VIDEO` line with its N, and N over M for each copy. Expected
      one of: `made H.264` at its own size; `its H.264 copy bytes=N, more
      than the letter's room ...: a 720p copy` and then `made H.264 at
      720p`; or that and `its 720p H.264 copy ... left out` with "The video
      could not be attached.". A copy `cut short at its limit` was stopped
      5 MB past the room: its N over M is then more than written. It is how
      often his videos now go at 720p or not at all. Cancel, Delete Draft;
      `tmp/Attachments` holds nothing of either.
      5. *The clip, locked while it is made:* as 4, the lock within a
      second of Add. In the log `COMPOSE-ITEM set aside as the app went,
      called off`, then `SHARE-VIDEO called off` (or `SHARE-FILE ...
      went=called off` if the read had not ended); no claim held past the
      lock, no 0x2182BAAD. Should `made H.264` come before the lock, write
      it down and redo the step with a longer clip. Wake after three and a
      half minutes: the row turning again, then `SHARE-VIDEO made H.264`
      and its row. Cancel, Delete Draft.
      6. *The clip, the letter closed while it is made:* as 4; while its
      row turns, Cancel, Delete Draft. In the log `COMPOSE-ITEM called off,
      the letter closed` and `SHARE-VIDEO called off`; `tmp/Attachments`
      holds nothing of it.
      7. *Save Draft waiting, the 20 seconds,* optional: it saves one draft
      to the test account, which every other step avoids. A new letter,
      "B-142 save" typed as the subject and nothing else, the clip, and
      while its row turns, Cancel, Save Draft: the sheet goes. Lock within a
      second. In the log `COMPOSE-ITEM let run 20 s as the app went, a Send
      or Save Draft waiting`, then one of: `SHARE-VIDEO not made H.264,
      stopped as the app went` and `COMPOSE-ITEM set aside, its conversion
      stopped as the app went`; `COMPOSE-ITEM set aside 20 s after the app
      went, called off`; `COMPOSE-ITEM its conversion stopped in front,
      read again` and then `set aside as the app went, called off`; or
      `SHARE-VIDEO made H.264` inside the 20 s. Write down which, and when:
      it is how AVAssetExportSession behaves as the app goes on this iPad.
      In the syslog, where the row is set aside, the "Save Draft"
      background time let go then, not held to its expiry; where it was
      made inside the 20 s, the time held while the draft's APPEND runs, up
      to the allowance, about 26 s from the app's going, and let go then,
      the draft kept either way (a large draft's APPEND may outlast it:
      B-142, Not covered); no 0x2182BAAD. Wake after three and a half
      minutes.
      Where it was made inside the 20 s: the draft was kept while the iPad
      was locked, nothing read again on the wake. Otherwise: the clip read
      and made again on the wake, then the draft kept. Either way, the
      draft in Drafts with the copy. Over IMAP, Drafts one more than
      counted. Open the draft from Drafts in the app, Cancel, Delete Draft;
      over IMAP, Drafts as counted.
      8. *Photos:* a new letter, one HEIC photo from the iPad's camera,
      and one panorama taken with its Camera's Pano before this step
      (deleted in step 12), over 4096 px on its long side; Add. Each
      `SHARE-PICTURE` line: `offered=public.heic read=public.heic ...
      way=JPEG at factor 1, N MB available size=WxH`, or, should Photos
      still offer a JPEG beside it, `read=public.jpeg ... way=own bytes`:
      write down which. For the panorama, `size=` its own width and height,
      as Photos shows them, not 4096 or less: the third commit sent it at a
      half or a quarter. Should its line say `factor 2` or more, write down
      the memory it gives. Each row "IMG_####.jpg" with its weight. Cancel,
      Delete Draft.
      9. *Attach File, optional:* only if a file of over about 1 GB, or one
      kept only in iCloud, is in Files already. A new letter, Attach File,
      that file, Open, and the lock within a second. Write down whether a
      claim is held on Blackmail, for how long, and any 0x2182BAAD.
      Nothing is changed for this (B-142, Not covered).
      10. *An original kept only in iCloud, optional:* only if Photos on
      the test iPad has a video kept only in iCloud (it had none so far).
      As 1: write down how long the claim is held while it downloads, and
      whether the app is ended. Nothing can be changed for this without the
      photo library's permission (B-142, Not covered).
      11. *The share sheet,* written down, nothing in it changed: Photos, a
      large video not used yet, Share, Blackmail. The sheet's spinner while
      it reads the video; lock within a second; wake after one minute: is
      the sheet still up, and does the syslog have a claim on the extension
      and a termination with 0x2182BAAD? Cancel if it is up.
      12. *Put back:* Drafts and Sent Mail as counted first; Local Drafts
      empty; the clips filmed for steps 4 to 7 and the panorama of step 8,
      if they were, deleted from Photos and from Recently Deleted; Photos
      otherwise as found; Blackmail in front on the Inbox; Auto-Lock as
      found. Nothing was sent, and
      nothing is left on the account.
      *Run on the test iPad 2026-10-26 (round r6-s8-fixes, int17 56bbf61,
      the first two commits), as the check then stood: its steps 1, 2, 4
      and 7 failed in a second run, each with a video never picked before.
      The read was called off as the app went, at the count-out and as the
      letter closed, and the claim was held until Photos' compatible copy
      was made; the app was ended 31 s after it left the front, the letter
      with it. An H.264 video held its claim 0.1 s. Fixed again by the third
      commit, `.current` and the H.264 copy made in the app, and the fourth,
      a HEIC at its own size, the 720p copy or nothing, each copy stopped
      past the room and its codec read back; the check above is for the
      fourth commit's build.*
      *Seen on the test iPad 2026-10-26 on int17 (939ad5a, the third and
      fourth commits): 1 to 8, 11 and 12 passed; 9 and 10 not possible, no
      file of over about 1 GB in Files and no iCloud Drive on the iPad, and
      no video kept only in iCloud in its Photos, which is not in iCloud.
      Every claim on Blackmail was held 0.03 to 0.4 s and let go before the
      app went into the background, step 3's photo 0.05 s after, its read
      called off as the app went; no 0x2182BAAD, and the app was never
      ended. The large videos were left out 0.25 to 0.43 s after Add; the
      clips made H.264 (`codec=avc1`) in 1 to 5 s. In 4 the clip's N over
      M 1.081; the measure's copy at its own size 1.387, over the room, and
      its 720p copy 1.224, which went, made in 5.2 s. So with 25 MB of
      room, at the measure's ratios, a 1080p HEVC clip of over about 18 MB
      goes at 720p, and one of over about 20.4 MB is left out. In 7 the
      720p copy was made 2.4 s after the app went, not stopped, and the
      draft was kept, reaching the server while the iPad was locked; but
      the "Save Draft" time was held to its expiry, about 26 s, by the
      draft's 34 MB APPEND, which ended 3.4 s after it, not let go as the
      step then said. Passed in its outcome; the step now says the time is
      held while the APPEND runs, up to the allowance. In 8 Photos still
      offered `public.jpeg` beside the HEIC under `.current`, and the JPEG
      went as its own bytes; no Pano could be taken, the iPad fixed in
      place, so the library's two panoramas, JPEG, were used, the one of
      6920 by 1650 going as its own bytes. In 11 Photos made its own copy,
      21.4 s, then opened the sheet while the iPad was locked, and iOS
      ended it 5 s later, with no claim on it. Also seen: a read's `done`
      run twice, harmless (B-142, Not covered); two empty staging folders
      left in `tmp/Attachments` by 5 and 6. In 2 Safari, and Blackmail
      again, were opened over SSH, not from the Dock and the app switcher;
      in 4 to 7 the iPad's own clips were used, none filmed, and 6 and 7
      were run with the measure in place of the clip, 6 because the clip's
      copy was made before Cancel could land. Nothing was sent; the draft
      of 7 was deleted in the step, Drafts and Sent Mail as counted.*
- [x] **B-143, a row comes into sight with its preview.** On the test
      iPad, the test account only, from a build of the `bm-prepcell`
      worktree (branch `fix-prepcell`) or of the int it is merged into.
      Nothing is composed, sent, saved, moved or deleted in the app, and
      no draft is tapped: one of the test accounts is signed in on the
      owner's phone and new mail rings it. The host makes the letters,
      each from another address, with a new Message-ID of its own and
      naming none on the account, and APPENDs them, read (`\Seen`), to
      the label "Notes", never the Inbox, each with its Date as its
      internal date; it notes each UID from its APPENDUID, and stops if
      one has none. Organize by Thread on, three panes; the app's
      connection log read after each step, a preview's FETCH being
      `UID FETCH … (UID BODY.PEEK[…]<0.n>)`; frames recorded through each
      try, about 0.14 s apart, as the round recorded them.
      1. *The round again.* Ten tries. For each, the host first APPENDs
      fourteen new letters, "B-143 rows try N letter M", M from 1 to 14,
      each from "TryN WriterM", letter 14 first and letter 1 last, so
      letter 1 has the folder's highest UID. The list goes by UID, the
      folder's order (`PageWindow`, `MessageThread.group`), so the
      fourteen are its top rows whatever the letters of the tries before
      are dated, and none has been drawn. The dates run with the UIDs:
      each letter dated a minute after the one APPENDed before it, a
      try's letter 14 a minute after the try before's letter 1, and the
      first try's letter 14 dated 160 minutes before that try, so the
      eleven tries' 154 letters (step 2 is the eleventh) never mix by
      date and none is dated after the run began. The empty label
      "Drafts" tapped, then "Notes"; the previews let land
      (one preview FETCH of the fourteen in the log, the time of its
      answer written down); then the list scrolled one row (77 view px,
      400 ms) at a time, six times, 0.6 s apart. Every row coming into
      sight at the bottom after the answer has its two lines in its
      first frame, and no row is blank in any frame after the answer.
      Any row that comes in blank written down, with its UID, the try,
      the time it came in and the time its preview was answered. On int17
      (92f2cb9) one try of ten had one, "Try6 Writer9", blank for at
      least 2.4 s until scrolled away and back (B-143, "Found").
      2. *Scrolled before the answer.* One try more, the host's fourteen
      letters as in 1 ("B-143 rows try 11 letter M"), the scroll begun at
      once after the tap on "Notes", before the FETCH answers: rows may
      come in grey while it is out; once it has answered, every row in
      sight and every row coming in after has its lines, none left grey.
      3. *Nothing lost.* After the last try, the list back at its top,
      the first row tapped: its letter in the pane, its row highlighted.
      The list scrolled down six rows and back: the row still
      highlighted and the letter still in the pane. Two panes, Edit, two
      rows ticked, scrolled down six rows and back: the two ticks still
      there; Done, three panes again.
      Nothing else is tapped: the letters are read, so opening one sends
      nothing.
      4. *Put back:* "Notes" left, the Inbox at its top. The host moves
      the UIDs it noted, and only them, from "Notes" to the Trash
      (`UID MOVE`), and deletes in the Trash only the UIDs that move
      answered (`COPYUID`); "Notes" itself stays. Never anything found by
      subject or Message-ID: a UID not noted is left, and written down.
      Nothing else was written.
      *Seen on the test iPad 2026-10-26 on int17 (56bbf61): 1 to 4 passed.
      In ten tries no row came into sight blank: each try's one preview
      FETCH named its fourteen UIDs, the rows were grey for 0.15 to 0.4 s,
      then all had their lines, and every row coming in at the bottom had
      them in its first wholly visible frame. In 2 the list had been
      moving 0.43 s when the previews came, and every row had its lines
      from then on. Two more, the list moving 0.196 and 0.114 s before the
      answer: none blank. On 92f2cb9 a second run had made the blank row 4
      times in 4 at 0.155 s or more and 0 in 7 at 0.068 s or less, so 2's
      try and the 0.196 s one were in that range, the 0.114 s one between
      the two. Two others did not count, the finger down before the new
      rows' envelopes had come, so that the list kept its earlier rows
      (B-143). Tries 11 to 15 reused tries 1 to 5's senders, and the first
      try's letter 14 was dated 220 minutes back, not 160, so that fifteen
      tries fitted. The host put the 210 letters in the Trash by a STORE
      of its label, the round's rules allowing no MOVE or EXPUNGE; one
      STORE answered NO was sent again. Nothing was sent.*
- [ ] **B-144, Mail's words.** On the test iPad, the test account only,
      from a build of the `bm-cm-words` worktree (branch `copy-words`) or
      of the int it is merged into. No step sends, saves, moves or deletes
      anything in the app, and no draft is tapped. The host first APPENDs,
      read (`\Seen`), to the label "Notes", never the Inbox, one letter from
      another address with a new Message-ID of its own and naming none on
      the account, "B-144 forward letter", with a small PDF attached,
      "B-144 plans.pdf"; it notes the UID from its APPENDUID, and stops if
      there is none. It puts a file of 30 MB, "B-144 large.bin", in On My
      iPad. Three panes; a screenshot of each screen named.
      1. *The Mailboxes pane.* Gmail's folders read, in this order, Inbox,
      Drafts, Sent, Junk, Trash, All Mail, then Starred and the others
      inside "[Gmail]", then the labels, "Notes" among them; "Sent Mail"
      and "Spam" nowhere.
      2. *The list's title.* Sent tapped: the list is titled "Sent". Junk:
      "Junk". All Mail: "All Mail". Trash: "Trash". Nothing in them is
      opened.
      3. *Edit in the Inbox.* With a letter already read open in the
      pane, Edit: the button at the top right reads "Cancel", whole; the
      bar at the bottom reads Select All, Mark, Move and Trash, Trash in
      the same blue as Mark and Move, not red. Nothing ticked, nothing
      else tapped. Cancel: the button reads "Edit" again, the bottom bar
      is back as it was, and the letter still open has its row
      highlighted again (B-133).
      4. *Edit in the Trash.* The Trash opened, Edit: the third button
      reads "Delete", in the bar's blue. Not tapped: Cancel.
      5. *Edit elsewhere.* In "Notes", Sent and Junk, Edit: "Trash" each
      time, then Cancel.
      6. *The widths (D-009).* In "Notes", Edit, in three panes and then
      in two (the view button; "< Mailboxes" and the calendar before the
      title): "Cancel" whole at the right, the title whole or cut with
      "…", never under a button; the same in Important, All Mail and
      Starred, and in the label with the longest name the account has,
      each title's look written down with Edit and with Cancel. Expected
      in two panes with Cancel, from the reading of 2026-10-25 (B-144's
      widths): "Important" cut, about "Impor…", and "All Mail" and
      "Starred" whole, only just. Each time Cancel, then back to three
      panes.
      7. *The Move sheet.* In "Notes", Edit, the "B-144 forward letter"
      ticked, Move: the sheet lists the folders by the names of step 1,
      "Sent" and "Junk" among them. Its Cancel: nothing moved, and the
      letter still in "Notes"; Cancel in the list.
      8. *Found in Sent.* Only if the Inbox has a conversation of two
      letters or more, all read, with a reply of the account's own that is
      only in Sent (B-104): Organize by Thread on, Complete Threads on, the
      conversation tapped, the reply's line tapped in the stack: "Found in
      Sent" over its body, never "Found in Sent Mail". Its body is peeked
      at, nothing marked. With none, written down, and left to
      `CompleteThreadsTests`.
      9. *Forward's question.* The "B-144 forward letter" opened (read, so
      the tap writes nothing), Reply, Forward: "Include attachments from
      original message?" with "Include" and "Don’t Include", the
      apostrophe curly in a screenshot zoomed in. A tap outside the
      question closes it; no composer opens.
      10. *Unable to Attach.* The compose button, Attach File, "B-144
      large.bin" from On My iPad: an alert titled "Unable to Attach",
      "One or more attachments failed to load.", with OK; no row. OK,
      then the composer's Cancel, and Delete Draft if it asks: nothing is
      saved, and Drafts and the Outbox are as they were.
      11. *Not on this iPad.* On any iPadOS 18 device with Mail and a
      Gmail account, never his: whether Mail's Trash button is red or
      blue, what Mail calls Gmail's All Mail, whether its Edit mode ends
      with "Cancel", whether its bar says "Archive" for that account, and
      when "Unable to Attach" shows. The test iPad has no Mail (B-028).
      12. *Put back:* "Notes" left, the Inbox at its top. The host moves
      the UID it noted, and only it, from "Notes" to the Trash (`UID
      MOVE`), and deletes in the Trash only the UID that move answered
      (`COPYUID`); "Notes" itself stays. It takes "B-144 large.bin" off the
      iPad. Never anything found by subject or Message-ID.
- [ ] **B-145, a tapped link opens at once.** On the test iPad, the test
      account only, from a build of the `bm-cm-pages` worktree (branch
      `copy-pages`) or of the int it is merged into. Nothing is sent: the
      composer of step 3 is cancelled and its draft deleted. The host makes
      four letters, each from another address, with a new Message-ID of its
      own and naming none on the account, and APPENDs them, read
      (`\Seen`), to the label "Notes", never the Inbox; it notes each UID
      from its APPENDUID, and stops if one has none. (a) "B-145 plain",
      text/plain, three lines: `https://example.com/b145-plain`,
      `www.example.com`, and `mailto:` to the test account's own address
      with `+b145` before the @ and `?subject=B-145`; (b) "B-145 HTML", an
      HTML letter with a link of its own, `<a
      href="https://example.com/b145-html">Example</a>`, and a YouTube
      address written in its text; (c) "B-145 stack" and (d) "Re: B-145
      stack", a day later, plain, its In-Reply-To and References naming
      (c)'s new Message-ID, so the two are one conversation, (d) with
      `https://example.com/b145-stack` in it. Three panes; Organize by
      Thread on.
      1. *Plain:* "Notes", then "B-145 plain"; its https link tapped:
      Safari comes to the front at once with the page, no "Open this
      link?" or any other question first. Back to Blackmail by the
      top-left "◀ Blackmail": the same letter in the pane, where it was.
      2. *Plain, `www.`:* the same, Safari at `http://www.example.com`.
      3. *Plain, `mailto:`:* the composer opens, To the address with
      `+b145`, Subject "B-145", as before (B-036). Cancel: it closes
      with nothing asked, nothing in it having changed, and Drafts has
      nothing new. Nothing sent.
      4. *HTML:* "B-145 HTML", "Example" tapped: Safari at once; back. The
      YouTube address tapped: YouTube, or Safari if it is not installed,
      at once; back.
      5. *A conversation:* "Re: B-145 stack", (d)'s line opened if it is
      closed, its link tapped: Safari at once; back: the stack where it
      was, (d) open.
      6. *Held:* a finger held on (a)'s first link: WebKit's menu, Open
      Link, Copy Link and Share…, under a card with "Tap to show preview",
      the site and the link's address, as before (decided 2026-10-01); on
      iPadOS 16.5.1 no page is drawn in the card until it is tapped (seen
      2026-10-27, B-145); what Mail on 18 shows for a link held is not
      known. A tap outside: the menu goes, nothing opens.
      7. *Put back:* the Safari tabs opened closed. "Notes" left, the
      Inbox at its top. The host moves the UIDs it noted, and only them,
      from "Notes" to the Trash (`UID MOVE`), and deletes in the Trash
      only the UIDs that move answered (`COPYUID`); "Notes" itself stays.
      Never anything found by subject or Message-ID: a UID not noted is
      left, and written down. Nothing else was written.
      If Mail is back on the test iPad (B-028), or an iPad with iPadOS 18
      and Mail is at hand: the same letters there, each link tapped, to
      see that Mail asks nothing either.
- [ ] **B-146, no white sheet under his signature.** On the test iPad,
      the test account only, from a build of the `bm-cm-pages` worktree
      (branch `copy-pages`) or of the int it is merged into. Nothing is
      composed, sent, moved or deleted in the app, and nothing is printed
      on paper: the Print panel's preview only. The host makes four
      letters, each with a new Message-ID of its own and naming none on the
      account in a Message-ID, In-Reply-To or References, and APPENDs them,
      read (`\Seen`), to the label "Notes", never the Inbox; it notes each
      UID from its APPENDUID, and stops if one has none. (a) "B-146 alone",
      the HTML body and the logo part of one of the letters on the account
      that carry the signature (B-130's 22), nothing else of it; (b) "B-146
      stack", a letter from another address, and (c) "Re: B-146 stack", a
      day later, (a)'s body as a reply to it, its In-Reply-To and
      References naming (b) by its new Message-ID, so the two are one
      conversation; (d) "B-146 quoted", a reply that keeps the sheet's
      class, its `<blockquote type="cite">` holding (a)'s body, as Apple
      Mail's reply and this app's quote it, alone in its thread. Three
      panes unless a step says two; Organize by Thread on.
      1. *Alone:* "Notes", then "B-146 alone": no white sheet. The
      signature's lines white on the black, like the words above it, its
      links blue, and the logo as drawn, dark ink on the black, hard to
      see: as Mail draws it. Then two panes: the same.
      2. *In a stack:* "Re: B-146 stack", (c)'s line tapped open if it is
      closed: its signature as in 1, no sheet; the letter above it as
      before.
      3. *Quoted:* "B-146 quoted": the quote's violet bar, and inside it
      the signature white on the black, no sheet.
      4. *Print:* on 1's letter, Reply, then Print: the preview's paper
      white, the signature's words black and the logo as on paper, as
      before; Cancel.
      5. *Put back:* "Notes" left, the Inbox at its top. The host moves the
      UIDs it noted, and only them, from "Notes" to the Trash (`UID
      MOVE`), and deletes in the Trash only the UIDs that move answered
      (`COPYUID`); "Notes" itself stays. Never anything found by subject
      or Message-ID: a UID not noted is left, and written down. Nothing
      else was written.
      If Mail is back on the test iPad (B-028), in Dark Mode, or an iPad
      with iPadOS 18 and Mail is at hand: (a) there, to see how Mail draws
      the signature, which is inferred from its code and not seen; the
      words and the logo written down beside 1's.
- [ ] **B-147, quote bars beside a plain letter's quotes.** On the test
      iPad, the test account only, from a build of the `bm-cm-pages`
      worktree (branch `copy-pages`) or of the int it is merged into.
      Nothing is composed, sent, moved or deleted in the app, and nothing
      is printed on paper: the Print panel's preview only. The host makes
      four letters, each from another address, with a new Message-ID of
      its own and naming none on the account, and APPENDs them, read
      (`\Seen`), to the label "Notes", never the Inbox; it notes each UID
      from its APPENDUID, and stops if one has none. (a) "B-147 plain",
      text/plain, not flowed, its lines: "Yes, Sunday.", a blank line, "On
      Monday, Carlo wrote:", "> Lunch on Sunday?", "> > Or Saturday?",
      ">> The garden is ready.", "> > > Three deep.", ">>>> Four deep.",
      "> See https://example.com/b147", "> Back to one.", ">From the
      store's line.", a blank line, "Sam"; (b) "B-147 flowed", text/plain
      with `format=flowed`, its lines "Yes.", "> One.", "> > Still one.",
      ">> Two."; (c) "B-147 stack" and (d) "Re: B-147 stack", a day later,
      (a)'s words as a reply to it, its In-Reply-To and References naming
      (c)'s new Message-ID, so the two are one conversation. Three panes
      unless a step says two; Organize by Thread on.
      1. *Plain, alone:* "Notes", then "B-147 plain". Under "On Monday,
      Carlo wrote:", a violet bar down the quote's left, its words 5 pt
      from it and violet; "Or Saturday?" and "The garden is ready." in a
      teal bar inside the violet one; "Three deep." in a green bar inside
      those, and "Four deep." in a fourth, green too; "Back to one." in the
      violet bar alone. No ">" before any of those lines. ">From the
      store's line." as typed, its ">" and no bar; "Sam" under it with no
      bar. The lines where they were: no blank line added above the first
      quoted line or below the last. The link blue; not tapped. The
      colours from a full-size screenshot: about rgb(191, 90, 242),
      rgb(0, 200, 250) and rgb(87, 217, 119), Mail's dark ones.
      2. *Flowed:* "B-147 flowed": "One." and "> Still one." in the violet
      bar, that line with its one ">"; "Two." in a teal bar inside it.
      3. *Two panes:* 1 and 2 again.
      4. *In a stack:* "Re: B-147 stack", (d)'s line tapped open if it is
      closed: its quotes as in 1.
      5. *Print:* on 1's letter, Reply, then Print: the preview's paper
      white, the quotes with their bars and words in Mail's light violet,
      teal and green, no ">" before them, ">From the store's line." as
      typed; Cancel.
      6. *Put back:* "Notes" left, the Inbox at its top. The host moves the
      UIDs it noted, and only them, from "Notes" to the Trash (`UID
      MOVE`), and deletes in the Trash only the UIDs that move answered
      (`COPYUID`); "Notes" itself stays. Never anything found by subject
      or Message-ID: a UID not noted is left, and written down. Nothing
      else was written.
      If Mail is back on the test iPad (B-028), in Dark Mode, or an iPad
      with iPadOS 18 and Mail is at hand: (a) and (b) there, the bars, the
      colours, the 5 pt, and how Mail draws the ">From" line, the flowed
      "> > " line and the fourth level, written down beside 1's and 2's.
- [ ] **B-148, a PDF among the words listed once.** On the test iPad, the
      test account only, from a build of the `bm-cm-pane` worktree (branch
      `copy-pane`) or of the int it is merged into. Nothing is composed,
      sent, saved, moved or deleted in the app: one of the test accounts
      is signed in on the owner's phone and new mail rings it. The host
      makes the letters, each from another address, with a new Message-ID
      of its own and naming none on the account, and APPENDs them, read
      (`\Seen`), to the label "Notes", never the Inbox, each with its Date
      as its internal date; it notes each UID from its APPENDUID, and stops
      if one has none. Three panes unless a step says two; the app's
      connection log read after each step; the screen recorded at 60
      frames a second for 2 and 5. On a build with B-170 the header lists
      no file and each row named here is a tile in the body: steps 3 and 4
      read as B-170's check, 2 and 4.
      1. *The letters,* "B-148 one", "B-148 two", "B-148 end", "B-148
      three" and "B-148 large": one, and two made as it is, Apple Mail's
      shape for a PDF among the words, as B-113's
      check made it (multipart/alternative of the plain words and a
      multipart/mixed of an HTML part, a PDF of about 300 KB sent inline
      with no `Content-ID`, and an HTML part after it ending "Sent from my
      iPad"); end, an HTML part and a PDF attached after it; three, HTML,
      a PDF, HTML, a second PDF, HTML, and a third PDF after all the words;
      large, Apple Mail's shape with a PDF of about 6 MB, over 5 MB, so it
      is opened in part.
      2. *One:* "Notes" opened, "B-148 one" tapped. From the first frame
      after the tap to the letter drawn, no file in the header, under the
      date only the rule; in the body the words before, "Programme.pdf"
      (or the name the host gave it) and its size in blue on a line of its
      own, the words after and "Sent from my iPad". In the recording the
      header's lower rule is at the same height in every frame from the tap
      to the letter drawn: the height written down. The blue name tapped:
      the PDF in Quick Look; Done, the letter as it was. Its list row has
      the paperclip.
      3. *End:* "B-148 end" tapped: the PDF's row in the header, grey from
      the tap then blue, as before; none in the body. Its row tapped:
      Quick Look; Done.
      4. *Three:* the header has the third PDF's row alone; the first two
      have their blue rows among the words, where they sat, each opening
      its own PDF.
      5. *Large:* "B-148 large" tapped: the log has its BODYSTRUCTURE first
      and then its words, not the PDF; no file in the header from the tap,
      and the header's lower rule at the same height in every frame to the
      letter drawn; the PDF's blue row among the words, tapped: it dims,
      "Loading…" after its name, from the tap until Quick Look comes, in
      the recording; the log has the PDF's FETCH, then Quick Look on it;
      Done, the row as it was, blue, no "Loading…".
      6. *Forward's question,* on "B-148 one": the Reply button, Forward:
      Mail's question about its file (B-107) is asked, the PDF being the
      letter's file still. Cancel at the question, so nothing is begun.
      7. *Two panes,* 2 and 3 again, then three panes.
      8. *No connection:* Airplane Mode on, "B-148 two", not opened before,
      tapped: "This message could not be downloaded." under its header,
      no file in the header and none in the body (B-148, Not covered).
      Written down if it is shown whole instead, kept on the iPad. Airplane
      Mode off, "B-148 two" tapped again: as "one" in 2.
      9. *Put back:* "Notes" left, the Inbox at its top. The host moves the
      UIDs it noted, and only them, from "Notes" to the Trash, and deletes
      in the Trash only the UIDs that move answered. Nothing else was
      written.
- [ ] **B-149, the pane covered from the tap to the paint.** On the test
      iPad, the test account only, from a build of the `bm-cm-pane`
      worktree (branch `copy-pane`) or of the int it is merged into.
      Nothing is composed, sent, saved, moved or deleted in the app. The
      host makes the letters, each from another address, with a new
      Message-ID of its own and naming none on the account, and APPENDs
      them, read (`\Seen`), to the label "Notes", never the Inbox, each
      with its Date as its internal date; it notes each UID from its
      APPENDUID, and stops if one has none. Three panes; the screen
      recorded at 60 frames a second through each step and read frame by
      frame; the app's connection log read after each step.
      1. *The letters,* "B-149 colour 1" to "B-149 colour 8": each an HTML
      letter that is one block of a colour of its own filling the pane,
      as B-041's check of 2026-10-25 had them, and "B-149 thread 1" and
      "B-149 thread 2", one conversation, the second's References naming
      the first, the first a block of one colour and the second of
      another.
      2. *Seven taps,* "Notes" opened, then the colour letters tapped one
      after another, 1.5 s apart. In every frame from each tap until
      "Loading…" or the letter, the pane under the header is black: never
      the letter before's colour beside the new selection or under the new
      header. Written down for each tap: the frames of black before
      "Loading…" or the letter, at most 30, and any frame with the
      selection moved and the old letter still under the old header (B-149,
      Not covered). The log has no "pane: cover lifted by its limit"; any
      such line written down with its tap, as it means WebKit said nothing
      of its paint.
      3. *Quick taps:* four colour letters, each opened once already in 2
      and so kept on the iPad (the log's `KEPT-LETTER shown` at each tap),
      tapped 0.2 s apart, four times over, and then the same letters
      tapped 2.5 s apart: no frame of any letter but the one tapped under
      its header; the pane ends on the last. A kept letter is the case
      that failed on 2026-10-27 (B-149, Found on the test iPad), in 20 taps
      of 28, at either pace; letters fetched from Gmail did not.
      4. *A conversation:* from a colour letter, "B-149 thread 2"'s row
      tapped, its conversation in the pane: no frame with the
      conversation's header over the colour letter's block (frames with
      the selection moved and the old header still up are the "Not
      covered" case, written down); then "B-149 thread 1"'s line tapped
      open: the stack stays on the screen, no black over it, the letter's
      body coming into its place as before.
      5. *After a launch:* the app ended from the app switcher and opened
      again, "Notes", the first colour letter tapped: black under its
      header, then "Loading…" or the letter, as in 2.
      6. *No connection:* Airplane Mode on, a colour letter not opened in
      this launch tapped: black, then "Loading…" within half a second,
      then "This message could not be downloaded." if it is not kept on
      the iPad. Airplane Mode off.
      7. *Put back:* "Notes" left, the Inbox at its top. The host moves the
      UIDs it noted, and only them, from "Notes" to the Trash, and deletes
      in the Trash only the UIDs that move answered. Nothing else was
      written.
- [ ] **B-150, Mail's menu on a photo held.** On the test iPad, the test
      account only, from a build of the `bm-cm-pane` worktree (branch
      `copy-pane`) or of the int it is merged into. Nothing is composed,
      sent, saved as a draft, moved or deleted in the app. The host makes
      the letters, each from another address, with a new Message-ID of its
      own and naming none on the account, and APPENDs them, read
      (`\Seen`), to the label "Notes", never the Inbox, each with its Date
      as its internal date; it notes each UID from its APPENDUID, and stops
      if one has none. The test iPad's Photos may be used (B-067). Three
      panes unless a step says two; holds timed from the screen recording.
      1. *The letters,* "B-150 photo": an HTML letter with words, a JPEG
      photo of about 1 MB shown among them by `cid:` as an iPhone sends
      one, a picture from the web, the same photo inside a link to a web
      page, and the account's signature logo by `cid:`, with words enough
      for the letter to scroll twice the pane's height (10); and "B-150
      thread 1" and "B-150 thread 2", one conversation, the second with a
      photo by `cid:`.
      2. *The hold:* "B-150 photo" opened, a finger held on the photo for
      about 0.6 s: a menu beside the finger, Quick Look, Save Image, Save
      to Files, Share, Copy, and none of WebKit's (no Save to Photos, no
      Show Text); no Quick Look under it or after the finger lifts. Written
      down: whether words near the photo were selected, or the loupe came,
      before the menu, and whether the photo lifted under the finger to be
      dragged, with no menu after it (B-150, Not covered). A tap outside:
      the menu goes, nothing done.
      3. *Quick Look:* held again, Quick Look: the photo full screen; Done,
      the letter as it was.
      4. *Save Image:* held again, Save Image. The first time, iOS asks to
      add to Photos: Allow. The photo in Photos, its size and kind as the
      host made it (Photos' info), written down.
      5. *Save to Files:* held again, Save to Files: Files' sheet; On My
      iPad, Save; the file there under its name. Then deleted in Files.
      6. *Share:* held again, Share: the share sheet beside the photo;
      closed with nothing chosen.
      7. *Copy:* held again, Copy; in Notes, if Notes is on the test iPad, a
      new note, Paste: the photo. The note deleted. Without Notes, written
      down as not tried.
      8. *A tap and a short press:* a tap on the photo: Quick Look, as
      before; Done. A press of about 0.3 s: Quick Look, no menu.
      9. *The others:* the logo held: the menu (any picture of the letter's
      own); the logo tapped: nothing, as before. The picture from the web
      held: WebKit's menu as before (Save to Photos among it), tapped:
      nothing. The photo in the link held: WebKit's menu for the link,
      closed with a tap outside. Tapped: on a build that asks before a link
      opens, "Open this link?", Cancel; on one that does not, Safari opens
      at the page: back to the app with the iPad's own back link, the
      letter as it was.
      10. *Moving:* a finger landing on the photo and dragging the letter:
      it scrolls, no menu. A flick of the letter, then a finger put on the
      photo as it coasts, to stop it, and held there a second: the letter
      stops, no menu; lifted, and held again on the still photo: the menu.
      Written down if the first hold gave the menu. A pinch on it: the
      letter zooms, no menu; then a hold on the zoomed photo: the menu by
      the finger, written down where.
      11. *A conversation:* "B-150 thread 2" opened, its photo held: the
      menu; Quick Look: that letter's photo. Done.
      12. *Two panes,* 2 and 3 again, then three panes.
      13. *Put back:* the photo saved in 4 deleted from Photos and from
      Recently Deleted, or left as the owner prefers; Files as found;
      "Notes" left, the Inbox at its top. The host moves the UIDs it
      noted, and only them, from "Notes" to the Trash, and deletes in the
      Trash only the UIDs that move answered. Nothing else was written to
      the account.
- [ ] **B-106, Move to Junk in the Flag sheet.** On the test iPad, the
      test account only, from a build of the `bm-cm-junk` worktree
      (branch `copy-junk`) or of the int it is merged into. Nothing is
      composed, sent or saved. The host makes the letters, each from
      another address, with a new Message-ID of its own, and APPENDs
      them, read (`\Seen`), to the label "Notes", never the Inbox,
      noting each UID from its APPENDUID. Three panes; the connection log
      read after each step.
      0. *The letters:* three, "B-106 junk one", "two" and "three",
      APPENDed "three" first, then "two", then "one", so "one" is the top
      row and "two" the row below it; and a fourth, "B-106 junk four",
      read, which the host APPENDs to "[Gmail]/Spam" itself, so on a build
      with B-158 (the int's) the row under "one" in Junk is the host's.
      1. *The sheet.* "Notes" opened, "B-106 junk one" opened, Flag: the
      sheet under the Flag button reads Flag, Mark as Unread, Move to
      Junk, in that order, in the plain style, no Cancel in the popover. A
      tap outside closes it, and nothing is written in the log.
      2. *Move to Junk.* Flag, Move to Junk: no question; the row goes as
      the popover closes, not in the frame of the tap, since UIKit runs a
      sheet's item only once the sheet is gone, 0.5 to 0.65 s after the
      tap on the test iPad (B-106, Found on the test iPad 2026-10-27): a
      shot about 0.3 s after the tap can still show the popover's last
      frame or "one" open, and the shot that counts is taken at least 1 s
      after the tap. In the same frame as the row goes, on a build with
      B-158, the int's, "two", the row below, opens
      in the pane, highlighted; it is read, so no STORE (the pane empties
      on a build without it); never "one" off the list with the pane still
      showing it. "Moving…" under the list until the answer, about a third
      of a second, so caught only by shots every 0.1 s from the tap, or
      written down as not caught; no alert. The log: one `UID MOVE n
      "[Gmail]/Spam"` answered `OK [COPYUID …]`, and nothing else
      written. Mailboxes,
      the Junk folder (named Spam in the sidebar until Mail's words are
      built, under "Blocked on the owner", "Mail's words in three
      places"; Junk after): the letter at its top, read. On Gmail's web,
      in Spam and no longer in Notes.
      3. *Inside Junk.* The letter opened there, Flag: Flag, Mark as
      Unread, Move to Inbox, and no Move to Junk. On B-158's build the row
      below in Junk, if any, opens after the Move: before it, the row under
      "one" is "B-106 junk four"; if it is another, the host notes that
      letter's UID and flags and puts its `\Seen` back as noted at the
      put-back. Move to Inbox: the row leaves Junk, the log one `UID MOVE
      n "INBOX"`; on B-158's build the row below opens, highlighted:
      write down which. The Inbox has the letter, read. A move into the
      Inbox is not new mail to Gmail; if the phone with the test account
      rings for it, write it down.
      4. *From a search.* All Mailboxes, "B-106 junk two" searched for:
      its hit, from All Mail, opened, Flag: Move to Junk offered, the
      hit's own folder being All Mail. Move to Junk: the hit goes, and on
      B-158's build the next result opens if there is one; the log's
      `UID MOVE` sent with "[Gmail]/All Mail" selected, and on
      Gmail's web the letter in Spam, no longer in Notes.
      5. *Not in Edit mode.* "Notes", Edit, a row ticked, Mark: Flag and
      Mark as Unread or Read alone, no Move to Junk (D-022). Cancel.
      6. *Spam not shown in IMAP.* On Gmail's web, Settings, Labels:
      Spam's "Show in IMAP" off. In the app, Mailboxes pulled down to
      refresh: no Junk folder. "B-106 junk three" opened in "Notes",
      Flag: Flag and Mark as Unread alone. Then "Show in
      IMAP" on again, as found, and the Junk folder back after a refresh.
      7. *Put back:* "one" in the Inbox, "two" in Junk and "three" in
      "Notes" deleted from the app, to the Trash, each by Edit mode's
      Trash ("Delete" on a build without B-144), which opens no other
      letter; the host deletes "four" in Spam and, in the Trash, only the
      letters with the Message-IDs it made, and puts back the `\Seen` of
      any letter noted in 3. Spam's "Show in IMAP" as found. Nothing was
      sent.
- [ ] **B-151, a lost answer's row goes at the next connection.** On the
      test iPad, the test account only, from a build of the `bm-cm-junk`
      worktree (branch `copy-junk`) or of the int it is merged into.
      Nothing is composed, sent or saved. The host makes the letters, each
      from another address, with a new Message-ID of its own, and APPENDs
      them, read (`\Seen`), to the label "Notes", never the Inbox, dated
      two days back and more, noting each UID from its APPENDUID. A Delete
      moves them to the Trash; a Move goes to an empty label of the
      account's own. Three panes; the connection log read after each
      step; Airplane Mode turned off after each step that turns it on.
      0. *The letters:* sixteen, "B-151 single 1" to "16".
      1. *Some moved, then an answer lost:* "Notes" opened at its top.
      Edit, the sixteen rows ticked, Trash ("Delete" on a build without
      B-144), and Airplane Mode on about a
      second after the tap. After "Deleting…", "Can't connect to mail
      server.", OK: the rows whose MOVEs the log shows answered `OK
      [COPYUID …]` stay off, the rest come back where they stood. Find in
      the log the MOVE that went with no answer, followed by `LOST-ANSWER
      UID MOVE folder=Notes uid=n`, and write down n and its row's
      subject. If there is none (every MOVE answered, or the next kept
      back with `NO-PATH UID MOVE not-sent`), there was no lost answer:
      write it down, and try again on what is left, the timing a little
      earlier or later.
      2. *The look:* Airplane Mode off, and the list left alone: no
      Refresh, no tap, up to a minute. In the log, after the watch's next
      check: `UID SEARCH X-GM-MSGID …` with "Notes" selected, then
      `LOST-ANSWER-LOOK folder=Notes uid=n` and `gone` or `there`. Gone:
      the row written down in 1 leaves the list by itself, with no alert
      and nothing new on the line under the list, and on Gmail's web the
      letter is in the Trash. There: the row stays, and the letter is in
      Notes on Gmail's web. The check after it sends no such SEARCH.
      3. *Refresh:* the same rows as at the end of 2, row for row.
      4. *Nothing went:* a letter in "Notes" opened, Airplane Mode on,
      Delete: the row back and the alert, and no `LOST-ANSWER` line in the
      log (one `NO-PATH UID MOVE nothing-sent`, or no line where the
      watch had found the path gone first, as in B-132's check). Airplane
      Mode off; after the next check, no `UID SEARCH X-GM-MSGID`, and the
      row stays.
      5. *A Move, scrolled down:* 1 again on what is left in "Notes", with
      Move in place of Delete, the empty label chosen and Airplane Mode on
      about a second after. Then, before Airplane Mode goes off, the list
      dragged up a little and left there, no longer at its top, the row
      written down still in sight. At the look, `gone`: nothing on the
      list moves, and that row stays where it is. The list scrolled back
      to its top: the row goes then, by itself. On Gmail's web the letter
      is in the label. If the look says `there`, the hold was not seen:
      write it down.
      6. *Put back:* the host deletes, in the Trash and in the label, only
      the letters with the Message-IDs it made, and what is left of them
      in "Notes"; the label stays, empty, as found. Nothing was sent.
- [ ] **B-152, the original marked once a reply or a forward has gone.**
      On the test iPad, the test account only, from a build of the
      `bm-cm-sent` worktree (branch `copy-aftersend`) or of the int it is
      merged into. Three panes, Organize by Thread on; the app's connection
      log read after each step. The host makes the letters, each from
      another address, with a new Message-ID of its own and naming none on
      the account, and APPENDs them, read (`\Seen`), to the label "Notes",
      never the Inbox; it notes each UID from its APPENDUID, and stops if
      one has none. The host reads a letter's flags with `UID FETCH … FLAGS`
      in "Notes", never by subject.
      1. *Nothing on reading.* The host APPENDs "B-152 one", "B-152 two"
      and "B-152 three". Open "Notes", tap "B-152 one": its letter in the
      pane, no arrow on any of the three rows; no `UID STORE` and no
      `SENT-MARK` line in the log; the host reads neither `\Answered` nor
      `$Forwarded` on any of them.
      2. *A reply put away.* Reply on "B-152 one", type a word, Cancel,
      Delete Draft: no `SENT-MARK` line; the host's flags as in 1.
      3. *A forward put away.* Forward "B-152 two", Cancel, Delete Draft:
      the same.
      4. *(sends, test account only, needs the owner's go)* Reply on
      "B-152 one", To the account's own address with `+b152` before the
      @, Send: the sheet closes at the 250 as before; within a few seconds
      the row of "B-152 one" shows the grey reply arrow; the log has one
      `SENT-MARK answered folder=Notes`, after the send's `WIRE-` lines,
      and one `UID STORE … +FLAGS.SILENT (\Answered)`; the host reads
      `\Answered` on it, and nothing else changed on the three.
      5. *(sends, test account only, needs the owner's go)* Forward
      "B-152 two" to the same address: the forward arrow on its row,
      `SENT-MARK forwarded`, `$Forwarded` on the host. Say whether Gmail
      keeps the keyword: the host reads it again after a Refresh.
      6. *(sends, test account only, needs the owner's go)* From the
      Outbox: Airplane Mode on, Reply on "B-152 three", the same address,
      Send: the Outbox's notice, no `SENT-MARK`. End the app in the
      switcher, Airplane Mode off, open it: the letter goes at the first
      pass, once, then `SENT-MARK answered` and the arrow on its row.
      7. *(sends, test account only, needs the owner's go)* Gone by then:
      the host APPENDs "B-152 four". Airplane Mode on, Reply on it, Send:
      the Outbox. The host moves "B-152 four", by its noted UID, to the
      Trash. Airplane Mode off, Refresh: the reply goes, once;
      `SENT-MARK answered original gone, nothing sent` in the log, no
      alert, and the host reads no `\Answered` on it in the Trash.
      8. *Mail's side,* only if Mail is back on the test iPad (the owner's
      question 25): the same reply and forward from Mail, then the host
      reads which keyword Mail wrote, `$Forwarded` or `Forwarded`, and
      whether it wrote it at once or only after the 250.
      9. *Put back:* "Notes" left, the Inbox at its top. The host moves
      the UIDs it noted, and only them, from "Notes" to the Trash; the
      letters 4 to 7 sent to `+b152` are left for the owner to say.
- [ ] **B-153, a share with no connection waits in the Outbox.** On the
      test iPad, the test account only, from a build of the `bm-cm-sent`
      worktree (branch `copy-aftersend`) or of the int it is merged into,
      installed with the share extension as the share sheet's checks say
      (`tools/build-share-ipa.sh`, TrollStore's helper, then
      `killall BlackmailShare`), and the app opened once. Airplane Mode
      means Airplane Mode on with Wi-Fi off. The connection log read after
      each step.
      1. *A link, offline.* Blackmail in the background. Airplane Mode on.
      In Safari, a Wikipedia page, Share, Blackmail: To the account's own
      address with `+b153` before the @. Before Send, Airplane Mode on
      (guarded): Safari cannot load a page and Settings shows Wi-Fi off;
      otherwise stop, as the Send would go. Send: the sheet slides away with
      one swoosh and no alert, Safari as before. Nothing can be sent: there
      is no connection.
      2. *A photo, offline.* In Photos, one photo, Share, Blackmail, the
      same To, Send: "Can't connect to mail server." over the sheet, no
      sound, the sheet stays, as before. Cancel, Delete Draft.
      3. *In the app.* Still in Airplane Mode, guarded as in 1 (Safari
      cannot load a page and Settings shows Wi-Fi off; otherwise stop, as
      the app's Outbox pass would send it), bring Blackmail back: the
      Outbox in the Mailboxes with 1; the line under the list says
      "1 Unsent Message"; the Outbox lists the letter, To the address, the
      page's title its subject, its time the share's. The app's
      connection log has `SHARE-WAITING taken into the Outbox`.
      4. *Once.* Home, then Blackmail again, and end it in the switcher
      and open it again, still in Airplane Mode: still "1 Unsent Message",
      one row.
      5. *Opened and put back.* Tap the letter in the Outbox: the composer
      with the link above his signature; Cancel untouched: back in the
      Outbox.
      6. *Deleted.* Still in Airplane Mode, the Outbox, Edit, tick the
      letter, Trash ("Delete" on a build without B-144): nothing asked, the row and the Outbox go, and
      "1 Unsent Message" with them. Airplane Mode off, Refresh: nothing is
      sent (no `LETTER-PLAN` line in the log).
      7. *(sends, test account only, needs the owner's go)* Steps 1 and 3
      again, then Airplane Mode off: the letter goes at the first pass, or
      at Refresh, once; the Outbox goes. In the letter that arrives, From
      the name in Settings, dated at the share's time, the link a link in
      Blackmail's pane.
      8. *(sends, test account only, needs the owner's go)* The share made
      with Blackmail not opened since: end Blackmail in the switcher,
      Airplane Mode on, share as in 1, Airplane Mode off, then open
      Blackmail: it goes at the launch's first pass, once.
      9. *Mail's side,* only if Mail is back on the test iPad (the owner's
      question 25): Wi-Fi off with Airplane Mode off, share a page to Mail:
      say whether Mail puts up an alert, and its words; then Airplane Mode
      on, the same: Mail's "Cannot Send Email" alert, written down.
- [ ] **B-154, Mail's paperclip in the keyboard's shortcut bar.** On the
      test iPad, the test account only, from a build of the
      `bm-cm-compose` worktree (branch `copy-compose`) or of the int it is
      merged into. Settings, General, Keyboard, Shortcuts as found, written
      down; it must be on for 1 to 6. The on-screen keyboard throughout but
      in 8. Nothing is sent but in 7: every letter ends with Cancel, and
      Delete Draft if it is asked. Before it, the host puts one small PDF,
      "B-154.pdf", in On My iPad.
      1. *In the letter alone.* A new letter, portrait, To left empty. Tap
      the body: a paperclip at the right end of the bar above the
      keyboard, after anything the system has there; Undo, Redo and Paste
      at its left as before. Tap To, then Subject: no paperclip in their
      bar. Tap the body again: the paperclip.
      2. *Its menu.* Tap the paperclip: a menu, "Attach File" and "Photo
      Library", each with its symbol; their order on the screen, top to
      bottom, written down, and where the menu stands. Tap outside: it
      goes, nothing opened.
      3. *Attach File.* Paperclip, Attach File: the Files browser, as the
      button under the files opens it. "B-154.pdf" from On My iPad: its
      row with its weight under Subject. Remove it.
      4. *Photo Library.* Paperclip, Photo Library: the photo picker,
      photos and videos, as the button opens it; what it opens on written
      down. One photo: its row, a spinner and then its weight. Remove it.
      Cancel, Delete Draft.
      5. *Landscape.* A new letter, landscape, the caret in the body: the
      paperclip at the right of the bar, and Send in the sheet's own bar
      at the top, in sight; the menu opened, Send still in sight and not
      covered. Tap outside. Cancel.
      6. *The buttons stay.* Under the files, "Photo Library" and "Attach
      File" as before; each opens its picker, Cancel in each. Cancel.
      7. *Held while a letter goes* (sends, test account only, needs the
      owner's go). A new letter To the test account's own address,
      Subject "B-154 held", the caret in the body, Send: while "Sending…"
      shows, the paperclip greyed and no menu at a tap. Skipped without
      the go, and written down.
      8. *A keyboard of keys,* if one is at hand: the bar iOS shows at the
      bottom while the caret is in the body has the paperclip, and its
      menu opens; Cancel. Without one, not done, and written down.
      9. *Not the share sheet.* From Safari on example.com, Share, Blackmail,
      the caret in the body: no paperclip in its bar. Cancel, Delete Draft
      if asked.
      Nothing else is tapped; Drafts and Sent Mail counted before and after.
- [ ] **B-155, the address book filled from his Sent Mail.** On the test
      iPad, the test account only, from a build of the `bm-cm-compose`
      worktree (branch `copy-compose`) or of the int it is merged into. The
      fill runs once for the account, at the first launch of a build that
      has it, so 1 is done before that build is first launched; a build
      with it launched before leaves 2 to nothing, and is written down.
      Nothing is sent, composed letters end with Cancel and Delete Draft if
      asked, and nothing is opened in Sent Mail but in 5's search.
      1. *The letters, before the launch.* The host APPENDs five letters
      to the test account's "[Gmail]/Sent Mail" (an APPEND sends nothing),
      each From the test account, with a new Message-ID of its own, and
      notes each UID from its APPENDUID, stopping if one has none: (a) To
      "Quentin Fill <quentin.b155@example.com>", read (`\Seen`), its
      internal date four months back; (b) the same To, unread, no flags,
      two months back; (c) To "Olive Old <olive.b155@example.com>", read,
      seven months back; (d) To the test account itself alone, read, three
      months back; (e) To "Prefix Fill <P.b155@example.com>", P the test
      account's address before its @, read, one month back. The book is
      not to know Quentin, Olive or Prefix Fill already: the host checks
      that none of the three addresses is in any other letter of the
      account.
      2. *The launch.* The build installed and launched. The Inbox's first
      page comes as before, and the list can be scrolled and a letter
      already read (not bold) opened meanwhile. In the connection log,
      after the first page and the counts: `SELECT "[Gmail]/Sent Mail"`,
      `UID SEARCH SINCE "dd-Mmm-yyyy"`, six months before the day, `UID
      FETCH … (UID INTERNALDATE ENVELOPE)` for at most a hundred letters
      each, and `BOOK-FILL letters=N people=M`, both numbers written down,
      with the time from the SEARCH to that line. No STORE and no BODY
      among them. An Inbox letter already read (not bold) tapped while
      they run, its UID and the time it took written down.
      3. *Offered.* A new letter. In To type "quen": "Quentin Fill" offered.
      Delete it; type "oliv": "Olive Old" not among what is offered.
      Delete it; type the first four letters of the test account's own
      address: the test account's own address on the first row, every row
      offered written down in order. "Prefix Fill" need not be among them:
      four rows are offered, ranked by how many letters he wrote to each,
      a tie going to the later letter, and its one letter puts it below
      every address starting with the same letters that he wrote to as
      often or more often, as the test account's `+tag` addresses of
      earlier rounds are (on 2026-10-27, nineteen of them, five at one
      letter but a later one, and it came 21st of 21). Then delete it and
      type P and a "." (P as in 1(e)), which only it matches: "Prefix
      Fill" offered. Cancel, Delete Draft if asked.
      4. *Nothing marked.* The host reads (b)'s flags: still no `\Seen`.
      5. *Search* (B-123). In Sent Mail, Current Mailbox, type "Quen" with
      no space after it: (a) and (b) found. Cancel the search. Nothing
      opened.
      6. *Once.* The app ended in the switcher and launched again: no
      `BOOK-FILL` line and no SEARCH in Sent Mail in the log.
      7. *Put back:* the host moves the five UIDs it noted, and only them,
      from Sent Mail to the Trash (`UID MOVE`), and deletes in the Trash
      only the UIDs that move answered (`COPYUID`). Never anything found
      by subject or Message-ID: a UID not noted is left, and written down.
      Nothing else was written.
- [ ] **B-156, Mail's drags on a row.** On the test iPad, the test
      account only, from a build of the `bm-cm-swipe` worktree (branch
      `copy-swipe`) or of the int it is merged into. Nothing is sent:
      More's Reply and Forward are opened and closed with Cancel, and
      Delete Draft if asked, nothing saved. A stands for the account's
      address. The host makes nine letters, each From and To A with
      `+b156` before the @, so that a Reply, Reply All or Forward sent by
      mistake stays in the test account, with a new Message-ID of its own
      and naming none on the account, and APPENDs them, read (`\Seen`), to the label "Notes",
      never the Inbox, letters 8 and 9 one conversation (9 answers 8,
      In-Reply-To and References), each dated a minute after the one
      before; it notes each UID from its APPENDUID, and stops if one has
      none. Subjects "B-156 swipe N", N from 1 to 8, and letter 9's "Re:
      B-156 swipe 8", as Gmail threads by subject too: the row of 8 and 9
      shows "B-156 swipe 8" with 2 beside it. Organize by Thread on, three
      panes, "Notes" open; the app's connection log read after each step;
      a screenshot of each drag held open.
      1. *A slow drag to the left* on letter 1's row, let go part way:
      More grey, Flag orange and Trash red, the Trash at the row's right
      edge, each with its symbol over its word; a tap elsewhere on the
      list closes it, nothing sent.
      2. *Flag:* letter 2 tapped, its letter in the pane; the drag, Flag:
      the row's flag at once, one `UID STORE n +FLAGS.SILENT (\Flagged)`,
      the row still highlighted; the pane's Flag button: Unflag offered,
      Cancel. The drag again shows Unflag; tapped, the flag gone, one
      `-FLAGS.SILENT (\Flagged)`.
      3. *To the right:* letter 3, a slow drag to the right: Unread, blue;
      a full drag: the dot at once, one STORE of `\Seen` off, the count
      beside "Notes" up by one; then a slow drag to the right shows Read,
      and a full drag takes the dot and the one off again.
      4. *The Trash by a tap:* letter 4, the drag, Trash: no question, the
      row gone at once, "Deleting…" under the list until one `UID MOVE n
      "[Gmail]/Trash"` is answered.
      5. *The Trash by a full drag,* the letter open: letter 5 tapped, its
      letter in the pane; a full drag to the left on its row: no
      question, the row gone at once, one MOVE, and the pane empty; on a
      build with B-158, the int's, the row below, letter 3's, highlighted
      and its letter in the pane instead, as after the pane's Delete. Watch
      for the row sliding back into place before it vanishes, by eye and,
      if it can be caught, in a screen recording: Mail's slides off. If
      it slides back, the row is to be taken off the list in the button's
      handler, before UIKit is told it is done, and this step tried
      again.
      6. *A conversation:* the row of letters 8 and 9, a full drag to the
      left: the row gone, two MOVEs, letter 8's first; watched for the
      slide back as in step 5.
      7. *More:* letter 6, the drag, More: a sheet over the row with
      Reply, Reply All, Forward, Trash Message, Flag, Mark as Unread and
      Move Message, in that order, with Move to Junk before Move Message
      on a build with B-106, the int's, where the account shows Spam in
      IMAP. Reply: the composer, To A with
      `+b156`, letter 6's words quoted; Cancel. Forward: the composer, no
      To, the letter below; Cancel. Move Message: the folder sheet;
      Cancel. Nothing in Drafts, nothing sent; nothing in the log but the
      letter's FETCH. Then More again, Trash Message: no question, the
      row gone, one MOVE, as step 4.
      8. *Not in Edit mode:* Edit, a drag on letter 7's row: no buttons;
      Done, or Cancel on a build with B-144.
      9. *Refused:* Airplane Mode on, a full drag to the left on letter
      7's row: the row goes, and comes back where it stood with "Can't
      connect to mail server."; Airplane Mode off.
      10. *In the Trash:* Trash opened; letter 4's row, the drag: More,
      Flag and Delete, red. Delete: "Delete Message?" with Cancel and
      Delete; Cancel: the row stays, nothing sent. More on it: Delete
      Message in Trash Message's place; tapped, the same question;
      Cancel. A full drag on letter 5's row: the same question; Delete:
      the row gone, one `UID STORE n +FLAGS.SILENT (\Deleted)` and one
      `UID EXPUNGE n`, n the UID the MOVE of 5 answered.
      11. *Put back:* "Notes" left, the Inbox at its top. The host moves
      the UIDs it noted that are still in "Notes" to the Trash, and
      deletes in the Trash only the UIDs those moves answered and the ones
      the app's MOVEs of letters 4, 6, 8 and 9 were answered with
      (`COPYUID`, in its log); "Notes" itself stays. Never anything found by subject
      or Message-ID. Nothing was sent.
- [ ] **B-157, Undo as in Mail.** On the test iPad, the test account
      only, from the same build as B-156's check. Nothing is composed or
      sent. Shake to Undo on (Settings > Accessibility > Touch), as it
      comes. The host APPENDs seven letters to "Notes" as for B-156, From
      and To A with `+b157`, "B-157 undo N", letters 1 to 6 read and
      letter 7 unread, noting each UID. A shake by hand, or
      AssistiveTouch's Shake; three fingers if they can be made. The app's
      connection log read after each step. First of all, before anything
      Undo can take back, a Trash, a Move, a Flag or an Unflag, by a
      drag, More, Edit mode or the pane, so before B-156's check begins
      when the two run together (its step 2 flags and unflags by drags):
      the app ended in the app switcher and opened again, then sent to
      the background and back (Home, then its icon); two shakes a second
      or two apart: no alert. Then the control: a drag's Flag on one of
      the host's letters in "Notes", a shake: "Undo Flag"; Undo: the flag
      gone, one `-FLAGS.SILENT (\Flagged)`. A shake with no alert and no
      control after it is not evidence. On 2026-10-27 the shake was made
      after B-156's Trash, still on the undo stack, and "Undo Trash" came;
      at step 10 AssistiveTouch's Shake did not reach the app just
      relaunched until it had been to the background and back; and a
      first shake was lost twice (B-157, Found on the test iPad).
      0. *Informative, not blocking*, on any iPadOS 18 device with Mail, if
      one is at hand (the test iPad has none, B-028): flag a letter, shake,
      and write down the alert's words; Cancel. Unflag it, shake, the same.
      Expect "Undo Flag", and say whether there is one after the Unflag.
      1. *A drag's Trash:* a full drag to the left on letter 1's row, the
      row gone. A shake: UIKit's alert, "Undo Trash", Cancel and Undo,
      its words written down; Cancel: nothing sent. A shake again, Undo:
      "Moving…", letter 1's row back where it stood; the log `UID FETCH n
      (UID X-GM-MSGID)` in the Trash and one `UID MOVE n "Notes"`, n the
      UID the Delete's MOVE answered; over IMAP letter 1 in "Notes" under
      a new UID, not in the Trash.
      2. *Edit mode, two as one:* Edit, letters 2 and 3 ticked, Trash
      ("Delete" on a build without B-144). A
      shake, Undo: both rows back, each where it stood, two FETCHes and
      two MOVEs, letter 2's first, the older (B-084).
      3. *The pane's Move:* letter 4 opened, Move, Junk ("Spam" on a build
      without B-144). A shake: "Undo
      Move"; Undo: its row back in "Notes", out of Spam.
      4. *More than one step:* letters 5 and 6 deleted by drags, 5 first.
      A shake, Undo: letter 6 back; a shake, Undo: letter 5 back.
      5. *Three fingers,* if they can be made: letter 5 deleted by a drag,
      three fingers swiped to the left: the banner "Undo Trash", letter 5
      back.
      6. *With no connection:* letter 6 deleted by a drag, Airplane Mode
      on, a shake, Undo: "Can't connect to mail server.", the row not
      back; Airplane Mode off, a shake: "Undo Trash" again; Undo: back.
      7. *After the search field:* the search field tapped, a letter
      typed, Cancel; letter 2 deleted by a drag; a shake: the alert comes.
      Undo.
      8. *A letter just opened, deleted in the pane:* "Notes" at its top,
      letter 7's row the first; the count beside "Notes" noted; letter 7
      tapped: the dot gone, the count down by one; Delete in the pane. A
      shake, Undo: its row back with no dot, the first row and in sight,
      the list still at its top (on 2026-10-27 it came back above the top
      of the pane, B-157, Found on the test iPad); the count as it was
      after the tap, not up by one; letter 7 tapped again: the count as it
      was, nothing more taken off. A Refresh: the same. Again by a full
      drag on letter 7's row, "Notes" at its top: a shake, Undo: back
      first, in sight. Then with the list changed between the Trash and
      the Undo: letter 7 by a full drag; the list dragged up until letter
      1's row is near the top of the pane, still in sight, and letter 1 by
      a full drag; the list back at its top (a tap on the status bar); a
      shake, Undo: letter 1 back; a shake, Undo: letter 7 back, the first
      row and in sight, the list at its top (before B-157's second change
      of 2026-10-27 it would have gone above the top of the pane this way
      too, read in the code, not seen).
      9. *Undo Flag:* a drag's Flag on letter 4. A shake: "Undo Flag", its
      words written down; Undo: the flag gone at once, one `UID STORE n
      -FLAGS.SILENT (\Flagged)`. Flag by a drag again, then Unflag by a
      drag; a shake: the alert's words written down; Undo: the flag back,
      one `+FLAGS.SILENT (\Flagged)`. A read mark by a drag to the right
      on letter 5, then a shake: the alert names the Flag before it, not
      the read mark; Cancel.
      10. *Nothing after a relaunch:* letter 3 deleted by a drag; the app
      ended in the app switcher and opened again, then sent to the
      background and back (Home, then its icon), as in the setup; two
      shakes a second or two apart: no alert. Then the control: a drag's
      Unflag on letter 4, flagged since 9, a shake: "Undo Unflag"; Undo:
      the flag back, one `+FLAGS.SILENT (\Flagged)` (a first Undo that
      says "Can't connect to mail server.", the connection lost while the
      app was away, as on 2026-10-27: a shake, Undo again). Without the
      control the no-alert shakes are not evidence: on 2026-10-27 the
      shakes from AssistiveTouch did not reach the app just relaunched.
      Letter 3 is left in the Trash for the host.
      11. *Put back:* as B-156's step 11, by the UIDs noted and the ones
      every MOVE answered; Spam left as found. Nothing was sent.
- [ ] **B-158, the letter after a Delete or Move in the pane.** On the
      test iPad, the test account only, from a build of the `bm-cm-next`
      worktree (branch `copy-nextletter`) or of the int it is merged into.
      Nothing is composed, sent or saved as a draft, and the app's Deletes
      and its Move go onto the host's letters alone. The host makes eleven
      letters, each from another address, with a new Message-ID of its own
      and naming none on the account, and APPENDs them to the label
      "Notes", never the Inbox, each with its Date as its internal date;
      it notes each UID from its APPENDUID, and stops if one has none.
      First two read letters alone, "B-158 drag 2" and then "B-158 drag
      1", dated older than the conversation and newer than any of Notes'
      own, drag 2 the older; then a conversation of three, "B-158 talk"
      (a), (b) and (c), each reply's References naming the one before,
      read (`\Seen`); then six letters alone, "B-158 next 6" down to "B-158
      next 1", all read but "next 3", which is APPENDed unread. The list
      goes by UID, the order they were APPENDed, the last on top: next 1
      to next 6, then the conversation, then drag 1 and drag 2, then
      Notes' own. It also
      makes the label "B-158 moved", if the account has none. Organize by
      Thread on, three panes, nothing set: View Next Message, Mail's
      factory default, is what the app does. A screen recording through
      each step, and the app's connection log read after each.
      1. *Delete opens the one below.* "Notes" tapped, then next 2's row:
      next 2 in the pane. Delete, once. Next 2's row goes, and next 3 is in
      the pane with its row highlighted, in the first frame without next
      2's row; any frame of "No message selected" between written down.
      Next 3's dot goes and Notes' count is one less; the log: the `UID
      MOVE` of next 2 to the Trash, next 3's body FETCH, and its `UID STORE
      … +FLAGS (\Seen)`. Delete is blue over next 3, not grey.
      2. *A double tap.* Delete tapped twice, as fast as a double tap, the
      gap between the taps written down from the recording: next 3 goes,
      next 4 opens, highlighted, and stays; the log has one `UID MOVE`,
      next 3's. A second or more later, Delete once: next 4 goes, next 5
      opens. Delete was never grey.
      3. *A Move.* Move, then "B-158 moved": next 5's row goes as the sheet
      slides away, next 6 opens, highlighted; the log's `UID MOVE` of next
      5 to that label.
      4. *A conversation.* The conversation's row tapped: its stack, (c)
      open. Delete: (c) goes; the row stays, of (b) and (a), highlighted,
      and the pane shows it again without (c), (b) open; no other row
      opens. A second later, Delete: (b) goes, and the row, now (a) alone,
      opens as one letter.
      5. *A search, at its foot.* The search field, Current Mailbox, "B-158
      next": two results, next 1 and next 6. Next 6, the last, tapped, and
      Delete: next 6 goes, next 1, the one above, opens, highlighted, the
      search's words and its one result still there. Delete: no result
      left, and the pane empty, "No message selected", as before B-158.
      6. *Edit mode as before.* Cancel the search; (a) tapped. Edit, (a)'s
      row ticked, Delete in the Edit bar ("Trash" once Mail's words for it
      are in): the pane empties and nothing else opens. Done (Cancel with
      B-144). On a build with B-156, the int's: "B-158 drag 1" tapped, its
      letter in the pane; a full drag to the left on its row: no question,
      its row goes, and "B-158 drag 2", the row below, opens in the pane,
      highlighted, as after the pane's Delete in 1.
      7. *Put back:* "Notes" left, the Inbox at its top. The host takes
      out of the Trash and out of "B-158 moved" only the letters with the
      Message-IDs it made, which nothing else on the account has, deletes
      them there, and deletes the label "B-158 moved" if it made it. Any
      UID it noted still in "Notes" is moved to the Trash the same way.
      Nothing else was written.
      Not on the iPad: Don't Select a Message, which no Settings row sets
      yet (host tests alone), Trash's question before an erase, and the
      foot of the pages loaded while older letters are still to come,
      where nothing opens (host tests alone).

- [ ] **B-159, his replies kept with an Inbox conversation.** On the
      test iPad, the test account only, from a build of the
      `bm-cm-offline` worktree (branch `copy-offline`) or of the int it is
      merged into. Nothing is composed, sent, saved, moved or deleted in the
      app. It needs Inbox conversations of more than one letter, each with
      a reply of A's (the account's address) in Sent Mail alone: two left
      on the account by B-104's check (subjects beginning "B-104") are
      used, and nothing is made. If fewer are left, J (a second test
      address) writes to A, A answers from Gmail on the web and J answers
      again (sends, test account only, needs the owner's go). Complete
      Threads on in Settings, three panes; the app's connection log read
      after each step.
      1. *Online.* The first conversation opened: A's line comes in once
      the newest letter has come, and reads "Found in Sent Mail" once
      open; its body comes in one `UID FETCH … (UID BODY.PEEK[])` in
      `[Gmail]/Sent Mail`, no STORE, and `KEPT-LETTER kept` is in the log.
      The second opened too, its A's line left closed.
      2. *Offline relaunch.* Blackmail ended, Airplane Mode on, Blackmail
      opened: the kept Inbox. The first conversation tapped: A's line is in
      the stack in its first frame, where it was online, and the letter
      the stack opens at is where it was. A's line opened: its body at
      once, `KEPT-LETTER shown`. Nothing in the log but the launch's own
      failure to connect.
      3. *Never opened.* The second conversation, offline: A's line is
      there; opened, it says the message could not be downloaded.
      4. *Back online.* Airplane Mode off, the first conversation opened
      again after ten minutes: the lookup's `SELECT`, `UID SEARCH
      X-GM-THRID` and `UID FETCH`es go once the newest letter has come,
      and A's line is there once, not twice.
      5. *The switch.* Complete Threads off: the stack without A's line,
      nothing looked up. On again.
      Put back: Airplane Mode off, Blackmail on the Inbox. Nothing was
      written.

- [ ] **B-160, reading with no connection: more pages, letters fetched
      ahead, and search.** On the test iPad, the test account only, from a
      build of the `bm-cm-offline` worktree (branch `copy-offline`) or of
      the int it is merged into. Nothing is composed, sent, saved, moved or
      deleted in the app. The host makes the letters, each from another
      address, with a new Message-ID of its own and naming none on the
      account, and APPENDs them, read (`\Seen`), to the label "Notes",
      never the Inbox: 130 letters "B-160 row N", N from 1 to 130, dated a
      minute apart, row 130 the newest, the body of row 7 holding the word
      "quincunx" and no other letter on the account holding it; it notes
      each UID from its APPENDUID, and stops if one has none. Three panes;
      the app's connection log read after each step.
      1. *Pages kept.* "Notes" opened and scrolled to its foot: the list
      pages down to row 1, each page one `UID FETCH` of summaries. Row 7
      opened: its body comes, `KEPT-LETTER kept`. Blackmail ended,
      Airplane Mode on, Blackmail opened, "Notes" opened: every row, 130
      to 1, in its first frame, scrolled from top to foot with none
      missing; nothing in the log but the launch's own failure to connect.
      Row 7 opens from the iPad, `KEPT-LETTER shown`.
      2. *Kept on past a fresh page.* Airplane Mode off, "Notes" opened and
      scrolled to row 60 before its fresh page lands, or with a finger held
      on the list until it has: row 60 and the rows below it still there
      once it lands, nothing moved under him. Blackmail ended, Airplane
      Mode on, opened again: "Notes" still holds every row.
      3. *Search with no connection.* Still in Airplane Mode, in "Notes",
      "quincunx" typed: row 7 alone, and "Some Results May Not Appear" on
      the line under the list; nothing in the log. "B-160 row 12": row 12
      alone, the words whole, as Gmail matches them. Cancel: the line says
      how old the list is again. All Mailboxes, "quincunx": row 7, once. A
      word in no letter: "No results", the same line under it.
      4. *Letters fetched ahead* (APPENDs to the Inbox, which rings the
      phone signed in on the test account; needs the owner's go). Airplane
      Mode off. The host APPENDs to the Inbox three letters, not read,
      "B-160 ahead N", each with a word of its own in its body only
      ("aheadone", "aheadtwo", "aheadthree"). Refresh: once the page and
      its previews have come, a `UID FETCH <uid> (UID X-GM-MSGID
      RFC822.SIZE BODY.PEEK[]<0.131072>)` for each of the three UIDs the
      host noted, among any for other unread letters of the Inbox not yet
      kept; no STORE, no SELECT between them; `KEPT-AHEAD letters=<n>`
      with n at least 3; the three rows still unread, here and in Gmail on
      the web. A letter tapped while they go opens after the piece on the
      wire, not after the three. Refresh again, nothing new: no `UID
      FETCH` of any of the three UIDs. Blackmail ended, Airplane Mode on,
      opened: each of the three opens from the iPad, `KEPT-LETTER shown`;
      "aheadtwo" searched in the Inbox finds its letter; the first four
      letters of the test account's address typed, nothing after them,
      find no letter for that alone, though every letter there is to it.
      5. *Put back:* Airplane Mode off. The host moves the UIDs it noted,
      and only them, from "Notes" and the Inbox to the Trash (`UID MOVE`),
      and deletes in the Trash only the UIDs that move answered
      (`COPYUID`). Never anything found by subject or Message-ID: a UID not
      noted is left, and written down. Nothing else was written.
- [ ] **B-161, the red number and the banners for new mail.** On the test
      iPad, the test account only, from a build of the `bm-cm-badge`
      worktree (branch `copy-badge`) or of the int it is merged into: the
      first build that asks for notifications, so written down first
      whether Settings > Notifications already lists Blackmail. Nothing is
      composed, sent, moved or deleted in the app. One of the test accounts
      is signed in on the owner's phone and new mail rings it: the steps
      that put a new unread letter in the Inbox are marked, and wait for
      his go; the rest use a letter already in the test Inbox that the
      host marks unread, its UID noted, and marks read again at the end.
      The app's connection log read after each step (its `NEW-MAIL` lines
      say when a check ran, the unread count and how many banners, and
      nothing of a letter), and the count beside Inbox in the folder pane
      written down at each step.
      1. *iOS's question.* The app opened; once the Inbox's list has come,
      iOS's own question about notifications comes over it, with nothing
      of the app's up (if the warning before the app stops opening is up,
      the question comes within half a minute of its OK). Its words
      photographed for the owner (B-161, New words). Allow. The app closed
      and opened again: not asked again.
      2. *The number.* The host marks one Inbox letter unread (`UID STORE
      -FLAGS (\Seen)`); Refresh: the Inbox's count one more. Home: the
      icon's number is the Inbox's count. Back, that letter opened (one
      STORE in the log); Home: the number one less.
      3. *No banner while in front* (puts a new unread letter in the
      test Inbox, which rings the owner's phone: needs the owner's go).
      The app in front on the Inbox; the host APPENDs one letter, unread,
      to INBOX, "B-161 in front": on the list within half a minute, and no
      banner at any time.
      4. *Banners while away* (as 3: needs the owner's go). Home, the iPad
      locked, on charge and Wi-Fi. The host APPENDs two letters, unread,
      to INBOX, a minute apart, UIDs noted: "B-161 away one" with two
      lines of words, and one with no subject. Then wait: iOS chooses when
      the check runs, after fifteen minutes at the soonest and perhaps
      hours later (if the round's tools can attach a debugger to the app,
      `-[BGTaskScheduler _simulateLaunchForTaskWithIdentifier:]` with
      `wtf.uhoh.blackmail.new-mail` starts one at once, as under Xcode; not
      tried). Two banners, each the sender's name, the subject or "(no
      subject)", and the first words; the icon's number the Inbox's unread
      count. Over IMAP the two letters still unread. The log, read later:
      one `NEW-MAIL unread=N banners=2`. Written down how long iOS took.
      5. *The tap.* The newest banner tapped: the app opens on the Inbox,
      that letter in the reading pane, its row highlighted, marked read
      (one STORE); with another folder in front before, the Inbox opened.
      6. *Back after a check.* After 4 the folder pane's Inbox count and
      the icon's number agree within a few seconds of the return (a sweep
      of the counts in the log).
      7. *The safe start.* Over SSH, as the rounds read the app's files:
      `Application Support/Launches/unfinished` reads 0 after a check,
      and after the app has been open half a minute past the Inbox's first
      page or been sent Home; 1 while a launch or a check is under way;
      `Application Support/New Mail/state.json` holds a mark, when he left
      and when a check ran, and nothing of a letter.
      8. *Notifications off.* Settings > Notifications > Blackmail, Allow
      Notifications off; Home: the number gone, and no `NEW-MAIL` line
      after it in the log. Put back on.
      9. *Only on charge and Wi-Fi* (the second commit). The app at Home,
      the iPad unplugged; the host marks the letter of 2 unread again.
      An hour or more on battery: the icon's number as it was, and the
      log with no `NEW-MAIL unread=` line in that time, only `NEW-MAIL
      held not-charging-on-wifi` if iOS ran a check. Plugged in, on
      Wi-Fi: at the next check (`NEW-MAIL unread=N`), the number one
      more. Written down how long iOS took either way.
      10. *Put back:* the letter of 2 marked read again; the UIDs the host
      noted in 3 and 4, and only them, moved to the Trash, answered by
      COPYUID. Nothing else was written.
- [ ] **B-162, his Contacts in To, Cc and Bcc.** On the test iPad, the
      test account only, from a build of the `bm-cm-contacts` worktree
      (branch `copy-contacts`) or of the int it is merged into. Nothing is
      sent, saved or deleted in the app: each letter begun is closed with
      Cancel and Delete Draft, which keeps nothing. Screenshots of the
      sheet name no one but the made-up cards below.
      0. *Before.* Settings > Privacy & Security > Contacts: if Blackmail
      is listed, its question has been answered and 1 cannot be seen;
      write down the switch, and ask the owner before Reset Location &
      Privacy, which asks every app again. In the Contacts app, by hand,
      three cards: "Sam Carlo" (first Sam, last Carlo) with
      sam@example.com and scarlo@example.org, in that order; "Pat Núñez"
      with pat@example.net; "Jo Pine" with no address. The host APPENDs
      two letters, read (`\Seen`), to the label "Notes", never the Inbox,
      each with a new Message-ID and naming nobody on the account, one
      From "Sammy <sam@example.com>" and one From "Sales
      <sales@example.org>", and notes their UIDs from APPENDUID. In the
      app, "Notes" opened once so their rows are listed, then the Inbox.
      1. *Asked as he types, not before.* Blackmail ended and opened
      again: no question at launch. New Message: To tapped, no question
      and no list. "s" typed: iOS's question over the sheet, at once,
      with the line "As you type, Blackmail suggests people from your
      Contacts." Written down: its title and buttons as the iPad shows
      them. OK (Allow) tapped: without another key, the list under To
      has Sam Carlo's two rows among its matches, each "Sam Carlo" with
      its address under it.
      2. *What matches.* "a" typed after the "s": sam@example.com and
      scarlo@example.org, both "Sam Carlo", ahead of "Sales"; nobody
      named "Sammy". To emptied, then "car": Sam Carlo's two rows; "arlo":
      neither; "nun": Pat Núñez; "scar": scarlo@example.org alone; "jo":
      no Jo Pine. Cc/Bcc tapped, "car" in Cc: the same two rows.
      3. *A pick.* In To, "sa", then sam@example.com tapped: a bubble
      "Sam Carlo", the list closed. "sa" again: scarlo@example.org ("Sam
      Carlo"), then "Sales"; no sam@example.com. Cancel, Delete Draft.
      4. *Asked once.* The app to the background and back, New Message,
      "c" in To: no question. Ended and opened again, the same.
      5. *The share sheet.* Blackmail opened once after 1, then Safari on
      example.com, Share, Blackmail: no question; "car" in To: Sam
      Carlo's two rows. Cancel.
      6. *A no.* Settings > Privacy & Security > Contacts, Blackmail off.
      Back in Blackmail, New Message, "car" in To: no Sam Carlo, no
      question. Cancel. The share sheet from Safari, "car": no Sam Carlo.
      Cancel. Blackmail's switch back on: its next return offers him
      again.
      The people he has written to coming before his Contacts is not
      looked for here, as it needs a letter sent; the host pins it
      (`ContactSuggestionsTests`).
      7. *Put back:* the three cards deleted in Contacts; Blackmail's
      Contacts switch as written down in 0 (off if it was never asked).
      The host moves the UIDs it noted, and only them, from "Notes" to
      the Trash (`UID MOVE`), and deletes in the Trash only the UIDs that
      move answered (`COPYUID`); a UID not noted is left, and written
      down.
- [ ] **B-163, the people at the top of the share sheet.** On the test
      iPad (iPadOS 16.5.1), the test account only, from a build of the
      `bm-cm-circle` worktree (branch `copy-circle`) or of the int it is
      merged into, packaged with the share extension
      (`BLACKMAIL_SHARE_EXT=1`) and installed so that iOS registers it, as
      for the share sheet's checks before. A stands for the account's
      address; letters go only to A with `+b163` before the @ ("A+b163"),
      or to A alone, with subjects beginning "B-163", so nothing leaves the
      account. Settings > Siri & Search, "Show When Sharing": on, as it
      comes from the factory; written down as found and left so. Contacts,
      My Card: whether it lists A or A+b163, written down as found and left
      so; iOS takes from it who the owner is. In Blackmail's Settings,
      A+b163 added under the account's addresses with "Add Another Email…",
      and Save, as his second address will be at the install (B-076): its
      circle is the one this is for. The logs: for the app's letters, the
      app's connection log; for a share, the newest `blackmail-send-*.txt`
      in the share extension's own tmp, from its last `SHARE-BEGIN` on, as
      the share checks before read it. A share that ends in Cancel writes
      no transcript, so what it did is read on the screen alone. No
      fixture is needed: nothing is read but the share sheet.
      1. *Before* (no send): Safari, any page, Share. The row of people at
      the top written down: none with Blackmail's badge. Close it.
      2. *Letters that go* (sends, test account only, needs the owner's
      go): from the app's composer, three letters to A+b163, "B-163 app 1"
      to "B-163 app 3": after each, in the app's log, one
      `SHARE-SUGGESTION people=1`, then `SHARE-SUGGESTION donated`; an
      `error=` line written down with its number. Then, from Safari's
      share sheet by Blackmail's icon, three shares of a page to A+b163,
      the subject typed over the page's title as "B-163 share 1" to
      "B-163 share 3": each one's transcript holds, after the letter's
      250, one `SHARE-SUGGESTION people=1`, and no `SHARE-SUGGESTION
      opened` line. A `donated` or `error=` line after it is written down
      if it is there; it may come after the transcript was written.
      3. *A letter to the account alone* (sends, test account only, needs
      the owner's go): from the app, one letter to A alone, "B-163 self".
      It goes; no `SHARE-SUGGESTION` line for it in the app's log.
      4. *A share that does not go, then goes* (sends, test account only,
      needs the owner's go), on a build whose share sheet stays up with
      its error when there is no connection (B-036); skipped on one where
      such a share waits in the Outbox (B-153), since the app sends it
      later: Airplane Mode on; Safari, a page, Share, Blackmail's icon, To
      A+b163, Subject "B-163 offline", Send: the sheet stays with the
      error. Airplane Mode off, Send again: it goes. Its transcript, from
      its `SHARE-BEGIN` on, holds one `SHARE-SUGGESTION people=1`, after
      the letter's 250: none for the Send that did not go.
      5. *The circle* (no send): Safari, a page, Share. Written down: the
      top row, and whether A+b163 is in it with Blackmail's badge, under
      its address, as no name was given, and where. Not there: close the
      sheet, open and leave Blackmail, wait a minute, and look again,
      twice at most; written down either way, beside what My Card lists.
      A, alone, with Blackmail's badge is never there.
      6. *Opened from it* (no send), where it is there: tap it. Blackmail's
      sheet comes up with one bubble in To, A+b163; the page's title in
      Subject; the caret in the body (B-120). Cancel: the sheet goes with
      no question.
      7. *Opened from it, and sent* (sends, test account only, needs the
      owner's go): tap it again; Subject typed over as "B-163 circle";
      Send: it goes. Its transcript, from its `SHARE-BEGIN` on:
      `SHARE-SUGGESTION opened people=1`, `RCPT TO:<A+b163>`, then one
      `SHARE-SUGGESTION people=1`.
      8. *A YouTube video from it* (no send): the YouTube app, a video,
      Share, and the system's share sheet (under More if the YouTube app's
      own panel comes first): whether the A+b163 circle is in its row
      with Blackmail's badge, written down. Where it is: tap it. To has
      A+b163; Subject has the video's title at once or within a second or
      two (B-126); where the caret is once it has, written down, and
      whether the title was there from the sheet's first frame. The body,
      at its start, is where Mail's would be. Cancel: no question.
      9. *Blackmail's icon* (no send): Safari, a page, Share, Blackmail's
      icon: To empty and the caret in it, as before. Cancel.
      10. *Put back:* the "B-163" letters in the Inbox and in Sent Mail
      moved to the Trash in the app, with Edit, then the Edit bar's red
      button, "Delete" on a build without Mail's words and "Trash" on one
      with them, and nothing else; A+b163 taken off the account's
      addresses in Settings, and Save; Blackmail in front on the Inbox.
      The circles told stay on the test iPad; written down. Nothing was
      sent but steps 2, 3, 4 and 7, to the test account itself.
      No send of its own: on the next five-photo share check, the
      `SHARE-SEND` lines' least memory compared with B-109's 160 MB, which
      matched B-070's, as the extension now loads Intents too.
- [ ] **B-165, a held draft's Cancel asks Save Draft.** On the test iPad,
      the test account only, from a build of the `bm-helddraft` worktree
      (branch `fix-helddraft`) or of the int it is merged into. Nothing is
      sent: no Send is tapped in any step, and the letter is a draft
      throughout. The files and the log as in B-057's check (`Local
      Drafts/<UUID>/letter.json`; the connection log, five taps on the line
      under the list).
      1. *A held draft.* Airplane Mode on (guarded). A new letter to
         carlo+b165@ (the round's carlo+TAG@ address), subject "B-165
         held", Cancel, Save Draft: Drafts lists it under "On this iPad
         only". End the app. In its `letter.json` write three tries the
         app did not live through, as in B-057's step 6:
         `sed -i 's/"format":1/"format":1,"autoAttempts":3/' letter.json`
         (BSD sed wants `-i ''`). Then `grep -o '"autoAttempts":3'
         letter.json` prints it once; printing nothing, the edit did not
         land, and online the pass would save the draft to Gmail by
         itself: stop, and write it again.
      2. *Online.* Airplane Mode off, open the app: no `APPEND` and no
         `MAIL FROM` in the log, which has `DRAFT-HELD unfinished-tries=3`;
         the row in Drafts reads "On this iPad only", then "Not saved to
         Gmail automatically. Open it, tap Cancel, then Save Draft."
      3. *Cancel untouched.* Tap the row: the composer opens on it. Tap
         Cancel without touching anything: the sheet comes, Save Draft and
         Delete Draft, as for a changed letter. Its own Cancel (a tap
         outside it): the sheet goes and the letter is still open. On int17
         (939ad5a) the composer closed at once with nothing asked (B-165).
      4. *Save Draft.* Drafts at its top. Cancel again, Save Draft: the
         composer closes; the log has one `APPEND` to `"[Gmail]/Drafts"`,
         and no `MAIL FROM`, `RCPT TO` or `DATA`; the row loses "On this
         iPad only" and its held line, and stays the first row, in sight,
         Drafts still at its top, within a few seconds and with no
         Refresh (on int18 it went one row above the top of the pane,
         B-165, Found on the test iPad 2026-10-27); `letter.json` is gone
         from `Local Drafts`; one copy in Drafts on the web.
      5. *Put back.* Open it from Drafts, type a word, Cancel, Delete
         Draft: no copy in Drafts, in the app or on the web. Nothing was
         sent.
- [ ] **B-166, the text size and Bold Text as the iPad sets them.** On the
      test iPad, the test account only, from a build of the
      `bm-cm-textsize` worktree (branch `copy-textsize`) or of the int it
      is merged into. Nothing is typed, sent, saved, moved or deleted in
      the app: every composer is opened untouched and closed with Cancel,
      which asks nothing for an untouched letter (B-069). The iPad's own
      settings are changed and put back. The host APPENDs, read
      (`\Seen`), to the label "Notes", never the Inbox, five letters, each
      from another address with a new Message-ID of its own and naming
      none on the account, and notes each UID from its APPENDUID,
      stopping if one has none: (a) "B-166 long", from "Bartholomew
      Example-Longname", with one Cc, a small PDF, "B-166 plan.pdf", and a
      text file, "B-166 notes.txt", and three paragraphs of plain text,
      its Date and its arrival on the Wednesday of the last six days, so
      that its row reads "Wednesday"; (b) "B-166 html", in HTML, a
      paragraph with no size of its own and one in `font-size:13px`;
      (c) "B-166 stack" and (d) "Re: B-166 stack", a day after it, naming
      (c)'s Message-ID in In-Reply-To and References, one conversation;
      (e) "B-166 answered", APPENDed with `\Seen \Answered`, so that its
      row has the grey reply arrow in its gutter.
      Three panes and Organize by Thread on, unless a step says otherwise;
      a full-size screenshot of each screen named.
      1. *Large, as before.* Settings, Display & Brightness, Text Size at
         its middle step (Large); Accessibility, Display & Text Size, Bold
         Text off, and Larger Text with Larger Accessibility Sizes off. In
         the app: "Notes" with (a) open, its row highlighted; New Message,
         then Cancel; Reply All on (a), then Cancel. The same three
         screens on the int18 build (26740c2), taken first: the same to
         the pixel but for the clock.
      2. *The largest of the seven, while the app is open.* With (a) open
         and "Notes" scrolled so its row is in sight a few rows down,
         leave the app; Text Size dragged to its right end; back in the
         app: the rows taller, about 130 points, their words larger, the
         same rows in sight where they were, (a)'s highlighted, its
         "Wednesday" whole; long names cut with "…", never a date. The
         Mailboxes: names and counts larger, rows taller, "Notes"
         highlighted; every folder's name whole, "Important" and the
         account's longest label among them, on a second line where it
         needs one, its row as tall as its two lines, nothing over the
         next row. The header's names, subject and date larger, its two
         files' rows 44 points or taller; (a)'s words larger. The bars'
         titles and buttons, the calendar, the search field, its two
         buttons once tapped (then Cancel) and the line under the list
         exactly as in 1. Nothing cut anywhere: no word clipped at its top
         or its foot, nothing over anything.
      3. *Two panes.* The view button: the list's bar with the view
         button, "< Mailboxes", the calendar, "Notes" and Edit as in 1;
         the rows as in 2. Back to three panes.
      4. *Edit mode.* In "Notes", Edit: the circles larger than in 1, every
         date whole, "Wednesday" too, the names giving way. Cancel. The
         same in two panes, then three again.
      5. *The letters.* (b): the paragraph with no size larger than in 1,
         the 13-pixel one as in 1. (d)'s row: the conversation's stack,
         its lines and its open letter larger.
      6. *The composer.* New Message: "To:", "Cc/Bcc" and "Subject:"
         whole, their lines taller than 44 points, Photo Library and Attach
         File larger; Cancel. Reply All on (a): a bubble in To and one in
         Cc, each as tall as its name, "Subject:" whole; Cancel. Reply All
         again, left open; leave the app, Text Size one step down, back:
         the open composer's lines and words at the new size, the bubbles
         with them; Cancel. Text Size at its right end again.
      7. *Bold Text, while the app is open.* With (a) open, Bold Text on,
         back in the app: the rows' names, subjects and previews, the
         Mailboxes, the header and (a)'s words bolder; the bars as they
         were (B-166, Not changed). Bold Text off: as in 2.
      8. *The largest accessibility size.* Larger Text, Larger Accessibility
         Sizes on, the slider at its right end, back in the app: each row's
         date, and on (d)'s row the blue chevron, on a line of their own
         under the names, at its right end; nothing over anything; about two
         rows to the pane. (e)'s row: its grey arrow whole in the gutter,
         inside the row's left edge and clear of the names. The Mailboxes as
         UIKit lays them out at this size, each name after its own icon,
         whole on as many lines as it takes, the Inbox's too, each row as
         tall as its name, nothing cut and nothing over the next row. The
         header and (a)'s words larger again. (d)'s row: on the
         conversation's lines each name on a line of its own, its date on the
         line under it at its left, a closed letter's first words under that;
         nothing past the pane's right edge, and the pane not scrolling
         sideways. Back to (a): the pane's folder button, the Move sheet's
         folders as the Mailboxes', each whole; Cancel, nothing moved. The
         calendar: Go to Date's words and its two buttons as in 1; Cancel.
         New Message: its lines as tall as their words; Cancel. Two panes,
         then three.
      9. *For Blackmail alone.* Larger Accessibility Sizes off, Text Size
         at its middle step. Accessibility, Per-App Settings, Add App,
         Blackmail, Larger Text for it at the right end of the seven:
         Blackmail as in 2, Settings itself at Large. Blackmail's entry
         then taken off the list.
      10. *The share sheet.* Text Size at its right end. Safari, any page,
         Share, Blackmail: "To:", "Cc/Bcc" and "Subject:" whole, the lines
         taller, the link in the body larger; Cancel. Nothing is sent.
      11. *His size.* Once his iPad's Display & Text Size and Per-App
         Settings are read (the owner's "His iPad's own settings"), 2, 4,
         6 and 8's screens at his size and Bold Text: nothing cut.
      12. *Not on this iPad.* On any iPadOS 18 device with Mail and a
         Gmail account, never his: Mail's list at the largest accessibility
         size, where its date goes; whether Mail's bars keep their size at
         the largest of the seven; whether Mail's search field, the word
         "Search" in it and its scope buttons grow, at the largest of the
         seven and the largest accessibility size; Mail's Mailboxes with a
         long name at both; whether (b)'s 13-pixel paragraph grows in
         Mail; Mail with Bold Text on. The test iPad has no Mail (B-028).
      13. *Put back:* Text Size at its middle step, Bold Text off, Larger
         Accessibility Sizes off, no Per-App entry for Blackmail; "Notes"
         left, the Inbox at its top. The host moves the UIDs it noted, and
         only them, from "Notes" to the Trash (`UID MOVE`), and deletes in
         the Trash only the UIDs that move answered (`COPYUID`); "Notes"
         itself stays. Never anything found by subject or Message-ID.
         Nothing was sent or saved.
- [ ] **B-167, Mail's options in Settings.** On the test iPad, the test
      account only, from a build of the `bm-cm-mailsettings` worktree
      (branch `copy-mailsettings`) or of the int it is merged into.
      Nothing is sent: no letter is written in any step. Screenshots name
      no one but the made-up letters below. The connection log as in
      B-057's check.
      0. *Before.* The host APPENDs five letters, read (`\Seen`), to the
      label "Notes", never the Inbox, each with a new Message-ID, From
      "Pat Example <pat@example.net>", naming nobody on the account, their
      Dates a minute apart, subjects "B-167 one" (the oldest) to "B-167
      five", and notes their UIDs from APPENDUID. In the app, "Notes"
      opened: five rows, "five" at the top. Settings' Mail part as the
      factory has it (step 1); if not, written down and set so first.
      1. *The page* (no write). Settings, scrolled to its foot: under the
      password's lines, "Mail" and "As in Settings > Apps > Mail. Set them
      as they are set for Mail on this iPad."; MOVE DISCARDED MESSAGES
      INTO:, Deleted Mailbox ticked, Archive Mailbox, and "In Mail: Mail
      Accounts > Gmail > Account > Advanced."; MESSAGE LIST: Preview "2
      Lines" in grey with "Blackmail always shows 2 lines." under it, Show
      To/Cc Labels grey and off, Swipe Options with a chevron, Delete or
      Move Message Action "View Next Message" with a chevron; MESSAGES: Ask
      Before Deleting grey and off (live on a build with B-168), Privacy
      Protection with a chevron; THREADING: Organize by Thread and Complete
      Threads on, Collapse Read Messages grey and on, Most Recent Message on
      Top grey and off, and Apple's line under them. Screenshots of the
      part, in two panes and three; nothing cut. A tap on each grey row and
      its switch: nothing moves. Privacy Protection tapped: a page with
      Block All Remote Content, grey and off, and its lines. Back.
      2. *Swipe Options* (no write). Tapped: a page "Swipe Options", Swipe
      Left "Flag", Swipe Right "Mark as Read". Swipe Left: a page of None,
      Mark as Read, Flag, Move Message and Archive, Flag ticked; None
      tapped, the tick moves; Back: "None" after Swipe Left. Settings'
      Cancel. In Notes a slow drag to the left on "B-167 four": More and
      Trash, no Flag; a tap elsewhere, nothing done. Settings again, Swipe
      Right to Move Message, Cancel: a drag to the right on "B-167 four"
      shows Move; tapped, the folder sheet; its Cancel, nothing moved.
      Both set back, Flag and Mark as Read: the drags as before.
      3. *Delete or Move Message Action.* Tapped: View Next Message ticked
      and "Don’t Select a Message", its apostrophe written down. The
      second tapped; Back: it is the row's value. Cancel. "B-167 one"
      opened from its row, the pane's Delete: the pane empties, "No
      message selected", Delete grey until the server has answered, and
      no letter opens; the log has one MOVE to the Trash. Settings, View
      Next Message again, Cancel. "B-167 four" opened, Delete: "B-167
      three", the row below, opens in the pane, highlighted (B-158).
      4. *Archive Mailbox.* Settings, Archive Mailbox tapped: the tick
      moves, and with Settings still up the pane's bin, on "B-167 three",
      is an archive box; Cancel. Edit in Notes: the third button reads
      "Archive". "B-167 five" ticked, Archive: the row goes, "Moving…"
      under the list, the log one MOVE to "[Gmail]/All Mail", and over
      IMAP the letter is in All Mail and not in Notes. The pane's archive
      box on "B-167 three": its row goes, "B-167 two" opens, and a MOVE to
      All Mail. A slow drag to the left on "B-167 two": Archive in purple
      at the edge, Flag, More; a tap elsewhere. Drafts: Edit reads
      "Trash"; Cancel. Trash: Edit reads "Delete", the pane's button a
      bin on a letter there; Cancel. Shake: "Undo Move", Cancel. Settings,
      Swipe Right set to Archive, Cancel: in the Trash a slow drag to the
      right on "B-167 four" shows nothing, and to the left Delete, Flag,
      More, no Archive; in Notes a drag to the right on "B-167 two" shows
      Archive; a tap elsewhere each time. From Notes, All Mailboxes,
      "B-167" searched for, Edit: the bar reads "Archive". "B-167 four",
      the Trash's hit, and a hit of "B-167 two" ticked, Archive: "Delete
      Message?", "This message will be deleted immediately. ..." if the
      second hit is the one from Notes, "Delete 2 Messages?" and "1 of
      them is in the Trash ..." if it is the one from All Mail, written
      down which; Cancel, nothing moves, no write in the log. Swipe Right
      set back to Mark as Read.
      5. *Organize by Thread.* Settings, Organize by Thread off: the list
      behind the sheet drawn again at once, a conversation of the Inbox's
      in rows of its own; on again, grouped again.
      6. *Put back.* Settings as the factory has it: Deleted Mailbox, View
      Next Message, Flag and Mark as Read, Organize by Thread and Complete
      Threads on. The host finds each of the five Message-IDs in Notes,
      All Mail and the Trash (`UID SEARCH HEADER Message-ID`), moves those
      outside the Trash to the Trash (`UID MOVE`), and deletes in the
      Trash only the UIDs that move answered (`COPYUID`) and those it
      found there; any other UID is left, and written down. Nothing was
      sent.
- [ ] **B-168, Mail's Block All Remote Content and Ask Before Deleting.**
      On the test iPad, the test account only, from a build of the int the
      `bm-cm-remoteask` worktree (branch `copy-remoteask`) is merged into
      with B-167's Settings rows, which set the two options; a build of
      this branch alone has no row for them, and the check waits for the
      int. Nothing is composed, sent or saved as a draft, and every Trash
      goes onto the host's letters alone. The host makes eleven letters, each
      from another address, with a new Message-ID of its own and naming
      none on the account, and APPENDs them read (`\Seen`) to the label
      "Notes", never the Inbox, each with its Date as its internal date;
      it notes each UID from its APPENDUID, and stops if one has none. Two
      HTML letters whose pictures from the web are on a web server whose
      access log the host reads, each at a path of its own made for this
      round and written nowhere else, a picture by `<img src>` and one by
      a `style` `url()`: "B-168 news", which also carries a picture of its
      own by `cid:` and a link, and a conversation of two, "B-168 talk"
      (a) and (b), (b)'s References naming (a), each with its own two
      paths, (b) with a picture of its own by `cid:` too. Then six plain
      letters, "B-168 bin 1" to "B-168 bin 6", and a conversation of two
      plain ones, "B-168 pair" (a) and (b). The list goes by UID, the
      last APPENDed on top. Organize by Thread on, three panes. In
      Blackmail's Settings both options written down as found, then set
      as each step says. A screen recording through each step, the app's
      connection log read after each, and the server's log, from the
      step's first second, for the round's paths.
      1. *Off, as it comes.* Both off. "Notes", "B-168 news" tapped: its
      pictures from the web there, no line over it; the server's log has
      both of its paths. Nothing else changed from before B-168.
      2. *Held back.* Block All Remote Content on; "B-168 bin 1" tapped,
      then "B-168 news" again: at its top "Message contains unloaded
      images." with "Load All Images" on its right, a rule under them;
      its picture by `cid:` drawn, the two from the web blank; the
      server's log has neither path from this step. The line's look,
      its colours and where the words wrap written down.
      3. *On paper.* Reply, Print: AirPrint's preview has the picture of
      its own and not the two from the web, and no line. Cancel the
      panel; still nothing in the server's log.
      4. *Load All Images.* Tapped: the letter drawn again from its top
      with no line and both pictures; the server's log has both paths
      now, once each. The link in it still opens Safari.
      5. *A conversation.* "B-168 talk" tapped: (b) open with its line,
      (a) closed above; (a)'s line tapped: it opens with its own line;
      nothing for either in the server's log. "Load All Images" on (b):
      (b)'s pictures come, its own by `cid:` still drawn, (b)'s line goes,
      (a) as it was, its line and its blanks; the server's log has (b)'s
      two paths and not (a)'s. Close (a) and open it again: still held
      back. Then "B-168 bin 1" tapped, and "B-168 talk" again: (a) and
      (b) both held back, their lines back. Settings, Block All Remote
      Content off, Save; if the pane still shows "B-168 talk", "Load All
      Images" on (b): its pictures come and its line goes (if the pane
      moved on, written down).
      Block All Remote Content off.
      6. *Ask Before Deleting, the pane.* On. "B-168 bin 1" tapped,
      Delete: a sheet from the Delete button, "Trash Message" in red;
      a tap outside it: the sheet goes, the letter stays in the pane and
      on the list, no `UID MOVE` in the log. Delete again, "Trash
      Message": the letter goes to the Trash, the next opens as B-158
      has it, one `UID MOVE`.
      7. *The Edit bar.* Edit, "B-168 bin 2" and "B-168 bin 3" ticked,
      Trash: a sheet from it, "Trash 2 Messages"; a tap outside: the
      ticks stay. Trash again, "Trash 2 Messages": both go, Edit mode
      ends.
      8. *A drag.* A slow drag to the left on "B-168 bin 4": More, Flag
      and Trash. Trash tapped: the row slides back, and a sheet over
      the row, "Trash Message"; a tap outside: nothing goes. Then a full
      drag to the left on it: it goes at once, no sheet. On "B-168 bin
      5", a slow drag, More, "Trash Message": a sheet over the row,
      "Trash Message"; tapped, it goes. On "B-168 pair", a slow drag,
      Trash: "Trash Messages"; tapped, both letters go. If a full drag
      in this step put up a sheet, written down (B-168's "Not seen").
      9. *Inside Trash.* The Trash, "B-168 bin 1" there, Delete: the
      erase question as before, "Delete Message?", and no other sheet;
      Cancel. Ask Before Deleting off, then "B-168 bin 6" in "Notes",
      Delete: nothing asked, it goes.
      10. *Put back:* both options as written down at the start; "Notes"
      left, the Inbox at its top. The host takes out of the Trash and out
      of "Notes" only the letters with the Message-IDs it made, which
      nothing else on the account has, and deletes them there, and
      empties the round's paths on the web server. Nothing was sent.
      Not on the iPad: an Archive from a drag, with no account set to
      discard into the Archive (`SwipeOptions.his`), his letters from
      Sent Mail held back in an Inbox conversation, and a list WebKit
      could not make (host tests alone); nor Mail's own, whether its slow
      drag's Trash asks and Ask Before Deleting's factory value, which
      need Mail on an iOS 18 device (B-168's "Not seen"); his own value
      is read off his iPad on the day.
- [ ] **B-169, a letter drawn as Mail draws it in Dark Mode.** On the
      test iPad, the test account only, from a build of the
      `bm-cm-darkpics` worktree (branch `copy-darkpics`) or of the int it
      is merged into. Nothing is composed, sent, saved, moved or deleted in
      the app, and nothing is printed on paper: the Print panel's preview
      only. The host makes the letters, each from another address, with a
      new Message-ID of its own and naming none on the account, and APPENDs
      them, read (`\Seen`), to the label "Notes", never the Inbox, each with
      its Date as its internal date; it notes each UID from its APPENDUID,
      and stops if one has none. The pictures from the web are on a host
      the round controls, by https, each about 600 by 300 px, so loading
      them tells no one else. Three panes unless a step says two;
      full-size screenshots, colours read from them.
      1. *The letters:* (a) "B-169 inverted", HTML with no scheme and no
         picture from the web: dark words on white, a picture by `cid:`,
         a link, a `<blockquote type="cite">`; (b) "B-169 web picture", the
         same with one picture from the web among the words; (c) "B-169
         pixel", (a) with a picture from the web 1 by 1 px, its width and
         height written; (d) "B-169 light only", (a) with `<meta
         name="color-scheme" content="light only">`; (e) "B-169 dark
         ready", a newsletter that declares `light dark` by `<meta>` and on
         `:root`, white cards with dark words, and in its head `@media
         (prefers-color-scheme: dark)` rules making the cards #1c1c1e and
         the words #f2f2f7, a link coloured for the dark; (f) "B-169
         background", (a) with `<body background="cid:…">` of a pale
         picture; (g) "B-169 stack" with (b)'s body and (h) "Re: B-169
         stack", a day later, (a)'s body, its In-Reply-To and References
         naming (g), so the two are one conversation; (i) "B-169 own
         body", `<meta name="color-scheme" content="light dark">`, nothing
         in its head, `<body style="background-color:#ffffff">`, its words
         `<p style="color:#333333">`; (j) "B-169 own class", declaring
         `light dark` by `<meta>`, `<body class="body" bgcolor="#ffffff"
         text="#333333">`, and in its head `@media (prefers-color-scheme:
         dark) { .body { background: #1c1c1e !important; } .body p {
         color: #f2f2f7 !important; } }`.
      2. *Alone:* "Notes", then each letter. (a) and (c) as before B-169:
         black, white words, the picture of its own as drawn, the bar
         violet; (b), (d) and (f) white from under the header across the
         pane and as tall as the letter, black words, the pictures as they
         are, the bar Mail's light violet, about rgb(88, 86, 214), the link
         blue, and the pane black below the letter; (e) its cards #1c1c1e
         with words #f2f2f7, on the pane's black, its link in its own
         colour; (i) white behind its words, which are #333333, the
         pane's margin black around the white; (j) #1c1c1e behind words
         #f2f2f7, not white. In each, the header and the list black as
         ever. Then two panes: the same.
      3. *The tap:* from (a) to (b) and back, recorded at 60 frames a
         second: black under the header from the tap until the letter, as
         B-149 has it, then the white of (b); no frame of (a)'s black under
         (b)'s header after (b) is drawn.
      4. *In a stack:* "Re: B-169 stack", both letters opened by their
         lines: (g)'s body white, (h)'s black with white words, their lines
         and the space between dark; (g) closed and opened again, white
         again.
      5. *Print:* on (b) and on (e), Reply, then Print: the preview's paper
         white with the letter's own light colours, as before B-169; (e)'s
         cards white with dark words, not its dark ones. Cancel.
      6. *Put back:* "Notes" left, the Inbox at its top. The host moves the
         UIDs it noted, and only them, from "Notes" to the Trash (`UID
         MOVE`), and deletes in the Trash only the UIDs that move answered
         (`COPYUID`); "Notes" itself stays. Never anything found by subject
         or Message-ID: a UID not noted is left, and written down. Nothing
         else was written.
      If Mail is back on the test iPad (B-028), in Dark Mode, or an iPad
      with iPadOS 18 and Mail is at hand: (a) to (f), (i) and (j) there,
      how each is drawn and where Mail's white ends around (b) and (i),
      written down beside 2's.

- [ ] **B-170, every file in the letter's body.** On the test iPad, the test
      account only, from a build of the `bm-cm-inlinefiles` worktree (branch
      `copy-inlinefiles`) or of the int it is merged into. Nothing is
      composed, sent, saved, moved or deleted in the app: one of the test
      accounts is signed in on the owner's phone and new mail rings it. The
      host makes the letters, each from another address, with a new
      Message-ID of its own and naming none on the account, and APPENDs
      them, read (`\Seen`) but for "B-170 thread 1", to the label "Notes",
      never the Inbox, each with its Date as its internal date; it notes
      each UID from its APPENDUID, and stops if one has none. Three panes
      unless a step says two; the app's connection log read after each step;
      the screen recorded at 60 frames a second for 2, 6 and 8, and a
      screenshot of each letter as it is drawn.
      1. *The letters,* "B-170 pdf", "B-170 photo", "B-170 among", "B-170
      before", "B-170 plain", "B-170 only", "B-170 large", "B-170 heic",
      "B-170 inline", "B-170 thread 1" and "B-170 thread 2": pdf, an HTML
      part and a PDF of about 300 KB attached after it; photo, an HTML part,
      then a JPEG of about 2 MB from a camera attached with no `Content-ID`,
      then a PDF; among, Apple Mail's shape for a PDF among the words, as
      B-148's check made it; before, a PDF and then an HTML part; plain,
      plain words, then a PDF and a JPEG; only, a PDF and no words; large,
      an HTML part, three JPEGs of about 2 MB each and a PDF of about 300
      KB, over 5 MB, so it is opened in part; heic, an HTML part and a HEIC
      photo attached; inline, plain words and then a JPEG sent inline with a
      `Content-ID` that the words do not name; thread 1 and 2, one
      conversation, the second's References naming the first, each an HTML
      part, a JPEG of about 200 KB attached with no `Content-ID` (part 2 of
      both, a different picture in each) and a PDF named for its letter,
      "one.pdf" and "two.pdf"; thread 1 APPENDed unread, so it opens with
      the newest, as Mail opens the unread.
      2. *PDF:* "Notes" opened, "B-170 pdf" tapped. From the first frame
      after the tap the header ends at the date and its lower rule, no file
      in it, the rule at the same height in every frame to the letter
      drawn: the height written down. Under the words a tile: a rounded
      box with a hairline border, about 160 by 120 pt, a page marked "PDF",
      the name and the size in small grey type, its last line empty.
      Written down: its colours on the dark pane, and whether its lines
      read. Settings, Display & Brightness, Text Size, at its largest, and
      back to the app: the tile as it was, its lines whole, the same size;
      the Text Size back to where it was. The tile
      tapped: it dims and its last line says "Loading…" until the PDF is in
      Quick Look; Done: the tile as it was.
      3. *Photo:* "B-170 photo": the photo under the words, as wide as the
      letter at most, and no tile for it; the PDF's tile under it. The
      photo tapped: Quick Look; Done. A finger held on the photo half a
      second: the menu Quick Look, Save Image, Save to Files, Share, Copy;
      a tap outside it. A finger held on the PDF's tile: Quick Look, Save
      to Files, Share, Copy, and the lift opens nothing; Save to Files:
      Files' sheet, Cancel in it; Copy: nothing over the pane. Written
      down if WebKit's own menu or a preview of the link comes first; the
      tile held and moved: no drag of it lifts.
      4. *Among and before:* "B-170 among": the words before, the PDF's
      tile, the words after, "Sent from my iPad". "B-170 before": the tile
      above the words.
      5. *Plain and only:* "B-170 plain": its words light on the black,
      then the PDF's tile, light on the black too, and the photo. "B-170
      only": the PDF's tile alone, and no "This message has no text.".
      6. *Large:* "B-170 large" tapped: the log has its BODYSTRUCTURE
      first, then its words, then a FETCH of each photo by its section as
      the pane draws it, and not the PDF; the photos come in one after
      another, in the recording; the PDF's tile says "Tap to Download".
      Tapped: "Loading…", the PDF's FETCH in the log, Quick Look; Done:
      "Tap to Download" again.
      7. *HEIC and inline:* "B-170 heic": a tile marked "HEIC", not the
      photo; tapped, Quick Look shows the photo; held, the menu has Save
      Image. "B-170 inline": the photo under the words, once; tapped,
      Quick Look.
      8. *Thread:* the conversation "B-170 thread", tapped as soon as the
      list has it: both letters open, each with its photo, its own, under
      its words, "one.pdf" under the first letter's and "two.pdf" under the
      second's; none of the photos blank, in the recording and a
      screenshot. Each tile tapped opens its own.
      9. *Print:* "B-170 photo", the Reply button, Print: in the preview,
      the header with no file line, and in the body the photo and the
      PDF's tile, in the letter's own colours on white, no "Tap to
      Download". Cancel: nothing printed.
      10. *Two panes,* 2 and 3 again, then three panes.
      11. *Put back:* "Notes" left, the Inbox at its top. The host moves
      the UIDs it noted, and only them, from "Notes" to the Trash, and
      deletes in the Trash only the UIDs that move answered. Nothing else
      was written.
- [ ] **B-171, Markup and Reply on a photo held.** On the test iPad, the
      test account only, from a build of the `bm-cm-markup` worktree
      (branch `copy-markup`) or of the int it is merged into. Nothing is
      sent and nothing is saved to Drafts: no Send is tapped in any step,
      and each reply begun is closed with Cancel and Delete Draft, which
      keeps nothing. The host makes the letters, each from another
      address, with a new Message-ID of its own and naming none on the
      account, and APPENDs them, read (`\Seen`), to the label "Notes",
      never the Inbox, noting each UID from its APPENDUID; it stops if one
      has none. Three panes; the connection log read after each step; the
      app's files read over SSH as the rounds read them.
      0. *The letters:* "B-171 photo", an HTML letter with words, a JPEG
      photo of about 1 MB shown among them by `cid:` as an iPhone sends
      one, a picture from the web, and the account's signature logo by
      `cid:`; "B-171 heic", the same with a HEIC photo by `cid:` in place
      of the JPEG; and "B-171 thread 1" and "B-171 thread 2", one
      conversation from two made-up senders, the first with a photo by
      `cid:`. "Notes" opened in the app.
      1. *The menu:* "B-171 photo" opened, a finger held on the photo:
      Quick Look, Markup and Reply, Save Image, Save to Files, Share,
      Copy, in that order. Screenshot.
      2. *Nothing drawn:* Markup and Reply: the photo full screen in Quick
      Look. Written down: where its Markup button is, and whether Markup
      is on before it is tapped. Done, with nothing drawn: back at the
      letter, no composer, nothing asked; no new directory in
      `tmp/Attachments` but the one copy of the file opened (B-063).
      3. *Drawn:* held again, Markup and Reply, the Markup button, a line
      drawn across the photo with a finger. Written down: what Quick Look
      shows at its Done and how many Dones close it; any question it asks
      photographed with its buttons, and which was tapped. Then: a reply
      opens over the letter, the letter's sender in To, "Re: B-171
      photo", the caret at its top and the keyboard up, the quote and the
      signature as a Reply's; one row under Subject, its name, kind and
      size written down. Screenshot.
      4. *Kept on the iPad:* "B-171 look" typed in the body; after five
      seconds, over SSH, `Local Drafts/<UUID>/letter.json` lists the row,
      its name and kind as the row shows, and its file is in the letter's
      own directory; that file pulled to the host and looked at: the
      photo with the line drawn on it, its kind by `file` written down. In
      `tmp/Attachments`, the copy's directory.
      5. *Cancel:* Cancel: Save Draft and Delete Draft asked. Delete Draft:
      the reply closes on the letter; the log has no `MAIL FROM`, `RCPT
      TO`, `DATA` or `APPEND`; no `Local Drafts` letter for it; the copy's
      directory gone from `tmp/Attachments`.
      6. *The others:* the logo held: the menu with Markup and Reply. The
      picture from the web held: WebKit's menu, as before, no Markup and
      Reply. A tap on the photo: Quick Look, written down whether it has
      a Markup button (it should not).
      7. *A conversation:* "B-171 thread 2" listed, thread 1's line opened,
      its photo held, Markup and Reply, a line drawn, Done: the reply's To
      is thread 1's sender, its subject thread 1's. Cancel, Delete Draft.
      8. *A HEIC:* "B-171 heic" opened; written down whether its photo
      shows. Where it does: held, Markup and Reply, a line drawn, Done:
      the row's name ends ".jpg", its kind a JPEG. Cancel, Delete Draft.
      9. *Put back:* "Notes" left, the Inbox at its top. The host moves the
      UIDs it noted, and only them, from "Notes" to the Trash, and deletes
      in the Trash only the UIDs that move answered (`COPYUID`). Nothing
      was sent, and nothing else was written to the account.

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
      *Known 2026-10-05, from the pictures he sends: his iPad's iOS is past
      every version TrollStore installs on, so the install is by a
      certificate, and the app stops opening on his iPad the day it runs
      out. Left to the owner: which certificate, and what he and his helper
      are told before that day (the in-app warning, built 2026-10-25 as
      B-137, its words awaiting his approval).*
- [ ] **The real signature logo** — what ships today is a solid black silhouette
      with no legible mark in either channel
- [x] **Signature in the source?** (B-035) *Decided 2026-09-26 by the
      owner: his signature never goes in the repo. How it reaches his
      iPad is the open item at the top of this file.*
- [x] **Mail's conversation stack default** — thirty seconds on an iPhone;
      newest-first is currently a guess, not a copy
      *Decided 2026-10-06 by the owner: "copy apple mail for these". Built,
      seen in the simulator and on the iPad 2026-10-07: oldest at the top
      and newest at the bottom, the read letters closed, the unread ones
      open with the newest and marked read at the tap, the pane opening at
      the oldest letter he has not read, or at the newest when he has read
      the rest, and a letter that comes put in at the bottom (B-074).*
- [x] **Pictures from the web in letters** — they load, as they always
      have, and a tracking pixel tells its sender the letter was opened; the
      spec asks for them blocked by default if feasible (B-055)
      *Ruled 2026-10-26: copy Apple Mail. Built as B-168.*
- [x] **A long press on a link** — WebKit's own menu, whose preview loads
      the page without "Open this link?"; every address in a plain letter
      is a link now. Leave it, or `allowsLinkPreview` off (B-055)
      *Decided 2026-10-01: left as it is, as Mail has it.*
- [x] **The Cc line arriving with the letter** — a conversation's stack
      moves down a line under him, against B-042's header of its final
      height from the tap. Let it stand and write it into B-042, or carry
      the Cc on the list's rows from the ENVELOPE, which holds it (B-055)
      *Decided 2026-10-01 and built: the rows carry it, and the header
      has its line from the tap. Seen on the test iPad 2026-10-21
      (B-055's check).*
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
      Built as B-080, seen in the simulator and on the iPad 2026-10-19, a
      Wednesday's row there 2026-10-25: no count on any row, the blue
      chevron in a circle after the date on a conversation's row in every
      folder, and VoiceOver saying how many.*
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
- [x] **B-102 part 2: write `\Answered` and `$Forwarded` after a send?**
      As Mail does, once, right after the reply's or forward's own 250. It
      needs a bounded exception to D-016's "no queue of offline changes":
      a reply waiting in the Outbox carries which letter it answers. If
      no, take part 1, the arrows on the rows, out again before the
      install: arrows only on letters answered elsewhere would make a
      missing arrow mean nothing. Either way, VoiceOver's "Replied" and
      "Forwarded" await his approval, and are held from his iPad until he
      gives it (B-102).
      *Ruled 2026-10-26: copy Apple Mail. Built as B-152.*
- [x] **Move to Junk in the Flag sheet** (B-106): built on
      `feat-flagmenu`'s last commit, not merged.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-106.*
- [x] **His own Sent Mail lines in a conversation after an offline
      relaunch** (B-111, D-021): Mail shows them; nothing of his Sent Mail
      is kept here, so they are not there. Keep it so (the default), or
      keep their summaries beside the kept letters.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-159.*
- [ ] **A printed letter's faint colours** (B-110): with no backgrounds
      printed, WebKit lightens a sender's light colours, small grey print
      all but gone. As built, Mail's light print (the default), or the
      sender's backgrounds printed.
- [x] **A PDF's two rows** (B-113), one in the header and one among the
      words: both (the default), or one.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-148.*
- [x] **Go to Date with Organize by Thread on** (B-117): a jump lands on
      the row that holds the day's first letter; when that letter was
      answered, the row is its conversation's, placed by its newest letter,
      so the rows in sight can be dated days after the day asked. As built
      (the default, Mail's order of conversations), or land on the first
      row dated on or before the day.
      *Ruled 2026-10-23: "Copy how Apple Mail works in terms of the date."
      Built as B-118: in Mail's list a conversation's row is dated by its
      newest letter and the rows go by that date, so a jump opens on the
      oldest row dated on or after the day, the days after above and the
      days before below, a conversation begun on the day and answered
      later up where its reply puts it; with every letter of the day
      answered later, the oldest row after it, "Showing" that day; a
      reply that comes only with a page after the first frame takes the
      row on top up the list, and the day's next row comes into its place.
      With Organize by Thread off as before. Seen on the test iPad
      2026-10-23 (B-118's check, above).*
- [ ] **Paper** (B-110): may a check print up to four sheets on a real
      AirPrint printer? It would run B-063's print check from Quick Look
      too. Until then no paper: every print was judged on the panel's
      preview and the PDF it saves. And whether the printer at his house is
      an AirPrint printer on his Wi-Fi.
- [ ] **Apple Mail after the install** (gap review, 2026-10-24): his Gmail
      account kept on in Apple Mail (the default: mailto: links and other
      apps' Email buttons keep working, Blackmail cannot take them, and it is
      the fallback on 2027-09-18; Mail hidden in the share sheet with
      Blackmail first, Blackmail in Mail's Dock place, Mail's badge off), or
      Mail turned off for it.
- [x] **The letter after a Delete or Move in the pane**: Mail opens the next
      one; Blackmail empties the pane on purpose (B-041), so a second tap
      cannot bin another. Copy Mail (the default, unless his iPad's Delete
      or Move Message Action says "Don't Select a Message", with Delete grey
      for a second after the next letter shows), or keep it empty.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-158.*
- [x] **A share with no connection**: Mail's sheet closes and the letter
      waits in its Outbox; Blackmail's stays up with "Can't connect to mail
      server." Close it and let the letter wait in Blackmail's Outbox, to go
      when Blackmail is next opened (the default, for shares with no
      files), or as today.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-153.*
- [ ] **Smart Invert for Blackmail alone**: if he uses it, off for Blackmail
      in Per-App Settings so his other apps keep it (the default), rather
      than off for the whole iPad.
- [x] **His own circle at the top of the share sheet**: if he shares by
      tapping it, Blackmail would need to donate its sends to get one (not
      built, the default; with Apple Mail kept on, Mail's circle works).
      *Ruled 2026-10-26: copy Apple Mail. Built as B-163.*
- [x] **Mail's words in three places**: the Edit bar's "Trash" outside
      Trash (Blackmail says "Delete"), and Gmail's "Sent Mail" and "Spam" as
      Mail names them, "Sent" and "Junk" (the default: Mail's words).
      *Ruled 2026-10-26: copy Apple Mail. Built as B-144.*
- [x] **Swipe to Trash on a row** (decided against by the spec): about 5
      letters a day go to the bin unopened, each Edit, tick, Delete here.
      As decided (the default), or Mail's swipe.
      *Ruled 2026-10-26: copy Apple Mail; the owner withdrew the brief's
      no-swipe rule the same day. Built as B-156.*
- [x] **"Open this link?"** (set by the spec, never asked of him): Mail opens
      a tapped link at once. As built (the default), or Mail's way.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-145.*
- [ ] **His iPad's own settings**, read before the install-day build so
      its defaults follow them: Settings > Sounds > Sent Mail (B-100: None
      takes the sound out), Mail > Threading > Complete Threads (B-104: off
      takes it out), Mail > Composing > Include Attachments with Replies
      (B-107's mode), and Display & Text Size, Larger Text and Bold Text
      (D-007). *Added 2026-10-24 from the gap review with Mail (nothing is
      built after the install, so each must be read before the last build):
      Accessibility > Per-App Settings (a text size or Smart Invert set for
      Mail alone does not show under Display & Text Size); whether Smart
      Invert is on; Mail > Ask Before Deleting (if on, Mail's question is
      to be built); Mail > Delete or Move Message Action (decides what
      follows a Delete in the pane); Mail > Blocked and its option (if Move
      to Trash, each blocked sender made a Gmail filter); Notifications for
      Mail and Fetch New Data; Undo Send Delay; whether his Home Screen
      has a Mail widget; and one link shared from Safari, watched (Mail's
      icon, or his own circle at the top of the sheet).* *Added 2026-10-26
      with D-024: Mail > Swipe Options, Swipe Left and Swipe Right
      (`SwipeOptions.his`); the Gmail account's Advanced > Move Discarded
      Messages Into (`SwipeOptions.his.discardInto`; Archive there also
      needs the Edit bar's and the pane's Archive, B-144's "not built");
      Accessibility > Touch > Shake to Undo (B-157).*
      *Ruled 2026-10-26: copy Apple Mail. Built as B-167 for Mail's own page
      only:* Swipe Options, Delete or Move Message Action, Ask Before
      Deleting (live once B-168 is merged), Complete Threads and Move
      Discarded Messages Into are a part of Blackmail's Settings laid out as
      Mail's page, at Mail's factory values, set from his Mail settings page
      at the install (the install-day list above), no longer read before the
      last build; Archive Mailbox archives from the Edit bar and the pane
      too. Still open, to be read off his iPad before the last build: Sounds
      > Sent Mail (B-100), Composing > Include Attachments with Replies
      (B-107), Display & Text Size, Larger Text and Bold Text, Per-App
      Settings, Smart Invert, Blocked and its option, Notifications for Mail
      and Fetch New Data, Undo Send Delay, a Home Screen Mail widget, the
      Safari share watched, and Shake to Undo (B-157). *2026-10-27: Mail >
      Ask Before Deleting and Privacy Protection's Block All Remote Content
      are built (B-168), off as from the factory, and matched in Blackmail's
      Settings on the day with no build (B-167's rows; "On the day", at the
      top).*
- [x] **His signature's white sheet** (B-130): Mail draws his signature
      with the rest of the letter, black with white words and the logo
      dark on it in Dark Mode or under Smart Invert (read in its code, not
      seen). The app's white sheet in both panes (built, the default), or
      none in the stack either, as Mail.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-146.*
- [ ] **A letter that is only a picture, printed in words** (B-131): when
      its page cannot be drawn, its header alone (built, the default), as
      the pane never says it has no text; or "This message has no text."
      under it, as before, true of its words and not of the letter.
- [x] **The new words on his screen**, each held from his iPad until the
      owner approves it, the entry listing them: VoiceOver's "Replied" and
      "Forwarded" (B-102); "Checking for Mail…" under the list while a pull's
      page is out (B-103); "Complete Threads", the line under it and
      "Found in Sent Mail" (B-104); "Recent Searches" and VoiceOver's
      "Recent search," (B-105); the Forward question with "Include" and
      "Don't Include" (B-107); "Photo Library", "Attach File" and the
      sentences for files that could not be attached (B-108); "This app
      will stop opening on September 18, 2027. After that, use Mail.",
      with OK, once a day in the app's last thirty days, the day the one
      its profile says, written in the iPad's way (B-137). It names Mail,
      so it goes with "Apple Mail after the install", above.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-144.*
      *B-137's sentence is not among them: its words wait with "His iPad's
      iOS version", above.*
- [x] **A Delete or Move whose answer is lost** (B-132): the connection
      dropping after Gmail has carried out a MOVE and before its answer
      comes, the row comes back with "Can't connect to mail server."
      though the letter has gone. In the Inbox at its top the watch takes
      the row off within about half a minute; anywhere else it stays
      until a Refresh, or a second Delete or Move, which finds it gone.
      As built (the default, B-092's "refused as not moved"), or a look
      in the folder on the next connection after such a failure, the row
      taken off if the letter has gone (not built).
      *Ruled 2026-10-26: copy Apple Mail. Built as B-151.*
- [x] **Edit mode's Done** (B-133): guides to Mail describe leaving its
      edit mode with Cancel, not seen on an iPad; Blackmail's button says
      Done. As built (the default), or Mail's word once seen on his iPad.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-144.*
- [x] **A YouTube share's subject** (B-125): Mail's is the video's title,
      which the YouTube app gives Mail and never a share extension; here
      it stays empty, some 31 letters a day, rows "(no subject)" that a
      search by title cannot find. Naming it needs the page's title fetched
      while the sheet is up (LinkPresentation, or YouTube's oEmbed). Mail
      fetches nothing to fill a share's Subject, taking the app's answer;
      its composer does fetch a page's preview for a link pasted into a
      letter, which it makes a rich link. A fetch here would have to never
      hold Send, never write over a subject he has typed, and leave it
      empty when the fetch fails. As built (empty, the default), or the
      fetch. *Decided 2026-10-25 by the owner: "fetch the title from
      YouTube for those shares, falling back to empty if it doesn't
      answer." Built from YouTube's oEmbed and seen on the test iPad
      2026-10-25: see B-126.*

- [x] **Quote bars beside plain-text quotes** (B-101): Mail draws its
      blue bar beside lines quoted with "> " in a plain-text letter too;
      here only HTML quotes have it. As built (no bar, the default), or
      Mail's bars there too.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-147.*
- [ ] **The quoted words in the bar's colour** (B-101): Mail colours the
      quoted words as well as the bar; that is built. The bar alone is one
      line out of `QuoteBars.css`. As built (Mail's, the default), or the
      bar alone.
- [x] **Mail's paperclip in the keyboard's shortcut bar** (B-108): Mail
      offers Attach File and Photo Library from a paperclip at the right
      of the bar above the keyboard; here they are two buttons under the
      letter's files, always in sight. As built (the default), or the
      paperclip too.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-154.*
- [x] **The address book filled from his Sent Mail** (B-017, B-123): the
      book learns from the rows the list shows and from his sends, so
      about half the people he writes to in a month are not suggested,
      and a half name in search does not find them, until one of their
      letters is listed. Reading his Sent Mail's recent envelopes once
      at sign-in would put them there from the first day. As built (the
      default), or the fill.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-155.*
- [x] **Three offline choices for the copy kept on the iPad** (D-016,
      "each needs its own decision later"; with nothing built after the
      install, now or never): fetching unread mail ahead for reading with
      no connection; keeping more than one page of each folder; searching
      with no connection. As built (none of them, the default), or which.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-160.*
- [x] **One frame of the letter before** (B-098): at a tap from letter to
      letter, the letter he left stays beside the new selection for a frame
      or two, 17 to 33 ms, the new header over it in the last, before
      "Loading…" comes, in 3 taps of 7 on the test iPad 2026-10-25 (5 of 7
      on 2026-10-21), and the new header over two frames of an empty pane
      for the first letter after a launch. As built (the default), or a
      cover over the pane from the tap, lifted once WebKit has painted
      "Loading…", which would hide the letter if it ever failed to lift.
      *Ruled 2026-10-26: copy Apple Mail. Built as B-149.*
- [ ] **Trash for letters only on the iPad** (B-144): in the Outbox, and
      for the letters kept on the iPad at the top of Drafts, Edit mode's
      third button says "Trash" in the bar's blue, the ruling's word
      outside the Trash, and its tap takes them off the iPad with nothing
      asked and no copy in the Trash: a letter not yet sent, or a draft
      not yet on the server, cannot be got back. Before B-144 it said
      "Delete", in red. What Mail's Outbox bar says was not seen. As built
      (the default), or "Delete" there: one line for the Outbox; in
      Drafts, which holds the server's drafts too, the word would follow
      his ticks.

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
