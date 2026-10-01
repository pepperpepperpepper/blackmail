# Known issues

Found by driving the prototype on a device, not by reading the code.

## B-001 — Replying to an HTML-only message quotes nothing — RESOLVED 2026-09-20

Fixed as predicted below, and the prediction that the preview would want the
same pass was right: the HTML walk lives in `HTMLText`, shared by
`Message.quotableText` (which keeps paragraphs) and `PreviewText.fromHTML`
(which flattens to one line). Verified on device forwarding a real HTML-only
receipt, which had previously produced a letter containing nothing but the
"Forwarded message" header. The original report follows.



**Seen:** screenshot 5. Reply to Dr. Aziz's appointment mail produces
`On 18 September 2026 at 6:43 PM, Dr. Aziz wrote:` followed by a bare `>`.

**Cause:** `openCompose` quotes `m.textBody`, which is nil for a message that
only has an HTML part. Most real mail is HTML-only, so this is the common case
rather than the edge one.

**Fix:** derive a plain-text rendering from the HTML when `textBody` is nil,
and quote that. Needs an HTML-to-text pass anyway — the message list preview
will want the same thing once real mail arrives, since a preview built from raw
HTML shows markup.

## B-002 — CLOSED, not a defect. Toolbar pitch matches.

Was "toolbar pitch is ~56 pt against the reference's 52.8". The 52.8 figure was
wrong: it came from eyeballing the reference before anyone had established that
the image is a *photo of an iPad*, so the scale it was divided by was the whole
580 px picture rather than the 443 px screen inside it. Two measurement passes
working from the corrected screen rect both read the reference's glyph pitch as
**58.3 pt** against our 56.5 — we were 1.8 pt *tighter*, not 3 pt looser, and
that is inside the noise.

Kept rather than deleted because the failure generalises: every number derived
from that image before `spec/references/OWNER_SCREENSHOT_GEOMETRY.md` existed
is suspect by about 31% in the same direction.

## B-003 — Suspended app resumes mid-navigation

**RESOLVED 2026-09-21. The requirement: after a while away, return to
the Inbox.**

PRODUCT_SPEC.md asks for two things that disagree — "the app opens into Inbox"
and "preserve scroll position where practical" — and the answer turned
out to be that both are right, at different timescales. A short
interruption leaves him exactly where he was. More than fifteen minutes
away counts as a new sitting and returns to the Inbox, with the folder
list refreshed.

**Fifteen minutes errs short on purpose.** The two failures are not
equal. Resetting too eagerly loses his place, which is a nuisance and now
a cheap one to undo — the calendar button and search both exist to get
back. Resetting too rarely means picking the iPad up next morning and
finding himself somewhere in last June with no idea how he got there:
that does not read as a preserved position, it reads as the app having
lost his mail.

**It will not fire over an open sheet.** A half-written letter is the one
piece of state in this app he cannot recover, and pulling the folder out
from under a compose window in order to be tidy would be the worst trade
in the product.

Verified on device at a temporarily shortened threshold, both branches:
26 seconds away returned to the Inbox and moved the sidebar highlight;
7 seconds away left the folder exactly as it was.

---

## B-011 — An All Mailboxes search cannot find a deleted message

**RESOLVED 2026-09-20.** It can now. Kept because the shape of the fix is
worth knowing before anyone touches search paging again.

Gmail's All Mail holds everything EXCEPT Trash and Spam — the exclusivity
this codebase already relies on in `countedFolders` — so the original
one-SELECT implementation could never reach a binned letter. Built anyway,
because search is used constantly.

**Why it was not cheap.** A UID means nothing outside the mailbox that
issued it, so three result sets cannot be concatenated, sorted, or paged by
the `beforeUID` cursor that every other list in this app uses. The merge has
to be by DATE, which means the repository now carries a `SearchSession`: the
All Mail UID walk, a buffer of rows fetched from it but not yet emitted,
Trash and Spam hits fetched whole, and everything emitted so far.

**The rule that makes it correct**, and the one to preserve: when the All
Mail buffer empties but the server has more to give, the merge must STOP
rather than fall through to the binned stream. Otherwise a message trashed
last March is emitted the moment the current chunk runs out, landing above
hundreds of newer letters not yet fetched. That is `primaryExhausted` in
`SearchMerge.take`, and there is a test named after it.

Ordering ties break on id, not just date — two messages sharing a timestamp
is ordinary, and without a total order one of them can be emitted twice or
skipped across a page boundary.

**Bounds accepted.** Trash and Spam are fetched whole up to
`maximumBinnedHits` (200 each) rather than paged; past that the oldest
binned matches are dropped. A Trash that fails to open is swallowed so the
All Mail half of the search survives — losing half a search is a gap, losing
all of it is the feature not working.

**Verified on device**, both directions: with one message in Trash
containing a term present nowhere else, an All Mailboxes search returned it
FIRST and in correct date position; switching to Current Mailbox dropped it.
Paging re-checked at page size 3 so boundaries fell between the two streams
— the binned hit appeared once, mid-stream, and the order stayed strictly
descending.

---

## B-012 — The list can only be jumped inside one folder

**RESOLVED 2026-09-21.** Docket item 7.

The jump sheet now carries the same Current Mailbox / All Mailboxes
control the search band does — deliberately the same enum and the same two
words, because "where should I look" is one question and he should not
have to learn two answers to it. The choice is remembered, like the date.

Jumping inside the folder he is standing in is still the default and still
the common case. What it silently excluded was the letters he SENT that
day, which for someone working back through a correspondence is half of
it.

**Why it moves the pane rather than filtering in place.** A list IS a
folder here: the title, the unread count and every page it fetches belong
to that folder. Quietly filling an "Inbox" pane with All Mail would make
the title a lie and send the next page fetch to the wrong mailbox. So an
"all mailboxes" jump asks the container to open All Mail properly and land
it on the date — the sidebar highlight moves with it, and everything on
screen agrees about what is being shown.

Verified on device: from the Inbox, All Mailboxes + 19 September switched
the pane to All Mail, moved the sidebar highlight, and reported "Showing
September 19".

---

## B-013 — Debug builds for iOS do not link

**OPEN, environmental, worked around.**

`swift build --swift-sdk ios165` fails at link with `undefined symbol:
swift_coroFrameAlloc`. Swift 6.2 emits that call for coroutine accessors and
the iOS 16.5 runtime does not have it; only the optimiser removes the calls,
so `-c release` builds clean.

Worked around rather than fixed: `tools/deploy-to-ipad.sh` now builds
`-c release` for its error check, which is the configuration that ships
anyway. The consequence to know about is that there is currently no debug
build for the device, so nothing can be run under a debugger there.

---

## B-014 — Cc revealed a row that could not be typed into

**RESOLVED 2026-09-20.** Cc had never worked in this app, and only sending
a real letter found it.

`ComposeViewController` built the Cc row with
`ccRow.addSubview(row(label: "Cc:", ...))` — a plain `addSubview` into an
empty wrapper, rather than handing the row straight to the stack. A
UIStackView turns `translatesAutoresizingMaskIntoConstraints` off for its
ARRANGED subviews; a plain subview keeps it on. So the 44 pt height
constraint that `row()` installs fought the autoresizing frame and lost, and
nothing ever sized the wrapper.

**Why it looked fine.** The label still drew. What was missing was the
field's tappable area, so pressing Cc/Bcc appeared to reveal a Cc row and
then tapping it did nothing at all — focus silently stayed wherever it was,
and the next thing typed went into the previous field. In testing that
produced `desk@example.netowner@example.com` in a single To
field, which on a real send would have been one malformed recipient and a
bounce.

The fix is to assign the row itself to `ccRow` and add THAT to the stack.
Verified on device: Cc is now a full-height row with its own rule, accepted
an address, and the delivered message carried a real `Cc:` header.

**The general lesson, since this file is where they go:** a view with an
intrinsic-size or height constraint that is `addSubview`d rather than
`addArrangedSubview`d will render and be invisible to touch. Nothing warns.

---

## B-015 — The first synthetic tap after an idle period is dropped

**OPEN, harness-only, does not affect the product.**

Driving the iPad with `touchsim`, the first tap after a pause is regularly
swallowed and an identical second tap at the same coordinates works. Seen
three times in one test run: opening the compose sheet, and twice on Send.

It matters only because it is indistinguishable from a mis-measured
coordinate, and chasing it as one wastes a screenshot cycle each time. When
a tap appears to do nothing, REPEAT IT before re-measuring.

---

## B-016 — Drafts were a dead end

**RESOLVED 2026-09-20.** Docket item 1.

Three separate failures wearing one coat. `saveDraft` APPENDed, so saving
the same letter twice left two near-identical copies and no way to tell
which was current. `Draft` carried no identity, so nothing could reopen one.
And tapping a draft opened it READ-ONLY in the pane to the right, with no
route back into the composer — so a letter he was interrupted writing could
never be finished.

For a man of ninety whose main correspondence runs through this app, being
interrupted mid-letter is the normal case, not an edge one.

**What it needed.** `Draft.savedID`; `saveDraft` returning the new id so a
save can chain; `deleteDraft`; `loadDraft`; `IMAPAppend.uid` to read
`[APPENDUID …]` off the APPEND reply (without it the only way to learn
where a message landed is to re-SELECT and guess at the highest UID, which
races anything else delivering); `IMAPClient.expunge(uid:)`; and a tap in
the Drafts folder opening the composer instead of the reader.

**Superseded drafts are EXPUNGED, not binned.** Now that an All Mailboxes
search reaches the Trash (B-011), a draft moved there rather than removed
would come back as a search hit for every half-finished sentence he ever
saved.

**Order matters and is deliberate:** append the replacement first, delete
the old copy second. The other way round risks destroying the only copy of
a letter and then failing to append, which loses work he cannot recover.
Attachments are resolved before either, because a draft reopened from the
server carries files that live inside the very copy being replaced.

**Verified on device, whole cycle:** compose → Save Draft → one copy in
Drafts → tap it → reopens in the composer with its subject → Save again →
still one copy → Delete Draft → folder empty.

---

## B-017 — Every address had to be typed by hand

**RESOLVED 2026-09-20.** Docket item 2.

There was no completion of any kind. One habit of his is what made this
the highest-value item left: he sends emails to himself,
constantly, which meant typing his whole address on glass every time,
and the same again for the people he Ccs weekly.

**Not backed by Contacts, deliberately.** That framework puts a permission
prompt in front of a man who will not know what it is asking, and a
"Don't Allow" tapped once is invisible and permanent. The addresses come
from his own mailbox instead, harvested from the ENVELOPE the message list
already fetches to draw each row — so the book fills itself at no extra
network cost, and his own address is seeded at launch because a letter to
himself is the one address watching his mail cannot teach.

**It also unlocked something that was impossible.** The email keyboard has
no comma key and `ComposeViewController` splits recipients on commas, so a
SECOND recipient could not be typed at all. Choosing from the list inserts
the separator, which is now the only route to addressing two people.

Ranking is tiered — a name prefix beats a local-part prefix beats a
substring — and ties break on id so the list cannot reshuffle between
keystrokes. A row that moves under a finger is a letter sent to the wrong
person. An address he has WRITTEN to outranks one merely seen, so a
newsletter sender met a hundred times does not outrank the man he replies
to.

**Verified on device:** tapping To with nothing typed offers his own
address first; tapping it fills the field and inserts the comma; typing
the first three letters of a name narrows to one; and it all works on the
second recipient too.

---

## B-018 — "Cc/Bcc" offered no Bcc

**RESOLVED 2026-09-20.** Docket item 3.

The button had said "Cc/Bcc" since the composer was written and revealed
only Cc. The same defect as `MailError` naming a Settings screen that did
not exist: the app promising a thing that was not there. The field was
added rather than the button renamed, because he Ccs constantly.

The model already carried `draft.bcc` end to end — SMTP has always put it
in `RCPT TO` — so this was a missing field, not a missing feature.

**The part that was not obvious.** Bcc must appear in exactly one of the
two places a letter gets written, and they pull opposite ways. On the wire
a surviving `Bcc:` header shows every blind recipient to everyone, so
`send` must not emit one — that was already true and is now pinned by a
test. But a DRAFT is stored rather than delivered, and omitting it there
drops a recipient he deliberately chose: he Bccs someone, is interrupted,
reopens the letter, and the person is gone with nothing to say so. So
`RFC5322Builder.build` takes `includeBcc`, `saveDraft` passes true, `send`
does not, and `loadDraft` reads the header back.

The row is added as an ARRANGED subview, which is the whole of B-014's
lesson applied on purpose rather than by accident.

---

## B-019 — Nothing could be marked unread

**RESOLVED 2026-09-20.** Docket item 4.

`setRead(false, …)` had existed in the repository since flags were written
and nothing in the interface ever reached it: the app could set `\Seen`
and never clear it. Leaving a letter unread is how a great many people say
"come back to this", and for someone whose mail is his main correspondence
that is a real way of keeping track.

It lives in the edit-mode toolbar, which is now **Mark / Move / Trash** —
Mail's own bar, in Mail's order. Deliberately not a swipe or a long press:
BRIEF.md's promise is that nothing needs a gesture beyond tap and
ordinary scrolling.

**The counter arithmetic is the fiddly half.** `countedRead` remembers
which messages this screen has already billed as a -1, so a reload
deriving `isRead` from pre-STORE server flags cannot bill one twice.
Marking unread has to UNDO that bookkeeping as well as adding one back, or
reading the message again later would be free and the count would drift
LOW — and a count that is too low says "no new mail" when there is some,
which is the exact failure the sidebar exists to prevent.

**Verified on device:** marking one read message unread restored its dot,
took Inbox from 7 to 8 AND Sent Mail from 2 to 3, because that letter
carries both labels — the same multi-folder counting as the read path,
running in reverse.

---

## B-020 — There was no way to attach a file

**RESOLVED 2026-09-20.** Docket item 5, and the sharpest edge left: he
sends photographs, and the path for it did not exist at
all.

`DraftAttachment` described only one kind of thing — a part of a message
already on the server, which is how a forward carries its files without
downloading them until send. A photo is the other kind: bytes on this
device. The struct now carries a `Source` enum with both, and
`loadAttachments` fetches accordingly.

**PHPicker, not the old image picker,** and the difference is a permission
prompt. PHPicker runs out of process and returns only what he chose, so it
needs no photo-library access — which matters because a "Don't Allow"
tapped once by a 90-year-old is invisible, permanent, and looks exactly
like the button being broken. Confirmed on device: the picker opened with
no prompt.

**Re-encoded as JPEG rather than passed through.** iPads store photos as
HEIC and a good many recipients cannot open it, and an attachment that
will not display is worse than none because neither end knows. Full
resolution is kept deliberately: the size ceiling is already refused
loudly at send, so there is no case for quietly shrinking what he chose.

**Removal exists now because attaching does.** A list that can be added to
and not subtracted from turns one mis-tap in a photo library into a letter
he cannot send without starting it over.

**Verified on device, whole round trip:** Attach Photo → picker with no
prompt → row reads "IMG_0772.jpg — 866 KB" → Save Draft → the Drafts row
shows a paperclip, so the server parsed a real MIME part → reopen → the
attachment is back at 889 KB, the couple-of-per-cent-high BODYSTRUCTURE
estimate this codebase already documents → Remove → gone.

---

## B-021 — The iPad's photo library is the previous owner's

**CLOSED 2026-09-22 as a non-issue — the premise was wrong.** This iPad
is NOT going to Sam: the app is sideloaded onto one of his own iPads.
This device stays here as the dev iPad, so the previous owner's photos
are not a handover blocker. On Sam's iPad, "Attach Photo" shows
Sam's photos, which is the correct behaviour. Kept for the record because
the wipe list it created was acted on as real for two days. See B-035 for
what the sideload actually requires instead.

**The original report, now moot:**

Attaching a photo opened the previous owner's photo library. Nothing to
do with this app — it is what is on the device — but
the moment the app can reach Photos it becomes visible to whoever uses it,
and "Attach Photo" is now a button he will press.

Wipe or migrate the photo library before handover, alongside signing out
of the Apple ID.

---

## B-022 — RESOLVED. Conversations open in the reading pane

Mail opens a thread as a stack of letters in the READING PANE. This app
opened it OUT IN THE LIST instead, on the reasoning that the pane should
always hold exactly one letter. The requirement is to follow Apple
Mail, so the list is now one row per conversation, always, and a tap opens the stack on the
right: newest expanded, the rest collapsed to a tappable line.

**One web view, not one per letter.** A column of web views is the usual
way to build this and it brings the usual defect: a web view does not
know its height until it has laid out, so each reports back a moment
after the others and the text jumps under the reader's thumb. The whole
conversation is one document (`ConversationDocument`), so there is one
scroll view and no heights to reconcile. Collapsing is a CSS class.

**Only the letter he can actually read is marked read.** Opening a
conversation marks the newest; expanding another marks that one. The
unread count is how he knows what is still waiting, and emptying it for
a thread he has read one line of would take that away.

**Not settled, and recorded as such:** whether the stack should run
newest-first or oldest-first. Mail has a "Most Recent Message on Top"
setting and this build puts newest first, which matches every other list
in the app. Mail's default has not been confirmed yet, so this is a choice and not
a copy.

## B-023 — The first tap after an idle period fails, and looks like an empty letter

**RESOLVED 2026-09-21.** Filed as "a reply shows no body"; that was the
symptom, and it was neither of the two things it looked like.

**What it actually was.** Opening the reply raised "Can't connect to mail
server", and tapping the identical row a moment later loaded it with its
body intact — four paragraphs of quoted text, exactly what the list
preview had been showing all along. So the body was never empty and was
never below the fold. The FETCH failed.

**Why the first one and not the second.** Gmail closes an IMAP connection
that has been idle a while, and this app does not find out until it next
uses it. `IMAPClient.teardown()` clears `connected` when a command fails,
so the first command after the drop fails and the second reconnects. That
is a bad shape for this product specifically: a man who picks the iPad up
three or four times a day would find the FIRST thing he touched each time
failed, and the fix — do it again — is one he would have to be taught,
and would reasonably read as the app being broken.

Reads now retry once when, and only when, the client actually tore the
connection down. Not writes: a STORE or a MOVE may have been carried out
before the socket died, and repeating it is not consequence-free.

**And the presentation was its own defect.** `show(summary:)` draws the
header from the summary before fetching the body, so a failed load left a
sender, a subject, a date and nothing beneath them. That does not look
like an error; it looks like an empty letter, and the only way to tell
was to tap it again. The pane now says the message could not be
downloaded, in the pane, where it cannot be dismissed by accident.

**The lesson worth keeping:** the symptom was a rendering question and the
cause was a connection one. Filing it unexplained would have left both
halves in place.

---

## B-024 — Anything that is not a read still fails on the first attempt

**RESOLVED 2026-09-21.**

B-023 fixed reads by retrying them. Writes could not take the same
medicine: a MOVE or an APPEND may have reached the server before the
socket died, and repeating it is a different outcome rather than the same
one twice.

**So the order is inverted instead of the remedy.** Before a write that
has been quiet for more than 90 seconds, the repository sends a NOOP.
That IS idempotent, so it can be retried freely into a reconnect — and
the write then goes exactly once, down a connection just proven to work.
The common case is Gmail's cleanly-closed idle socket, where the probe
fails immediately and the reconnect costs one round trip.

**Sending was never exposed to this.** `SMTPClient` opens a fresh
connection per letter, so the frightening case — a letter sent twice —
could not arise and does not need defending against.

**What is still not airtight**, recorded rather than implied. A
half-open socket can stall the probe for the read timeout, and a command
whose reply is lost in flight remains ambiguous. (Since B-049, a write
whose turn at the connection comes after the command ahead of it has torn
the connection down, with not a byte of the write sent, goes once on a new
connection; one that went out is still never sent again.) The residue is small and
bounded: the flags are idempotent; a UID is never reused within a
UIDVALIDITY, so a repeated MOVE or EXPUNGE either does the same thing or
fails to find the message; and APPEND, the one genuinely duplicable
command, would leave a second draft — the mildest outcome on the list.

**Verified on device:** flagging a message after 130 seconds of silence
worked, which is the path where the probe fires; unflagging immediately
afterwards also worked, which is the path where it is skipped.


## B-025 — Send-side inline images: HALF LANDED, and it fixed the signature

Apple Mail inserts a photograph at the cursor, in the body flow, as a
`cid:` image inside `multipart/related`. This app appended files at the
end. **The MIME machinery for that is now built and shipped** —
`RFC5322Builder` emits `mixed > related > alternative > {plain, html} +
inline images`, parts carry `Content-ID` and `Content-Disposition:
inline` — but the composer half is still open: nothing inserts a photo
AT THE CURSOR yet, so a photograph he attaches still lands at the
bottom as an ordinary file.

**What the machinery was built for first: the signature.** Both images
in Sam's real signature point at Google URLs, and both are dead for
recipients today — the portrait 403s in every variant, and the logo URL
serves a PNG to `curl` but renders as a broken box in an actual client
(verified in headless Chromium). Every letter he has sent for who knows
how long carried two broken images. The logo now ships as
`cid:sig-logo` inside the related set, bytes downscaled from 832x620 to
210x156 (7.5 kB) since it displays at 35x25. Byte-exact round trip
verified with Python's independent `email` parser plus a Chromium
render of the decoded letter.

**The reading side changed with it**, and deliberately. A part marked
`Content-Disposition: inline` is no longer "an attachment": no row in
the header, no paperclip in the list. That is what Mail does with
signature images and inserted photographs, and without it every letter
carrying the logo would have shown a paperclip forever. The part still
reaches the reading pane's `cid:` resolver — it is hidden from the
LIST, not dropped. (An old comment said inline images must be listed
because the spec wanted them listed; that predated anything that
could resolve a `cid:`, when listing was the only way the picture was
reachable.)

**The portrait is still absent** and still needs a photograph from the
owner; when one arrives it is a `SignatureImages` entry plus one
`<img>` in the markup, nothing more.

**The composer half remains open**: insertion at the cursor needs an
`NSTextAttachment` in the composer's text view — the point where the
editing surface genuinely has to change, which D-013 declined to do.
Evidence stays thin: exactly one of 433 of his sent messages is a photo
he placed in his own typed region.

**Setup note.** The logo lives in `UserDefaults` under
`blackmail.signatureInlineImages` (a JSON array of
`{contentID, filename, mimeType, dataBase64}`, stored as DATA like the
account itself), beside a `signatureHTML` whose logo `<img>` points at
`cid:sig-logo`. Whoever does Sam's real setup edits the plist once
more; the procedure is in INVESTIGATIONS.

## B-026 — One blank body, observed once, not reproduced

Opening a message showed the header filled in — sender, To, subject,
date — and nothing at all underneath. Not the load-failure path, which
renders "This message could not be downloaded." in the pane; this was an
empty document, so `loadMessage` had RETURNED and `render` had run.

**What it was not.** Three targeted attempts failed to reproduce it:

- the message being unread (marked it unread again, reopened: rendered
  perfectly, count 4→3),
- the connection being idle (waited 160 s, opened a read message: fine),
- the first open after a cold launch (relaunched, opened a read message
  first: fine).

The one occurrence was the first open after a fresh INSTALL, of an
unread message, while the initial mailbox sync had just finished — so
the remaining suspect is a cold-start race between the body fetch and
the list's first load, both of which contend for the one IMAP
connection. That is a hypothesis with a single data point behind it and
it is written here as one.

**Why it is worth the entry anyway.** This is the same SYMPTOM as B-023,
whose stated root cause was Gmail dropping an idle connection, fixed
with a retry. If that retry can return an empty body rather than an
error, the fix is incomplete and the defect is invisible: a blank pane
does not look like a failure, it looks like an empty letter, and the
only way to tell is to tap the message again.

**Next step when it recurs**, rather than more guessing: the app already
keeps a redacted protocol transcript (`Diagnostics`, 500-line ring
buffer, five taps to open the viewer). Reproduce, then read the
transcript for the FETCH that came back short.

## B-027 — An empty stack view left the reading pane's header ambiguous

`MessageHeaderView` gets its height from a chain of constraints running
sender → To → rule → subject → date → `attachmentStack` → rule → bottom.
`attachmentStack` is a `UIStackView`, and an empty one has **no
intrinsic height** — so on a message with no files, nothing in that chain
decided how tall the header was. The layout was AMBIGUOUS, and Auto
Layout is entitled to pick any value that satisfies it.

It picked different values in different panes. For a single message it
settled on the content height and everything looked right, which is why
this survived so long. For the conversation stack it settled on **760 pt
of an 834 pt pane**, leaving the web view pinned underneath exactly 0
points tall.

**The symptom was a blank reading pane**, and every layer said it was
fine: the IMAP fetch succeeded, the document was built correctly (the
same HTML rendered perfectly in a browser), the web view reported
`didFinish`, and a DOM probe came back `5 children / 235 px / 791
characters of text`. There was simply nowhere to draw it. What found it
was logging the frames — `web 613x0 header 613x760 view 613x834`.

**Fixed** with a zero-height preference on the stack at
`.defaultLow`: with files, the arranged subviews' required constraints
win and it breaks harmlessly; with none, the header collapses to its
text the way it always appeared to.

**Worth remembering as a class of bug.** An ambiguous layout is not a
crash and not a warning you will necessarily see — it is a view that is
correct everywhere you happened to look.

## B-028 — Apple Mail is not installed on the dev iPad

Worth knowing before anyone plans to check a parity question against it:
`MobileMail.app` is **absent** from `/Applications`, there is no Mail row
in Settings between Passwords and Contacts, and launching
`com.apple.mobilemail` raises iOS's *Restore "Mail"?* prompt. Only
`MailCompositionService.app` survives. The previous owner deleted it.

Restoring needs an App Store download and **no Apple ID is signed in**
on this device, so it is not a thing that can be done in passing.

**The privacy item here is also moot** (B-021, B-035): this device is not
being handed over. `/var/mobile/Library/Mail` still
exists with an `Envelope Index` — the previous owner's correspondence.
Deliberately not read. It belongs on the wipe list beside B-021's photo
library.

## B-029 — FIXED. The search field scrolled away with the mail

In use, the search area scrolled with the message list. It was
not intentional.

`SearchHeaderView` was assigned to `tableView.tableHeaderView`, which
scrolls with the content by definition. That contradicted the measured
reference — the build notes specify a **"pinned 43 pt search bar"** —
and it contradicted this project's own D-012, which justified the
contextual scope bar by promising that *"the search field itself never
moves, nor does anything above or beside it."* It moved.

It also mattered more than either of those, because the end user
**searches all the time**. A search field you have to scroll back to the top of the
list to reach is a search field with a scroll in front of it.

**Fixed** by making it a section header of the plain-style table, which
pins to the top of the pane while the rows scroll underneath.

**One trap on the way, worth keeping.** The table asks
`heightForHeaderInSection` and then RESETS the header view's frame
during the same layout pass — so answering from `searchBar.bounds.height`
returned the height the band had a moment ago. The scope bar then drew
on top of the first message instead of pushing it down. The height is
now computed from `Theme` via `wantedHeight`, independent of the frame.

## B-030 — The deliberate sweep for ambiguous layout, and what it found

Two bugs in two days had one shape (B-027, B-029): a view whose size
Auto Layout had never actually been told, which resolved benignly in
every place anyone had looked and wrongly somewhere nobody had. That is
not a bug to fix one at a time, so this was a hunt for the class.

`hasAmbiguousLayout` is public API, so the hunt did not have to be a
reading of constraint chains. `LayoutAudit` walks the window every two
seconds for the first three minutes after launch and reports, once
each: views UIKit calls ambiguous, views with children and no width or
height (**the shape of B-027** — a `WKWebView` at 613x0), and our own
views mixing an autoresizing mask with constraints. Findings go to the
same connection log as the protocol transcript.

**It now runs only when switched on** (B-038 #7). It is main-thread work
through the first minutes of every launch and does nothing for him, so it
is off by default, and `#if DEBUG` could not be the gate because there is
no debug build for the device (B-013). The switch is the **Layout** button
on the connection log (five taps on the list's status line): on, it
sweeps once there and then, keeps sweeping for three minutes, and does
the same at every launch until it is switched off. A launch with
`-blackmail.layoutAudit YES` also turns it on for that launch. On an
iPad where nobody has pressed the button, the audit reports nothing.

**Found, and fixed:**

1. **`ComposeViewController.attachmentsStack`** — the same empty
   `UIStackView` as B-027, in the same kind of chain: the header block's
   height is content-driven and `bodyView` is pinned beneath it. With no
   photographs attached, which is nearly every letter, nothing decided
   how tall the stack was, so Auto Layout was free to hand the writing
   area zero points exactly as it had the reading pane. Found by reading
   the code with B-027's shape in mind, before the sweep even ran.

2. **The scroll view in `SettingsViewController` AND
   `AccountSetupViewController`** — reported ambiguous at 580x584. The
   stack is bounded by the scroll view's CONTENT guide vertically but
   only centred on its FRAME guide horizontally, so the content width
   was never stated. Fixed by tying the content guide's width to the
   frame guide's, which is the canonical way to say "vertical only".
   Worth its own note: one of the two is the setup form, which **had
   never been run on a clean device** (see the clean-install item), so this was a
   latent defect on the one screen nobody can check by using the app.

**Checked and sound:** `RootViewController`'s three-pane chain is fully
determined on both axes and does update its column widths on rotation;
every table sets an explicit `rowHeight` rather than
`automaticDimension`; `MessageCell` and `SearchHeaderView` lay out by
frame and cannot be ambiguous; `DiagnosticsViewController` is pinned on
four sides.

**Noise the sweep taught us to ignore**, now filtered: the keyboard and
text-editing internals, an alert's header scroll view (legitimately
zero-high on a sheet with no title, which is every sheet here), the
date picker's out-of-month calendar cells, and `UIWindow` itself, which
reports ambiguous whenever a presentation is in flight.

**After the fixes the sweep is silent** across the message list, a
single message, a conversation stack, focused search, the composer, the
draft action sheet, Settings and Go to Date.

## B-031 — The clean-install run, done, minus the last step

The setup form had never been exercised on a device with no account.
That mattered more than an untested screen usually does, because
removing the bootstrap import (B-010) made this the ONLY way into the
product: if the form were broken there would be no way in at all, and
the dev iPad's working state proved nothing, since its credentials
predate the removal and the Keychain survives a bundle swap.

**How it was done safely.** The account JSON was removed from
`UserDefaults` ALONE — never `CredentialStore.clear()`, which deletes
every internet password in the app's access group and would have taken
the dev iPad's real credential with it. The Keychain was left untouched,
the plist was backed up first, and the restore was verified by sha256
against the backup.

**What ran, on a device with no account:**

- The app launches to the setup form rather than to an empty mail
  interface or a crash.
- Its layout is correct — this is the screen whose scroll view was
  ambiguous until B-030, and nobody could have seen that by using the
  app, because nobody could get to it.
- **Focus walks all three fields under synthetic touch**, confirming
  what B-008/B-009 already claimed rather than discovering it: tapping
  the second field directly moves focus, and the keyboard's `next` key
  walks on to the third, where the return key becomes `go`.
- `carlo@example.org` typed into the address field, sixteen letters
  into the password field, a name into the third.
- `go` submits. A deliberately wrong password produces the RIGHT
  failure: the keyboard dismisses, both other fields keep their
  contents so nothing has to be retyped, and the message is *"Google
  refused that password. Check it is an APP password, not your normal
  one."* — the refused-credential string and not the network one, so
  the error classification works against a real server.
- Nothing was saved. `save` runs only after `connect` and
  `listMailboxes` both succeed.
- Restoring the backup brought the account back: mail loading,
  signature and conversation grouping intact.

**And then the last step, with a real credential.** `carlo@example.org`
and its app password typed into a device with no stored account:
Gmail accepted it, `CredentialStore.save` wrote it, the root swapped to
the mail interface, and the Inbox loaded. The saved account was read
back and is correct — address, username, both hosts, both ports, and
notably stored as **bytes**, which is what `loadAccount` reads and the
thing a hand edit of this plist gets wrong (see the INVESTIGATIONS note
on editing the stored account).

Setup cannot know the signature, so the freshly-written account was
merged with the signature, its markup and the capitalised display name
from the backup, rather than restoring the whole backup over the top —
keeping the account exactly as the APP wrote it.

**So the clean install is proven end to end.** The one route into this
product works from nothing.

### A consequence worth knowing before anyone screenshots this screen

The password field is **unmasked** on a device with no passcode (D-011,
and right for a ninety-year-old who cannot check what he typed). The
test harness did not account for it: `type-on-ipad.sh` goes to
real lengths never to display, log or `ps`-expose the value, and then
the app renders it in 17 pt and the next screenshot captures it in
plain text.

That is not a defect in the app. It IS a hole in how the app is driven,
and the rule that follows is: **never capture the setup screen between
typing a password and submitting it**, or crop above the fields. The
images from this run that contained the credential were shredded.
Anyone repeating this should treat the password as exposed and rotate
it if that matters to them.

## B-032 — An empty letter now says so, which makes a blank pane diagnostic

A message with nothing in it rendered as a header with blank space
beneath. That is also precisely what B-026 looked like, and it is why
B-026 took three experiments to chase: there was no way to tell "this
letter is empty" from "the fetch returned nothing".

`MailText.hasNoVisibleContent` decides, and the reading pane says
**"This message has no text."** in the same grey as the download-failure
notice but with different words — because the presentation is not what
matters, the sentence is. Wired into the single-message pane and into
each letter of a conversation stack.

**The value is the contrapositive.** After this, a reading pane with
nothing in it can ONLY be a bug. The next B-026 is diagnosable on
sight.

**A correction, recorded because the reasoning was wrong first.** This
was proposed on the belief that several of Sam's messages have no body
— he sends subject-only mail constantly. They do not. His signature
travels INSIDE the HTML body, so a subject-only letter from him still
carries 5.7 kB of signature table; one such letter has no text part
at all and eight characters of prose, and still renders a full
signature block. Measured, not assumed. The change stands on the
contrapositive above rather than on his mail.

**The risk is a false positive**, which would hide a real letter behind
a notice saying there isn't one, so the guard is deliberately
reluctant: a picture with no words is a letter (people send a
photograph and say nothing), a signature alone is a letter, and only a
message with no prose, no images and nothing but markup is called
empty. Verified on device that ordinary HTML and plain-text mail, and
the conversation stack, render exactly as before.

## B-033 — CLOSED. Sending 535'd for an afternoon, and it was two passwords in the keychain

**Status: complete.** What it was: every send failed SMTP AUTH with 535
while the same credential authenticated from scripted clients. What it
turned out to be, found over eight addenda: a Keychain holding two
items for one account (an old build's item beside the new one, so
`loadPassword` returned either), on a device whose old credential
belonged to a different Gmail account entirely. What shipped:

- **The sibling sweep** in `CredentialStore.writePassword` — one item
  per account is the invariant; the sweep enforces it before writing.
- **The Gmail canonicalization finding, recorded in the docs**:
  IMAP accepts an app-password token under a mismatched username and
  opens the token's mailbox; SMTP binds the pair and answers 535.
- **Two permanent diagnostic lines**, `DATA-REPLY-CODE` and
  `SESSION-IDENT`, born from a night of eight documented screenshot
  misreads: identity and outcomes as numbers, never prose off glass.
- **The drafts chain closed clean end to end** (addendum 8): builder,
  append, Gmail's verbatim serve-back, parser, construction, UI — no
  link transposes anything, and `DraftHeadersRoundTripTests` pins the
  round trip so it stays that way.
- Clean-install provisioning proven end to end with a real credential.

**2026-09-30 (D-016 phase 0): the probes no longer name anyone.** The
`PAIR` probe, which wrote each listed letter's sender and subject into
the connection log (`PAIR uid=23 sender=… subject=…`), is out of the
tree, and `SESSION-IDENT` no longer ends with the first row's sender. Its
folder, uidv, exists, uids and first-row stay, which is all B-045's
device checks read, and it ends instead with `msgid=`, Gmail's id for
the first row's letter, which tells apart the letters of one
conversation the way the sender did in addendum 6 without naming anyone.
Addendum 4 says both probes "print identities and pairings, never
content"; a subject is content, and the log they wrote to is made to be
copied out to someone else and is written to a file on every send.
`KeptCopyTests` fails if a listing leaves a subject or a correspondent
anywhere in the log but in the server's own lines. The addenda quote
both probes as they were.

**One question outlived the entry** — app letters that Gmail 250-accepts
yet which appear on no server — and it moves to **B-034** with its full
elimination table, the IMAP and display sides exonerated by numbers and
zoom respectively, and its instrument already chosen.

The eight addenda below are kept as the record of the investigation:
what held, what was wrong (including two of my own wrong theories, both
retracted in place), and what each probe measured. They are history
now, not open work.


Every send from the app failed SMTP AUTH with `535 BadCredentials` while
the same credential — proven by scripted `smtplib` from this host AND
from the device's own network — authenticated instantly, both AUTH
PLAIN and AUTH LOGIN, on both ports. A transcript that says "valid
credential refused" reads like an impossible bug; it took four probe
builds to find the truth, and each probe ruled out one lie I had
believed about the transcript (including a STARTTLS exchange I
transcribed that the binary provably cannot send — screenshots of
small text are testimony, not evidence; the decisive probes printed
booleans and lengths, never contents).

**The truth, via a reference file planted in the app container and one
boolean:** `passMatchesRef=FALSE`. The app was authenticating with a
password that was NOT the one just saved. Two items matched the
keychain query — the setup form's `SecItemUpdate` did not match an
older item's attributes, `SecItemAdd` succeeded BESIDE it, and
`loadPassword` then returned either sibling. IMAP kept accepting the
OLD one, so mail flowed all day and nothing looked wrong there.

**Fixed** in `CredentialStore.writePassword`: a sweep deletes every
sibling for the same account+server — any protocol, any port — before
writing, so exactly one item survives. One item per account is the
invariant; the sweep enforces it.

**And a second cause was hiding behind the first.** After the fix, a
send still 535'd once — then succeeded 46 minutes later with the SAME
credential: `235 Accepted`, and Gmail took the letter
(`250 2.0.0 OK finished`). Google had temporary-blocked SMTP AUTH for
the old password after the afternoon's failures; the block expired on
its own. `BadCredentials` is what Gmail returns for that state too, so
the string cannot distinguish "wrong password" from "right password,
temporarily blocked" — worth knowing before anyone regenerates a
perfectly good app password.

**Delivery of the first successful letter is confirmed only by the
server accepting it**, not by its arrival in the recipient's mailbox:
server-side and direct-IMAP searches of both accounts found nothing,
though the app displayed replies that the server could not show me.
The display and the server disagreed; the discrepancy is unresolved
and worth a second look. The probes are removed and the build on the
device is clean.


---

## B-033 ADDENDUM (late evening) — what held, what was wrong, what remains open

**Held:** the keychain sibling bug and the sweep fix. The old item's
password belongs to a DIFFERENT Gmail account — almost certainly
the account from the original dev setup, whose mailbox is exactly
the correspondence the app displayed
when `loadPassword` returned the old sibling. Gmail IMAP accepts an
app-password token under a mismatched LOGIN username and opens the
TOKEN's mailbox; SMTP binds the pair and answers 535 — which was the
afternoon, in one sentence.

**Wrong, and corrected here:** the "temporary Google block" theory in
the section above. The mismatch explains every 535 without it.

**Also wrong, twice, and worth the humility:** a "second concurrent
writer" theory — the suspicious file mtimes were my own edits, and a
transcript line I believed in was my fifth misreading of small log
text today. There was no interleaver.

**Verified fixed:** after re-entering the password through Settings
(with field coordinates checked against a screenshot first — the
first attempt typed into the name row and saved nothing), the app is
on carlo's mailbox, matching direct IMAP exactly.

**OPEN — app letters are accepted then silently dropped.** Four app
sends reached `DATA-REPLY-CODE 250` (a number, not a read), yet none
arrived and none has a Sent copy — while the SAME credential from
scripted SMTP delivers instantly, and the app-built letter's exact
bytes (17 KB, multipart/related, logo) sent raw from the host DELIVER
and appear in Sent. Credential exonerated, content exonerated,
protocol code reads correct. Something in the app's exact wire bytes
triggers a silent drop. Next step, precisely: log the payload byte
count and a digest of the built message at send time, diff against
the known-good raw; or dump the built message into the app container
before `send` and byte-compare. One build cycle.

The Diagnostics transcript gained one permanent line: the DATA reply
code as a bare number (`DATA-REPLY-CODE 250`), because today proved
that reading protocol replies out of screenshots is testimony, not
evidence.

---

## B-033 ADDENDUM 2 — the elimination table, and the one contradiction left standing

**What is proven, machine-side, not by screenshot:**

| Claim | Evidence |
|---|---|
| The keychain holds exactly ONE item, imaps:993, carlo | probe: `KEYCHAIN 1 items: [imaps:993 "Blackmail (carlo@example.org)"]` |
| pw1 is carlo's and ONLY carlo's | python IMAP: owner-mail+pw1 → AUTHENTICATIONFAILED; carlo+pw1 → OK, 18 messages |
| carlo's mailbox is 18 messages, newest Google alert 06:18 | raw IMAP dumps, three times across the evening, plus Sent/Drafts/All |
| The app builds the letter byte-identically to the known-good | `BUILD-SIZE raw-letter=17997 html=5310 inline=1` = host rebuild 17,997 |
| The app's SMTP session authenticates and is accepted | `DATA-REPLY-CODE 250`, full 250-OK text with Gmail queue id |
| Identical bytes + identical sequence from python deliver | "logo test five" (host raw send) arrived at owner-mail 23:02 |
| The app's letters appear NOWHERE server-side | every folder of every reachable account, two clients, repeatedly |
| The app's list shows phantom rows for its own sent letters | rows "From: owner-mail … sink three/four" minutes after each send |
| No second writer, no interleaver | mtimes were mine; the "foreign probe line" was a misread |

**The contradiction:** the app holds the only-carlo credential, yet displays
rows that exist in no mailbox that credential can open. One of the "proven"
facts above is therefore wrong, and after six documented misreads of
screenshots tonight, the likeliest wrong fact is one I read off glass rather
than measured. The transcript's own text has been read wrong too many times
to be treated as ground truth without numbers.

**Next step: one build cycle, one log line:** at list time, log the
SELECTed mailbox name, UIDVALIDITY, EXISTS count, and the newest message's
Message-ID — that maps the app's IMAP session to one specific mailbox and
ends every remaining guess. If that line says carlo/18, the phantom rows are
client-side and live in the list controller; if it says anything else, the
session identity question reopens with a number attached.

**State restored before stopping:** device plist back to smtp.gmail.com:465,
no self-signed flag; keychain single-item via the sweep; clean probe-free
build deployed; the TLS-sink debug bypass stripped from the tree. 355 tests
green. The DATA-REPLY-CODE line stays, deliberately — tonight is the proof
of why it exists.

## B-033 ADDENDUM 3 — the session is pinned: it IS carlo's mailbox

The one-cycle logging build ran. At list time the app logged:

    SESSION-IDENT folder=INBOX uidv=1 exists=18 uids=18

Server-side, computed independently by scripted IMAP the same minute:

    server EXISTS: 18
    server UIDVALIDITY: 1

**Exact match.** The app's IMAP session is carlo's real mailbox, listing
the real 18 messages — the same 18 every direct probe has seen. The
"mystery mailbox" reading of the app's display is therefore dead: no
phantom rows exist in the listing the app draws (`uids=18` — a phantom
row would make it 19).

Two consequences. First, the rows I read all evening as owner-mail
correspondence and sent-letter phantoms were rendered from data that does
not come from this listing — either client-side state I have not located,
or (six misreads tonight say this is live) my own misreading of glass.
The reading pane's "From: owner-mail / Subject: sink capture two" header
block remains unexplained by this addendum and is the next thing to
reproduce WITH the SESSION-IDENT probe in the build, since a loadMessage
for a message that is not in the 18 would now be visible as a session
anomaly in the same log.

Second, the SMTP mystery is now cleanly isolated: IMAP provably carlo,
SMTP provably authenticated and 250-accepted, letters provably absent
from every server — with the IMAP side no longer suspect, the fault is
in the SMTP session's payload or identity alone, and the byte-identical
host send that delivers narrows it to the one thing still unmeasured:
what the app's TLS layer actually puts on the wire. A properly-certified
capture sink (Let's Encrypt on a real domain, not self-signed) is the
instrument for that.

`SESSION-IDENT` stays in the tree as permanent diagnostics, alongside
`DATA-REPLY-CODE`, for the same reason: identity established by numbers,
not by reading screenshots.

## B-033 ADDENDUM 4 — the phantom reproduced, and bisected to the display era

The reading-pane header block reproduced under the probe: after sending
"phantom probe one" to owner-mail, the top list row read "Owner-mail /
phantom probe one" and opening it rendered a full header block
`From: owner@example.com / To: Carlo / Subject: phantom probe one`
— for a letter that exists on no server.

Then the bisection, in numbers:

- Post-send listing: `SESSION-IDENT folder=INBOX uidv=1 exists=18 uids=18
  first-row=1/17 sender=Owner-mail <owner@example.com>` — the real
  mailbox, 18 UIDs, but the first row's sender already wrong.
- Clean relaunch (no send), PAIR probe on the same construction path:
  `PAIR uid=17 sender=Carlo <carlo@example.org> subject=Fwd: Your
  receipt…`, `uid=18 … Google … Security alert` — **every uid→sender→
  subject pair matches the server exactly.**

So: the FETCH-and-parse layer produces correct summaries; the phantom
metadata appears only in the listing that runs **after a send**, and by
the time SESSION-IDENT sees the summaries array its first row already
carries the sent letter's recipient and subject attached to a real UID.
The corruption happens between the correct `summaries(...)` return and
the array the listing ends up holding — a post-send state path
(`onDraftsChanged`/`onMessagesChanged`/reload) or the threading/display
layer that consumes it. One more cycle discriminates: send, then read
the PAIR lines of *that* listing — pairs correct ⇒ display layer;
pairs wrong ⇒ the post-send reload fetches something other than what a
clean launch does.

Both probes (`SESSION-IDENT`, `PAIR`) stay in the tree until B-033
closes; both print identities and pairings, never content.

## B-033 ADDENDUM 5 — the discriminator: two listings, interleaved

The post-send cycle ran with both probes live. Same seconds on the clock:

    PAIR uid=15 sender=Carlo … Fwd: Your receipt
    PAIR uid=16 sender=Carlo … Fwd: Your receipt
    PAIR uid=17 sender=Carlo … Fwd: Your receipt
    PAIR uid=18 sender=Google … Security alert
    SESSION-IDENT folder=INBOX uidv=1 exists=18 uids=18
                first-row=1/17 sender=Owner-mail <owner@example.com>

The PAIR loop is *inside* the construction that SESSION-IDENT then reads.
Correct pairs in, wrong first row out — in the same invocation — is not
possible. The resolution is that they are **not** the same invocation:
the send fires both `onDraftsChanged` and `onMessagesChanged`, two
listings run, and the PAIR lines visible belong to the clean one. The
phantom-carrying listing's own PAIR lines exist in the log one window
further down, uncaptured — and reading them is the entire next step:
they either name the UID whose parse produced Owner-mail, or they show
that listing fetching a different folder or a second connection
(`retryingIfDisconnected` can open one) — after a day in which the
keychain was proven single-item, a second *session* is not the same as a
second *item*, and this is where that distinction gets tested.

The phantom's shape is now fully bounded: post-send only, real UIDs,
metadata from the sent letter attached to a real row, produced by a
listing interleaved with a provably-clean one.

## B-033 ADDENDUM 6 — resolution of the phantom: the drafts folder, and a transpose

Pixel-truth at 3× zoom rewound one wrong fact: SESSION-IDENT says
`first-row=1/17 sender=Carlo <carlo@example.org>` — it never said
Owner-mail. Misread #7. The listing data was correct at every stage,
all along: fetch, parse, construction, first row.

What remained real after the zoom pass — the reading pane's header
block at 3× is unambiguous:

    From: owner@example.com
    To: Carlo
    Subject: phantom probe one

That is the just-sent letter with **From and To transposed**. And the
synthesis that closes the phantom:

- The composer **autosaves a draft** (the 2,257-byte APPEND seen in the
  transcripts) to the Drafts folder while composing.
- `sendTapped` deletes it after the send — which is why every later
  server-side drafts check finds 0.
- The "phantom rows" are the **Drafts folder listing**: a drafts list
  shows the recipient where a mail list shows the sender — "Owner-mail
  / phantom probe one" is the draft's To-address and subject, rendered
  in the list because the app was sitting on the Drafts folder after the
  send's `onDraftsChanged`, not on INBOX. My screenshots never verified
  which folder was selected.
- The reading pane rendered the draft's headers with **from and to
  transposed** — a real defect, small and fixable, in the drafts render
  path (loadDraft/MessageHeaderView for drafts).

Two bugs die here and one is born: the "mystery mailbox" and "phantom
metadata" never existed — both were the drafts folder seen without
knowing it was the drafts folder, plus one misread log line each. The
real defect found in the wreckage: **the drafts pane transposes From and
To.** That is the fix to make.

The SMTP vanishing — 250-accepted letters absent from every server —
remains the one genuinely open question, now with the IMAP side
completely exonerated by numbers and the display side exonerated by
zoom. The instrument for it is unchanged: a capture sink with a real
certificate.

## B-033 ADDENDUM 7 — correcting my own correction: there is no transpose to fix

Addendum 6 concluded "the drafts pane transposes From and To" and named
it the fix to make. That conclusion was premature, and pursuing it found
the opposite:

- The builder's bytes: `From: Carlo <carlo@example.org> | To:
  owner@example.com` — correct, proven by round-tripping the exact
  saveDraft build on Linux.
- The parser and the loadMessage construction: sender IS the From
  header, to IS the To header — correct, same round trip.
- No local Message construction in the UI transposes anything; the only
  two build sites pass sender through verbatim.

**No transposing code exists.** The single observation of a transposed
header block survives its 3× zoom, but it sits alone at the end of a
night with seven documented misreads, on a message that cannot be found
on any server, in a folder state that was never verified. An attempt to
leave a live draft on the server for byte-inspection could not be
completed through synthetic touch (the save dialog's buttons would not
land), so the one untested step — what Gmail serves back for an
appended draft — remains unmeasured.

What ships instead of a ghost-fix: `DraftHeadersRoundTripTests`, four
tests pinning the entire saveDraft → loadMessage round trip exactly as
both sides run it. If a transpose ever becomes real — in the builder,
the wire bytes, the decode, or the header-to-Message mapping — it trips
in seconds. The file's doc comment carries the whole story, so nobody
re-proposes a fix for code that provably does not transpose.

If the transposed render is ever observed again: leave a draft on the
server by hand (Cancel → Save Draft), then fetch its raw bytes before
anything else — the stored bytes are the only step this record has not
measured.

## B-033 ADDENDUM 8 — the last unmeasured step, measured: Gmail serves drafts back verbatim

The chain is now measured end to end, every link, with the app's own
builder bytes:

1. Builder bytes (Linux round-trip): `From: Carlo <carlo@example.org>
   | To: owner@example.com` — correct.
2. APPEND to `[Gmail]/Drafts` with the app's exact flags
   (`\Draft \Seen`), from a real IMAP client: OK, APPENDUID 6/4.
3. **What Gmail serves back: the identical 397 bytes, header for
   header.** And the ENVELOPE it serves — what list rows are built
   from — reads `from (("Carlo" NIL "carlo" "example.org")) …
   to ((NIL NIL "owner" "example.com"))`. Correct, not transposed.
4. Parser and loadMessage construction (Linux round-trip): correct.
5. UI constructions (code audit): pass sender through verbatim.

**No link in the chain transposes anything, and the one link outside
our code — Gmail's handling of an appended draft — is now measured and
clean.** The single transposed-header observation therefore cannot have
come from this pipeline in any state it can occupy. It stands as an
unreproduced rendering anomaly, most plausibly a ninth misread or a
real message seen in a folder state that was never verified. The
regression tests in `DraftHeadersRoundTripTests` guard the whole
pipeline regardless.

The probe draft was deleted after the measurement; carlo's account
holds no test residue from this.

## B-034 — DOES NOT REPRODUCE (2026-09-22). The letters arrive.

**The question, stated once and precisely:** a letter sent from the app
authenticates (`235 2.7.0 Accepted`), uploads (`DATA-REPLY-CODE 250`
with a real Gmail queue id), and the connection closes cleanly — and
the letter then exists on no server: not in the recipient's mailbox
under any sender, not in the sender's Sent, not in any folder of any
reachable account. Meanwhile the SAME credential from scripted SMTP,
and the app-built letter's EXACT bytes sent raw from a host, both
deliver instantly and get Sent copies.

**Everything already eliminated, with the evidence that eliminated it
(carried from B-033's addenda):**

| Suspect | Eliminated by |
|---|---|
| Wrong credential at send time | keychain proven single-item (`KEYCHAIN 1 items:`); pw1 proven carlo-only |
| ~~The letter's bytes~~ **NOT ELIMINATED — see the correction below** | `BUILD-SIZE raw-letter=17997` is a LENGTH, not a digest |
| The command sequence | python replicated EHLO/MAIL FROM (incl. `BODY=8BITMIME SIZE=`)/RCPT/DATA/stuffing — delivered — but the replay was transcribed from a log read off GLASS |
| The credential's outbound health | host probe from the same credential: delivered |
| IP reputation | iPad and host share the egress IP (203.0.113.10) |
| The device clock (Date header) | iPad clock correct to the second |
| Message-ID / subject / recipient | RCPT TO verified verbatim; fresh UUIDs; host sends with foreign IDs deliver |
| The IMAP session's identity | `SESSION-IDENT folder=INBOX uidv=1 exists=18 uids=18` == server truth |
| Gmail's post-acceptance handling of appended mail | drafts served back verbatim (B-033 addendum 8) |
| A second writer / interleaver | mtimes were ours; the "foreign probe" line was a misread |

### CORRECTION 2026-09-22 — one row of that table was overclaimed, and it is the one the conclusion rested on

**"The letter's bytes" was never eliminated.** The cited evidence,
`BUILD-SIZE raw-letter=17997 html=5310 inline=1`, is three integers.
Two different 17997-byte messages produce it. No digest of the built
message was ever taken — the B-033 addendum *proposes* "a count and
a digest of the built message at send time" as a next step, and it was
never carried out. The row said "== host rebuild byte-for-byte"; the
measurement behind it was a length comparison.

That matters because this table is what sends the investigation to the
transport layer. If the app builds a *different* letter of the same
length, every downstream observation is explained without any TLS
mystery at all: the bytes are handed to `write` faithfully, transmitted
faithfully, accepted by Gmail faithfully, and dropped because of what
is IN them.

**A second row is softer than it reads.** "The command sequence" was
replicated by a python script transcribed from a diagnostic log **read
off the screen** — in an investigation that has now recorded eight
misreadings of that screen. It is good evidence; it is not machine
evidence.

**So the cheapest instrument is not the capture sink.** The sink
measures what the app puts on a TLS session to a server that is *not*
Gmail, on a different port, with a different password — an inference
about the failing path rather than a measurement of it. Before any of
that: write the exact `raw` bytes and `Diagnostics.transcript()` to
files in the app container during a real, failing Gmail send, and pull
them off. One deploy, one letter, no domain, no certificate, no open
port, no credential exposure. That settles the bytes question and the
sequence question on the actual failing session.

Also worth knowing before anyone tries to reproduce the reference
letter: `RFC5322Builder.rfc5322Date` uses `"EEE, d MMM yyyy HH:mm:ss
Z"` — `d`, not `dd` — so a letter built on days 1-9 of a month is
**17996** bytes, not 17997. And `/tmp/app_letter5.eml` (the 17997-byte
reference) has **no `Cc:` header and one recipient**, so any comparison
run against a cc'd letter cannot match by construction. That file lives
in `/tmp` on a server and its provenance is recorded nowhere; copy it
somewhere durable before relying on it again.

**What remains unmeasured, and therefore suspect:** the actual bytes
the app's TLS layer puts on the wire. Every transcript line is written
from what the code HANDS to `connection.write`, not from what
NWConnection transmits. A self-signed capture sink failed at the TLS
handshake (correct iOS behavior — `connect failed 54`), so the wire has
never been seen.

**The instrument, already chosen:** a capture sink with a real
certificate — Let's Encrypt on a real domain, port 465, logging the
full session. Point the account's `smtpHost` at it for one send. Two
outcomes, both conclusive: the sink's log contains the session → those
bytes diffed against the known-good raw name the divergence; the sink
sees nothing while the transcript claims a session → the transport
layer itself is lying to the log, a different and stranger bug with its
own next step (an in-process echo: log a digest of the exact `Data`
handed to `send`, and of the completion's byte count).

**Constraints and notes for whoever picks this up:** `deploy-to-ipad.sh`
takes `IPAD_SSH_PORT`; the typing harness takes `IPAD_SSH_PORT` and
`IPAD_FLIPPED` (the device is currently flipped 180°). Verification sends go
to owner-mail, at most two, one with a cc. The permanent probes in the tree (`SESSION-IDENT`,
`DATA-REPLY-CODE`, `BUILD-SIZE`-era learnings; `PAIR` until 2026-09-30,
see B-033) exist to keep this investigation in numbers.

---

### RESOLUTION ATTEMPT 2026-09-22 — instrumented, sent twice, both delivered

**Status: does not reproduce. Not the same as fixed — read the last
section before closing it.**

The correction above said the cheapest instrument was not the capture
sink but an in-process dump. That was built and run:

- `CaptureProbe` wrote the exact `Data` handed to `SMTPClient.send`, the
  exact dot-stuffed payload handed to `TLSConnection.write`, and
  `Diagnostics.transcript()` — all to files in the app container.
- `TLSConnection.write` gained `WIRE-OUT bytes=` / `WIRE-ACK err=`,
  length-only and gated above 1 KB so the `AUTH` line's length (which is
  the credential's length) is never recorded.
- Built, deployed and md5-verified on device
  (`a7f8356…`), and driven through the real compose UI with touchsim.

**Two letters, both to owner-mail, single recipient, no cc, signature
with the inline logo — the shape of the ones that vanished. Both
arrived**, intact, with `sig-logo.png` resolving as `cid:sig-logo`.

The captured session, machine-recorded rather than photographed:

```
ENVELOPE from=carlo@example.org rcpt=1 host=smtp.gmail.com:465
220 smtp.gmail.com ESMTP …
250-smtp.gmail.com at your service, [203.0.113.10]
235 2.7.0 Accepted
MAIL FROM:<carlo@example.org> BODY=8BITMIME SIZE=17953
RCPT TO:<owner@example.com>          250 2.1.5 OK
DATA                                     354 Go ahead
WIRE-OUT bytes=17956 / WIRE-ACK err=none
250 2.0.0 OK  1790053739 …               221 closing connection
```

**What that settles for good.** `SIZE=17953` equals the dumped letter
byte for byte; the wire payload is exactly `raw + 3` (the terminator, so
no line needed dot-stuffing); and the write completion handler fired
with **no error** before the 250. The app hands the transport what it
says it hands it, and the transport takes it. **The
transport-is-lying hypothesis is dead, and the capture sink is
unnecessary** — no domain, no certificate, no open port, and no
credential was ever exposed to a non-Gmail server.

**What it does NOT settle.** Why the earlier letters vanished. Three
candidates survive and this run cannot separate them:

1. Gmail was silently dropping submissions from that credential during
   or after the 535 storm, and has since stopped. Self-resolving, and
   consistent with everything observed.
2. The earlier server-side searches missed letters that were in fact
   delivered. Hard to credit given how thoroughly they were done, but
   the search evidence is the one part of the original investigation
   that was never machine-recorded either.
3. A genuinely intermittent fault that simply did not fire twice today.

**The permanent instrument.** The byte dumps were removed — they write
his correspondence to the container in plaintext, which must not ship on
a device going to a ninety-year-old. `CaptureProbe.dumpTranscript` and
the `WIRE-OUT`/`WIRE-ACK` probes stay: redacted, no message content, and
they end the practice this record has suffered from throughout, of
drawing conclusions from a photograph of a debug screen. Deployed clean
as md5 `9b0d4ba…`.

**If it recurs**, the transcript is already on disk — no rebuild needed:

```
ls -t <container>/tmp/blackmail-send-*.txt | head -1
```

A `-fail` suffix means the send threw; `-ok` means it reached the
letter's 250 (it meant the 221 until B-044, which stopped waiting for it). Read
`WIRE-ACK` first. Only if that line is missing while a later `250` is
present does the transport become a suspect again, and only then is the
sink worth building — the scoping for it is done and needs nothing
bought: a server with a valid certificate is already available.

---

## B-035 — OPEN. It is a sideload onto HIS iPad, and the signature cannot follow it

**Established 2026-09-22, and it invalidates a standing assumption.** Every
handover note in this file assumed the dev iPad was the one Sam would get.
It is not: the app is sideloaded onto one of his own iPads, and this one
stays as the dev iPad. So B-021's photo wipe, B-028's Envelope Index and the
Apple ID sign-out are all struck. What replaces them is harder.

**The blocker: his signature can only be installed by editing a plist.**
`signatureHTML` and `blackmail.signatureInlineImages` — the rich signature and
the inline logo — are reachable from **no UI in the app**.
`SettingsViewController` edits the plain-text `signature` only, and the one
thing it can do to the rich version is *clear* it (`plainOnlyButton`, line 262).
Everything else has always been done by writing
`wtf.uhoh.blackmail.account.v1` directly into the container, which needs
filesystem access to the app's sandbox.

On this jailbroken dev iPad that is routine. On a sideloaded install it
depends entirely on the install vector, and for a plain AltStore/SideStore
sideload it is **not available at all**. The account itself is fine — B-031
proved setup works from the app's own form with nothing but an address and an
app password — but a letter with no signature is not what this was built for,
and the whole of B-025's inline-logo work reaches his iPad only if this is
solved.

**The fix, recommended:** ship his signature as a compile-time default —
the markup and the logo bytes in the bundle, applied when an account is first
saved. This is a single-purpose app for one person; the signature is not
really a setting. It removes the plist dependency completely and makes the
install a matter of typing an address and a password. The trade-off is that
his contact details would then live in the source rather than only on his
device; the decision is the owner's.

**CORRECTION 2026-09-22, same day: the signing worry above was the wrong
one.** The owner has a **paid** Apple Developer membership, so the
free-Apple-ID seven-day refresh never applied. Measured from
`~/.apple-signing`:

| | |
|---|---|
| Certificate | `Apple Distribution: A. Developer`, team `JGLH7HX44Y` |
| Profile | the ad-hoc profile, created 2026-09-18 |
| Both expire | **2027-09-18 10:22:36 GMT**, the same instant |
| `ProvisionedDevices` | **exactly one** — `00000000-0000000000000000` |

**That one device is the dev iPad** (`idevice_id -l` agrees to the
character). An ad-hoc build launches only on a UDID baked into the profile
when it was generated, so **today's IPA cannot run on Sam's iPad at all** —
not as a weekly expiry, as a refusal to launch. This is the actual
deployment blocker and it was invisible behind the wrong question.

**The fix is small and needs no code:** add Sam's iPad's UDID to the team
(ad-hoc allows 100 iPads per membership year and one is in use),
regenerate the ad-hoc profile with both devices, drop the new
`.mobileprovision` into `~/.apple-signing/`, re-sign. `deploy-to-ipad.sh`
picks it up unchanged. Getting his UDID needs the iPad on a cable
(`idevice_id -l`, or Finder) — it is not shown anywhere in Settings.

**What remains true about expiry.** Cert and profile die together on
2027-09-18, on a device belonging to someone who cannot re-sign it, and a
lapsed membership revokes the certificate *immediately* rather than at
expiry. Annual, not weekly — but it still lands on him. The only route
with no expiry at all is TrollStore, which depends on his iPad's iOS
version (roughly 16.6.1 or below), which is why that question still
matters.

**So the questions that remain are two, not three:**

1. **Which iPad, and which iOS?** It decides TrollStore-or-certificate,
   and therefore whether this expires at all.
2. **Does the chosen vector give filesystem access to the app container?**
   If not, the signature has to ship as a compile-time default — see
   above. A paid certificate does **not** help with this: signing and
   sandbox access are unrelated, so this half of B-035 stands untouched.

**Related, and now more urgent than it looked:** the signing expiry recorded
against this dev iPad (cert and ad-hoc profile both dying 2027-09-18) applies
to whatever is used on his iPad too, unless the vector is TrollStore. An app
that stops launching on a date nobody is watching, on a device belonging to
someone who cannot fix it, is the worst failure mode this project has.

---

## B-036 — BUILT 2026-09-30, seen working on the iPad. He shares to email constantly, and the app cannot receive a share

**2026-09-22: he shares to email a lot, and none of the share routes
is implemented.** Measured
from `ios/Resources/Info.plist` and the package, not inferred:

| Route into a mail app | Declared? |
|---|---|
| `NSExtension` (share sheet) | **absent** — and there is no extension target and no `.appex` anywhere |
| `CFBundleURLTypes` (`mailto:`) | **absent** |
| `CFBundleDocumentTypes` ("Open in…") | **absent** |

So Blackmail appears in no share sheet, answers no `mailto:` link, and is not
an "Open in" target. Every one of those routes goes to Apple Mail.

**Why this matters more than it sounds.** He is keeping his own iPad, which
still has Apple Mail on it. The failure is therefore not "a feature is
missing" but **a split correspondence**: anything he shares goes out through
Apple Mail, under Apple Mail's account, and never appears in Blackmail's Sent
— so the app that was built so he could find his mail would be missing a
chunk of it, in a way neither he nor anyone helping him would spot. For
someone whose stated main problem was *finding* things, that is the worst
possible shape of bug.

**The good news, and it is genuinely good.** The provisioning profile is a
**wildcard**: `application-identifier = JGLH7HX44Y.wtf.uhoh.*`, with
`keychain-access-groups = JGLH7HX44Y.*`. So a share extension at
`wtf.uhoh.blackmail.share` needs **no new App ID and no new profile** — the
existing ad-hoc profile already covers it, and it can read the same Keychain
items the app uses. That removes the two steps that usually make this a
portal chore.

**The two real obstacles:**

1. **No App Groups.** Apple does not allow the App Groups capability on a
   wildcard App ID, and App Groups is the normal way an extension hands data
   to its container app. The credential is fine (shared Keychain covers it),
   but the ACCOUNT — address, hosts, signature — lives in the app's own
   `UserDefaults`, which the extension cannot read. The clean way out is to
   mirror the account into the shared Keychain group and let the extension
   send by itself, rather than handing off to the app. That also makes
   sharing work without the app being launched, which is the behaviour Mail
   has and therefore the one his hands expect.
2. **UNVERIFIED: can this toolchain even build a nested `.appex`?** The whole
   project is SwiftPM cross-compiled on Linux with `xtool` and signed with
   `zsign`, deliberately without Xcode (see BUILD_DECISION). An app extension
   is a second bundle inside `Blackmail.app/PlugIns/`, with its own Info.plist
   and its own signature. Nothing here has ever produced one. **This is the
   risk that decides whether B-036 is a day or a fortnight**, and it should be
   settled with a throwaway do-nothing extension before any of the above is
   designed.

**`mailto:` is probably not available and should not be counted on.** iOS
routes `mailto:` to the *default mail app*, and becoming the default needs the
managed `com.apple.developer.mail-app` entitlement, which Apple grants by
application and which an ad-hoc sideload will not have. Registering the scheme
may simply do nothing. Worth five minutes to confirm on the dev iPad before
anyone budgets for it; not worth planning around.

### SPIKE RUN 2026-09-22 — the toolchain CAN build an extension. Two other things block it.

The decisive question is answered: **yes.** `Sources/BlackmailShare` compiles,
links and signs on this Xcode-less Linux pipeline.

The one line that makes it work is in `Package.swift`:
`-Xlinker -e -Xlinker _NSExtensionMain`. An extension's entry point is
Foundation's, not the `main` SwiftPM generates, and this is exactly what Xcode
passes for an extension target. Verified in the Mach-O rather than assumed:

```
filetype 2 (MH_EXECUTE)     LC_MAIN entryoff = 0x4818
entry lands in __TEXT,__stubs        _NSExtensionMain: UNDEFINED (imported)
_main: defined at 0x100004000        ← NOT the entry point
```

Without that flag the bundle builds, installs, and is silently never loaded.

`package.sh` bundles it as `PlugIns/BlackmailShare.appex`, and zsign signs the
nested bundle by itself (`SignFolder: PlugIns/BlackmailShare.appex`). So build,
package and sign are all solved.

**Blocker 1 — zsign cannot give the extension its own entitlements.** It takes
one `-e` for the whole archive, so the `.appex` is signed with the APP's
`application-identifier` (`JGLH7HX44Y.wtf.uhoh.blackmail`) while its bundle id
is `wtf.uhoh.blackmail.share`. iOS wants those to match. Two-pass signing —
the appex alone first, then the app — does **not** survive: zsign re-signs
nested content and overwrites it, measured. The options are patching zsign
(it is open source and this is a small feature), or finding a signer that
does per-bundle entitlements. `ldid` is on the dev iPad and does support
them, but re-signing the appex after the fact invalidates the outer bundle's
`CodeResources` seal, so it is not a drop-in.

**Blocker 2 — the dev iPad cannot test registration.** `deploy-to-ipad.sh`
writes files into an existing bundle with `cp -a`; installd is never
involved, and **plugin registration happens at install time**. The `.appex`
lands on disk correctly signed and is simply never registered: `pluginkit` is
not present on the device, and `uicache -p` does not register it either.
Confirming an extension actually appears in the share sheet needs a real
`ideviceinstaller` install — and that tool is missing on both machines
(it is already on `provision-ipad.sh --check`'s list for the on-site install).

**The extension is therefore OPT-IN and off by default** (`BLACKMAIL_SHARE_EXT=1`).
That is not tidiness: the copy-based deploy never exercises installd, but
`provision-ipad.sh` does a real install on HIS iPad, and an extension with a
mismatched identifier is the sort of thing installd rejects outright. Shipping
an unverified `.appex` by default would risk the one install that matters in
order to gain a feature that does not work yet.

**Revised estimate.** Not the hour first estimated. Blocker 1 is a zsign
patch and a second entitlements file; blocker 2 is `ideviceinstaller` plus one
real install. Both are bounded and neither is research. Call it a day or two,
with the share-sheet-appears-at-all question answerable in the first hour of it.

**Order of work, if it is taken on:** the throwaway `.appex` first (it either
builds or it doesn't, and everything depends on that), then the Keychain
mirror, then the extension's own compose sheet — which should be the smallest
thing that works: recipient, subject, the shared item attached, Send. Not a
second copy of the composer.

### BUILT 2026-09-30 — signed as itself, the account handed over, a sheet that sends

All of the order of work above except the install. What the host checks
is listed with each part; what only a device can show is listed last.

**Blocker 1 is gone: zsign is patched.** `tools/zsign/bundle-entitlements.patch`
adds `-X KEY=FILE` to zsign 1.1.2 (the installed version, and the newest
upstream tag): the nested bundle whose bundle id, or whose path inside the
`.app`, is KEY is signed with FILE's entitlements instead of `-e`'s, gets
the profile embedded in it as Xcode would, and a KEY that matches nothing
fails the signing rather than quietly signing that bundle as the app.
`tools/zsign/build.sh` rebuilds it into `/mnt/build/zsign-blackmail`
(TOOLCHAIN.md). The entitlements are now the repo's, in `ios/Resources`.
Without the extension the app is signed with `Blackmail.entitlements`,
byte for byte the signing directory's `blackmail.entitlements` that every
build proven on his iPad was signed with, no `keychain-access-groups` at
all. Only an IPA carrying the extension signs the app with
`BlackmailWithShare.entitlements`, which adds the shared group, and the
extension with `BlackmailShare.entitlements`. So the default build, the
one `provision-ipad.sh` would put on his iPad, is signed exactly as before
until the extension build has been seen on the dev iPad.

`tools/sign-ipa.sh` is the one way deploy and provision sign, and it
refuses to sign an IPA carrying the extension with a zsign that has no
`-X`. It then reads every signature back with `tools/check-signature.py`,
out of the Mach-O itself: each bundle's `application-identifier` is the
team plus its own bundle id, the team is JGLH7HX44Y, both carry the shared
keychain group when there is an extension and the app claims no
`keychain-access-groups` when there is not, the DER and XML entitlements
agree, the CodeDirectory's identifier and team are right, every page and
special-slot hash matches, the CMS signature is over the CodeDirectory, the
profile allows what each bundle claims, and the app's seal matches every
file in it, the extension's signed executable included. Measured on the
same unsigned IPA:

| Signed with | Extension's application-identifier | Check |
|---|---|---|
| stock zsign 1.1.2, one `-e` | `JGLH7HX44Y.wtf.uhoh.blackmail` | FAILS, and no profile in the extension |
| patched zsign, `-X` | `JGLH7HX44Y.wtf.uhoh.blackmail.share` | passes, all 41 checks |
| patched, then the extension re-signed alone | its own | FAILS: the app's seal no longer matches |

The last row is the two-pass approach, and why it could not work.

`provision-ipad.sh` could not have signed anything with the zsign here: it
handed zsign the IPA with no `-o`, which 1.1.2 refuses for an archive. It
signs through `sign-ipa.sh` now.

**The Keychain mirror (`ShareMirror`).** No App Groups, as expected: the
profile's entitlements are `application-identifier`, `keychain-access-groups
[JGLH7HX44Y.*, com.apple.token]`, `get-task-allow` and the team, nothing
else. So there is no shared container, and everything the extension needs
goes through one shared keychain group, `JGLH7HX44Y.wtf.uhoh.blackmail.shared`:
the account (address, hosts, name, both forms of the signature) with its
app password, the signature's pictures, and the recipient book, which is
what puts his own second address one tap away in the extension too. The
extension build's app lists its own group first in `keychain-access-groups`,
so an item added without naming a group stays where every earlier build
put the app password; `CredentialStore` names none and is unchanged. The
mirror names the shared group in every query. It is written by
`CredentialStore.save` and `saveAccountOnly`, cleared by `clear`, and
brought up to date at launch, going into the background and coming back,
off the main thread, each item written only when it has changed. All of
that only in an app that carries the extension (`ShareMirror.app`): a
build without it makes no Keychain call it did not make before. The other
way, the extension leaves who it sent to, one item per letter, and the app
takes those into its book as used, then removes exactly the items it read.
One list read, changed and written back by both processes would lose a
letter noted between the app's read and its delete. A Keychain that refuses
logs to the connection log and costs the app nothing. Checked behind a
`SharedKeychain` seam in `ShareMirrorTests`.

**The extension's sheet.** `ShareViewController` (in the library, so the
extension's executable is only an entry point and every line it runs is
the app's) shows a small composer over the app he shared from: Cancel and
Send, To with the book's suggestions, Cc/Bcc, Subject, the body, and a row
per shared file with Remove. The letter is `ShareLetter`: the title the
sharing app gives as the subject, the address alone above his signature as
the app adds it, text as text, a photo re-encoded to JPEG and attached as
the composer does. The HTML twin is Mail's envelope with the address as a
real `<a href>`: his own shared letters, read in Mail's output, carry the
address as bare text in a `<div>`, which this app's reading pane cannot
tap. It sends through `Submission` (called `Outbox` until B-052 gave the
app an Outbox of its own), which `IMAPMailRepository.send` now sends
through as well, with `ComposeActions` deciding the order exactly as in the
app's composer: "Sending…" at the tap, one letter however many taps, the
share ended at the 250, everything left as it was with the reason when it
fails, Cancel refused while it goes (`ShareSheetTests`, against the scripted
submission server). No Save Draft: that needs the IMAP connection this sheet
does not open, and a shared link is two taps to share again. With anything
of his in it (words above the signature, an address, a subject of his own),
Cancel asks before throwing it away, measured against the letter the share
began as, so it still asks after a Send that did not go
(`ShareSheet.asksBeforeCancelling`). The time iOS allows while it sends is
asked of `ProcessInfo`, an extension having no `UIApplication`.

What was shared is read one item at a time, and each photo or file is
staged on disk before the next is begun (`ShareItems`): an extension runs
under a far smaller memory ceiling than the app, and every photo decoding
at once to be re-encoded as JPEG would have it killed before the sheet
appeared. A file is copied rather than read, and one that would take the
share's files past 25 MB, which Gmail would refuse anyway, is left out
without being copied. The activation rule allows five images or files, as
the composer's picker allows five photos.

With no account mirrored it says "Open Blackmail once, then share this
again." That is also what an install of this build shows until the app has
been opened once, since the mirror is written by the app.

**`mailto:`.** `CFBundleURLTypes` declares the scheme, `MailtoLink` reads
RFC 6068 (addresses before `?` and in `to=`, `cc=`, `bcc=`, repeats kept,
percent-decoding, `+` left a plus, CRLF to line breaks), and the composer
opens with his signature under the body. A link's Cc and Bcc open their
rows in the composer (`Draft.showsCcAndBcc`): a link in a letter is a
stranger's, and a Bcc in a hidden row would get the letter unseen. Reply
All and a reopened draft with a Cc or Bcc open the same way. A link tapped
in a letter no longer asks "Open this link?" and goes to Apple Mail: it
opens this app's composer. One in another app arrives only if iOS sends it
here, which it does for the default mail app; that is still expected not
to happen.

**Still unseen, all of it needing a device:**

- That the extension is registered and appears in the share sheet at all.
  It needs an install through installd: `tools/build-share-ipa.sh` builds
  and signs `ios/Blackmail-share.ipa`, to go on with `ideviceinstaller -i`
  or through TrollStore, never the copy-based deploy.
- That it loads: the principal class is found by its Objective-C name
  (`ShareViewController`, present in the binary), and the entry point is
  `_NSExtensionMain`, both read from the Mach-O, neither run.
- That the Keychain reads work across the two on a device, and that the
  app's password item is untouched by the extension build's
  `keychain-access-groups`: copy-deploy it to the dev iPad, relaunch, and
  check the app still signs in with its existing password, before any
  extension build goes near `provision-ipad.sh`.
- The app's side of the mirror, which lives in `CredentialStore` and
  `AppDelegate` and runs only against the real Keychain: a signature
  changed in Settings reaches the next share, and removing the account
  leaves the extension saying "Open Blackmail once".
- Memory: share five full-size photos from Photos at once, and a video,
  and see the sheet come up with them attached (or the video left out if
  it is over 25 MB), then send. The letter is still built whole in memory
  at Send, as in the app.
- What Safari and YouTube put in the extension item: the title is taken
  from `attributedTitle`, then `attributedContentText`.
- The sheet's look beside the app's composer, and sending over TLS from the
  extension.
- Whether iOS hands another app's `mailto:` link here.

It stays opt-in (`BLACKMAIL_SHARE_EXT=1`) until the first of those has been
seen.

**Seen on the iPad, 2026-09-30**, the jailbroken test iPad, on carlo's
mailbox. The build with the extension was first copy-deployed: the app
opened and read the Inbox, so its password item survived the new keychain
groups. Then the same signed IPA was installed through installd with
TrollStore's helper (`trollstorehelper install installd force <ipa>`, the
IPA path last; with it first the helper returns 166 and does nothing).
After opening the app once, Safari's share sheet on a Wikipedia page
listed Blackmail second in its row. Its sheet came up with the page's title
as the subject, the address in the body with his signature under it, and
the recipient suggestions from the app's book, his second address among
them. Send gave way to "Sending…", the sheet closed at the server's
answer and left him in Safari, and the letter arrived in the Inbox with the
link blue and tappable. Not yet tried: YouTube, a shared photo (five at
once), Cancel with text in it, a failed send, and a `mailto:` link.

---

## B-037 — BUILT 2026-09-29 as B-048, not yet seen on the iPad. No way to switch between the two-panel and three-panel view

**Built as B-048; the decision is D-015.** What follows is the request as it stood.

**Requested 2026-09-22.** The shell is hard-wired to three panes:
Mailboxes | list | message. There is no way to drop to two and give the
letter more of the glass.

**It is a small change, and the groundwork is already right.**
`RootViewController` is deliberately *not* a `UISplitViewController` — it is
a plain container with hard constraints, and it already holds the two column
widths as stored properties (`mailboxWidth`, `listWidth`), sized from
`Theme.mailboxColumnWidth(forScreenWidth:)` and `Theme.listColumnWidth(…)`.
Two-panel mode is those constraints plus `divider1` changing, animated.

**Four things to get right, three of them learned the hard way here:**

1. **Hide the pane, do not zero its width.** A view with children and no
   width is *exactly* the B-027 shape — the ambiguous-layout class that cost
   two bugs and produced `LayoutAudit` — and the audit, once switched on
   from the connection log's Layout button (it is off by default), will
   report it every two seconds for three minutes. Set `isHidden` on the
   mailbox nav and the divider, and deactivate rather than zero the
   constraint.
2. **Follow Mail for the control.** Mail's answer is a sidebar toggle in the
   leading toolbar position, and the north star is to match Mail wherever
   Mail has an answer (see D-012). It should not be
   buried in Settings: this is a thing he might want to flip while reading,
   and a 44 pt target in the bar is what his hands already know. Settings can
   hold it as well, but the bar is the primary.
3. **Persist it**, the same way `organizeByThread` and `lastJumpScope` are
   persisted — `UserDefaults`, read with `object(forKey:)` so the default is
   explicit rather than `false`-by-accident. Three-pane stays the default.
4. **Do not let B-003 fight it.** The fifteen-minute away-timer refreshes the
   folder list and returns to Inbox; toggling panes must not be mistaken for
   a return, and a return must not silently re-expand a pane he collapsed.

**What it buys him.** The reading pane on an 11" iPad in landscape is
currently about half the width. For a 90-year-old reading at a large text
size, the difference between half and two-thirds of the screen is real, and
the Mailboxes column is the least-used of the three once he is settled in a
folder.

**Blocked on the device only for verification** — it can be written and
cross-compiled now; it cannot be seen until the iPad is back.

---

## B-038 — Performance review done 2026-09-22. Full report in docs/PERFORMANCE.md

Done while the iPad was offline, so: static review plus real benchmarks
run against the library on the Linux host. 66 candidate findings, each then
independently re-checked; **26 survived**.

**The headline is good.** Every network and parsing layer — `TLSConnection`,
`IMAPClient`, `IMAPMailRepository`, `SMTPClient` — is a plain actor with no
`@MainActor` leakage anywhere. Nothing found in the whole review can produce
a frozen screen, which is this product's worst outcome by its own ranking. No
third `MIMEDecoder` quadratic (base64 scales exactly 1:5:25). Previews are
hard-capped at 2048/8192 bytes so scrolling never pulls a body. Search is
debounced. Rows are a fixed 96 pt with no self-sizing pass. This is not a
codebase with a performance problem.

**The three worth doing first**, and none is a micro-optimisation:

1. `MessageDetailViewController.swift:165` — the reading pane keeps the
   PREVIOUS letter's header and body on screen for the whole fetch, while the
   selection bar has already moved. After a delete it re-reveals the letter he
   just deleted. `show(thread:)` at :229 already does this correctly and its
   comment explains why. This is the most-hit action in the app.
2. `RecipientBook.swift:92` — `record()` re-encodes and rewrites the entire
   300-entry address book per harvested address, ~1.2 ms each, 2-2.5 per
   message: **~150-190 ms per 50-row page**, and 1000+ calls on a wide
   search. Batch the flush. Lands on all three things he does constantly.
3. `RootViewController.swift:141` — a duplicate `await list.reload()`; the
   list view controller already reloads itself. Beyond the wasted round trips
   it **blanks out previews that had already landed** and **erases a search
   typed in the first seconds after launch, dismissing the keyboard**.

**A correctness bug fell out of it**, not a performance one:
`RecipientBook.shared` is a class whose dictionary is mutated from the
repository actor and read on the MainActor per keystroke — tools-version 5.9
means the compiler never flagged it. **Reproduced: SIGSEGV 8 runs out of 8.**
Real-world odds are low (order once a year) but the fix is an `NSLock` around
the dictionary access only — explicitly NOT held across `save()`, which would
trade a yearly crash for a per-keystroke hitch in the very interaction being
protected.

**Send-path CPU is 40-70x off** where it should be: `SMTPClient.dotStuffed`
walks the message byte-at-a-time through `Data` (3.5 s on a five-photo
letter), and `RFC5322Builder.uniqueBoundary` substring-scans every
attachment's base64 for a boundary that provably cannot appear in it. Both
fixes were verified byte-identical against the 366 tests. And there is **no
send feedback of any kind** — no spinner, no disabled button — during those
seconds.

**What would change most if measured on his actual iPad:** the `RecipientBook`
number (it rests on CFPreferences coalescing being cheap, which is documented
but not measured), and `LayoutAudit`, which ships in release and runs 90
whole-window main-thread sweeps over the first three minutes of every launch.
That one is unmeasurable from Linux and costs one `#if DEBUG` to remove. (Since
done as a runtime switch, off by default, instead of `#if DEBUG`; see B-030.)

---

## B-039 — A UID command could run in the wrong mailbox, and act on another letter

**RESOLVED 2026-09-28.** Found in simulation, then reproduced on the iPad
against the build before the fix, and the fix confirmed there the same
night (see "Confirmed on the iPad" below). A read mark or a flag landing on
the wrong letter looks like nothing at all, so it may well have happened
before anyone was looking.

**What it was.** A UID means nothing outside the mailbox that issued it, and
Gmail numbers each mailbox on its own, so one UID can name three different
letters in Trash, Spam and All Mail. The repository sent a SELECT and then
the command that depended on it, but the two took the connection
separately, with actor hops between them, and the SELECT was skipped
whenever the repository's own note said that mailbox was already open.
Any other screen's SELECT could land in between: a preview pass for another
mailbox, a search on its way through Trash, Spam and All Mail, the next
page of the list. The FETCH, STORE, MOVE or EXPUNGE then ran wherever that
had left the connection. The same note was also wrong for a moment after
every reconnect: the client reported itself connected before LOGIN was
answered, the note was cleared only once the connect returned, and a tap in
between skipped its SELECT and was answered BAD.

**What it could do.** Reads came back empty or wrong: blank previews under
search results, a letter that opened empty or as a different letter.
Writes acted on whatever letter wore the same UID in the mailbox left
selected. A Delete tapped during an All Mailboxes search could bin a letter
he never chose.

**How it was found.** By running the real `IMAPClient` and
`IMAPMailRepository` against a scripted Gmail-shaped server while measuring
where the lag came from: a Delete issued during an All Mailboxes search ran
its UID MOVE in
the wrong mailbox in 19 of 30 trials, and 196 of 250 previews under search
results came back blank. `MailboxAtomicityTests` reproduces it against the
previous code: 10 or 11 of its 30 writes run in Trash, Spam or All Mail
instead of the Inbox, none of those changes the letter he chose, and one
moves a different letter to Trash.

**The fix.** `IMAPClient` now owns the selection for its connection,
cleared on every connect and teardown, and the repository keeps no note of
it. Every UID command names the mailbox it must run in and goes out in one
hold of the exchange gate with the SELECT it needs; a command sent in
chunks takes a hold per chunk and checks again each time. Every command
that acts on a UID also names the UIDVALIDITY the UID came from, which the
id already carried, and is checked in the same hold after the SELECT: a
mailbox renumbered since the row was drawn refuses the command with nothing
sent. A refused SELECT still sends nothing that depended on it and keeps
the connection. The pairs that were two calls, an attachment's structure
and its bytes, a draft's `\Deleted` and its EXPUNGE, now go in one hold
each as well, and so do a folder's first page and a date jump, whose two
SEARCHes must come from one numbering.

**The same reconnect window sent a refused password twice.** A call that
found the connection being made either asked to connect as well, during
the TLS handshake, or queued its command, once the client called itself
connected. When the LOGIN was refused, the first made an attempt of its
own and the second read the closed connection as a dropped socket and
retried into a new one: with a revoked app password, two failed logins
for one moment of use. Every call already waiting when an attempt fails
now gets that failure, and the password goes once.

**And any other failure in that window, once (2026-09-29).** The read
retry still took a connect that failed some other way for a dropped
socket, when the read had queued its command after the client called
itself connected: a server that accepts the connection and never greets,
or a socket that dies during the LOGIN. The read connected again, and
against a server that says nothing that is a second connect timeout at
launch. A read no longer retries when an attempt to connect has failed
while it waited. `RepositoryTrafficTests` caught it now and then, as two
connections where it expected one: whether the Inbox's first page asked
before or after the socket came up was the order two tasks ran in. With
eight copies of that test running at once on the development computer it
failed 72 times in 320; with this, once, where the second call started
only after the attempt had failed, which the client rightly takes for
another attempt. The launch test now holds the handshake until both calls
are waiting, as they are at launch, and failed 0 times in 960.
`RepositoryWireTests` holds both halves of the window for a failure that
is not a refusal.

**Confirmed on the iPad, 2026-09-28**, on carlo's mailbox, driving the real
UI: open a letter in the Inbox, type an All Mailboxes search for a word with hits in Trash and All Mail,
tap Delete about half a second later, then read the connection log.

- Build before the fix, first try: the delete's `SELECT "INBOX"` landed
  between the search's `SELECT "[Gmail]/Spam"` and its SEARCH, so the Spam
  SEARCH and its FETCH ran in the Inbox; the reload after the delete then
  ran its `UID SEARCH ALL` and page FETCH in All Mail, and the list headed
  "INBOX" showed All Mail's letters under blank previews.
- Build before the fix, second try: the search's `SELECT "[Gmail]/Spam"`
  landed between the delete's `SELECT "INBOX"` and its `UID MOVE 16`, so
  the MOVE ran in Spam. Gmail answered `OK Success` with no COPYUID: nothing
  moved, the app believed the letter gone, and it was still in the Inbox
  after a relaunch. With All Mail selected at that instant it would have
  binned All Mail's UID 16, a different letter.
- Fixed build, same steps, twice: the delete went at a mailbox boundary of
  the search as `SELECT "INBOX"` + `UID MOVE` in one hold, Gmail's COPYUID
  named the letter that was open, the refresh ran wholly in the Inbox, and
  every UID command in both logs ran in the mailbox it was meant for. An
  All Mailboxes search on its own returned hits from Inbox, Trash and All
  Mail with every preview filled, and the keyboard stayed up as they landed.

**Tested** in `MailboxAtomicityTests`, over mailboxes that number their
letters from the same UID so that a write in the wrong one changes some
other letter: previews for three mailboxes fetched at once beside a search
and a letter being opened; thirty writes landing at different points of an
All Mailboxes search, each changing its own letter and nothing else; a tap
while the connection is being made again; every kind of write against a
renumbered mailbox; every kind of call against a refused SELECT; a draft
discarded as a letter is opened, with and without UIDPLUS; a folder and a
date jump opened mid-search; a search cancelled while it waits to take the
connection back. `RepositoryWireTests` has the rows drawn before a
renumbering, paged both ways and previewed, and the refused password in
both halves of the reconnect window; `ExchangeGateTests` has which line
each command waits in. Each fails with its part of the fix reverted.

---

## B-040 — CHANGED 2026-09-28. Less of the connection spent on work he did not ask for

Behaviour he could notice, from the third batch of the lag fixes. Checked
on the scripted server (`RepositoryTrafficTests`); none of it has been
seen on the iPad yet, and the TODO says what to look at.

**At launch the Inbox comes first.** The connection sends LOGIN, one LIST,
and the Inbox's first page, and only then asks for the unread counts, a
STATUS per folder. It used to be the other way round: finding the Inbox's
real name ran the whole count sweep, the folder pane ran another, and the
Inbox's SELECT came eighteen or so commands in. The folder pane now shows
the folder names as soon as that LIST answers, with no numbers beside
them, and the numbers appear once the Inbox's rows are up. Before, the
pane stayed empty until every count was in. If the Inbox cannot be
fetched at all, the counts are not asked for: with a password Gmail
refuses, or a server that cannot be reached, launch makes one attempt,
and the counts come with the next Refresh. Asking for them anyway would
connect again straight after the failure and send the refused password
a second time.

**The counts are asked for once, not once per reason.** About eight things
ask for them: Delete, Move or Flag from the reading pane, deleting or
moving a selection, Refresh, saving Settings, coming back after a while.
Each used to run the whole sweep, and several in a row ran several.
Now one sweep runs at a time, and anything that asks while it runs gets
exactly one more sweep after it. That one more is what keeps the device
bug recorded at `RootViewController.bindList` fixed: a sweep that had
already counted the Inbox when an unread letter left it would otherwise
be the last word, and the Inbox would read one too many. Nothing waits
in front of a sweep, so the counts after a Move come as soon as the
connection is free.

A letter he reads while a sweep is out asks for one more as well. The
read takes one off its folders once the server has the flag, and a sweep
that counted the Inbox before that would land afterwards with the letter
still unread. At launch that is the usual case, since the counts go out
just as the Inbox's rows appear, which is when he taps the newest
letter. The Inbox may read one too many for the length of that sweep,
and is right once the next lands.

**The Move sheet lists the folders the app last listed.** It used to ask
for every folder's count, which it does not show, and opened empty for
most of a second. It now takes the names from the last LIST, or sends a
LIST alone the first time. So a folder made in another client since the
last sweep is not offered until the next one; any Refresh is a sweep.

**A jump into All Mail no longer shows today first.** Opening All Mail to
jump to a day used to load and draw its newest page and then replace it
with the day. The day is now the only thing it loads. If there is no
mail on or after the day, or the jump fails, the newest page is loaded
after all and the status line or the usual alert says why, so the pane
is never left empty. A jump that fails once he has started a search, or
opened another folder, is let go quietly, with no alert and no newest
page: the list belongs to what he did next, and the newest page would
clear the search box and what he had typed in it.

**The address book is written once per page, not once per address.**
Addresses seen in a page of mail are kept in memory and written out when
the page is done, and whatever is left when the app goes into the
background. An address he has sent to is still written at once. The
book is also locked now: noting addresses from the connection while the
composer ranks them for a keystroke, or while the book was being written
out, could crash the app (B-038). Two writes at once, one at the end of a
page and one as the app goes into the background, take turns, so the
older copy cannot land last.

**Seen on the iPad, 2026-09-28**, on carlo's mailbox (recorded 2026-09-30,
from that day's connection logs): a cold launch sent two commands before
`SELECT "INBOX"`, where the build before sent about twenty. The rest of
what the TODO lists for B-040 has not been looked at.

---

## B-041 — CHANGED 2026-09-28. What he sees when he acts

Behaviour he could notice, from the first half of the fourth batch of the
lag fixes: what the reading pane and the list do the moment he taps,
deletes, moves or flags, comes back to the app, or picks the iPad up.
The rules are checked on the scripted server and in host tests
(`PaneLoadsTests`, `PaneActionsTests`, `ComingBackTests`); the screens
that apply them are UIKit, which the host cannot build, and none of it
has been seen on the iPad yet. The TODO says what to look at.

**The letter he taps is on screen at the tap.** The reading pane used to
be drawn only once the letter's body had come, and for that whole time it
held the previous letter, header and body, beside a selection that had
already moved: a plausible letter that was not the one he tapped. The
header now changes at the tap to the new letter's sender, subject and date,
with "Loading…" where the body will be, and "To: me" until the letter's
own recipients arrive with it. A conversation's stack already worked this
way. Loading that page also starts the web view's content process while
the body is on its way, rather than after it.

Two things went with the old way. Reply, tapped while a letter was still
loading, opened a reply to the PREVIOUS letter, because the pane still
held it; it now does nothing until the letter is there. And emptying the
pane, after a Delete or a folder change, only hid the web view: the next
letter he tapped unhid it, and the letter just binned was back on screen
under the next one's header until that one's body came. The pane is now
emptied properly.

**Tapping through letters downloads the one he stops on.** Tap four in
quick succession and the first, if its body is already on its way, still
arrives and is thrown away, the two in between are never asked for, and
the fourth comes next. Each used to be downloaded whole, one after another,
the one he wanted last; with a photo letter among them that was seconds.
Every letter he tapped is still marked read, as Mail marks a letter read
when it is selected, however briefly, so the unread dots and counts are
exactly what they were. What that costs: the letter he stops on waits for
the read marks of the unread ones he tapped past, one short exchange each.

**Delete, Move and Flag from the reading pane change the list in place.**
All three used to reload the whole list and count every folder again,
about fourteen commands for one letter binned: every preview blanked and
refilled, a search he was in was cleared with its text, a date jump went
back to today, the list went back to the top, and the binned row stayed
on screen for most of a second. Now:

- Delete empties the pane and takes the row off at the tap, and the
  previews, the search, the date and his place in the list all stay. The
  Delete button stays grey until the server has the first one, so a
  second tap cannot bin the next letter he opens meanwhile. If the server
  refuses, the row comes back and he is told the app could not connect.
- A letter binned while still unread comes off every folder's count at
  once; a read one changes no count, and nothing is swept for it. Unread
  from the Inbox, the counts are swept once after the MOVE, for Trash's.
  Inside Trash, Delete marks the letter deleted and nothing else, as
  before, and the one off Trash's count is the whole change.
- Move empties the pane and takes the row off in the same way once he
  has chosen the folder. An unread letter moved is counted by one sweep
  afterwards, the only way to know the count of the folder it went to.
  Moved out of All Mail, a letter is still in All Mail, and its row
  stays there. Moved to Trash or Spam, it is a Delete.
- Binned from All Mailboxes search results, a letter also goes from the
  Inbox's rows under them, so cancelling the search does not bring back a
  row that would open empty.
- Binned from search results, a letter further down the folder than the
  list has paged no longer stops the folder short. Its page used to come
  back one letter short, which the list takes for the end of the folder,
  and after cancelling the search nothing older could be scrolled to until
  Refresh. A page short of letters the folder has gone on to hold is now
  made up from further down, one more FETCH, which also covers letters
  removed from another client since the list was fetched; upward after a
  date jump too.
- Flag shows on the row at once, and on an All Mailboxes hit, on the same
  letter's Inbox row under the search as well, so cancelling the search
  shows it. If the server refuses, the flag goes back and he is told; it
  used to stay on screen with nothing said, although Gmail did not have
  it. A second tap on Flag for the same letter while the first is on its
  way is ignored as a double tap; Flag on another letter he has opened
  meanwhile goes as usual.
- Opening an unread letter inside a conversation marks it read at the
  tap, as a tap on a row does, and takes one off the counts; it used to
  wait for the letter's body and then reload the list and count every
  folder again.
- In Edit mode, whatever the pane does to the list leaves his ticks
  alone. Opening a letter in the conversation still in the pane used to
  tick that conversation for him, and a Flag, Delete or read from the pane
  kept only one of his ticks, so a bulk Delete straight after acted on
  the wrong letters. A page loaded as he scrolled in Edit mode used to
  drop all but one of them too.

Refresh is still the whole reconciliation: whatever was done locally, it
fetches the list and every count again. It now keeps the previews already
drawn, fetching only the new letters', and keeps the open letter's row
highlighted if it is still there.

**Coming back after more than fifteen minutes, to the Inbox he left.** He
still lands on the Inbox, at the top (B-003). If the Inbox was already
showing it is no longer thrown away and rebuilt: the list scrolls to the
top and leaves Edit, the rows he left stay, previews and all, until the
newest page replaces them, and the letter in the reading pane stays there.
It used to be a black list under "Updated Just Now" for a second or two,
and an empty reading pane. From any other folder the Inbox opens as before.
Either way the folder counts are asked for once the Inbox's first page has
come, launch's order, and not at all if it could not be fetched.

**Picking the iPad up.** If the connection has been quiet for more than
ninety seconds when he comes back, the same threshold the write probe uses
(B-024), a NOOP goes at once. It waits behind anything he has already
tapped, but the connection is usually free as he comes back, so it is
normally on the wire straight away, and a letter tapped then waits for
its answer: a round trip, or on a half-open socket the 30 s read deadline,
which is what the letter's own command would have waited without it. A
connection that died while the iPad slept is found and replaced then,
before he taps anything, rather than by the first letter he opens, which
used to pay a failed command and a whole reconnect, 0.6 to 1.1 s. A
Delete, Move or Flag made while the NOOP is out probes the connection for
itself, as any write after ninety seconds of quiet does, and goes once, on
the replacement if there is one. After a shorter quiet nothing is sent.
Nothing is sent as he leaves either: a LOGOUT there would cost a reconnect
on every return. If Gmail refuses the password while the connection is
being replaced, nothing he does sends it again for a minute: each tap fails
at once, with the "Can't connect to mail server." these screens give for a
refused password today. Otherwise his first tap would send the same
refused password a second time within seconds of the first. After the
minute, a tap or a Refresh tries again, once; Gmail refuses a correct app
password now and then, and the refusal used to stand until he next came
back to the app, with nothing to tell him so.

**The connection log** no longer notes "webview: load failed -999" when a
page in the reading pane is replaced before it has finished, which now
happens whenever a letter arrives while "Loading…" is still being drawn.

**Seen on the iPad, 2026-09-28** (recorded 2026-09-30): Delete from the
reading pane went as one command, where the build before sent about
fourteen; the warm-up NOOP found a dead socket and replaced it before the
first tap; coming back after more than fifteen minutes refreshed the list
in place. A flag set on a search hit and cleared after the search ended
missed the folder's copy; that was found there and fixed (`1477ee1`).

---

## B-042 — CHANGED 2026-09-28. Things that move under him

Behaviour he could notice, from the second half of the fourth batch of the
lag fixes: the list and the reading pane holding still while what is in
them changes, and saying what they are doing while he waits. The rules are
checked in host tests (`ListPlaceTests`, `FeedbackTests`,
`PaneDocumentTests`); the screens that apply them are UIKit and WebKit,
which the host cannot build, and none of it has been seen on the iPad yet.
The TODO says what to look at.

**Search results start at the top.** A search started from far down a
folder used to draw its results under the scroll offset the folder had,
so the newest hits were above the top of the pane, and a short result set
showed empty pane with "No results" or "Could not search" up out of sight:
it read as the search not having found the letter. Every result set now
starts at its first hit, including each new one as he types on and one
that could not be run. Refresh goes to the top too, once the newest page
has come. A Delete or a Move from Edit mode, or a draft saved, sent or
deleted in Drafts, fetches the newest page afresh as before, and the rows
he could see stay where they were in it, as the old scroll offset roughly
did; if he was further down than the newest page reaches, it goes to the
top. From a search's results, the folder comes back where he was in it.

**Cancelling a search puts him back where he was in the folder.** The
folder used to come back at whatever depth the results had been scrolled
to. It now comes back with the row he had at the top of the pane at the
same height, found again by its letters rather than by its position, so a
letter binned from the results meanwhile does not shift it; if that row
itself has gone, the next one he could see stays put. And the folder's
previews that had not come in when the search replaced it are fetched
again, or taken from the same letter found by the search, where they used
to stay blank until Refresh.

**Paging upward after a date jump holds still.** Scrolling up past the day
he jumped to loads the newer mail above it. A newer letter in a
conversation already listed takes that conversation's row up to where the
new letter is, and the list used to correct its position by the number of
rows added, so each such conversation below the top of the pane slipped
the list by a row: 0 to 3 rows a page, measured on the host with the real
grouping. And the highlight moved to another letter on every page that
added rows. Now the rows he can see stay exactly where they were, except
one that has moved up because newer mail joined it, and the highlight
stays on the letter open in the reading pane, or on his ticks in Edit
mode. The same hold applies whenever the list is regrouped under him: a
row binned from the reading pane above the top of the pane no longer
shifts the rows he is looking at, and nor does the Organize by Thread
switch.

**Go to Date and Move start at the tap.** Both used to start only once
their sheet had finished sliding away, about a third of a second, with
nothing on screen to say anything was happening. The request now goes as
he taps Go, or the folder, and the list's status line says "Going to
3 May…" or "Moving…" until it is done; then it says where the jump landed,
as before, or goes back to what it said. A jump into All Mail from another
folder opens All Mail during the slide, saying "Going to …". An alert
brought by a failure while the sheet is still sliding away, which UIKit
would drop, is held and shown once the sheet has gone; "Can't connect to
mail server." as ever. It is held for a second at most, in case UIKit
never says the sheet has gone, and if two come meanwhile the later is
shown, the earlier only if the later has nothing to go over. A second
tap on Go, or on a folder, while the sheet slides away is ignored.

**The reading pane's header lists a letter's files from the tap.** It
used to list them only when the letter arrived, a row of at least 44 pt
per file, which pushed the letter, or a conversation's whole stack, down
under him as he began to read it. The files are now known from the list
row, which describes the letter's parts, and the header is its final
height from the start. The file rows are grey until the letter has come,
and open as before after that; a file download from the letter before
does not light them up early. The same holds when he opens a
conversation. It does not hold when he opens another letter inside the
stack: the header changes to that letter once it has come, files and all,
as before.

**A draft he taps stays highlighted, with a spinner, until it opens.** In
Drafts the row used to lose its highlight at the tap, with nothing on
screen for the tenth of a second to half a second the draft took to
download, and a second tap downloaded it again. Now the row stays
highlighted, with a small spinner where the unread dot goes, until the
composer opens; a second tap on it does nothing, and a tap on another
draft meanwhile opens that one instead of both. If the draft cannot be
fetched, the highlight goes and he is told the app could not connect.

**The reading pane comes back after WebKit loses it.** The letters are
drawn by a separate WebKit process, which iOS ends when it needs the
memory, typically while he is in Photos or Safari. Nothing answered for
that, so he could come back to a black pane, or a conversation stuck on
"Loading…", under a header still naming the letter. The pane now draws
again what it was showing, from what it already holds: the letter, the
conversation with the letters he had opened and the bodies that had come,
or the grey words. It does so once he is back in the app with the pane on
screen, not while he is still elsewhere. No letter is fetched again to do
it; the inline pictures of a conversation's letters are asked for again,
and those of any letter but the last one downloaded come from the server.
The position he had scrolled to inside the letter is not kept: it comes
back at the top. If the page drawn again is lost again while it loads or
within ten seconds, which points at the letter itself being too much for
WebKit, it is not drawn a third time: the pane says "This message could
not be shown.", and tapping the letter again tries afresh. The connection
log notes "webview: content process ended" each time, which settles how
often it happens.

**A conversation's letter no longer sticks on "Loading…" when its body
comes quickly.** A body that arrived before the conversation's page had
finished loading was lost, and the letter said "Loading…" until he closed
and opened it again. It now waits for the page.

## B-043 — CHANGED 2026-09-28. The reading pane's own work, off the screen's thread

Behaviour he could notice, from the fifth batch of the lag fixes: nothing
the pane draws has changed, only when and where the work is done. The
rules are checked in host tests (`PanePageTests`, `PaneLoadsTests`,
`PaneDocumentTests`, `ConversationDocumentTests`, `DisplayDatesTests`,
`MIMEDecoderTests`); the web view that applies them is WebKit, which the
host cannot build. What the iPad has shown is at the end; the TODO says
what is still to look at.

**A big letter no longer holds the screen while it is drawn.** When a
letter came, the app made its page on the same thread that draws the
screen and answers his fingers: took off the sender's wrapper, pointed its
pictures at the app, and escaped plain text. For a letter in a
conversation it then wrote the whole body into a script a character at a
time. Measured on the development computer, which is about as fast as an
A12 iPad: a newsletter of 200 KB held the screen for 18 ms on its own and
50 ms in a conversation, three frames, and a letter of a megabyte for a
tenth of a second on its own and up to four tenths in a conversation. A
scroll caught, a tap waited. The page is now made on another thread, and
the body goes to the page as it is, with nothing escaped; the app's own
part holds the screen for well under a millisecond on the development
computer. In a conversation WebKit then copies the body across to the
page on the same thread, and after a pause of more than ten seconds makes
itself a new JavaScript engine in the app to do it, which it keeps for ten
seconds. That part has not been timed on the iPad; it is copying, not the
old character-at-a-time loop, so it should still be far quicker. The
letter itself comes no sooner on its own; in a conversation it comes
sooner by the time the escaping took.

**A letter he has moved on from is not drawn, and is not made either if
he left before it came.** As before for the download, now for the page:
tapping quickly through large letters draws only the one he stops on.

**Attachments and inline pictures open sooner.** Their decoding is about
eight times quicker: a 5 MB PDF took about 0.6 s to decode before it could
be shown, and now takes under a tenth of a second.

**Times and dates follow the iPad's settings as before, for less work.**
The list's times and the pane's dates used to build a date formatter for
every row and every letter. They are now kept, and made again when the
time zone, the language or region, or the 24-hour clock is changed in
Settings. Which day is today is worked out every time, so after midnight
a letter from late the evening before says "Yesterday" once the list is
drawn again, as it did.

**Confirmed on the iPad, 2026-09-28**, on carlo's mailbox, driving the real
UI. The app launched with `callAsyncJavaScript` bound from `libswiftWebKit`.
An HTML newsletter drew with its pictures and the page's own colours
inverted as before. A conversation of four plain letters filled its newest
letter's body, with the `<` and `>` of the quoted addresses shown as
typed. Opening the oldest letter put its body in and moved the header to
it; opening two more a third of a second apart left the header on the one
opened last. With three letters open, `killall -9
com.apple.WebKit.WebContent` brought the stack back with every open body
in. Closing a letter and opening it again put its body straight back and
moved the header to it. A 34 KB PDF decoded and opened. Three letters
tapped a third of a second apart drew only the last. The list's times read
"Friday", "Wednesday" and "21/09/26" on a Monday, as before. Not yet seen:
a letter of a megabyte, a conversation of twenty letters, a body with
backslashes or `</script>` in it, a change of time zone or 24-hour clock,
and the fill's own time on the iPad.

**Seen on the iPad, 2026-09-28** (recorded 2026-09-30): with WebKit's
process killed, the pane drew the letter again; new search results started
at the top once the list laid out first (found there, fixed in `b7e1333`),
and cancelling a search brought the folder back to the row he was on.

---

## B-044 — CHANGED 2026-09-29. Sending says so, goes once, and closes when it has gone

Behaviour he could notice, from the sixth and last batch of the lag fixes:
the send path. The rules are checked in host tests (`ComposeActionsTests`,
`SMTPSendTests`, `DataPayloadTests`, `BoundaryTests`,
`TransportDeadlineTests`, `LinkTransportTests`); the sheet that applies
them is UIKit, and so is the Drafts list, and the time iOS gives an app in
the background is iOS's, none of which the host can run. None of it has
been seen on the iPad yet. The TODO says what to look at.

**What the iPad showed before it**, on the development iPad on 2026-09-29,
with the build before this batch and the test account writing to itself. A
plain letter: nothing changed on screen after Send, and the sheet closed
about 1.6 s later; Gmail's goodbye came 21 ms after its 250. Two taps on
Send half a second apart: two letters went, and both arrived. A draft
reopened after a minute and a half and sent: after the 250 the sheet
waited about half a second more for the Drafts cleanup (NOOP, STORE,
EXPUNGE). A letter with five pictures, 4.3 MB on the wire: about 4 s with
nothing on screen, 1.35 s of it before the app so much as connected to
Gmail, and 146 ms stuffing the letter. The same letter with the iPad
locked 0.3 s after Send and unlocked a minute later: the upload stopped
with the app, the write deadline fired as it woke, "Message was not sent."
was shown, and nothing was delivered.

**Send says it is sending.** Tapping Send used to change nothing on screen
until the letter had gone or failed: seconds for a letter with photographs,
a minute or more on a poor line, and Send was there to be tapped all that
time. A tap that seems to have missed gets tapped again, and every tap sent
the letter again. Now Send gives way at the tap to a spinner and
"Sending…", and for a letter of a megabyte or more, how much of it has gone:
"Sending… 40%". Cancel, Attach Photo and each Remove are greyed, and the
sheet cannot be swiped away, until the letter has gone or failed. A second
tap sends nothing. The figure is of what the iPad has handed to the
network, which runs a little ahead of what has arrived, so it stops at 99%
and the sheet closes when Gmail says it has the letter.

**The sheet closes as soon as the letter has gone.** After Gmail had taken
the letter the sheet used to wait for Gmail's goodbye and for the
connection log to be written to its file, and for a letter finished from
Drafts, for the draft to be taken out of Drafts as well: a check that the
connection was alive, often a new connection, and three commands more. It
now closes at Gmail's answer to the letter; the draft is removed after
that, and then Drafts is drawn again, as before. The goodbye is still said
and the file still written, after (B-034; a file named `-ok` now means
Gmail's answer to the letter was read, and the goodbye is not in it).
Nothing that happens once Gmail has the letter could make it an error
before either; what has gone is the wait. A line that died after Gmail's
answer used to hold the sheet up, with Send live, for the whole 30 s read
deadline before the letter was reported sent, and a tap on Send in that
time sent it again. Still one connection per letter (B-024).

A letter finished from Drafts leaves the Drafts list as the sheet closes,
before its draft has been removed from Gmail. The sheet used to cover the
list until the draft had gone; closing sooner uncovers it for as long as
the cleanup takes, about half a second and more with a reconnect, and a
tap on the row in that time opened the letter just sent as a draft, with
a Send that would send it again. The row stays off until Drafts has been
fetched again after the cleanup, which has the say: gone if the draft was
removed, back if it could not be.

**If it did not go, nothing is lost.** The sheet stays with the letter in
it as he wrote it, everything is live again, and the reason is said as
before.

**Photos chosen just before Send go with the letter.** The photo picker
hands its photos over after it has closed, one at a time as each is read
in and made a JPEG, which for a few large ones takes seconds. Send or Save
Draft tapped in that time took the letter as it stood at the tap: the
photos appeared in the sheet after it, the letter went without them, and
the sheet closed as though they had gone too. This was so before B-044;
with the new "Sending…" it would have been watched happening. Now Send
shows its spinner at once and sends when the last photo is in, and Save
Draft keeps the draft once they are all in it.

**Nothing closes the sheet under a letter, or leaves it up after.** The
Cancel sheet's Save Draft and Delete Draft do nothing once a letter is on
its way, and Send puts the Cancel sheet away if it is still open, which
on the iPad it can be: it hangs from the bar Send is on, and leaves that
bar live. Either would have closed the sheet in the middle of a send,
leaving a failure nowhere to be said, and with Delete Draft a letter
neither sent nor kept. The sheet does one of Send, Save Draft and Delete
Draft, once; only a Send that fails puts it back. And when the letter has
gone the sheet closes whatever it has up over itself at that moment: an
alert about a photo that could not be added, or the Share or Look Up the
text menu offers. It used to be told to close itself, and a sheet that
is showing something closes that instead; with Cancel and the swipe held
while a letter goes, it would have stayed up, held, with no way out but
quitting the app.

**Locking the iPad does not stop a letter halfway.** The app now asks iOS
for time to finish a send, from the tap until Drafts has been tidied, and
a Save Draft, from the tap until the save is answered. Without it, locking
the iPad straight after Send suspended the upload, as above: the letter
failed when he came back. It could as well have waited on a connection
that had died meanwhile, or gone and been reported as not sent. iOS
decides how long it gives. If that runs out first, the app gives the time
back when asked and does nothing else: the sheet stays, nothing is said,
the letter carries on if iOS lets the app run, and whatever becomes of it
is shown when he comes back. A Save Draft cut off the same way could leave
no draft, and no sheet to say so.

**Less of the iPad's own work before the letter goes.** Getting a letter
with five large photographs, 27 MB on the wire, ready to send took about
4.9 s on the development computer, which is about as fast as an A12 iPad,
before a byte of it went: most of it copying the letter a byte at a time to
check for lines that start with a dot, and three searches of every
photograph for text that cannot occur in one. It now takes about 0.28 s
there, and the letter is the same letter, byte for byte. The rest is the
photographs being encoded, which it always paid. The 1.35 s the iPad took
before connecting, above, has not been timed again.

**Not taken.** Sending the envelope and DATA in one round trip (SMTP
pipelining) would save about a tenth of a second a letter, now behind the
spinner, at the cost of a path where every recipient is refused that is
easy to get wrong and cannot be checked against Gmail from here
(PERFORMANCE.md, Record and leave). Delete Draft, from Cancel, removes the
draft after the sheet has gone as before, without asking iOS for time: cut
off, the draft is simply still there.

**Confirmed on the iPad, 2026-09-29**, on carlo's mailbox, each letter to
the account itself, the same five checks as on the build before it:

- A plain letter: "Sending…" and the spinner at the tap, Cancel and
  Attach Photo grey; the sheet closed at the 250, 1.2 s from the envelope,
  with no wait for the 221. Before: nothing on screen for 1.6 s.
- Send tapped twice half a second apart: one envelope, one letter. Before:
  two envelopes, two letters.
- A draft reopened after 95 s of quiet: the sheet closed at the 250, and
  1.2 s after the tap the row had left Drafts; NOOP, STORE and EXPUNGE
  followed in the 0.56 s after the 250. Before: the sheet waited for them,
  0.48 s.
- Five pictures, 4.3 MB on the wire: "Sending… 60%" during the upload; the
  payload was ready 15 ms after the 354 against 146 ms before, and it
  arrived once with all five.
- Five pictures, the lock button pressed 0.48 s after Send: the envelope
  went 0.72 s after the tap (1.35 s before), the upload and the 250 came
  with the screen off, and on unlocking a minute later the sheet was gone
  and the letter had arrived once. Before: suspended mid-upload, "Message
  was not sent." on unlocking, nothing delivered.
- Wi-Fi off in Control Center: "Can't connect to mail server." at once,
  the letter still in the sheet and every control live; Wi-Fi on again,
  the same Send delivered it once.

Two things were changed after it: "Sending…" is drawn in the text's white
rather than a disabled item's grey, which read faint, and a held Remove is
drawn grey rather than staying red.

---

## B-045 — FIXED 2026-09-29, confirmed on the iPad. Refresh did not show mail that had come into the open folder

**Found on the iPad, 2026-09-29**, on the test account, build 3fc7b91.
Fixed on the scripted server the same day; the fixed build has not been
seen on the iPad yet, and the TODO says what to look for.

**What he saw.** With the Inbox open, he sent three letters to himself from
the iPad and tapped Refresh. The list kept its seventeen rows under
"Updated Just Now", while the folder pane beside it said the Inbox had 4
unread. A second Refresh showed the three.

**What the connection log showed.** The Refresh's `UID SEARCH ALL` was
answered with the seventeen old UIDs, and the page's `UID FETCH` asked for
those seventeen. Gmail's `* 20 EXISTS`, announcing the three, came at the
end of the FETCH's answer, after the SEARCH. SESSION-IDENT then said
`exists=17 uids=17`, and the STATUS of the Inbox that followed said
UNSEEN 4.

**The cause.** A SEARCH answers from the session's view of the mailbox, and
Gmail, like most servers, adds new mail to that view only once it has
announced it to the session with EXISTS, which it does when it chooses: in
the answer to a SELECT or a NOOP, or riding on some later command, here the
FETCH. The client does not SELECT a mailbox that is already open on its
connection, and did not before B-039 either, and nothing else asked the
server for news before listing. So a Refresh of the folder already open
listed what Gmail had told the session of, and no more. Opening a folder
the connection did not have open SELECTs it and was never affected; one it
still had open from other work, All Mail after an All Mailboxes search,
was. Nor was the Inbox after picking the iPad up after a while, where the
warm-up's NOOP (B-041) had already asked. A letter archived or binned from
another client stayed on the list the same way, until Gmail got round to
its EXPUNGE. The SESSION-IDENT count was the SELECT's, so the log could not
show the listing was short.

**The fix.** A SEARCH in a mailbox already open now goes behind a NOOP, in
the same hold of the connection, so Gmail announces what it has before the
SEARCH and no other command comes between them. Not when a SELECT of it
went in the same hold, however long its answer took, and not when the
session has asked for that mailbox's news in the last two seconds, by its
SELECT or by any NOOP, the warm-up's and a write's probe (B-024) included.
A Refresh tapped again three seconds later while he waits for a letter asks
again. A search as he types asks as a listing does, and the rest of its
burst then go on the answer the first had while that is under ten seconds
old, so a burst of typing asks once. Only a search starts a burst: a search
five seconds after a Refresh or after the folder was opened still asks, for
the letter he is after may have come in between. A question dated after
now, the clock having been set back, counts as old, not as a moment ago.
The same NOOP's EXPUNGEs take a letter removed elsewhere out of the same
SEARCH, for nothing more. The count SESSION-IDENT reports now follows every
EXISTS and EXPUNGE, so a listing that did miss mail shows as `exists` above
`uids`.

**What it costs.** One NOOP per listing from the top of the folder already
open, unless one has just gone: a Refresh, a date jump, and the reload
after a Delete or a Move from Edit mode or after a draft is saved, sent or
deleted. Nothing for a folder he opens that the connection does not have
open, which is SELECTed; one it still has open from other work, All Mail
after an All Mailboxes search, pays it like a Refresh. For a search in the
Current Mailbox, one NOOP for the first keystroke's search and nothing for
the rest while that answer is under ten seconds old. An All Mailboxes
search SELECTs each of its mailboxes and adds nothing, except when the
Trash is the folder open: its first mailbox is then already open and asks
as a Current Mailbox search does. Nothing per page: scrolling walks the
listing the Refresh took, as before, and a page whose listing has gone
SEARCHes again without asking, since it is cut below a letter already on
screen.

**What it does not cover.** A letter that lands less than two seconds after
the last question and before a Refresh is shown by the Refresh after that
one, and a letter that lands while he types is found by the first search
once the burst's answer is ten seconds old, or after a Refresh. Pages
loaded as he scrolls still ask for nothing, because the list is meant to
hold still under him: a letter removed elsewhere further down than the last
Refresh reached stays listed until the next one, if Gmail goes on serving
it, as before.

**Tested** in `ArrivingMailTests`, over a scripted server that now tells a
connection with the mailbox open of new mail only on a NOOP or at the end
of a UID FETCH, never on a SEARCH, and of a letter removed elsewhere only
on a NOOP, as Gmail did here: a Refresh after three letters to himself
lists them on the first reload with one NOOP added; a letter removed
elsewhere leaves the list; a second Refresh three seconds on asks again,
and one under two seconds after the folder's SELECT does not; the warm-up's
NOOP and a write's probe are shared; a page adds nothing; a date jump lands
on a letter that arrived after the folder was opened; a Current Mailbox
search finds one, and so does the first search a few seconds after the
folder was opened or refreshed; a burst of five keystroke searches sends
one NOOP, and All Mailboxes none; a SELECT answered after two seconds is
not followed by a NOOP; a clock set back an hour does not stop a Refresh or
a search asking; a page whose listing has gone asks for nothing; the count
follows the EXISTS and EXPUNGE, an EXPUNGE counting down from the last
EXISTS; and, after a socket that died in the quiet, the NOOP is the write
it loses and the Refresh, the date jump and the search each land on one
reconnect. `RepositoryWireTests` has a search cancelled while its NOOP is
out send nothing after it. The tests that pin exact traffic now run on a
clock nothing moves, so a stalled host cannot add a NOOP to them. Each
fails with its part of the fix taken out: without the NOOP, the Refresh
lists the old top rows exactly as the iPad's log had it.

**Confirmed on the iPad, 2026-09-29**, the same account and the same
steps: with the Inbox open, two letters sent to itself, then one Refresh.
`a019 NOOP` was answered `* 24 EXISTS`, the `UID SEARCH ALL` after it
listed 24 UIDs with the two new ones, SESSION-IDENT said `exists=24
uids=24`, and both letters were at the top after that one Refresh. It did
the same after the picture letters and after the letter sent once Wi-Fi
came back.

---

## B-046 — FIXED 2026-09-29, confirmed on the iPad. A reopened draft carried the signature's logo as a file

**Found on the iPad, 2026-09-29**, on carlo's mailbox, the test account,
build 3fc7b91. He wrote a new letter, with the signature the composer puts
in, whose logo is an inline picture; tapped Cancel, then Save Draft; opened
Drafts and tapped the draft. The composer listed "logo.png - 8 KB" as an
attachment row with Remove, though he had attached nothing. He tapped Send,
and the letter that arrived showed the logo as a file, a paperclip in the
list and a file row in the header, besides the one in the signature. The
same letter sent fresh was 18,134 bytes; sent from the reopened draft,
28,883, about one more base64 copy of the logo.

**What it was.** A saved draft is stored as the letter it will become, so
it carries the signature's logo as an inline part under `cid:sig-logo`,
which is what makes its markup show the picture. `loadDraft` turned every
part of the stored letter into an attachment, that one included, and
`saveDraft` and `send` then added the logo from `SignatureImages` again,
inline, as they always do; the reopened copy went beside it as an ordinary
file. Each further save and reopen added one more. On the scripted server
the stored draft holds one logo after the first save, two after the
second and three after the third, and the composer lists one, two, then
three "logo.png" rows.

**The fix.** Reopening leaves out any part whose Content-ID is one of the
signature's pictures (`Draft.reopening`, `SignatureImages.contains`).
Saving and sending add them afresh as before, so the letter he sends from
a reopened draft is the one he would have sent fresh: the logo once,
inline, and his own files once each. Matched by Content-ID, the identity
the builder writes them under, rather than by file name, which a photo
called "logo.png" could share, and rather than by leaving out every part
with a Content-ID.

**A picture in the body of a draft begun in another client** still comes
back as a file row and goes as a file. The composer is plain text with an
HTML twin made at send (D-013), so there is nowhere in the body to keep
it. As a file it still goes with the letter, where he can see it and
remove it; left out, the letter would go without it and nothing on the
sending screen would say so.

**Not undone:** a draft that was reopened and saved again under the old
build already holds the extra copies as ordinary files with no Content-ID,
which nothing tells apart from a file he attached. They reopen as
"logo.png" rows he can Remove. Only drafts on the test account can have
them.

**Tested** in `DraftSignatureImagesTests`, over the scripted server, with a
submission server on port 465 that keeps what it is sent. A new letter
with the signature and a photo, saved and reopened, lists only the photo.
Sent, it carries the logo once, inline, and the photo once: the same parts
as the same letter sent fresh. Saved and reopened three times, the stored
draft holds one logo and one photo every time, and Drafts one copy. Each
fails with the fix reverted. A draft begun elsewhere, with a picture in
its body and a PDF, reopens and sends with both as files.

**Confirmed on the iPad, 2026-09-29**: a new letter, Save Draft, reopened
from Drafts: no attachment row. Sent from there it went as 18,131 bytes,
the same as a fresh letter (the build before sent 28,883), and arrived
with no paperclip. The draft with a photo he attached has not been tried. The TODO says what to look
at.

---

## B-047 — FIXED 2026-09-29, confirmed on the iPad. The Inbox was called "INBOX"

**Found on the iPad, 2026-09-29**, on carlo's mailbox, the test account,
build 3fc7b91. The sidebar's first row read "INBOX", and after he tapped
it the list's title read "INBOX" too, while at launch the same list is
titled "Inbox". Mail calls it "Inbox" everywhere, and he knows Mail.

**What it was.** The screens showed a folder's `name`, which for a listed
folder is the last part of its IMAP name, and IMAP names the inbox
"INBOX". The list opened at launch, before the server has been heard
from, is made by hand as "Inbox", so the same folder had two names
depending on how he had reached it.

**The fix.** `Mailbox.displayName`: "Inbox" for the inbox, however the
server spells it, and the folder's own name for everything else, so
Gmail's "Sent Mail", "All Mail", "Starred" and the rest read as before.
The sidebar row and what VoiceOver reads for it (`Mailbox.accessibilityLabel`),
the list's title and the Move sheet show it. The id, which is what goes on
the wire, and the name stay the server's. The Inbox the list opens on at
launch is one value, `Mailbox.inboxBeforeListing`, rather than a copy made
by hand in each of the two places that need it. Search's scope buttons say
"Current Mailbox" and "All Mailboxes", and the reading pane names no
folder, so neither changed.

**Tested** in `MailboxNameTests`: the rule for each spelling of the inbox,
the launch folder and the listed one called the same, what VoiceOver reads
for a row, and the folders the scripted server lists, the inbox "Inbox"
with its id and name still "INBOX" and the rest as LIST names them. Those
about the inbox fail with the rule reverted to the folder's own name. The
screens themselves are UIKit and never run on this host, so one test reads
their source: no line in `UI/` shows a folder's `name`, and the sidebar,
the list and the Move sheet each show `displayName`. It fails with any one
of the four places put back to `name`.

**Confirmed on the iPad, 2026-09-29**: the sidebar's first row and the
list's title read "Inbox" at launch and after tapping it. VoiceOver and
the Move sheet have not been looked at.


---

## B-048 — CHANGED 2026-09-29, seen on the iPad. Two panes or three, with Mail's view button

**Asked for by the owner, 2026-09-29**, and by B-037 since 2026-09-22:
"there should be a 2 pane and three pane view (switchable)". iOS 10 Mail
had exactly that on the 12.9-inch iPad; D-015 has the sources and the
reasoning.

**What he sees.** A button in the top-left corner, over the folders, drawn
as a sidebar. Nothing else changes until he taps it: the app still opens in
three panes. Tapped, the folders go and the list he was reading moves to
the left edge, 375 pt wide, with `< Mailboxes` and the calendar before its
title, and the letter takes the rest, 818 pt of the 11-inch screen where it
had 613. Tapped again, the three panes come back. `< Mailboxes` shows the
folders with the open one highlighted; a folder tapped there shows its
list, fetched as a tap in the three-pane sidebar fetches it; the folder
already open, tapped, brings back its list as he left it and fetches
nothing. The button is in the same corner either way, and VoiceOver reads
it "Hide Mailboxes" or "Show Mailboxes".

**What a switch keeps: everything.** The folder and its highlight, his
place in the list and the letter selected in it, a search with its text,
scope, results and keyboard, Edit mode with his ticks, the letter in the
reading pane, which is neither fetched nor drawn again, and a sheet or the
composer. Nothing moves up or down and nothing is animated. A tap on the
button while another finger is on the screen is not taken, so nothing
slides out from under that finger. `< Mailboxes` puts the keyboard away, as
leaving any screen does; the search stays in the list for when he comes
back to it.

**Kept** from one launch to the next. Coming back after a while (B-003)
lands him in the Inbox's list and leaves two panes two.

**What two panes cost.** The list's bar holds five things in 375 pt, and
the folder's name gets what is left: about 75 to 85 pt at 1194, by the
font's metrics, which Gmail's own names fit, "Sent Mail" only just, and a
longer name of his own does not; it ends in "…". The name is whole in the
folders behind `< Mailboxes`, and in three panes, where it has about
185 pt. The bottom bar, with Refresh and Settings, belongs to the list, so
it is not there while the folders are in front, as it is not under the
folders in three panes.

**Tested** in `PaneArrangementTests`, in three layers.

- `PaneArrangement`, by value: three panes by default, and three for
  anything under the key that is not one of the two words; both
  arrangements' widths at 1194 and 1366, filling every landscape iPad with
  no pane zero wide; and what is on screen at launch in each, after a switch
  either way, after `< Mailboxes`, after a tap on another folder and on the
  one already open (the Inbox the list opens on before LIST has named it
  included), and after a return from a while away. That covers which
  column is shown, the list's left edge, the divider, and the view button
  and `< Mailboxes` before the calendar, in that order.
- `PaneShell`, which the container calls from the view button,
  `< Mailboxes`, a folder tap, B-003's return and the date jump. With the
  container's two parts written down, it checks what each of these lays
  out, which of them opens a list, that a switch is kept, and that a
  folder opened by any route comes in front. With the opening bound to the
  repository over the scripted server, it checks that switches,
  `< Mailboxes`, taps on the open folder and a return, in any order, send
  nothing, while a tap on another folder sends its SELECT, UID SEARCH and
  UID FETCH and nothing more.
- `RootViewController`, which is UIKit and is not built on this host, is
  read function by function. It makes the shell once and never again. Each
  button and tap hands over to the shell and sends nothing itself. Every
  folder is opened through the shell, and the list is swapped nowhere
  else. `arrange` sets each width, edge, hidden flag and bar item from the
  arrangement's own value, runs the layout sweep and animates nothing. And
  the list puts the calendar after the container's items, unanimated.

Each of 29 sabotages (the rule reverted, or the container made to fetch,
skip, swap or animate) fails at least one of these tests. What the
screens actually draw is for the iPad.

**Not yet seen on the iPad.** The TODO says what to look at, the layout
sweep in both arrangements included.

**Seen on the iPad, 2026-09-29**, on carlo's mailbox. It launched in
three panes as before, the view button in the Mailboxes bar's corner.
With a newsletter open, the button made two panes: the list at the left
edge with the view button, "< Mailboxes", the calendar, "Inbox" and Edit
on one bar, nothing cut short, the newsletter still open and its row
still selected, now 818 pt wide. "< Mailboxes" showed the folders with
the Inbox highlighted and the letter still open; tapping the Inbox
brought its list back as it was. A search typed in two panes, keyboard
up, came through a switch to three panes with its words, scope, results
and keyboard. Two panes survived killing and reopening the app, and the
switch back to three after that sent nothing on the connection. Not yet
tried: Edit mode across a switch, another folder opened from "< Mailboxes",
VoiceOver on the button, the layout sweep in both.

---

## B-050 — CHANGED 2026-09-30, seen on the iPad. Reply and Forward send the original as it looked

**What was wrong.** Reply, Reply All and Forward quoted the original as
plain text, in the composer and in the letter's HTML alike: `quotableText`
takes the text part, or `HTMLText.plainText` of the markup, which keeps the
words and drops every link, picture and table. A forwarded newsletter
arrived as a column of words with its addresses gone, a reply handed people
their own letter back flattened, and a forward's pictures went as files
under the letter. Mail sends the original as it looked. He replies to about
436 letters a month and forwards about 168.

**What he sees while he writes: nothing new.** The composer is plain text
(D-013) and still shows the quote as words he can edit, and the letter's
text/plain part is what it was, byte for byte, with one exception below.
What changed is the HTML twin, which is what most people read.

- **Reply and Reply All.** Mail's attribution in its own
  `<blockquote type="cite">`, and in the one beside it the original's own
  markup, the shape his device writes (INVESTIGATIONS, "The skeleton, read
  off his own device"). No style is written on the blockquotes, as his
  device writes none: the bar beside a quote, blue in Mail, is drawn by the
  reader's client for `type="cite"`.
- **Forward.** "Begin forwarded message:", then the header block with bold
  labels and a bold subject, then the original's markup. The order is the
  iPad's, From, Date, To, Subject, as read off his own forwards. A **Cc**
  line now follows To when the original had one, in the text as well as the
  HTML; that placement is from an iOS forward among the Apple Mail samples
  of the crisp-oss/email-forward-parser project
  (`test/fixtures/apple_mail_en_body_variant_13.txt`, whose labels are
  French), so the English line is inferred, not seen. Mail on the Mac
  writes From, Subject, Date, To, Cc (the same project's other Apple Mail
  samples). The Cc line is the one change to the text part, and only for a
  forward of a letter that had a Cc.
- **A plain-text original** is quoted as HTML with its `http://`,
  `https://` and `www.` addresses made links; a Wikipedia address keeps its
  brackets and a sentence keeps its full stop.
- **Pictures on the web** stay on the web, in a reply and a forward alike:
  nothing is fetched to embed.
- **A reply carries none of the original's parts**, the pictures it shows by
  `cid:` included, as a reply never has (INVESTIGATIONS, "Forwarding now
  carries the files"). Such a picture is left out of the quote with its
  `<img>`; the rest of the letter goes as it looked. Carrying them back
  would make a one-line reply to a letter of photographs upload every
  photograph, with no row and no weight on screen, and would make Send and
  Save Draft fetch them first, so a reply to a letter since archived on
  another device, or sent after the socket had died, would fail where it
  goes today, with nothing on screen he could take off. Carrying them is an
  owner decision, and would want rows with their weight and a cap, as a
  forward has.
- **A forward's pictures** the original shows by `cid:` go inline, as
  related parts beside the markup, each under a Content-ID of this letter's
  own (`bmquote1.` and a fingerprint), so a sender's own `cid:sig-logo`
  cannot land on his signature's logo, which still goes once. A picture the
  markup shows by an id the letter does not carry is left out with its
  `<img>`. A part the markup does not show goes as a file.
- **A forward still lists every part of the original as a row with its
  weight**, the pictures included, so he can see what it weighs and take
  anything off. At Send, a picture the quote shows goes in the quote rather
  than as a file; one he took off does not go at all. One that cannot be
  fetched fails the Send, as a file always has, and it is a row he can take
  off. The fetch is a read, so a socket that died while he wrote costs a
  reconnect, not the first Send (B-023).

**What he sees is what goes.** The quote is kept exactly as it went into the
body (`QuotedOriginal.region`). At Send, if the body still ends with it,
byte for byte, the HTML carries the original's markup. If he has changed it
in any way, cut it short or deleted it, the HTML is what it was before this
change, made from the body as it stands, with the quote's addresses linked;
a forward then sends its pictures as files, as it always did. Nothing finer
is attempted. The plain words are often not the markup's (a text part is a
different rendering, or a stub), so an edit cannot be mapped back onto the
markup faithfully, and a near miss would send, in the HTML most people read,
words he had deleted from the letter he saw. What he types above the quote
is not an edit of it; what he types onto the attribution line is, as the
quote must start a line of its own. The same plain rendering goes when the
original's markup, once made safe, shows nothing at all, an empty text/html
part say, as an empty quote would not be what he saw.

**The original is made safe first** (`QuotedMarkup`). Kept: text, links,
pictures, tables, and styles written on the elements. Dropped: scripts,
event handlers, forms, frames, embedded objects, `<meta>`, `<base>`,
`<link>`, comments, `<style>` blocks, a link's `ping`, and any address that
is not `http`, `https`, `mailto`, `tel`, `sms` or, for a picture, a `data:`
picture that is not SVG, however it is spelt with entities or spaces. A
`<style>` block applies to the whole letter rather than the part it came in,
so a newsletter's sheet would restyle his words and his signature; senders
who want their look kept in Gmail already write it inline. A stray closing
tag in the original cannot close the quote around it, and a style that could
draw the original over his words and signature is dropped: a `position`
other than `static` or `relative`, an offset, a `z-index`, a transform or a
negative margin. A newsletter that pulls itself into place with a negative
margin loses that element's styling. The sender's document wrapper goes as
`DocumentWrapper` takes it off for the reading pane, in the same pass:
`DocumentWrapper`'s regular expressions cost more than the whole pass. A
head its sender never closed, which HTML allows, ends where a browser ends
it, at the `<body>` or the first thing a head cannot hold; it used to run to
the end and take the letter with it.

**Drafts.** A reply or forward saved to Drafts is marked, in the stored HTML
only, with a comment holding a fingerprint of the plain quote
(`<!--bm-quote:…-->`). Reopening takes the quote up again when the reopened
text's quote has that fingerprint, so a draft sent after being put down is
the letter that would have gone before: the same markup, and for a forward
the same pictures, which live in the stored draft and are fetched from it
before the old copy is replaced. A quote he had changed is marked too, and
comes back as the same plain rendering with its addresses linked. A reopened
reply lists no rows of the original's; a reopened forward lists its rows as
before. A draft whose text was changed anywhere else, in Gmail or another
client, comes back as plain text, as a draft begun elsewhere does. A letter
that is sent carries no mark.

**Size and time.** A forwarded newsletter now carries its markup,
quoted-printable, beside the words. Measured on this host in a release
build: 150 kB of markup goes out as 211 kB where it went as 114 kB, and a
megabyte as 1.47 MB where it went as 0.79 MB, both far inside Gmail's 35 MB;
a letter of a megabyte or more shows "Sending… N%" (B-044). Making a
megabyte of markup safe takes about 0.08 s and building the letter 0.07 s;
building used to take 0.34 s, nearly all of it quoted-printable, which is
now written into bytes (below). Unchanged: making the plain quote from the
markup when he taps Forward, 0.18 s for a megabyte, on the main thread.
Markup over 4 MB, which is markup with pictures pasted into it as `data:`
addresses, is not carried: that quote goes as its words with their addresses
linked, and a forward's pictures as files. A reply adds nothing but the
markup, as it carries none of the original's parts. Linking the addresses in
a plain quote is one pass over each line; it searched the rest of the line
again after every address, 12 s for a 200 kB line with an address every
hundred bytes in a release build, on the actor Send and Save Draft wait on.

**Quoted-printable, into bytes.** The encoder built its output a `String`
at a time: 0.35 s for a megabyte in a release build on this host, which was
nothing for a letter he types and a third of a second for a forwarded
newsletter. It now writes bytes, about 0.02 s, and the same bytes as before
for every input; the old encoder is kept in `QuotedPrintableTests` as the
reference, over the awkward cases, every wrap point and 150 random texts.
B-044's dot-stuffing and boundary scan are untouched.

**Tested** in `RichQuoteTests` and `RichQuoteRepositoryTests`, letters built
and read back with the app's own MIME reader, and sent and saved by the
shipping repository over the scripted server; in `QuotedMarkupTests`, the
sanitizer; and in `QuotedPrintableTests`. Some are guards that today's code
passes by construction (no leak, the text part unchanged, the encoder's
bytes). Each rule reverted on its own fails at least one test: the
untouched-quote check and its rule that the quote starts a line, the
sanitizer and each of its rules (handlers, schemes, styles, positioning,
closing tags, the head and where an unclosed one ends, a self-closed `svg`
or `math`, the empty comment `<!-->`, attribute names and repeats, `ping`,
`srcset`), the renaming, of an id written in another case or percent-encoded
and of every reference in a style, the forward's rows, the shown-only rule,
the words when the markup shows nothing, the 4 MB ceiling, the links and
linking in one pass, the Cc line, reopening, its fingerprint and the
trailing newline it ignores, the draft's mark on an untouched quote and on a
changed one, a reply carrying none of the original's parts and so never
failing for want of them, a forward's fetch at Send, the refusal to send it
without a picture, and its retry on a dead socket, and the encoder's dot and
trailing-space rules. The megabyte timings above are bounds on the wall
clock, so they are checked only when `BLACKMAIL_LARGE_TESTS` is set; linking
holds a 100 kB line to a second, where the old search took three in the
suite's build.

**Not done.** The composer shows none of the pictures, and a reply's quote
leaves out those the original carried as parts. The HTML shows the original
as it looked, which can hold words its text part does not, a newsletter's
especially; he did not remove them, but he did not see them in the composer
either. A newsletter that relies on its `<style>` sheet loses that part of
its look. Blackmail's own reading pane draws no bar beside a quote (TODO,
"blue bars on quoted text"). A draft edited in Gmail or another client comes
back as plain text.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, each letter to the
account itself. A newsletter with pictures, tables and links, forwarded:
it arrived under "Begin forwarded message:" with From and Date, looking
as the original did, its pictures, table and links intact, where before
it came as flattened text. A reply, with one word typed above the quote,
to a letter of his own carrying a link: it arrived with the attribution
line, the original's link blue and tappable, and the original's
signature, indented under his. This app's reading pane indents a quote
but draws no blue bar. Not yet tried: a reply with the quote edited.

---

## B-051 — CHANGED 2026-09-30, seen on the iPad. Save Draft with no connection lost the letter, and nothing he was writing was kept

**Found in the gap review of 2026-09-30** ("Ways a letter is lost" in the
TODO), in the code, not on the iPad. Two ways a letter he had written was
gone with nothing to say so:

- Save Draft closed the sheet first and sent the draft to Gmail after it.
  With no connection, or a password Gmail no longer took, the save failed
  once the sheet had gone: nothing was said, and nothing had been kept on
  the iPad. `ComposeActions.saveAndClose` ended in
  `try? await saveDraft(…)`, and a test pinned the silence.
- Nothing he was writing was kept anywhere until Send or Save Draft. If iOS
  ended the app while he wrote, as it may once he has gone to Safari for a
  link and stayed there, the letter was gone. Swiping the sheet down lost it
  the same way, without a question.

He writes about 70 letters a day and has about 1,900 drafts, so both
happen to him. Mail keeps a draft on the device and puts it in Drafts when
it can.

**What he sees now.** Save Draft with no connection: the sheet goes as
before and nothing is said, and the letter is at the top of Drafts, the
first line of its preview reading "On this iPad only". When the connection
works again it goes to Gmail's Drafts, once, and the line goes. A letter
reopened from Drafts and saved again with no connection is listed once, in
place of its copy on the server, which is removed after the new one is
there, as Save Draft always did. With a connection, Save Draft is what it
was, one APPEND and the old copy removed, and the letter is on the iPad
only while the save takes.

When a kept letter reaches Gmail, its row in Drafts becomes the copy there,
without the folder being fetched again: a search he is in, the rows he has
ticked in Edit and the place he has scrolled to all stay, and the copy it
replaced leaves the list, a search's hits included. (The first version of
this fetched the newest page after every landing, unasked, which ended a
search, took him back to the top from the pages below it, and left the
removed copy among the hits of a search it could not end.) In Edit, Delete
takes a kept letter off the iPad as Delete Draft does; Move and Mark leave
kept letters as they are, since there is nothing on the server to move or
mark yet. They used to be handed to the repository under the row's own id,
which failed silently, and the row came back.

While he writes, the letter is kept on the iPad three seconds after he
stops, and at once when he leaves the app, inside background time as Send
and Save Draft are (B-044); with a photo still being read in, the time is
held until it has landed and the letter is kept again with it. If iOS ends
the app, the next launch has the letter at the top of Drafts, marked, with
every word and photo, and takes it to Gmail's Drafts at the first chance.
The same for a sheet swiped down with a letter he had changed, and for a
letter whose Send was cut off by iOS ending the app. A letter he never
touched is not kept, and one he emptied does not replace what was kept
before. A letter he sent or deleted leaves nothing on the iPad; one he
saved, nothing once Gmail has it. A letter open in the composer is never
taken to the server behind it, and is not listed in Drafts until the sheet
has gone.

**When a kept letter goes up:** at Save Draft; each time a folder's newest
page has just been fetched, which is at launch, at a Refresh, on opening a
folder and on coming back after a while; each time the app comes back to
the foreground, after the connection's check (B-024's probe, `warmUp`); and
as he leaves the app. One letter at a time, inside background time, and with
none waiting nothing is sent. Only Save Draft makes a connection: every
other pass goes only over one already up, so after a launch that could not
connect, or a password Gmail refused, nothing is sent until he does
something that connects. The first version connected at every return to
the app while a letter was kept, and sent a refused password each time; it
said a password refused at the warm-up was not sent again, which held only
for a refusal made by the warm-up itself. A letter that fails with the
connection still up, a forward whose original has gone from Gmail or an
APPEND Gmail refuses, is passed over, and not tried again unasked until he
changes it or the app is launched again; the letters after it go. It used
to stop the pass, and as the newest it held back every older letter for
good, at the cost of its own round trips after every page. A letter
carrying a megabyte or more of photos goes unasked only as he leaves the
app, when nothing he taps waits behind its upload (PERFORMANCE.md, #4).

**Mail's own behaviour, and what was chosen.** Apple's guide ("Save a draft
in Mail on iPad") documents Save Draft and says nothing of a letter being
written when the app is ended; what Mail does then was not checked on a
device. Here the letter is not reopened in the composer at the next launch:
it is in Drafts, at the top. A composer that opened by itself would stand
over the Inbox he came to read, and a letter whose writing had made the
app crash would crash it again at every launch. No mark of Mail's for a
draft not yet on the server was found either, so "On this iPad only" is
this app's own, in words, where the preview's first line would be; VoiceOver
reads it first.

**How it is kept.** In Application Support, `Local Drafts/`, one directory
per letter: `letter.json`, written atomically, and its photos, which are
hard links to the composer's staged copies, so `AttachmentStore.purge()`
at launch leaves them. One letter is one entry however often it is kept.
JSON for D-016's reasons, and alongside D-016's copy of his mail rather
than inside it: never under `Kept/`, never wiped or evicted with it.
Excluded from iCloud backup. A file cut short, unreadable, or of a format
this build does not know is passed over and left where it is, never
deleted, and never stops a launch: it may be the only copy of a letter.

**Never twice in Drafts.** An APPEND whose answer is lost to a dropped line
may or may not have reached Gmail, and nothing on the iPad can tell which;
sent again blind, the letter could be in Drafts twice, and not sent again,
nowhere. Each time the letter is kept it is a new version, which goes up
under a Message-ID of its own, and is written down as tried just before
the APPEND goes, once the connection, the look in Drafts and the files are
done, so a save that failed before any of it was sent is never looked for.
The next upload of a letter tried before first asks Drafts for those
Message-IDs (`UID SEARCH HEADER Message-ID`): a copy of this very version
is taken as the save's and nothing is sent; copies of older ones are
removed with the old copy. A first save sends nothing it did not send
before. One Message-ID per version rather than per letter, so a copy found
is known to be this text and not an older one, and Gmail is never handed
two different letters under one Message-ID. A search refused on a working
connection is taken as nothing found: the letter goes up again, and at
worst Drafts has it twice rather than it never going. Until the next pass
has asked, a letter whose upload was cut off is listed twice: its row on
the iPad, and the copy the cut-off upload left.

Sent or deleted after an upload of it was cut off, the letter's copy in
Drafts is known only by those Message-IDs. Its words and photos leave the
iPad at once, and a record of the versions tried stays, never listed, until
the copies have been found and removed, after the sheet has gone, or by the
next pass if there is no connection then. The first version threw the
record away with the letter, and the sent letter stayed in Drafts for good.
A letter sent or deleted before its upload reached the APPEND never goes
up at all.

A kept letter can be opened from its row while a pass is taking it up. It
stays on the iPad until the composer has done with it: its photos are its
own files, the composer's copy still names the copy the upload has just
replaced, and the versions tried are how its next Save Draft, Send or
Delete finds the copy that landed. The first version took it off the iPad
as the upload landed, photos and all, from under the open letter: Send then
failed on the missing photo, Save Draft dropped the photo without a word
and put a second copy in Drafts, and Delete left the copy that had landed.
Closed untouched, it leaves the iPad then, since the server has it as it
stands. A Save Draft made while its upload is still on the wire waits for
that upload, then goes.

**Another account.** A letter is kept with the address of the account it
was written in, and goes only to that account's Drafts. One of another
account is listed and goes nowhere until he opens it and saves or sends it,
and it opens without the files it named on the server, a forward's or a
reopened draft's: those are named by folder and UID, and Gmail gives every
Inbox the same UIDVALIDITY (D-016), so in another account they can be parts
of another letter.

**Another mailbox under the same address, built 2026-09-30.** A password
saved in Settings can open another mailbox under his address (B-033), and a
mailbox can be renumbered under the UIDVALIDITY it had; either way a folder
and a UID a kept letter names can be another letter. Found in the code and
made on the scripted server, not on the iPad: a draft reopened from its
row and saved offline, taken up in a later launch with Drafts renumbered
under the same UIDVALIDITY, sent `UID STORE 302 +FLAGS.SILENT (\Deleted)`
and `UID EXPUNGE 302` onto another draft; and a forward of "Plans", sent
offline, went in the next launch with the file of the letter now under the
Plans' UID, "Medical results", as Plans.pdf.

Now everything a kept letter names on the server names its letter by Gmail's
id (X-GM-MSGID) as well as by folder and UID: the copy it was reopened from,
each of a forward's or a reopened draft's files, and each picture of its
quote, kept in `letter.json` beside them (`savedLetter`, and `letter` in
each file and picture; absent from a letter kept before, which reads as it
did). The id is that of the row the letter came from: a letter opened from a
row is that letter once the server has said so (B-053), and a forward, a
reply or a draft reopened from it carries its id (`Message.gmailMessageID`).
A copy this launch put in Drafts itself, reopened from the row its upload
drew, which names no letter, has its id asked in its own FETCH, `UID FETCH n
(UID X-GM-MSGID BODY.PEEK[])` in place of `(UID BODY.PEEK[])`, at no round
trip more. So has a copy an upload cut off after Gmail had it left there,
which the next upload finds by its version's Message-ID and takes as its
own: that search was made in this launch, so the copy is this launch's own
as surely as one its APPEND named. Left out at first, such a copy was
fetched plainly and named nothing, and a draft reopened from it and kept
offline into a later launch removed, and sent the file of, whatever draft
was then under its UID. Nothing is added to an upload, a Save Draft or an
autosave: asking in the APPEND's hold would have cost a SELECT and a FETCH
at every upload, and naming the copy by its version's Message-ID a second
kind of name to vouch by. Nothing is removed, fetched into a letter or sent
by folder and UID alone unless the server has shown in this launch that the
UID holds that letter, by B-053's rules:

- The copy a letter was reopened from goes as a write on a row goes
  (`deleteDraft`): the same letter named under its UID in this launch, and
  the `UID STORE` and `UID EXPUNGE` go as they always did; another, and
  nothing is sent; none yet, and `UID FETCH n (UID X-GM-MSGID)` goes first.
  Refused, nothing is expunged and the new version is in Drafts all the
  same; the log says `KEPT-UNVOUCHED folder=[Gmail]/Drafts nothing-sent` and
  `DRAFT-SUPERSEDED folder=[Gmail]/Drafts not-that-letter left`. The old
  copy stays in Drafts for him to delete; it is not guessed at. The same for
  the copy removed after Send or by Delete Draft in the composer, and after
  the Outbox's pass has sent the letter. Drafts' list leaves out the copy a
  kept letter stands in for only where the listing names, under its UID, the
  letter the kept one names there (`ListLetters.keep`); another draft under
  that UID stays listed. It used to be hidden by its UID alone for as long
  as the letter waited, where he could neither see nor open it.
- A file or a picture is taken from the letter the reading pane last
  fetched only when that is its letter. Otherwise it is fetched as it
  always was, and the FETCH that describes the letter, which on Gmail asks
  X-GM-MSGID already, is compared before the part's bytes are asked for:
  no round trip more, and nothing changed on the wire. Under a UID this
  launch has seen to hold another letter, nothing is sent at all. Not
  there, whether another letter is under the UID, none is, or its folder
  is gone or renumbered, the letter is looked for by its id in All Mail,
  `UID SEARCH X-GM-MSGID`, and the same part fetched there, that FETCH
  naming the letter too; the log says `CARRIED-PART folder=INBOX
  reason=another-letter` (or `gone`, or `folder`), then `CARRIED-PART found
  folder=[Gmail]/All Mail`. A forward whose original has been archived
  since is found the same way, where it used to fail. A line that goes
  while the letter is described or looked for is not the letter's being
  gone: nothing is noted of it, and the letter waits for the connection as
  any other does.
- Not found in All Mail either, nothing of the letter goes (`CARRIED-PART
  not-found nothing-sent`): it stays on the iPad saying "One or more
  attachments failed to load.", in Drafts on the line under "On this iPad
  only" (`LocalDrafts.draftsRows`, which the list draws), in the Outbox as
  its reason (B-052), and in the sheet if he sends it, and is not tried
  again unasked until he changes it or the app is launched again; the
  letters after it go. Changed since and refused again for a reason a
  draft's row does not give, it says nothing: each refusal sets its own
  reason, or none, and an earlier one's does not stay behind. The words are
  Mail's, as its users quote the alert iOS Mail puts up when a forward's
  attachments cannot be had ("Unable to Attach", "One or more attachments
  failed to load.", Apple's forums, thread 254851082, iOS 16.4.1). Mail
  offers Continue Anyway there; nothing here sends a letter short of a file.
  A sixth string beside the spec's four, as "This message is too big to
  send" is (`MailError.attachmentsMissing`).

A letter kept by a build before the ids were names things by folder and UID
alone, and goes as it always did until a password is saved.
`CredentialStore.save` counts each save in `Local Drafts/password-saves`,
beside the letters and touching none of them, and each letter is stamped
with the count its launch found (`passwordSaves` in `letter.json`; absent,
so 0, in one kept before). A password saved in Settings reaches the
repository only at the next launch, so from then on a letter kept before
the save opens without what it names by UID alone, as a letter of another
account opens, is not taken to the server by a pass, and no longer hides
its old copy in Drafts' list; a letter kept after the save names this
mailbox's letters. A count rather than the time of the save: a clock set
back would make a letter kept before the save look kept after it. The same
rule holds for a letter kept from a server without Gmail's extension, whose
rows carry no id; with no password saved, such a server goes by folder and
UID as it always did. Nothing is said on such a letter's row, as nothing
is said on another account's: it is listed, and opened it shows what it
has lost.

**Tested** in `KeptReferencesTests`, over the shipping repository and
`LocalDrafts`, the scripted server and a submission server, a later launch
being a new repository and store over the same directories, and another
mailbox the same one renumbered under its UIDVALIDITY: the draft reopened
and saved offline removes no other draft whether Drafts has been listed or
not, the question asked in the second case, and removes its own copy, asked
about only when unlisted; a copy this launch uploaded names itself when
reopened; Send and Delete Draft in the composer, and the Outbox's pass,
remove no other draft; a draft reopened, saved and sent in one launch sends
what it did; the forward sends the Plans' own file, found in All Mail, never
the other letter's, whether the listing named the other letter or the
describing FETCH did, with the other letter on screen, or with its folder
given a new UIDVALIDITY; nowhere to be found, it stays in the Outbox with
the words, lets the next letter go, is not tried again, and keeps the sheet;
a quoted picture the same; a draft whose file is nowhere stays in Drafts
with the words; a forward made and sent in one launch, and one sent by the
Outbox's pass in its launch, ask for nothing more, and one sent after
another letter was opened sends the two FETCHes it always did; an autosave
keeps the ids and sends nothing; an old `letter.json` reads and goes as it
did, and after a password save, from the next launch, opens without what it
names by UID alone, is not taken up and does not hide its copy, while one
kept after the save keeps its names; letters kept before a save that name
their letters, and a plain one, go as ever after it; on a server without the
extension nothing is named and everything goes as before; a copy found by
its Message-ID after a cut-off upload names itself when reopened, and
neither the draft nor the forward reopened from it removes or sends another
draft's; Drafts lists another draft under a kept letter's UID and leaves out
its own copy; a draft refused again for another reason no longer shows the
words; and a line lost while the original is described or looked for in All
Mail leaves the forward waiting, saying nothing, and the next pass sends it.
Each fails with its part undone in a scratch copy, one at a time:
forty-three sabotages, each failing at least the test named for it (the
superseded copy, the pass's copy, the composer's Send and Delete Draft
naming no letter; the reopened draft not naming its copy; `savedLetter`, a
file's id or a picture's id not kept; `deleteDraft` ignoring the letter; the
part's FETCH not comparing; this launch's `seen` not asked before a part; no
look in All Mail, or none for a renumbered folder; a forward or a quoted
picture not naming its original; the letter opened not naming itself; the
reading pane's copy not naming its letter, or taken whatever its letter;
"not found" said as `attachmentFailed`; a draft's refusal not written down,
or its row without the words; the password count never or always "saved
since", not written, read at every call rather than at launch, or not
stamped at a keep; a pass taking a letter naming by UID alone across a save,
a letter opened keeping those names, Drafts hiding its copy; a copy this
launch uploaded not remembered, or fetched by the FETCH that brings nothing
without the extension; the copy or the part asked about by a FETCH of its
own whatever this launch had seen; a copy found by its Message-ID not
remembered as this launch's; the Drafts row drawn without the words; Drafts'
list hiding by UID alone, never hiding a named copy, or not handed the
letters; an earlier refusal's words left behind; every letter kept before a
save held, or what names its letter dropped with the rest after one; and a
line lost in the look in All Mail, or in the describing FETCH, taken for the
original's being gone).

**Not yet seen on the iPad.** The TODO says how to make each case by hand.

**Tested** in `LocalDraftsTests`, with the composer's own wiring
(`ComposeActions(letter:…)`), the shipping `LocalDrafts` and the repository
over the scripted server, and a submission server for Send; and in
`ComposeActionsTests` with the keeping written into the log. Save Draft
with the line down, and with the password refused (one LOGIN), keeps the
letter, and a relaunch finds it; one the iPad cannot write goes straight to
the server. A first Save Draft sends exactly what it used to, with no
SEARCH. The later upload happens once however many ask at once, not while
the composer has the letter open, and takes it off the iPad. Coming back
three times with the password refused sends no LOGIN. A letter that cannot
go on a working connection lets the older one go, and is not tried again
until it changes. A large letter is not taken up while he is using the
app, so a letter he opens is answered with its APPEND held, and goes as he
leaves. A pass holds background time, given back once. A letter of another
account is not taken up, and opens without its server parts. An APPEND cut
off after the server had it is not sent again, a newer version replaces the
copy it left, a reopened draft cut off replaces its old copy once, and a
refused search lets the letter go up again. Sent or deleted after a cut-off,
nothing is left in Drafts, with the line down the next pass finishes it,
Delete in Edit does the same, and a letter deleted before its APPEND never
goes. Opened while a pass takes it up, then saved, saved before the upload
has landed, deleted, left alone, or with a photo sent or saved: one copy or
none, and the photo intact. Kept again while it goes, the newer text stays
and replaces it next time. A reopened draft saved offline replaces its
server copy when it goes. A kept photo survives the launch purge and goes
up with the letter, and one removed leaves its directory. Autosave keeps
the letter after the pause, once however many changes came before it, and
at once on leaving the app, inside background time given back once, held
for a photo still coming, and keeps nothing he has emptied. Send, Save and
Delete leave nothing behind, an autosave due after them included. A
swiped-away sheet keeps what he wrote and nothing he did not; closed
untouched, a letter reopened from the iPad stays kept. Letters are listed
newest first. A store with a truncated file, a file that is not JSON, an
empty directory, a stray file and a letter of an unknown format lists and
uploads the good one. Drafts lists kept letters above its own, in place of
the copies they replace, never grouped with them, and moves nothing else;
a letter that lands is drawn as its copy, in a search's hits and at the
top of a list that starts at the top, and the copies that went leave both.
Each of twelve sabotages fails at least one of these: the letter not kept
at Save Draft; not taken off once the server has it; no guard against two
uploads at once; no search before sending again; the version not written
down before it goes; the photo left as the staged file; no autosave; Send
and Delete not taking it off; an autosave landing after them; a swiped
sheet keeping nothing; one unreadable file emptying the list; Drafts
listing only the server's letters. And each of thirty-two more, each one
of the changes above undone in a scratch copy: the entry taken off while open,
or not taken off as the composer closes; no record kept for a letter sent
or deleted, or none finished by Send, Delete, Edit-mode Delete or the pass;
the pass stopping at a failure, or retrying one refused; the version noted
before the connection and the files, or after the APPEND; a letter gone
before its APPEND still sent; the pass connecting; large letters taken
unasked; no background time; another account's letters taken, or their
parts kept; the current version searched for at a first save; `abandon`
always or never removing; a landing ignoring a newer version; a refused
search failing the save; a copy found skipping the old copy's removal; no
fallback when the iPad cannot keep; an emptied letter kept by the autosave
or on leaving; removed photos left on disk; the list oldest first; a save
not waiting for the upload on its way; the copy that landed not drawn in
the hits, not hidden, or drawn at the top of a list opened at a day; the
leftovers' removal doing nothing.

**Not taken, and still to do.** Letters kept here are not searched: search
asks the server. `HEADER Message-ID` has not been tried against Gmail's own
SEARCH. A kept letter carries a forward's files, and a reopened draft's, as
parts of a letter on the server; if that letter is deleted from Gmail before
the kept one goes up, and is not in All Mail, the upload fails, and the
letter stays in Drafts on the iPad saying "One or more attachments failed to
load.", where he can open it and take the file out (above, "Another mailbox
under the same address"). One kept before the ids were says nothing. A large
letter on a slow uplink may not finish in the time iOS gives as he leaves,
and then goes again from the start, looked for first, at the next departure;
Save Draft in the composer sends it at once. Move and Mark in Edit pass over
kept letters without saying so. The Edit-mode routing and the list's handling
of a landing are UIKit, and only the pieces under them are tested here
(`LocalDrafts.delete`, `ListLetters.landed`). A Send cut off by iOS ending
the app comes back as a draft, and may be a letter that went: that is the
Outbox's to settle, next, on this store (TODO).

**Not yet seen on the iPad.** The TODO says what to look at.

**Seen on the iPad, 2026-09-30.** Wi-Fi off in Control Center, a letter
written, Cancel, Save Draft: Drafts listed it at the top, "On this iPad
only", beside the one "Can't connect to mail server." alert. Wi-Fi on,
Refresh: one copy on the server, the mark gone. A letter written and left
for five seconds, then the app force-quit and relaunched: the letter was
in Drafts, already uploaded after the Drafts page loaded. Not yet tried:
photos in a kept letter, and a letter opened while it uploads.

---

## B-049 — CHANGED 2026-09-30, seen on the iPad. New mail arrives on its own

**From the gap review of 2026-09-30.** New mail appeared only when he
tapped Refresh. Nothing asked the server for it: no IDLE, no polling, and
coming back to the app only warmed the connection up (B-041) and, after a
while away, fetched the Inbox again (B-003). "Updated Just Now" was said at
every fetch and never changed afterwards, so an hour-old list said it had
just been fetched. About 99 letters a day reach his Inbox, half of them
links he shares to himself from Safari. Checked on the scripted server
(`NewMailTests`, `ListPlaceTests`, `FeedbackTests`); nothing of it has been
seen on the iPad, and the TODO says what to look at.

**What he sees.** With the Inbox's list in front of him, a letter that
reaches Gmail is on the list within half a minute, fifteen seconds on
average, with no tap, and the counts beside the folders follow it. A letter
archived or binned on the phone leaves the list the same way. The line
under the list ages: "Updated Just Now", "Updated 1 minute ago", "Updated
12 minutes ago", "Updated at 14:13", "Updated Yesterday", then the date.
When the last try failed it says so under the age: "No Connection", or
"Password Needs Updating". Before a list's first page has come it says
"Checking for Mail…"; it used to say "Updated Just Now" before there was
any mail. After a jump to a day it says where he is, as before, until the
next Refresh.

Mail's words where they are known, from Mail's own bottom bar in published
screenshots of iOS 8 ("Updated Just Now", "Updated 2 minutes ago", "Updated
at 16:55", "Updated Yesterday", "Connecting...") and as users of later
versions quote it ("Checking for Mail...", "Updated 5 minutes ago",
"Account Error" under the "Updated" line when an account fails). Guessed:
"1 minute", singular; minutes giving way to the time of day at the hour;
the date's form; and the two failure lines, since "Account Error" would
tell him nothing.

**Where he is decides when the new rows go on.** Nothing he is looking at
or touching moves:

- At the top of the Inbox's list, no search, nothing ticked, no finger on
  the list: at once. The new rows go on at the top, the rows below move
  down by as many, and the list stays at the top, where he sees them come.
  The letter open in the reading pane stays open and its row stays
  highlighted wherever it now is; a reply to it takes its conversation's
  row to the top, highlight and all. A letter taken out elsewhere comes
  off; if it is the one open in the pane, the pane keeps it.
- Scrolled down: nothing on the list changes, not a row, not where it sits,
  not the highlight. The letters wait, and go on the moment he has
  scrolled back to the top and the list has come to rest there. Put on at
  once, a reply in a conversation he could see would have taken its row up
  out from under him, and a letter gone would have closed its gap.
- A finger resting on the list, a tap on a row as a letter comes: held
  the same, and put on at the next check once the finger is lifted, since
  a finger that never dragged tells the list nothing when it lifts.
- Edit mode with ticks: the same, and every tick stays on its letter. They
  go on at Done, or when the last tick is taken off. Edit mode with
  nothing ticked is the top as usual.
- A search showing: the Inbox's list is not checked at all while it
  shows, only the Inbox's count. The first check after the search ends
  finds what came, within half a minute; letters found just before it
  began go on as it ends, if the folder comes back at its top.
- A day jumped to: only the count, while the list does not reach the
  Inbox's newest letter. A day whose window reaches it, or a list paged
  back up to it, is checked as the top of the Inbox is. The next Refresh
  lists it all. A letter a check found as he jumped is not put on the
  day; it is searched for again once the list starts at the newest letter.

Refresh, a Delete or Move from Edit mode and a return after a while away
fetch the list afresh as before, and whatever was waiting with it. More
than a page (50) waiting at once, or an Inbox renumbered, is not added to
the list: it is fetched afresh when he is next at the top, without an
alert if that fails, since he did not ask for it. One such fetch at a
time; one that fails is made again at the next check that finds him at
the top, and one that lands after he has started typing a search is
dropped rather than clear the field under his fingers.

**Another folder in front.** One STATUS of the Inbox a check, which leaves
his folder selected, and the counts swept only when the Inbox's is not
what the sidebar shows. Nothing else of the Inbox is fetched until he opens
it.

**The watch's sweeps are quiet.** A sweep of the counts that the watch
asked for and that fails leaves the counts as they were, with no "Can't
connect" put over the letter he is reading: he did nothing, and the line
under the list already says "No Connection". Merged with a sweep he asked
for, it is his, and fails as every sweep always has.

**What it sends.** Every half minute, in the background line of the
exchange gate, one command in a hold of its own:

- The Inbox open on the connection: a NOOP. Nothing more when nothing has
  changed, which is nearly every time.
- Something arrived or left, told on that NOOP's answer or on any since (a
  preview's FETCH can bring the EXISTS), or found by a check whose letters
  never reached the list (below): a `UID SEARCH UID n:*` from the
  lowest letter the list holds, which says both what is new above its
  newest and which of its letters have gone; a `UID FETCH` of the new
  letters' summaries alone; each new letter's preview as the list draws
  it, within the usual 2 KB and 8 KB; and one sweep of the counts, merged
  with any other (`SweepCoalescer`). No SEARCH ALL, and no page fetched
  again.
- The Inbox not open on the connection, after another folder's work: its
  SELECT in place of the NOOP, and the SEARCH after it, since a SELECT is a
  view nobody has searched.
- Another folder, a search or a day in front: `STATUS "INBOX" (UNSEEN)`.

A letter he opens while a check waits for the connection goes first; one
he opens while the check's command is on the wire waits for that one
answer, not for the SEARCH and FETCH after it. Checks never overlap; the
next is half a minute after the last has finished.

**What it keeps.** B-045: a NOOP answered is the Inbox's news asked for,
so a Refresh within two seconds of a check sends no NOOP of its own, and a
listing of the Inbox from the top counts as searched, so the check after
it searches only if something has changed since; a date jump that found
nothing, or a listing the server refused, does not, since the list on
screen stays the one it was. B-024: a check's NOOP proves
the connection only once it is answered, as the warm-up's does; answered,
a write in the next ninety seconds goes without a probe. While the app is
in front the connection is never ninety seconds quiet, so a write probes
only in the moments after a return, and waits behind a check's NOOP like
anything else. B-039: every UID command in one hold with its SELECT.
B-041's warm-up and B-003's return are as they were. And while the app is
in front the connection is never quiet long enough for Gmail to end the
session, so his taps meet a connection proven a moment ago.

**A write behind a check that finds the socket dead.** A Delete, a Flag or
a read mark made while a check's NOOP is out waits for it. When the NOOP
finds the socket dead it tears the connection down, and the write's turn
comes with none: not a byte of it has gone, the SELECT included. It used to
fail there, "Can't connect", and a write is never sent twice, so the letter
stayed in the Inbox and a letter just opened had its dot put back; on a
half-open socket that was every write made in the thirty seconds the NOOP
waited for its answer. Now the client says the write was not sent
(`IMAPClient.Unsent`) and it goes once, on a new connection
(`IMAPMailRepository.sendingOnce`), by the rules a read's retry keeps: not
after a refused password, and not when an attempt to connect failed while
it waited. A write that went out on a socket that had died, whose command
the server may have carried out, still fails and is not sent again.

**Why a NOOP every half minute, and not IDLE.** IDLE on the one connection
would put a DONE and its answer in front of every tap, a read with no end
where every read has a deadline (`TransportDeadline`), and a gate that has
to break an exchange it did not start. IDLE on a second connection would
leave taps alone, but it is a second LOGIN at every return to the app, a
revoked password sent twice, its own reconnects, and Gmail's end of IDLE
after about half an hour; Gmail allows fifteen connections, so the count
was never the problem. A NOOP is what the one connection already sends as
the write's probe, the warm-up and the catch-up. It costs up to half a
minute before a letter shows, where IDLE would take seconds.
ARCHITECTURE.md asks for IDLE while the app is active "if stable with the
provider"; this keeps what that asks for, mail arriving while he looks,
and IDLE stays open for later if half a minute proves too slow. Mail itself
does not have Gmail push to it: Settings offers a Gmail account Fetch and
Manual only, which users have reported for years; how often Mail checks
while it is open in front is not known here.

**Nothing while the app is away.** The checks stop as it goes into the
background and start again as it comes back, the first half a minute
later, after the warm-up and B-003's return, and never before the launch's
first page has been tried. A check on the wire as it goes is answered, as
any command is, and nothing after it is sent: no FETCH, no sweep, no fetch
of the list afresh, and nothing on the line.

**What a check found and lost is searched for again.** Gmail tells a
session of a letter once, on the first answer after it arrives, and the
SEARCH that follows takes that as searched. A check whose letters never
reached the list, stopped as the app went away with its SEARCH or FETCH on
the wire, refused part-way (`[UNAVAILABLE]` to the SEARCH or the FETCH), or
overtaken by a jump to a day, used to leave every NOOP after it saying
nothing had changed: the letter stayed off the list under "Updated Just
Now" until another came, or he tapped Refresh. The watch now remembers
that it owes a search (`MailWatch.searchOwed`), and the next check of the
list makes one, found or not by its NOOP. It costs a SEARCH, once.

**A refused password stops them.** The check that finds the socket dead
reconnects, as a read does; if its LOGIN is refused, that is the last
password the watch sends until a LOGIN of his own has been accepted, and
its refusal stands for every call for a minute, as the warm-up's does, so
the letter he taps next does not send the same password straight after
it. Any refusal, not only a wrong password: Gmail's
`[ALERT]` asking for a sign-in on the web would otherwise be a failed LOGIN
every half minute. (Since B-056, only a refused password stops them: a
LOGIN refused for another reason is tried again by the watch five minutes
after the last refusal.) The app has no sign-out; the watch belongs to the
root view controller and ends with it.

**With no connection** each check tries to connect, which with no network
fails at once, before any TLS, and the line says "No Connection" under the
age of what is on screen. The first check once the network is back
connects and lists what came.

**And a retry that did not go, found on the way.** A Delete or a Flag made
while the warm-up's NOOP was out on a dead socket probes first (B-024), and
its probe fails with the warm-up's. The probe was retried only if the
connection was still down when it looked, and when the warm-up had already
connected again it was not: the write failed, and a write is never sent
twice, so the letter stayed. With eight copies of `ComingBackTests`' test
running at once it failed in 7 of 320 runs on the code before this change.
The check's NOOP would make that any half minute. A read or a probe is now
retried when the connection it began on has been torn down, whether or not
another call has connected since; the refusals are still never retried.
The same test failed in 0 of 320 runs with this and in 3 of 320 without it,
as did the check's own. Those two tests race, and pass without the rule on
most runs; the rule itself is tested in every state a failed read can find
the connection in (`IMAPMailRepository.retries`).

**What it does not cover.** A letter read, flagged or moved between
folders on the phone keeps its old look here until Refresh. Sent, Drafts
and the other folders' lists are not checked, only the Inbox's count
beside its name. An Inbox whose first page never came, with no connection
at launch, stays empty until Refresh, and goes on saying "No Connection"
though the counts come back. A tap landing just as new rows go on at the
top can meet the row that moved, as in Mail. The connection log gains a
NOOP and its answer every half minute, so its 500 lines hold about two
hours of an idle app, where an idle app used to add nothing to it.

**Tested** over the scripted server with a clock the test moves. In
`NewMailTests`: a letter that arrives is listed at the half minute and not
before, with a NOOP, a SEARCH from the list's lowest letter and a FETCH of
it alone, and its preview is 2 KB; nothing arriving is one NOOP a check,
proves the connection for a Flag eighty seconds on and spares a Refresh a
moment later its NOOP; another folder is one STATUS a check, leaving its
mailbox selected, the count follows, and the STATUS proves the connection
for a Flag; a search showing is one STATUS and its next page needs no
SELECT; a day jumped to, and a list whose first page never came, are one
STATUS; the Inbox left closed by an All Mailboxes search is SELECTed and
searched; two letters one check apart while he is scrolled down are each
fetched once and held, and go on newest first with a letter gone elsewhere
taken off; a letter held under a resting finger goes on at the next check
once it is lifted; a letter removed elsewhere leaves; a tap during a
check's NOOP goes before its SEARCH, and one made while the check waits
goes before it; a Delete made while a check's NOOP is out on a dead socket
goes once, on the new connection, whether the connection was quiet long
enough for the Delete to probe or had been proven by the check before; a
Flag that went out on a dead socket is not sent again; nothing is checked
while the app is away, the watch started twice is one loop, and a check
out as it goes sends nothing after its command, sweeps nothing and hands
the list nothing, a renumbering included; a letter whose SEARCH or FETCH
was out as the app went, whose SEARCH or FETCH was refused, or whose check
a jump to a day overtook, is listed by the first check that can list it;
a refused password, and a LOGIN refused for another reason, stop the
checks until his own LOGIN, or a PREAUTH, is accepted (since B-056, a
LOGIN refused for another reason only for five minutes), and after it a
socket that dies is replaced by the next check; with no connection each
check says so, the first after lists what came, and the connection it
makes is proven for a Flag; more than a page at once, or a renumbering, is
fetched afresh and not added to, and a renumbering seen check after check
is swept once; a letter Gmail told of on the previews' FETCH rather than
on a NOOP is listed by the next check, after a date jump that found nothing
and after a refused Refresh too; the retry rule in each state a failed read
can find the connection in; and the watch's sweeps are quiet unless merged
with one of his. In `ListPlaceTests`: held while scrolled, ticking,
searching or touched, nothing moving and every tick and highlight kept; at
the top the open letter keeps its highlight; news already held or shown is
not news again; a fetch afresh or a day drops what was held; only a list
at the newest letter is checked, takes news, and puts it on at the top, or
is fetched afresh. In `FeedbackTests`: the line's wording over time, a
failure under the age, a list never fetched, and what each check's
outcome says on the line of the list in front. Each of these fails with
its part of the change taken out; the controllers' own calls (the quiet
fetch's one-at-a-time and search checks, the first page's hold on the
watch at a return, the quiet sweep's alert) are UIKit and are not on the
host.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox. With the Inbox open
at the top, a letter sent from the app to the account itself went on at
the top of the list by itself between 35 and 50 seconds after Send,
Gmail's delivery included, and the Inbox's count in the sidebar went from
1 to 2; nothing was tapped. Not yet tried: a letter arriving while he is
scrolled down or in Edit mode, the line's aging over minutes, and the
line with Wi-Fi off.

---

## B-052 — CHANGED 2026-09-30, seen on the iPad. A letter that could not be sent lasted only as long as its sheet

**Found in the gap review of 2026-09-30** ("No Outbox" under "Ways a letter
is lost" in the TODO), in the code, not on the iPad. Send with no
connection kept the sheet with "Can't connect to mail server." (B-044),
and nothing was lost while the sheet was up; but the sheet was the only
place the letter was. He had to leave it open until the connection came
back and tap Send again. Swiped away, or ended by iOS while it waited, it
was at best a draft (B-051). And a send whose DATA had gone when the line
died, before Gmail's 250 came back, said "Message was not sent." when Gmail
may well have had it: tapped again, it went twice. A Send cut off by iOS
ending the app came back as a draft that may have been a letter that went
(B-051, "Not taken").

**What Mail does.** Apple's page "If you can't send email on your iPhone or
iPad" (support.apple.com/en-us/102556, 15 September 2026): "If you get a
message that says your email wasn't sent, then that email goes to your
Outbox", which is in "your list of mailboxes"; "If you don't see an Outbox,
then your email was sent"; to send it again, tap it there, check the
address, tap Send. While one waits Mail's bar says "1 Unsent Message"
(pictured by OS X Daily in 2014 and 2016, and quoted in Apple's forums,
thread 5962939; a user on JustAnswer read the bar out as "updated at 12:18
PM with 1 unsent message", then the account error), and it sends the letter
by itself once there is a connection, usually (OS X Daily). Its alert, as users quote
it, is "Cannot Send Mail" and "A copy has been placed in your Outbox." over
the reason, "The connection to the outgoing server … failed" or "The
recipient … was rejected by the server" (Apple's forums, threads 8473284
and 8269994). Mail puts a letter the server refused in the Outbox as well;
this app does not (below). Guessed, not checked on a device: where Mail's
list puts the Outbox, "2 Unsent Messages" for the plural, what VoiceOver
says for it, and whether Mail says anything at all as its composer closes
with no connection.

**What he sees now.** Send with no connection, or on a line that goes
before Gmail has answered, or on a Gmail that says "not now": "Sending…"
as before, then the sheet closes, and one notice says "Message is in the
Outbox. It will be sent when the iPad is connected and Blackmail is open."
Mail's "a copy" and the name of Gmail's server would tell him nothing, so
the words are the app's own. "And Blackmail is open" because nothing sends
it while the app is put away: every pass is the app's own doing, and there
is no background task, so a Wi-Fi that comes back while it is put away
sends nothing until he opens it (the first wording, "when the iPad is
connected", promised what it could not keep). An "Outbox" row with a
tray-and-arrow icon comes into the Mailboxes, a block of its own below the
folders, with how many letters wait beside it, so nothing above it moves;
in two panes it is in the same column (D-015). The line under every list
says how many wait, under the age and over a failure: "Updated 3 minutes
ago", "1 Unsent Message", "No Connection". The Outbox lists each letter by
whom it is to, as he wrote their names, and its subject, newest first, with
"Sending…" under them while it goes; it has no search, no calendar, and
Refresh there takes what waits over a connection already up. When the
connection is back, with the app open, the letter goes by itself, once, and
leaves, and the Outbox leaves the Mailboxes with its last letter.

Tapped, a letter opens in the composer and is out of the Outbox while it is
there: Send sends it, and puts it back if it cannot go; closed untouched it
is back as it was; changed and swiped away, or saved, it is a draft. A
letter on its way cannot be opened: gone while the composer had it, a Send
there would send it again. Nor can one a pass has just sent: it leaves the
Outbox at its 250, before its old copy in Drafts is removed, and that copy
is told to the list as gone then too. The first version removed the copy
first, and for those round trips the row was back without "Sending…", to
be opened and sent a second time. A pass never takes a letter the composer
has open, looked at as the letter goes, not before the pass asks whether
the connection is up. In Edit, Delete takes it off the iPad. A letter
reopened from Drafts and sent with no connection is not listed in Drafts
while it waits, where a tap would open it to be sent a second time, and
its copy there is removed once it has gone, as Send in the composer
removes it, and only if the server shows that UID still to hold the draft
he reopened (B-051, "Another mailbox under the same address").

**What waits and what keeps the sheet** (`Outbox.waits(after:)`). Waits,
since nothing was said about the letter and it may go later as it is:
`MailError.cannotConnect` (no connection, the submission server not
reached, or a forward's files or the Sent Mail look below failing for want
of the IMAP connection), the new `MailError.connectionLost` (the line
went, or stopped answering, before the server's verdict: a peer that hung
up, a link that failed, a deadline that passed) and the new
`MailError.refusedForNow` (a 4yz reply at any step, RFC 5321's "not now":
Gmail's "421 4.7.0 Try again later" at the greeting, "454 4.7.0" to AUTH,
"451 4.3.0" after DATA; AUTH LOGIN is not tried after a 4yz to AUTH PLAIN,
which would only send the password again). Keeps the sheet
with the reason, as B-044 has it, since sent again as it is it would fail
again: `passwordNeedsUpdating` (the account: the same password would be
refused at every pass, and each refusal counts toward Google's lockout),
`messageTooLarge` (something has to come off the letter), `notSent` (every
other refusal the server makes with a code, a 5yz: every recipient
refused, the letter refused after DATA, a sender refused, and a letter to
nobody; every recipient refused with a 4yz is "not now") and
`attachmentFailed` (a forward's file gone from Gmail, or its original's
folder renumbered or deleted since, which the IMAP client says as "Can't
connect" and the repository now tells from a connection that is down: taken
for one, such a forward waited for good and, as the oldest, ended every
pass before the letters after it). Since 2026-09-30 that is a file named
by folder and UID alone, kept before the ids were or from a server without
Gmail's extension; one that names its letter by Gmail's id is looked for
in All Mail when it is not under its UID, and goes from there, and found
nowhere it is `attachmentsMissing`, "One or more attachments failed to
load.", its row's first line, which keeps the sheet as well (B-051).
Anything else, a photo's file that cannot be read, is "Message was not
sent." as it always was. `SMTPClient`
used to throw `notSent` for all of it past the connect; it now tells a line
that went, a transport error, and a "not now" from a refusal. Both are
read out as "Message was not sent.", so the share extension says what it
said before.

iOS taking back the time it gave for a send, with the 250 still to come:
the time is given back and nothing else happens, as before (B-044). If iOS
then suspends the app, the send fails as he comes back, at the write or
read deadline, a lost connection: the letter waits in the Outbox, being
sent, and the sheet closes with the notice. If iOS ends the app, the letter
is in the Outbox at the next launch, since it was put there before a byte
went.

**How it is kept.** On B-051's store, in the same `Local Drafts/` in
Application Support, out of iCloud backup, never under D-016's `Kept/`, its
photos hard links of its own. A letter in the Outbox is a kept letter with
two more fields in `letter.json`: `outbox`, the Message-ID it goes under,
and `unsettled`, the Message-IDs of attempts whose DATA went and whose 250
never came back. Both absent from a letter an older build kept, which
reads as a draft, so no new format; and `cutOff`, when the latest of those
attempts was last known to be on its way. At the tap on Send the letter is
kept, as B-051 had it, and put in the Outbox under a Message-ID made then
on the account's domain, which `RFC5322Builder` is handed at every
attempt, so every attempt is the same message; sent again from the
composer with an attempt still unsettled, it keeps that attempt's
Message-ID rather than taking a new one. Kept as a draft again, by the
composer that has it open, it leaves the Outbox and keeps its `unsettled`.
What a reply or forward quotes, B-050's markup and pictures, is kept with
the letter now, a draft's too, so a letter sent later looks as it would
have at once. The markup is a file of its own, `quote.html`, beside
`letter.json`: a newsletter's is a megabyte, and inside the JSON every
write of the letter's state (the one between RCPT and DATA among them)
decoded and encoded it again, about 25 ms on the host, and every list that
counts the Outbox decoded it. It is read only when the letter is opened or
goes; a list reads the letters without it. It counts toward the megabyte
that holds a draft's upload back (`LocalDraft.isLarge`), since it goes in
the APPEND. Another account's letters are listed and never sent from this one,
and open without the quote or the parts they name on the server (B-051).
So, since 2026-09-30, are this account's letters kept before a password was
saved that name parts by folder and UID alone; every other part a letter
in the Outbox carries names its letter by Gmail's id, and goes only from
that letter (B-051).

**Never twice.** A letter is waiting until its attempt is about to send
DATA; just before, once the server has taken the envelope, the attempt is
written down (`SMTPClient.send`'s `beforeData`, `LocalDraftStore.
noteSending`), and from then on it is being sent. Before a letter with such
an attempt goes again, Sent Mail is asked for it, `UID SEARCH HEADER
Message-ID`, since Gmail files there what it takes over SMTP
(`MailRepository.sentMail(holds:)`). Found, it went: nothing is sent, and it
leaves the Outbox. Not found, it goes again, under the same Message-ID, but
only once ten minutes have passed since the cut (`Outbox.settling`): a
server may take that long over a letter after its terminating dot (RFC 5321
§4.5.3.2.6, which is also how long the app waits for the 250), and Gmail
files it in Sent Mail only once it has taken it, so a look a moment after
the cut, from the Outbox opened or the connection coming back, proves
nothing; until then the letter waits, still being sent. Each look asks for
Sent Mail's news first, with a NOOP in the same hold, unless the SELECT
went in it (`IMAPClient.searchNow`): a SEARCH in a mailbox already open on
the connection answers from what the session was last told (B-045), and
with Sent Mail left open by his own visit to it, a letter Gmail filed since
was not found and went again. A NOOP refused fails the look. The look is
made in the folder LIST gives the \Sent role, or in All Mail when LIST names
no Sent Mail ("Show in IMAP" off for it), never in a name guessed; with
neither listed, the letter cannot be looked for and is not sent blind: its
row says "Message was not sent.", and so does the sheet if he sends it.
The look is a read, retried once on a new connection when the socket dies
under it, as every read is (B-023), a pass's too: the pass began on a
connection that was up. A search the server refuses, or that cannot run,
sends nothing: the letter waits, still being sent, for the next pass to ask
again, and the letters after it go. Taken as "not there", as a refused
search in Drafts is (B-051), the letter could go twice, which cannot be
taken back; waiting costs a pass. A letter whose attempts never reached
DATA is simply sent. A verdict after DATA, a refusal or a "not now",
settles that attempt, since the server said it did not take it. Deleted
from the Outbox while a pass has it on its way, before its DATA, the write
before DATA finds it gone and DATA is never sent. Sent again from the
composer, a letter opened from the Outbox asks Sent Mail first too: found,
the sheet closes as for a letter sent, and nothing more goes, whatever he
changed; a password refused for the look keeps the sheet with "Password
needs to be updated", as for a Send refused for it. Saved as a draft
instead, a letter with an attempt unsettled goes to Drafts only once Sent
Mail has said it does not have it: taken there before, it left the iPad
and the record with it, and sent later from Drafts it went again with
nothing looked for. Found, or not yet answered, it stays on the iPad,
listed in Drafts, and a Send from there asks first; found, no pass asks
again until he changes it or the app is launched again.

**When a waiting letter goes.** By B-051's pass, and at its moments: after
a folder's newest page, on coming back after the warm-up, and as he leaves
the app, inside background time; and at one more, the first check of the
watch (B-049) to reach the server after one that could not, which is the
connection coming back while he reads. That one takes drafts too; it is
not every check, so a letter the server refuses is not tried every half
minute. The Outbox first, oldest first, in the order he sent them, then the
drafts. One letter at a time, and only while the IMAP connection is up,
which says the network works and the password was taken, and which the
look in Sent Mail needs; the SMTP connection is then made for a letter he
asked to send, as every letter makes its own. A refused password ends the
pass, and nothing more goes from the Outbox unasked until a Send of his own
has gone, or the app is launched again: each page would otherwise send the
refused password again. A letter refused for its own reason stays, the
reason as the first line of its row ("Message was not sent."), and is not
tried again unasked until the app is launched again; the letters after it
go. A submission server that cannot be reached while IMAP works ends the
Outbox's part of the pass, as does a "not now" from it; the drafts after it
still go up: each letter after it would cost a connect for the same
failure. Size: an Outbox letter goes over a connection of its own, so its
photos hold nothing he taps and it goes at once; what a forward or a
reopened draft has to fetch from Gmail first comes over the one IMAP
connection, and a megabyte or more of that waits for him to leave the app,
as a large draft does (`LocalDraft.fetchesLarge`). That is its rows from
Gmail and nothing else: a forward's quoted pictures that go are ones that
are also its rows, fetched once, and counting them again held a forward of
600 kB of photographs back as 1.2 MB. Nothing sends while the app is put
away (above).

**The share extension** keeps its sheet with the reason when a letter
cannot go. It has no app group, only the shared keychain group, so it
cannot reach the store. The keychain mirror could carry a small letter, but
then two processes would write the one thing that must never go twice: the
extension, suspended mid-send by iOS, cannot say whether its DATA went, and
the app, taking the letter over, would have to look for an attempt it never
wrote down. A photo would not fit, and a shared link is two taps to share
again.

**Names.** The enum the app and the extension send through, which was
called `Outbox`, is `Submission` (`SMTP/Submission.swift`); the Outbox he
sees is `Outbox` (`Mail/Outbox.swift`), its letters kept by `LocalDrafts`,
and its mailbox's role `.outbox`.

**Tested** in `OutboxTests`, with the composer's own wiring, the shipping
`LocalDrafts` over a directory of the test's own, the repository over the
scripted server, and a scripted submission server per connection that can
fail to open, hang up after the letter before its 250 (closed, reset, or at
a deadline), hold that reply, let it go late or let its deadline pass,
refuse the password, refuse a recipient, or say "not now" at the greeting,
at AUTH or after DATA; in `LocalDraftsTests`; and in `ComposeActionsTests`.
Send with no connection closes the sheet once, says so once, draws nothing
after, gives the time back once, and leaves the letter waiting in the
Outbox and not in Drafts, there after a relaunch; a later pass sends it
once however many ask, under the Message-ID it entered with, with no look
in Sent Mail; no pass connects. A DATA cut off before the 250 is being
sent, is looked for in Sent Mail after a relaunch, found and not sent
again; not found, it goes once more under the same Message-ID; a refused
search sends nothing, lets the next letter go, and the next pass asks
again; deleted while its look was out, its DATA never goes; opened from the
Outbox and sent, the earlier attempt is looked for first. A recipient
refused, a letter too big after DATA, and a refused password keep the
sheet, out of the Outbox, with nothing to look for. The time taken back
before the 250 leaves the sheet, and the line dying after leaves the letter
in the Outbox. A refused password goes once, whatever pages and returns
follow, until his own Send goes. A stuck letter lets the next go, says why
on its row, is not tried again until a relaunch. Letters go oldest first.
An unreachable submission server ends the Outbox's part of the pass. The
reopened draft's copy is not listed while the letter waits, and is removed
after it goes. Photos do not hold a letter back and a forward's files do.
Another account's letter is not sent, and opens without its quote. What a
letter in the Outbox names on the server, its reopened draft's copy, its
files and its quoted pictures, is tested with the drafts' in
`KeptReferencesTests` (B-051). The rows, count, VoiceOver label, open,
close untouched, swipe to a draft, and Delete. With nowhere to keep it,
Send goes straight and a failure keeps the sheet. The submission client
tells a lost line from a refusal; DATA waits for the write before it and
never goes when that throws; the quote survives the store; the line's three
lines. Also: a letter Gmail filed in a Sent Mail already open is found;
nothing found a moment after the cut sends nothing, from a pass or the
composer, and the composer's Send keeps the Message-ID; the look goes to All
Mail with no Sent Mail listed, and with neither the letter is refused with
its reason and no folder is guessed; a look cut off goes once more on a new
connection; a look refused for its password keeps the sheet; a letter saved
as a draft with an attempt unsettled is not taken to Drafts while Gmail has
it, and a Send from it sends nothing, and is taken there once Sent Mail has
not got it; a letter a pass sent leaves the Outbox and its Drafts copy's row
before the copy is removed; a pass leaves a letter opened as its turn comes;
a forward whose original's folder was renumbered is refused with its reason
and lets the next letter go; a "not now" at three steps waits, settles the
attempt, and does not try AUTH LOGIN; a lost line at a deadline and at a
reset is a lost line; the attempt is written down after the last RCPT and
not at all when every recipient is refused; the Outbox goes before a draft,
and an unreachable server leaves the draft to go; his own Send refused for
its password stops the pass; a pass sending a letter after a cut-off upload
leaves nothing in Drafts; a quote's markup is kept beside the letter and
counted in its size; a forward's quoted pictures are counted once; the
notice's words. Each of these fails with its part undone in a scratch copy:
thirty-seven sabotages at first, each failing at least the test named for it
(the queued branch, the entry into the Outbox, a lost line keeping the
sheet, the SMTP split, the look, a refused look taken as none, the write
before DATA, a deleted letter's DATA, the Message-ID, the password latch and
its clearing, a refusal stopping the pass or not being recorded, the Drafts
copy kept or listed, the Outbox in Drafts, an open letter in the Outbox, a
keep leaving it in the Outbox, photos holding it, another account's letters
sent or their quote kept, the letter not taken back or its attempt not
settled after a refusal, the unsent line, the quote, the pass skipping the
Outbox, `unsettled` dropped at a keep, the sheet not letting go or staying
live, the count read as unread, the row's reason, the order, an unreachable
server tried for every letter, a refused look stopping the pass, the look
made in Drafts, the fallback queuing, the row's name), and twenty-six more
for what followed, each failing the test named for it (the look without its
NOOP, or with the NOOP skipped inside two seconds; the Drafts copy removed
before the letter left the Outbox; the pass's open check and its order; a
forward's refused folder taken for no connection; a 4yz read as a refusal,
AUTH LOGIN after one, a verdict after DATA left unsettled; no settle time; a
new Message-ID at every Send; Sent Mail guessed; the markup in the JSON, not
counted, or written at every keep; the old notice; a forward's pictures
counted twice; a letter saved as a draft taken to Drafts unlooked; the
pass's discard a plain remove, and no tidy after it; his own Send's refused
password not latched; only a clean close taken as a lost line; no retry for
the look; a refused password at the look taken as unsettled; drafts before
the Outbox; an unreachable server ending the drafts too; the write before
DATA made before MAIL FROM as well).

**Not taken, and still to do.** That Gmail files a letter taken over SMTP
in Sent Mail under the Message-ID the app gave it has not been checked
against Gmail, nor has `HEADER Message-ID` against Gmail's SEARCH (B-051),
nor how long after its 250 it is there (the ten minutes are RFC 5321's,
not measured); `RFC5322Builder`'s own comment says Gmail rewrites the id on
submission. If
it does, the look finds nothing, and a letter cut off after its DATA goes
again, twice, which is what happened before this change and no worse; the
first device check below settles it. A letter the pass cannot send for its
own reason says so on its row and nowhere else: there is no alert while he
reads. No "Sending 1 of 2" as Mail has. A letter found in Sent Mail after he
changed it in the composer went as it was; saved as a draft instead, it
stays on the iPad, since Gmail has the letter already. No background task:
a letter waits for the app to be open (above). A letter a pass cannot send
because neither Sent Mail nor All Mail is listed can never go from the
Outbox; that needs "Show in IMAP" turned back on in Gmail. Deleting from the Outbox a letter
reopened from Drafts leaves its old copy in Drafts, as deleting a kept
draft does (B-051). The sidebar's row, the Outbox's list, the notice and the
watch's trigger are UIKit and not on the host; the pieces under them are
tested (`LocalDrafts.outbox`, `LocalDraft.outboxRow`, `Outbox.mailbox`,
`UpdatedLine.text`).

**Not yet seen on the iPad.** The TODO says what to look at.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, before the branch
was merged, each letter to the account itself:

- Wi-Fi off in Control Center, Send: the sheet closed, "Message is in the
  Outbox. It will be sent when the iPad is connected and Blackmail is
  open." once, Outbox with 1 at the foot of the sidebar, and the line
  "Updated Just Now / 1 Unsent Message / No Connection". The log says
  `OUTBOX-WAITING error=cannotConnect`, nothing sent. Wi-Fi on, nothing
  tapped: about a minute later one envelope, one 250, the Outbox gone and
  the letter in the Inbox once.
- Gmail filed that letter in Sent Mail under the Message-ID the app gave
  it (the ENVELOPE of the Sent Mail row carries it), so the look before a
  second attempt has something to find.
- Five pictures (4.3 MB on the wire), the lock button pressed 0.48 s
  after Send: the upload finished with the screen off, one envelope, the
  250 4.7 s after the tap, and on unlocking a minute later the sheet was
  gone, no Outbox, and the letter arrived once.
- To "nobody": Gmail answered RCPT TO with 553 5.1.3; the sheet stayed
  with "Message was not sent." and the letter in it, and nothing went to
  the Outbox.

Found there and fixed before the merge: the line under the list fitted
itself to the width it already had, so after a short line it never grew
back, "Updated Just Now" wrapped onto three lines and "1 Unsent Message"
was cut short. It is now measured against the width the bar leaves
between Refresh and Settings; seen right in both states.

Not yet tried: a DATA cut off before the 250 (the Sent Mail look on the
device), a letter opened from the Outbox and changed, and Delete there.

---

## B-053 — CHANGED 2026-09-30, seen on the iPad. A launch drew an empty Inbox, and with no connection nothing at all

**From D-016, phase 1.** Every launch after iOS had ended the app, which
is most times he picks the iPad up, drew an empty Inbox under "Checking
for Mail…" for a second or more, and a folder pane of names with no counts.
With no connection the Inbox stayed empty for good, with one "Can't connect
to mail server.", and so did every folder he opened. The spec asks for the
opposite ("Cached Inbox appears within 500 ms", "Offline launch still shows
cached messages"). Built and checked on the scripted server, then seen on
the iPad before the branch was merged (below).

**What he sees now.** At launch, the Inbox as the last listing of it left
it, previews, dots and flags, and the folders with the counts the last
sweep gave them, in the first frame, before anything has been sent. The
line under the list says "Checking for Mail…". A second or two later the
fresh page takes the kept one's place and the line says "Updated Just
Now"; only the new letters' previews are fetched. Where it goes, by the
rules the watch's letters follow (B-049) and B-042's:

- At the top: in place, the list staying at the top.
- Scrolled down the kept rows: the rows he can see stay where they are on
  screen, found again by their letters, and the letter open in the pane
  keeps its highlight.
- A search showing, or typed and not yet run: left alone, field, hits and
  all. The folder's letters under it are the fresh page when it ends, where
  he was in them.
- A finger on the list: nothing until it lifts. A finger lifted from a tap,
  which tells the list nothing, is looked for four times a second.
- Rows ticked in Edit mode: nothing until Done, or the last tick taken off,
  as the watch's letters wait. Rows moved under his ticks would be a Delete
  of letters he did not choose.

A letter he opens, flags or marks in the second before the fresh page
comes keeps what he did when it lands: the page was asked for before his
STORE and says unread or unflagged, and it used to put the dot back on the
letter he had just read, until the next Refresh. His mark stays over any
listing asked before the server took it, a Refresh's included, and one
asked after has the say (`ListLetters.reading`, `holdingHisMarks`).

Until the fresh page has landed the list does not page below the kept
rows, and the watch checks only the Inbox's count. Every folder he has
opened before draws its kept page the same way the moment he opens it,
with a connection or without. A folder never opened is empty, as before.
One listing over the kept page at a time: the folder's own as it opens,
and the watch's only once that has failed (`OverKept`); a folder opened
while a check was out used to send its SEARCH and page twice. A folder
tapped in the kept folder pane before the launch's LIST has landed waits
for it, so its rows are counted in All Mail and Important as Gmail counts
them, and kept so; they used to be drawn and kept without, and reading one
left those counts high.

With no connection the kept pages stay, and once the first page has failed
the line says how old they are, "Updated Yesterday" or "Updated at 10:42",
with "No Connection" under it, and the one alert comes as before, kept by
D-016 as the strongest cue that the list is old. A letter he taps shows
its header and then the failure, as before; Search, Go to Date, Delete,
Move and Flag fail and put things back, as before. The watch's first check
to reach the server once the connection is back fetches the page afresh,
as does a Refresh, and a letter that came meanwhile is on it. The first
launch, and the first after a password is saved, are as before.

**What is kept, and when.** `MailShelf`, in
`Application Support/Kept/<hash of the address and the IMAP server>/`: a
`folders.json`, and a `page-<hash of the folder name>.json` per folder, each
saying its format, out of iCloud backup. The folder list from every sweep
of the counts (not from the names-only LIST, whose counts are zeros). A
folder's newest page from every listing from the top: opening it, Refresh,
the reload after a Delete or Move in Edit mode or a draft, the return after
a while away. Replaced whole, and the previews added as they come, for the
rows on it. Not kept: the pages below it, a day jumped to, a search's hits,
the letters the watch puts on (the next listing has them), the letters
themselves (phase 2), and the Outbox and the letters `LocalDrafts` keeps,
which are in `Local Drafts/` beside it and which nothing here touches.
Between listings, only his writes, once the server has answered OK: a read
mark or a flag on the letter wherever it is kept, by its Gmail message id,
since Gmail's flags belong to the letter; a move off its folder's page, and
off none when it leaves All Mail for a label; a delete, or a move to Trash
or Spam, off every kept page but that one; a draft removed off Drafts'.
The folder counts move as the folder pane's own do for his read and unread
marks and an unread letter binned (`MailShelf.counted`), so a launch draws
the counts he last saw. A write the server refuses changes nothing. Written behind, on a queue of its
own, a moment after each change, and at once as the app goes into the
background (`AppDelegate.applicationDidEnterBackground`). A launch reads the
folder list and the page of the folder it opens, nothing more.

**Never the wrong mailbox.** Every Gmail Inbox reports UIDVALIDITY 1, and
the app-password trap (B-033) can open another mailbox under his address,
so a folder, a UIDVALIDITY and a UID do not say whose a kept row is.

- The copy is the account's: its directory is named for the address and
  the server, and every other one under `Kept/` is removed at launch.
- A password saved, in setup or Settings, or the account cleared
  (`CredentialStore.save`, `clear`): the whole of `Kept/` goes, and the
  shelf running keeps nothing more until the next launch, or, since
  B-056, until the screens are built again over the new password.
- A listing from the top whose folder has another UIDVALIDITY than its kept
  page, or a row whose X-GM-MSGID is not the kept row's under the same UID:
  the whole copy goes, every page and the folder list, before the fresh
  page is kept, and no kept preview goes across to it, on the shelf or on
  the list. The connection log says `KEPT-DISCARDED folder=INBOX
  reason=uidvalidity` or `reason=msgid`.
- Every write on a row, and every letter opened from one, names the row's
  Gmail message id, from the list, Edit mode, the reading pane, a
  conversation, Drafts' composer and a search's hits alike, and the
  repository holds it against what the server has named under that UID in
  this launch (`IMAPMailRepository.seen`): in every row it has sent, from a
  listing from the top, a page below, a day jumped to, a search, the
  watch's news or All Mail's copy of a letter, and in every answer to the
  question below; a folder's is forgotten when its UIDVALIDITY changes.
  The same letter there, and the write or the letter's FETCH goes as it
  always did, byte for byte. Another letter there, and neither the write
  nor the question is sent (what goes ahead of any write still goes: the
  NOOP after a quiet spell, B-024, and the LOGIN or LIST a connection or
  unknown folder roles need): the row leaves the kept page and the list,
  nothing is shown, and the log says `KEPT-UNVOUCHED folder=INBOX
  nothing-sent`, or `nothing-shown` for a letter opened. Nothing named
  there yet, and the question is asked, for the row's id.
- The question, for a write: one `UID FETCH <uid> (UID X-GM-MSGID)` first,
  in the same hold as its SELECT and UIDVALIDITY check (B-039). The same id
  and the write goes, and that UID is not asked about again; another, or
  none, and nothing is written, the row leaves the kept page and the list,
  and the log says `KEPT-UNVOUCHED folder=INBOX nothing-sent`; the next
  write naming the same letter under that UID is refused at once, the server
  having named another letter there, or asked again if it named none. From
  the reading pane the row comes off rather than back, and the pane says
  "Can't connect to mail server." as for any write that did not go; the read
  mark of a tap empties the pane. In practice it is asked of a kept row the
  server has named nothing under yet, once a row, at one round trip. One
  tapped before its own folder's first page has come: in the Inbox in the
  first second of a launch, and in a folder opened before in the first
  second after he opens it, however long the Inbox has been listed. And, in
  the copy's own mailbox, one the fresh page lacks, the oldest kept rows
  pushed off it by mail come since, acted on after that page has landed: in
  Edit mode while the swap waits for his ticks, in the quarter second while
  the list looks for a lifted finger, or from a conversation opened from the
  kept page at launch whose earlier letter he flags or reads after the
  listing. Until 2026-09-30 it stopped as soon as a listing from the top had
  found kept rows under the same UIDs with the same ids, or the row's own
  folder had been listed, so a kept row the fresh page lacked went unasked;
  that rule now covers only a call that names no letter: a draft removed
  that was found by its Message-ID, or whose draft names no letter (a draft
  removed names the letter its draft names since 2026-09-30, B-051), a
  letter kept in Local Drafts that has gone up, opened in the composer from
  its row (`openDraft`, which names its copy in Drafts by folder and UID
  alone, and asks its id in the same FETCH), and a row from a server
  without Gmail's extension, whose UIDVALIDITY is taken at its word, as it
  always was.
- The question, for a letter opened, in the reading pane, a conversation or
  Drafts' composer: asked by the FETCH that brings it and at no round trip
  more: `UID FETCH <uid> (UID X-GM-MSGID BODY.PEEK[])` in place of `(UID
  BODY.PEEK[])`, still PEEK, so the FETCH marks nothing read. The id is
  compared before anything of the letter is shown or kept for a Forward. The
  same id and it opens, and the row is vouched for; another, or none, and
  nothing of it is shown, no STORE goes for it, the pane empties, the row
  leaves the kept page and the list, and the log says `KEPT-UNVOUCHED
  folder=INBOX nothing-shown`. A row the server has disowned stays disowned
  for the launch, whichever of the tap's read mark and its FETCH is answered
  first: the other is refused too, and nothing goes unasked because the row
  has left the kept page. A letter the server has named under its UID in
  this launch is fetched as it always was, byte for byte. A copy of Gmail
  kept and a server now without the extension: nothing is asked and nothing
  opened or written on a kept row, as for a write.
- A kept row still drawn after the copy is thrown away. The listing that
  throws the copy away does not take the kept rows off the screen: its page
  waits for a finger to lift or for his ticks to go (`KeptSwap`,
  `OverKept`), and reaches the list a moment after it has landed in any
  case. The folder counted as listed from then, so a tap, the pane's Flag,
  Move or Delete, or Edit mode's Mark, Move or Delete on one of those rows
  went unasked onto whatever letter this mailbox has under that UID, and a
  letter opened then was fetched as the kept row's. Found by reading the
  code, not on the iPad. Now the fresh page has named the letter under each
  of its UIDs: a kept row under one of them, carrying another letter's id,
  is refused at once with nothing sent, and one under a UID the page does
  not have is asked about and refused. The row comes off the list while it
  still carries the kept id, and the fresh page, when it goes on, shows the
  server's letter under that id. The reading pane can still hold the kept
  letter after the swap: its Flag, Move or Delete is refused the same way,
  and the list's row under that id, the server's letter, is neither
  flagged, taken off nor put back for it; a letter of a conversation opened
  there sends its read mark by its own id and leaves the list's row alone.
- Whatever lands while the question is out. The launch's listing can come
  first and throw the copy away; the row under that id is then the
  server's own letter, and a "not the kept letter" answered after it
  leaves that letter on the kept page and on the list. What is taken off
  is only a row still carrying the kept row's message id.
- The question is asked on a connection shown to be up, holding the gate:
  a torn-down connection is a read to go again on a new one, never
  "another letter".
- A file of another format, cut off, or not JSON reads as nothing kept, is
  deleted, and never stops a launch.

**What it sends.** At launch, what it always did: LOGIN, the one LIST, the
Inbox's SELECT, SEARCH and page, then the counts. Drawing the kept pages
sends nothing and begins no connection. The additions are the vouching
FETCH above, only for a write on a row whose UID the server has named
nothing under yet in this launch, and X-GM-MSGID in the FETCH of a letter
opened from such a row, at no round trip more: a kept row before its
folder's first page, and a kept row the fresh page lacks, pushed off it by
new mail, acted on while the swap is held for his ticks or a finger, or
from a conversation opened from the kept page at launch. One round trip for
each write, once a row, and none more for a letter opened; the Inbox's
listing used to let the second kind go unasked. A write, or a letter opened,
on a row any listing, page, day, search or check of this launch has brought
sends what it always did. A folder listed before the LIST sends the LIST
first; at launch the Inbox has asked for it already.

**What it costs.** A launch's read of the folder list and a fifty-row page
of 27 KB, a fresh shelf included, took a median 1.1 ms on the development
computer in the debug build (PERFORMANCE.md), on the main thread, far under
the 30 ms at which D-016 would move it off. On disk about 27 KB a page and
2 KB for the folders. Nothing kept is written to the connection log: the
two notes above name the folder and the reason, and drawing the kept pages
writes nothing. The files are out of iCloud backup, and on an iPad with no
passcode (D-011) they are not encrypted at rest.

**What it does not cover.** The counts kept are the last sweep's, moved by
his own marks since: offline they can be off by the letters that came, or
were read on the phone, after it. A letter read or flagged on the
phone keeps its old look on the kept pages until its folder is listed
again, and a letter moved into a folder is not on the folder's kept page
until then. The swap, the first frame, the folder pane drawn from the copy,
the pane emptied for a disowned row and the write as the app goes into the
background are UIKit and not on the host; the pieces under them are tested
(`ListOpening.kept`, `ListLetters`, `KeptSwap`, `OverKept`,
`PaneActions.notTheKeptLetter`, `UpdatedLine`, `MailShelf.flush`).

**Tested** in `KeptCopyTests`, over the shipping repository and client, the
scripted server and a shelf in a directory of the test's own: a launch
draws the kept Inbox with its previews before any command or connection,
and the first page replaces it with the letter that came overnight on top
and only its preview to fetch; a launch with no connection keeps the Inbox
and Sent pages and the counted folders, draws nothing for a folder never
opened, and says "Updated Yesterday" over "No Connection"; only a listing
from the top keeps a page, and the next replaces it whole, a letter come and
a letter gone; a read mark, a flag, a move and a delete each change the
kept pages as Gmail changes the letter, and refused, nothing; so do a
delete in Trash, a draft removed, a move to Spam and a move out of All Mail,
after a relaunch too; a renumbered Inbox and another mailbox under the same
numbers each throw the copy away and carry no preview, and the same mailbox
keeps it; an early write is vouched for once, a second row in turn,
nothing after the Inbox's listing in the Inbox, and a kept All Mail row
once, its folder not yet listed; with nothing kept, a listing proves its
own rows and a write sends the write alone; a mismatch writes nothing
from the pane, a read mark or a delete, and the rows go until the next
listing, which puts the server's letter back under that id; the Trash's
Delete and a draft removed on a kept row that is another letter destroy
nothing, and a landed draft refused on reopening is asked about again
when removed, its copy not expunged; the vouching FETCH goes again on a
new connection, and Gmail's id is not read off a torn-down one; a vouch
that loses the race to the first page leaves the server's letter on the
kept page and the list; a letter opened from a kept row is vouched for
by its own FETCH, PEEK, and not asked about again; one from a proven
row, or with nothing kept, is fetched byte for byte as before; a
mismatched one shows nothing and writes nothing, whichever of the read
mark and the FETCH is asked first, the second refused with nothing sent;
a server without the extension neither opens nor writes a kept row; with
the copy thrown away by another mailbox under the same numbers and the
kept rows still shown under his ticks, Edit mode's Mark and Delete, the
pane's Flag and a letter opened write and show nothing, only the row the
fresh page lacks asked about, and the fresh page then shows the server's
letters; a write naming a kept row's letter under a UID the fresh page
has as another letter sends nothing at all, a Mark, a Flag, a Move and a
Delete; one under a UID it lacks is asked once and writes nothing; the
same two for a letter opened, in the pane and in Drafts' composer; a tap
right after the listing has thrown the copy away, before the swap, is
refused, and the pane's Flag on a kept letter after the swap leaves the
server's row as it is; in the copy's own mailbox, a kept row pushed off
the fresh page by new mail is asked about once, before Edit mode's Mark
and the pane's Flag under his ticks, in its own FETCH when opened, and
before the Flag from a conversation opened at launch after the swap, and
a kept row the page has sends the STORE alone; writes and letters
opened on rows from the first page, a conversation, a page below, a day, a
search, the watch, All Mail's copy of an Inbox row, the Trash and Drafts
send exactly what they did (the same test passes on master, 5bacbda, its
calls naming nothing); a write naming no letter, and a server without the
extension, go as they did; a renumbered folder forgets what its old
numbers named; a folder listed before the LIST is counted as Gmail counts
it, and kept so; a launch with a copy sends the commands a launch without one
sends; nothing kept reaches the log. In `MailShelfTests`: a file of another
format, one cut off and one not JSON are nothing kept and deleted; a saved
password wipes `Kept/`, leaves the letters in `Local Drafts/`, and ends the
running shelf; another account's copy goes as the shelf is made; the
launch's read, timed and printed. In `KeptPlaceTests`: the swap under a
finger, under ticks, scrolled, at the top and under a search; the page held
for a finger or ticks and put on when they go, and dropped when he has
replaced the kept rows; one fetch over the kept page at a time, the
folder's own first; a day jumped to no longer the kept page; his read mark
and flag staying over a page asked before the server took them, going back
when refused, and never onto another letter under the same id; a preview
going across from a row with no message id, as a landed draft's; a
disowned row taken off only while it is still the kept one; the watch
leaving the kept rows alone; a kept preview going only to the same letter.
In `FeedbackTests`: the line over the kept page. The suites that pin the
repository's command sequences build it with a shelf, as the app always
has one (`KeptShelves`): `RepositoryWireTests`, `RepositoryTrafficTests`,
`ComingBackTests`, `NewMailTests`, `ArrivingMailTests`,
`MailboxAtomicityTests`, the pane's, the drafts', the Outbox's and the
rest. Where they have a row at hand its writes and its letter opened name
the row's Gmail message id, as the app's do (`NamingTheLetter`); only a
draft reopened by the id its upload gave it, a letter taken by its UID with
no row, a draft removed by its id alone, and the one test of a write naming
no letter on Gmail's rows name none (`NamingNoLetter`). A row listed from a
server without the extension has no id to name. Each of these fails with
its part undone in a scratch copy, one sabotage at a time, each failing
the test named for it. Thirty in the first build: no page kept, every page
kept, the read mark not kept, the flag kept before the server's OK, a binned
letter left on other pages, a flag not kept on the same letter elsewhere, no
discard for a new UIDVALIDITY or for another message id, the previews not
carried to the kept page, the list carrying them whatever the message id, no
vouching, a mismatch written anyway, vouching after the mailbox is proven or
twice for one row, the pane putting a mismatched row back, a wipe that
removes nothing or leaves the running shelf keeping, another format read, a
bad file left on disk, another account's copy kept, the folder list not
kept, the previews not kept, a kept page drawn for a jump and the Outbox,
the line saying the age while it checks, the watch checking the kept rows, a
swap to the top when scrolled or under a finger, a swap that clears the
search, a listing that vouches the kept page at launch, and a kept subject
in the discard note. Thirty-one since: a letter opened unvouched, a proven
row's letter fetched with the id, a disowned row forgotten, the opening
FETCH without PEEK, a kept row dropped whatever has landed, the list's row
taken whatever it now is, the extension read outside the hold, a server
without it asked anyway, his marks not held over a listing, put onto another
letter, and a refused read mark or flag put back onto another letter, a row
with no message id refusing a preview, a second fetch over the kept page
while one is out, the watch's before the folder's own, a fetch while a page
waits, a held page put on under a finger or ticks, or over rows he has
replaced, a folder listed before the LIST, ticks ignored, the Trash's Delete
and a draft removed unvouched, a listing that does not prove its own rows
(which fails twenty-nine tests across the wire suites as well as its own), a
delete in Trash or a draft removed left on its page, a move to Spam left on
All Mail's, a move out of All Mail taken off it, a disowned row left hidden
after the next listing, a day jumped to still the kept page, the vouch not
retried, and the flag not held. One after the iPad: the kept counts left at
the last sweep's (`MailShelfTests`). Thirteen for every write and every open
naming its letter: the row's id ignored; another letter under the UID asked
about rather than refused; a UID named nothing yet taken as vouched once its
folder has been listed; the server's answer not remembered; only a matching
answer remembered; the pane editing the list's row whatever letter it is; no
row remembered, which fails eleven of the pane's tests too, their pinned
wire gaining a FETCH; only a listing from the top remembered, which fails
the page below, the day, the search hit, the watch's letter and All Mail's
copy; a write naming no letter never asked, or asked whenever its UID is
unnamed; a new UIDVALIDITY keeping the old letters; the proven mailbox still
trusted for a named letter; and the pane naming no letter. Three of them run
again once the suites named their rows: the proven mailbox trusted for a
named letter the server has named nothing under fails the test of kept rows
pushed off the fresh page at each of its four questions, and five others; no
row remembered fails thirty of the pane's and the wire suites' tests where
it failed eleven, their pinned wire gaining a FETCH; and another letter
under the UID asked about rather than refused fails the letter opened from a
kept row that is another letter, which pins the two FETCHes the app sends
where it pinned four. And a disowned row forgotten, which no test caught
once a tap's read mark and FETCH named their letter, fails a landed draft
refused on reopening and then removed, its copy's EXPUNGE sent unasked onto
the other draft.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, before the branch
was merged; force-quit is the app sent to the background, then ended:

- Wi-Fi on, force-quit, open it: the first frame caught, under a second
  in, had the Inbox as it was left, previews and dots, the folders with
  their counts, and "Checking for Mail…"; the next, "Updated Just Now"
  over the same rows. The log is LOGIN, LIST, `SELECT "INBOX"`, `UID
  SEARCH ALL`, the page's `UID FETCH`, then the counts, as before, the page
  in 0.55 s from Gmail's greeting, so the kept rows stand alone for about a
  second of a launch on Wi-Fi.
- An unread letter tapped at once, before the launch's page had been taken:
  `UID FETCH 21 (UID X-GM-MSGID)` before its `UID STORE`, and the letter's
  own FETCH as `UID FETCH 21 (UID X-GM-MSGID BODY.PEEK[])`, which Gmail
  answers with the id ahead of the body; the ids matched, the letter
  opened, no `KEPT-` line, and its dot stayed off when the fresh page
  landed. Tapped a moment later, after the page, its FETCH is the plain
  `(UID BODY.PEEK[])`.
- The kept Inbox count was the last sweep's: a letter marked unread was
  counted in the pane and not on the copy, so the next launch drew 1 for 2,
  and reading that letter at once left the Inbox with no count until the
  sweep. The copy's counts now follow the pane's (above).
- Wi-Fi off in Control Center, a letter sent to the account itself just
  before, force-quit, open it: the kept Inbox, dots and all, "Updated 6
  minutes ago" over "No Connection", and one "Can't connect to mail
  server."; Sent Mail, opened before, its kept page with "Updated 12
  minutes ago", Spam, never opened, empty with "No Connection". Each folder
  opened offline brings the alert again, as it did before the copy. Wi-Fi
  on, Refresh: the fresh page, the letter sent before the cut on top of it,
  "Updated Just Now", and every count Gmail's.

Not tried yet, and in the TODO: the swap under a finger, scrolled or under
ticks, the page lands too soon on Wi-Fi to be caught by hand; a flag in the
first second; a letter tapped with no connection; the password saved again.

**Every write and every open naming its letter, built 2026-09-30, seen on
the iPad the same day**, on carlo's mailbox, before the branch was merged:

- After "Updated Just Now", a letter opened, flagged and unflagged from the
  pane, Edit mode's Mark as Unread and Mark as Read, and a letter opened in
  Sent Mail each sent what they always did: `UID FETCH 21 (UID
  BODY.PEEK[])`, the `UID STORE`s alone, no `(UID X-GM-MSGID)` FETCH and no
  `KEPT-` line.
- Another mailbox's copy, made by hand: with the app ended, two rows of the
  kept Inbox page were given Gmail message ids of no letter there, UIDs 23
  and 20, as the same UIDs would carry in another mailbox. Wi-Fi off, open
  it, the kept rows; Edit, a tick on row 23; Wi-Fi on. The listing that
  followed at once said `KEPT-DISCARDED folder=INBOX reason=msgid`, and the
  tick held the kept rows on screen. Mark as Unread then: `KEPT-UNVOUCHED
  folder=INBOX nothing-sent`, no command at all for it, and the letter
  under UID 23 still read on Gmail when the fresh page came on.

Not caught by hand: a letter opened from such a row, which the listing at
reconnect beats, and Edit mode ticks rather than opens.

---

## B-056 — CHANGED 2026-09-30, not yet seen on the iPad. A new password waited for a relaunch, a refused sign-in read as "Can't connect", and the signature could be lost for good

**Found in the code 2026-09-30**, going through what would stop the app for
good once it is on his iPad with no way to update it. Google revokes every
app password when the Google password changes, which over years is the
likeliest thing to happen to this account, and the repair was the one
place the app failed a helper:

- **A new password saved in Settings was not used until the app was
  ended.** `IMAPMailRepository` kept the password it was made with, and
  Settings only asked for a Refresh, which ran on it (its own comment said
  "Settings reaches it at the next launch"). The helper typed the new
  password, Settings said nothing was wrong and closed, and the list went
  on saying "Password Needs Updating", the Outbox stayed stopped, and every
  tap sent the revoked password again. iPadOS keeps an app suspended for
  days, so the fix could look like it had failed until someone knew to
  swipe the app away.
- **Settings and setup checked reading only.** The setup form's comment
  said "Prove both halves before saving", and only IMAP was asked. An app
  password made while signed in to another Google account passes IMAP,
  which opens that account's mailbox, and fails every letter (B-033).
  Settings had no line saying where a new password is made.
- **Every refusal but one read as the network.** Only `NO
  [AUTHENTICATIONFAILED]` to LOGIN counted as the password; every other NO
  or BAD, Gmail's "[ALERT] Application-specific password required", "[WEBALERT
  …] Web login required", "[ALERT] Too many simultaneous connections",
  became "Can't connect to mail server." and "No Connection", which no change
  of Wi-Fi or password mends. Google's ALERT text, which RFC 3501 §7.1 says
  MUST be shown, went nowhere but the connection log. The list's, the
  pane's and the folder pane's alerts said "Can't connect" whatever they had
  caught, a refused password included. After any refusal the watch never
  signed in again by itself. And SMTP's 534, "Please log in via your web
  browser", was taken for the password, which sends a helper off to make
  app password after app password while Google waits for a sign-in on the
  web.
- **The signature could be lost with no way back.** The formatted signature
  reaches the iPad only from outside the app (B-035), and three things took
  it away for good: "Send my signature as plain text instead", one tap with
  no question, then Save; an emptied box saved; and setup shown again,
  whose Connect built a new account and saved it over the stored one. Setup
  is shown whenever the password cannot be read at launch, and the password
  item was written by deleting every item for the account first and then
  adding the new one, so a failed add, on a full disk, left no password,
  while Settings said "Could not save. Nothing has been changed."

**What he sees now.**

- A new password saved in Settings is signed in with at once. The sheet
  closes, the screens are built again over a new repository, as setup's are
  once it has an account, and the list says "Checking for Mail…" and then
  "Updated Just Now". The copy kept on the iPad goes as it did at any
  password saved (D-016), so the Inbox is empty for a moment; the letters
  kept in Drafts ("On this iPad only") and the Outbox stay, and the Outbox
  goes at the first pass after the new page. The old repository's
  connection is closed, and nothing still holding it signs in again or
  sends a letter (`IMAPMailRepository.retire`).
- Settings and setup check sending too. With IMAP's LOGIN, LIST and LOGOUT
  done, a sign-in on the submission server, EHLO, AUTH and QUIT, and no
  letter. A password IMAP takes and SMTP refuses is not kept: "Gmail took
  that password for reading mail but refused it for sending. Make the app
  password while signed in to Google as <his address>." A submission server
  that cannot be reached, or says "not now", does not stop a password IMAP
  has just taken: a Wi-Fi that blocks port 465 must not leave a revoked
  password in place. Under the Settings password field: "Make one at
  myaccount.google.com/apppasswords while signed in to Google as <his
  address>." A setup Connect whose save fails now says "Password could not
  be saved." rather than "Could not reach Gmail".
- A refused password, in any alert about getting his mail or acting on it
  (a folder, a letter, a Refresh, Go to Date, the pane's Flag, Move and
  Delete, a draft reopened): Mail's "Cannot Get Mail", "The user name or
  password for “Gmail” is incorrect.", with Settings and OK. Settings opens
  over the list with the keyboard up in the password field.
- A sign-in refused for any other reason is a third state beside the
  password and the connection. The line under the list says "Gmail Refused
  Sign-In"; the alert says "Cannot Get Mail" over "Gmail refused the
  sign-in. The server returned the error: <Google's ALERT text>", or
  "Gmail refused the sign-in." where there was none; setup and Settings say
  the same under their button. WEBALERT's address, a sign-in link into his
  account, is left out; the log keeps the whole line. The watch signs in
  again five minutes after such a refusal, and every five minutes while it
  lasts, twelve LOGINs an hour against the hundred and twenty a check every
  half minute would send; a refused password is still never tried again
  unasked. SMTP's 534 is this state too, and keeps every rule it had as the
  password's: his own Send keeps the sheet, and the Outbox stops until a
  Send of his goes, the app is launched again, or a password is saved.
  IMAP's refusal does not take those rules, met as a forward's files are
  fetched or as Sent Mail is asked: the letter waits in the Outbox, as it
  did while such a refusal read as no connection, and goes with the first
  pass once Gmail lets go.
- "Send my signature as plain text instead" asks first: "Send Signature as
  Plain Text?", "Your messages will no longer carry the formatted version of
  your signature.", Cancel and Use Plain Text. Saving an emptied signature
  asks: "Remove Signature?", "Nothing will be added to the bottom of your
  messages.", Cancel and Remove.
- The signature first set on this iPad, its text, its formatted twin and
  the pictures the twin shows, is kept once in `Application
  Support/Original Signature/signature.json` and never written again
  (`OriginalSignature`): by the first launch that finds a signature, or the
  first save of one. "Restore Original Signature" under the signature box,
  only where one has been kept, asks "Restore Original Signature?", "The
  signature first set up on this iPad will replace the one shown here.",
  Cancel and Restore, and puts it in the form, to be saved with Save. The
  share extension is handed the restored pictures as they are saved, as it
  is the account.
- Setup's Connect starts from the stored account when the address is the
  same, trimmed and without case, and changes only the name.
- The password item is written in place first, updated where there is one
  and added where there is none, and every sibling under the account and
  server goes only once that has worked (`PasswordWrite`). A write that
  fails leaves the old password working.

**Mail's words, and the app's.** "Cannot Get Mail" and "The user name or
password for “Gmail” is incorrect." are iOS Mail's, as its users quote them
(Apple's forums, threads 5452189 and 4202286; Google's Gmail community,
thread 167880147), and one user quotes tapping OK on it (Microsoft's Q&A,
question 4475893). "The server returned the error:" is Mail's on the Mac
for this very refusal ("… Web login required", as Mac users quote it). The
app's own: "Gmail Refused Sign-In" (Mail says "Account Error", which would
tell him nothing, as for the other two), "Gmail refused the sign-in.", the
sending sentence, the Settings line, and the three confirmations. Not found
in anything quoted: whether Mail's alert has a Settings button, and where;
this one has it first, then OK.

**On the wire.** Nothing changes until a sign-in is refused or a password is
saved; the everyday wire is as it was. The connection log gains
`SIGN-IN CHECK host=smtp.gmail.com:465` and `SIGN-IN CHECK imap=ok
smtp=refused`, `smtp=sign-in-refused` or `smtp=not-checked`, and
`PASSWORD-SAVED signed in afresh`: no address, no password, nothing of a
letter.

**Left as it was.** The composer's own alert for a Send refused for its
password still says "Password needs to be updated in Settings.": Mail's
"Cannot Get Mail" is for getting mail. A letter kept on the iPad between the
save and the new screens is stamped with the old count and treated as the
old mailbox's, as one kept before a relaunch was (B-051). The original
signature is the first one seen: a signature typed in Settings before the
formatted one is put on the iPad would be the original, so the formatted one
goes on first.

**Tests.** `SignInTests` (the check against the scripted servers, the
wrong-account trap, each form's words, the alerts' words and the third
line, a pane write's refusal, a new password signed in with at once with the
Outbox going and the old repository silent, a repository retired with a
command still out, letters kept before the save, setup keeping the
signature, the original kept once and restored, the emptied signature asked
about, and the password item's order); `IMAPConnectTests` (the refusals and
their ALERT text, and a retired client); `NewMailTests` (the watch trying
again after five minutes, never sooner, a refused password never, past
the five minutes too, and a refused sign-in never retried by a read);
`OutboxTests` (534 keeps the sheet and stops the Outbox; IMAP's
`[UNAVAILABLE]` to his Send's forward, and to a pass's look in Sent Mail,
leaves the letter waiting and the Outbox going); `ShareMirrorTests` (the
restored signature's pictures handed to the share extension as they are
saved); `RepositoryTrafficTests` (Go to Date's alert says what was
caught). Each fails with its part of the change undone.

Not seen on the iPad: the TODO has the checks.
