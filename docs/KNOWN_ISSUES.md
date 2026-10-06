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

**Settled 2026-10-06 (B-074): oldest first, as Mail's factory settings
have it.** The setting is off unless he turns it on. The stack now runs
from the oldest at the top to the newest at the bottom. It opens at the
oldest letter he has not read, or at the newest when he has read the rest.
The unread letters open with it, and are marked read at the tap.

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
the composer does (since 2026-10-05 a JPEG that fits goes as its own bytes
and a GIF or PNG whole: "2026-10-05: as Apple Mail does", below). The HTML
twin is Mail's envelope with the address as a real `<a href>`: his own
shared letters, read in Mail's output, carry the address as bare text in a
`<div>`, which this app's reading pane cannot tap. It sends through
`Submission` (called `Outbox` until B-052 gave the app an Outbox of its
own), which `IMAPMailRepository.send` now sends through as well, with
`ComposeActions` deciding the order exactly as in the app's composer: "Sending…" at the tap, one letter however many taps, the
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
  it is over 25 MB), then send. The letter was built whole in memory at
  Send then, as in the app; since B-070 it is made from the staged files
  as it goes, and never held whole.
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

**A large photo made the sheet vanish. Changed 2026-10-04; the change not
yet seen on the iPad.** A shared photo was loaded as a `UIImage` and made a
JPEG with `jpegData`, which decodes every pixel of it inside the extension:
49 MB for a 12-megapixel photo, 195 MB for 48 megapixels, more for a
panorama. iOS kills a share extension at about 120 MB, and the sheet simply
vanishes, with nothing said. One such photo was enough.

Now a picture is read from its file (`loadFileRepresentation`), as the type
the sharing app offers it in first, so Photos' original HEIC rather than a
copy made for sharing (`SharedPhoto.fileType`; since 2026-10-05 a JPEG
whenever one is offered, and a JPEG that fits goes as its own bytes, not
made again: "2026-10-05: as Apple Mail does", below). ImageIO makes the JPEG from
it as a thumbnail: at most 4096 px on its longest side, never made larger,
turned upright by its EXIF orientation, decoded there and then, quality
0.85 as the composer's (`SharedPhoto.jpeg`). It is made inside the callback
the file lasts for, in its own autorelease pool, staged on the disk, and
only then is the next begun (`oneAtATime`). A file ImageIO cannot open, or
none given, is tried as its bytes (`loadDataRepresentation`), the same way;
never as a `UIImage`. A photo from his iPad's camera, 4032 px, keeps its
size; since 2026-10-05 only where the memory left allows it, and at a half
where it does not (below). 4096 px is 16 megapixels at 4:3, more than any
screen it will be read on.

**The size asked for is one the decoder reaches by halving.** A thumbnail
lets the decoder read a JPEG, a HEIC, a TIFF or a PNG whole, or at a half, a
quarter or an eighth (CGImageSource.h, `kCGImageSourceSubsampleFactor`),
and at nothing in between. Which of those a thumbnail's size picks the
header does not say: the smallest still no smaller than what is asked is
inferred, and the sheet vanishing at 4096 fits it whether a size exactly
at a half counts or not. So it is asked for the longest side divided by the smallest
of 1, 2, 4 and 8 that brings it to 4096 or less, in whole pixels rounded
down (`SharedPhoto.size`). Rounded down, so that however a decoder rounds
an odd side's half, it is never short of what is asked, which would have
it read at the next factor down, twice the size each way. 8064 goes at
4032, 5712 at 2856, a 16000 px panorama at 4000, and 4032 stays. The
factor is passed as well, where it is more than 1: the header documents
it, and not how the size picks one, so both are given and neither is
relied on alone.
What it costs: a picture a little over 4096 px goes at half its size, 4097
at 2048. Past an eighth, over 32768 px, it is asked for 4096: the decoder
reads the eighth, larger, and a second picture of 4096 is made from it.

The picture decoded, at four bytes a pixel:

| Photo | Read at | Decoded | Goes at |
|---|---|---|---|
| His iPad's camera, 4032 by 3024 | whole | 49 MB | 4032 by 3024 |
| 24 megapixels, 5712 by 4284 | a half | 24 MB | 2856 by 2142 |
| 48 megapixels, 8064 by 6048 | a half | 49 MB, where it was 195 | 4032 by 3024 |
| A panorama, 16000 by 4000 | a quarter | 16 MB | 4000 by 1000 |
| A square, 8192 by 8192 | a half | 67 MB | 4096 by 4096 |
| A panorama, 40000 by 10000 | an eighth | 25 MB, and 17 MB made from it | 4096 by 1024 |

Of a JPEG or a HEIC up to 32775 px, the decoder holds no more than 4097 px
on the longest side, so 67 MB is the most, for a square. That is the
decoded picture only. What ImageIO holds besides, to turn it upright and
to encode it, is not known here; only the iPad can say (check 3 in the
TODO). A WebP, a GIF, a BMP or
an AVIF is not read at a factor: it is decoded whole whatever is asked,
195 MB for one of 48 megapixels, and the sheet would go; since 2026-10-05
it is left out and said instead (below). Photos keeps his pictures as HEIC
and JPEG; those others come from the web.

**Seen on the iPad, 2026-10-04, before the fix.** The first build of this
change asked for 4096 px of every larger photo. Installed through
TrollStore's helper on the test iPad, it was given a 48-megapixel JPEG from
Photos: 8064 by 6048 as stored, EXIF orientation 8, a GPS tag. The
BlackmailShare process started and was gone within half a second. The sheet
never appeared, and there was no crash report. A Wikipedia page shared from
Safari opened the sheet as before. Asked for 4096 of 8064, whose half is
4032, the decoder read the whole: 195 MB. Hence the size above. A deploy
that copies files into the bundle leaves the share extension unable to
start at all, so every check of it is on a build installed through
TrollStore's helper, as on 2026-09-30.

**Seen on the iPad, 2026-10-04, after the fix**, on a build installed
through the helper, on carlo's mailbox, every letter to the account
itself. The same 48-megapixel JPEG, which Photos said had its location
included: the sheet came up and stayed, "Photo.jpg — 437 KB", and the
letter brought a JPEG of 3024 by 4032, upright in its pixels with no
orientation tag, with no GPS at all and the date it was taken. Five
camera photos at once, each with its location: the sheet listed
five, said nothing of one left out, showed "Sending… 65%" and closed; all
five arrived, the one read 4032 by 3024 as taken, no GPS, the date, its
zone and the Display P3 profile kept. A 64-megapixel panorama, 16000 by
4000: the sheet stayed, and it arrived at 4000 by 1000. A video's link
from the YouTube app: the link in the body, blue in the letter that
arrived, and no subject, the app handing over the link alone and no
title, as Safari gives. After them the app read the Inbox and sent from
its own composer. No 24-megapixel photo or HEIC of 48 was at hand. The
test iPad gives a share extension 180 MB; nothing here says how near
these came to it. Each photo went as "Photo.jpg": Photos gives an
extension no suggested name. Since 2026-10-05 it goes under its file's
name, as Mail sends it (below).

What goes with a JPEG made here: the picture, its colour profile, and the moment it
was taken with its offset from UTC, so a recipient's Photos files it under
that day. Nothing else. The colour profile rides with the picture itself, so
Display P3 stays Display P3 at no cost. The location does not go, neither
the GPS nor a place's name. Mail sends it unless Location is switched off
under Options at the top of the share sheet. He would not know it was there,
and in a photo taken at home it is his address, to whoever the letter is
forwarded to. Nor the orientation: it is in the pixels now, and a tag left
saying to turn the picture would turn it again. Nor the camera, the lens,
the exposure, or Apple's own notes. It is a list of what may go, not of
what may not (`SharedPhoto.kept`), so whatever else a photo carries stays
behind. The JPEG is written with those properties and the quality alone,
never with `CGImageDestinationAddImageFromSource`, which would copy the
file's metadata across. `…CopyImageSource` was ruled out with it; since
2026-10-05 it sends a photo as its own bytes, and only with the file's
metadata replaced, never merged, and what it wrote read back (below).

Decided with it:

- **A GIF goes as the file it is**, copied and never read, when it fits
  in what is left of the letter and says nothing of where it was. An
  animated GIF is what people share, and a JPEG of one is a still frame of
  the joke. Every mail program shows a GIF. Past those it is made a JPEG
  of its first frame. Until 2026-10-05 it had to be 5 MB or less as well,
  the letter's 25 MB shared among the five pictures the sheet allows; Mail
  has no such bound, and it is gone (below).
- **A PNG the same.** A PNG is mostly a screenshot: words, which JPEG blurs
  at the edges of every letter, or a picture with a clear background, which
  JPEG has not got. A location is looked for three ways before either goes whole: the
  rule's own keys, ImageIO's own name for the GPS, and the XMP, where a PNG
  may keep it. One that has one is made a JPEG, which carries none.
- **A camera's RAW photo only when nothing else is offered.** Photos offers
  the finished picture beside it, and developing a RAW asks far more of the
  extension and looks flat without Photos' own.
- **The name** was the sharing app's suggestion without the extension it
  came with, and the one it goes with: "IMG_0412.HEIC" goes as
  "IMG_0412.jpg", not "IMG_0412.HEIC.jpg". "Photo.jpg" without one, as the
  composer names it. Since 2026-10-05 the suggestion still goes so, and
  failing one the file's own name, as Mail does; "image0.jpeg" with
  neither, never "Photo.jpg" (below).
- A provider that offers no picture type this knows, but that `UIImage`
  could read, which is what decided a picture before, is read as
  `public.image` the same way. A page, words, a PDF, a video and an SVG go
  on as before.
- **A picture opened and not made into one is not read again.** Its bytes
  are read only when its file could not be opened: no file given, or one
  ImageIO does not know. Opened, with no image at its index, or the
  thumbnail or the JPEG not made, it is left out there. Its bytes are the
  same bytes, and would only be held in memory to fail the same way.
- **A picture that could not be attached is said.** The pictures a share
  offers are counted, and those attached (`ShareItems.Tally`). One left
  out, for want of room in the 25 MB, of a disk to stage it on, or of a
  picture ImageIO could make, is a plain line above what is attached:
  "1 photo could not be attached.", "2 photos could not be attached." A
  share of pictures alone of which none came shows "The photo could not
  be attached." ("The photos …" for more than one) and Cancel, in place of
  the letter. So there is no letter to send without the photo he chose,
  and nothing left out goes unsaid. The rule is `ShareItems.leftOut`, from
  the counts alone.

**Tests.** `SharedPhotoTests`, 25. The size: a 48-megapixel photo to 4032
by 3024 either way up, 24 megapixels to 2856 by 2142, a panorama to 4000
by 1000, a square of 9000 to 2250, 4097 to 2048, a half of exactly 4096
kept, an odd side's half rounded down, past an eighth to 4096. The factor
at every bound. Every longest side from 1 to 40000 px: asked no more than
the decoder's own share of it, rounded up; never more than 4096; up to
32775 exactly its share, with no more than 4097 px decoded; at the
smallest factor that does it. The other side to the nearest pixel, never
under one; a picture no larger kept at its own size; a size unsaid. The
type chosen from what is offered, and what is not a picture. Whole or a
JPEG at each bound. The names. Only the date kept out of an iPad photo's
full property list, and a location found where a file keeps it. The
staging's room, and bytes kept whole going as their own type. What is said
of a picture left out, for each count that matters, and the tally. And the
iPad's part, read from its source as the screens' wiring is: the file and
then the bytes, each in its own pool, one answer each way, the bytes only
after a file not opened; no `UIImage` made, and no `jpegData` or
`loadObject`, anywhere in the share code; the thumbnail's four options,
the longest side asked for, and the factor; only `kept`'s properties and
the quality written; the sheet counting each thing offered, each picture
and each one attached, its line above what is attached, and the words
with Cancel in place of the letter.

Sabotaged one at a time in a scratch copy, the whole suite run each time,
counted in failures, each failing only `SharedPhotoTests`. This change:
4096 asked of every larger photo, the first build's rule (16, three
tests); a half rounded up (3, two tests); past an eighth not brought to
4096 (6, three tests); the short side cut down rather than rounded (8,
three tests); the short side let fall to nought (2); 4096 asked of every
picture in `jpeg` whatever its size (1); the factor not passed (3);
`.undecodable` sent on to the bytes, the early return gone (4, two
tests); a JPEG not made taken for a file not opened (3); the words in
place of the letter whenever no picture came, something else or not (3,
two tests); the line counting the pictures offered, not those left out
(5, two tests); a picture attached not counted (2); the line not put on
the sheet (1); an empty letter where the words should be (1). The first
run of that last also failed `LargeLetterTests.testPicturesStillComing…`,
a timing test of the mailbox that none of this touches, the sabotaged file
not being built on the host; run again, only the sheet's test failed.
Counted again, against the tests this changed: the sheet back on `UIImage`
and `jpegData` (5, two tests), the orientation not applied (1), no
autorelease pool for the file (2), no fallback to the bytes (4, two
tests), every property written into the JPEG (1). Counted before this
change, in tests it did not change: RAW read ahead of a finished picture
(1), a GIF or PNG kept whole with a location (2), whole without the room
for it (1), whole at any size (2), the bound the whole 25 MB (2), every
property kept (13, two tests), GPS not taken for a location (2), a
suggested name's extension kept (6), the room not counting what is staged
(2), ImageIO's own GPS name not looked for (1). Taking out the guard that
keeps a picture of 4096 or less at its own size now fails nothing, and
should not: read at 1, such a picture is asked for its own longest side,
so the rule cannot enlarge it with the guard or without. The whole suite:
1343 tests, 4 skipped, 0 failures. The device build (`swift build
--swift-sdk ios165 -c release`) compiles and links, the extension with
ImageIO, and gives no new warnings.

**The composer, looked at and not changed.** Its photo picker loads each
photo as a `UIImage` and makes it a JPEG with `jpegData` at full size, and
starts all it was given, up to five, at once. So it decodes whole bitmaps
too, in the app, which iOS allows far more memory than the extension: five
from his iPad's 12-megapixel camera come to about 240 MB together. A
48-megapixel photo, one synced from an iPhone, is decoded at 195 MB and
sent at its full 8064 by 6048 px, a JPEG of perhaps 10 to 20 MB, so two of
them may well be too big to send together (B-007). Five such at once could
come near 1 GB. Full size is kept on purpose there (its comment).
Shrinking as the sheet does would take `loadFileRepresentation` and
`SharedPhoto.jpeg`, which is in the library already, but it changes what
he chose to send, so it is the owner's call. Neither path sends a
location: a `UIImage` has none to give.

**Not covered.** Whether the decoder does read a 48-megapixel HEIC or JPEG
at a half when asked for 4032, inside the extension: check 3 in the TODO.
What ImageIO holds besides was measured on the test iPad on 2026-10-04 by
a small program doing what `SharedPhoto.jpeg` does, outside an extension:
a JPEG peaks at about three times its decoded picture, 148 MB for 12
megapixels read whole and 149 MB for the 48-megapixel one read at a half,
204 MB for a 4096 px square; a HEIC from his camera at about once, 51 MB;
turning it upright costs nothing. The test iPad lets a share extension
have 180 MB, so these fit there; an iPad that allows 120 MB would lose
any 12-megapixel JPEG (since 2026-10-05 read at a half there instead,
below). His iPad, and its limit, are not known yet. Whether ImageIO heeds
`kCGImageSourceSubsampleFactor` in a thumbnail at all; the size does not
depend on it. A WebP, GIF, BMP or AVIF of 48 megapixels is still decoded
whole, and would still make the sheet vanish; since 2026-10-05 it is left
out and said instead (below). The line for a picture left
out is not seen on the iPad: nothing at hand makes a picture fail on
purpose. Which types Photos, Safari and YouTube offer, and in what order:
taken from Apple's word that a provider lists its best first. Whether
`CGImageMetadataCopyTagWithPath` finds an XMP location in a PNG. A PNG
over 5 MB with a clear background went as a JPEG, its clear parts solid,
and a GIF over 5 MB lost its movement and arrived as a .jpg; since
2026-10-05 only one that does not fit the letter, or says where it was. A
Live Photo goes as its still. The JPEG, up to about 5 MB, is held in
memory a moment before it is staged. The letter was built whole in memory
at Send, as in the app, until B-070. The checks are the numbered list at the
end of "Blocked on the iPad coming back" in the TODO, and
`BLACKMAIL_SHARE_EXT` stays opt-in until they pass.

**2026-10-05: as Apple Mail does. Seen on the iPad the same day.**
The owner's ruling, on photos shared into the sheet: "just follow what
Apple Mail would do." So what Mail does was looked for first, in his own
Sent mail (868 letters), on the test iPad's disk, and in Apple's
documents and forums, each claim checked by a second reading.

What Mail does:

- **The name.** A photo shared from Photos goes under its library name,
  IMG_ and four digits. A camera photo went as .jpg, in lower case,
  which is how Photos names the JPEG it makes of a HEIC; a
  screenshot as .PNG, the original PNG, its case kept; an older device's
  JPEG as .JPG. A picture with no name goes as image0.jpeg, image1.jpeg,
  counted from nought in each letter, one count for every type: image0.jpeg
  and then image1.png. Mail never sent one as "Photo.jpg" or "Photo 1.jpg",
  and does not tell two of one name apart.
- **Where the name is.** Photos gives a share extension no suggested name,
  but the file it hands over has it. A copy left in the extension's tmp on
  the test iPad was IMG_0776.JPG, byte for byte the original in DCIM, its
  EXIF whole: GPS, orientation 8. Others report OutgoingTemp/<UUID>/IMG_NNNN.JPG
  for an original, …/Compatible/IMG_NNNN.jpg for a HEIC made a JPEG, and
  …/RenderedPhoto/IMG_NNNN.JPG for an edited one. The sheet took no notice
  of the file's name, so every photo went as "Photo.jpg".
- **The size.** Mail's default, and what his iPad sends, is Actual Size:
  the very file Photos hands over, never decoded. The camera's encoding as
  it was, all its EXIF, the orientation a tag and the pixels not turned.
  Mail never shrinks a photo by itself; over the account's limit it offers
  Mail Drop. It also offers Small, Medium, Large and Actual Size.
- **The type.** Photos makes a HEIC a JPEG before it hands it to Mail, and
  to a share extension (WWDC17, session 503). A provider may offer several
  types, public.jpeg and public.heic among them. Which, and in what order,
  Photos offers has never been logged.
- **The location.** At Actual Size Mail sends everything, the location
  too, unless Location is switched off under Options in Photos' share
  sheet.
- **The memory.** The test iPad gives a share extension 180 MB; his iPad
  likely less, about 120. A JPEG's decode peaks at about three times the
  decoded picture, 148 MB for 12 megapixels; a HEIC from a camera at about
  once, 51 MB. A WebP, GIF, BMP or AVIF is decoded whole whatever size is
  asked (above).

What changed, in the share extension only:

- **A JPEG first.** When a provider offers public.jpeg it is read, ahead of
  the HEIC and any other still (`SharedPhoto.fileType`). It is what Mail
  gets: a camera's JPEG as it is, or a HEIC made a JPEG in Photos' own
  process, not in this extension's memory. Not ahead of a GIF or a PNG
  offered before it, which is the picture as it is: Mail sends a
  screenshot as the PNG it is, and a GIF made a JPEG stops moving.
- **Its own bytes.** A JPEG whose file fits in what is left of the letter
  goes as its own image data, never decoded (`SharedPhoto.Way.own`).
  ImageIO copies it with `CGImageDestinationCopyImageSource` into a file of
  the type the source says it is (`CGImageSourceGetType`), written straight
  where it is staged and never held in memory (`ShareItems.Staging.written`:
  the room looked for by the size of the file it comes from before
  anything is written, and the file measured after). The copy is given
  `kCGImageDestinationMetadata` alone, a metadata made fresh that holds
  only the date it was taken, its offset from UTC and the TIFF orientation
  (`SharedPhoto.keptOwn`), set by ImageIO's own property names; never
  `kCGImageDestinationMergeMetadata`. So, by CGImageDestination.h, every
  EXIF, IPTC and XMP tag the file had is replaced by those three. Not
  merged with `kCGImageMetadataShouldExcludeGPS`: the header says that flag
  cannot reach a location kept in a maker's note or in XMP of a maker's
  own. `kCGImageDestinationOrientation` cannot be given with the metadata;
  the orientation is in it, as a tag, and it must be, since these pixels
  are not turned. A copy ImageIO refuses, or one that comes out too large
  for the room, is made a JPEG as below.
- **Its own bytes read back.** That the location is gone rests on one call
  doing as its header says, on an iPadOS that is never updated, and the
  decode could never carry a location where this can. So the file written
  is opened again as ImageIO opens any picture, before it may go
  (`SharedPhoto.readBack`). If it holds more than one picture, or still
  says where it was (GPS or IPTC, by the rule's keys and by ImageIO's own
  names, or a GPS tag in its XMP), or carries Apple's notes or a maker's
  note (`SharedPhoto.keepsMoreThanReplaced`), it is thrown away and the
  photo made a JPEG here, which can carry none of them; its line says
  `(not as its own bytes: the file written still says more than was
  kept)`. A JPEG with a GPS tag and neither a date nor an orientation is
  given an empty metadata, the one case the header's words least settle;
  the read-back is what answers it.
- **Whole at any size.** A GIF or a PNG that fits in what is left of the
  letter and says nothing of where it was is copied as it is. The 5 MB
  bound is gone: Mail has none at Actual Size. One that says where it was
  is made a JPEG, as before. What was left of the letter was also the
  room Send had, below, until B-070.
- **The memory at Send.** The letter was built whole in memory at Send,
  in the extension, as the app built it: every file read back, its
  base64, the letter, and the letter again made ready for the wire.
  Measured on the host, the files read, the letter built and readied, the
  peak was 5.4 to 6.9 times the files, by how the allocator gave memory
  back. A photo as its own bytes makes a letter far larger than a JPEG of
  4096 px did: a 48-megapixel JPEG of perhaps 15 MB went as a JPEG of a
  few hundred KB on 2026-10-04, and would have been about 100 MB at Send,
  in an extension allowed about 120. Killed there, the sheet goes at
  "Sending…" and the letter does not. First, `RFC5322Builder` made each
  file's base64 only as it wrote it into the letter, and the peak was 4.1
  to 5.1 times the files; and a picture went as its own bytes or whole
  only while the letter took three fifths or less of the memory left, at
  five times its files (`SharedPhoto.sendRoom`), shrunk past it with
  `(not as its own bytes: more than Send could build, room for 9 MB)`.
  Then, the same day, B-070: the letter is made from the staged files as
  it goes, never whole, and what Send holds does not grow with them. The
  room at Send is gone with it; a picture is weighed against what is left
  of the letter's 25 MB alone, as a video and any other file always were.
  At Send the log has three lines, `SHARE-SEND files read` with the files'
  count and bytes, now from the rehearsal before the connection,
  `SHARE-SEND built` before DATA, and `SHARE-SEND sent`, each with the
  memory left and the least there has been since the extension started
  (`SharedPhoto.memory`: its limit less its footprint at its highest), and
  the last with the least at any step of the letter's progress, `W MB at
  the least while it went`.
- **Shrunk only where Mail would leave him stuck.** Made a JPEG of at most
  4096 px, as on 2026-10-04: a photo that does not fit in what is left of
  the letter, which Mail would send by Mail Drop and this cannot; a
  picture that cannot go as its own bytes, a
  HEIC with no JPEG offered, a TIFF, a WebP, an AVIF, a BMP, a RAW photo;
  a GIF or PNG that says where it was; a JPEG ImageIO would not copy, or
  whose copy still says where. The 25 MB stays, and so does "1 photo could
  not be attached." for one that still does not fit.
- **The memory read before each.** Right before a picture is decoded, the
  extension asks what is left before iOS kills it: `os_proc_available_memory`;
  failing that, `task_info`'s `limit_bytes_remaining`; failing both, 80 MB
  is assumed, two thirds of the 120 MB an iPad is thought to allow, the
  rest the extension's own (neither figure measured). The decision is
  `SharedPhoto.factor(width:height:type:available:)`, which the suite
  runs: the least factor that brings the picture to 4096 px, as before, or
  a larger one where its peak would take more than three fifths of what is
  left. The peak is three times the decoded picture, at four bytes a
  pixel, for a JPEG, a PNG or a TIFF (the last two not measured, so taken
  as a JPEG), 1.2 times for a HEIC, and the JPEG made at a byte a pixel. A
  format ImageIO cannot read at a factor is decoded whole, and is tried at
  its least factor alone: a larger one would only make the JPEG smaller.
  Where even an eighth would not fit, the picture is left out, counted,
  and the sheet says "1 photo could not be attached." instead of
  vanishing; its line says what would have had to be left, the peak over
  three fifths, rounded up, beside what was, rounded down, so the first is
  always the larger. The size asked for is the factor's own
  (`SharedPhoto.size(width:height:factor:)`), so the two agree. Three
  fifths, because the multipliers are peaks measured outside an extension
  on one iPad; the rest is for the extension's own memory growing while it
  decodes and for the formats not measured. At three fifths the estimate
  may be short by two thirds of itself before the extension is killed.

  | Made a JPEG here, with this much left | Whole | A half | A quarter | An eighth |
  |---|---|---|---|---|
  | 12-megapixel JPEG | 264 MB | 66 MB | 16.5 MB | 4.1 MB |
  | 12-megapixel HEIC | 118 MB | 29.5 MB | 7.4 MB | 1.8 MB |
  | 48-megapixel JPEG | | 264 MB | 66 MB | 16.5 MB |
  | 48-megapixel WebP, decoded whole | | 996 MB | | |

  With less than the last figure in its row, the picture is left out.
  So a 12-megapixel JPEG made a JPEG again here is read at a half on every
  iPad there is, and goes at 2016 by 1512; a HEIC from his camera at its
  own size on the test iPad, and probably at a half on his. A 4032 px photo
  made 2016 px is accepted on this path only: as its own bytes it goes at
  its own size.
- **The name, as Mail's** (`SharedPhoto.named`, `SharedPhoto.name`). The
  sharing app's suggestion, when it has one; else the name of the file it
  handed over, taken inside the callback while the file is there; else
  none. A name of nothing but an extension, ".jpg", is none. The bytes,
  read when ImageIO could not open the file, use the file's name only when
  a file was given. A picture that goes as its own bytes or whole keeps its
  file's name as it is: IMG_0776.JPG stays IMG_0776.JPG, IMG_0775.PNG
  stays. A JPEG made here keeps the name and ends .jpg: IMG_0777.JPG goes
  as IMG_0777.jpg, IMG_0412.HEIC as IMG_0412.jpg. A suggestion goes as
  before, its picture's extension off and the one it goes with on. With no
  name, image0.jpeg, image1.png: "image", a number, and .jpeg for a JPEG,
  one count for the share across every type, of the pictures staged
  (`ShareItems.Staging.unnamed`), so the names in the letter run on without
  a gap. Two of one name are not told apart. One more than Mail is known
  to do: a file whose extension says another type than it goes as takes
  the one it goes with, so a JPEG is never sent as .HEIC. Any other file
  is named as before (`ShareItems.filename`).
- **One line in the log for each picture** (`SharedPhoto.Report`). It goes
  in the connection log, which the extension writes to its own tmp as
  `blackmail-send-*.txt` when the letter is sent:

  ```
  SHARE-BEGIN offered=2
  SHARE-PICTURE offered=public.jpeg,public.heic read=public.jpeg name=file "IMG_0776.JPG" way=own bytes, metadata replaced bytes=2345678
  SHARE-PICTURE offered=public.heic read=public.heic name=suggested "{6 chars}.jpg" way=JPEG at factor 1, 140 MB available bytes=1867233
  ```

  The types the provider offered, in its order; the one read, with the
  type the file turned out to be when that is another; where the name came
  from and the name; the way, which for a JPEG made here is the factor and
  the memory left, or left out and why, and why a JPEG, GIF or PNG did not
  go as itself; and the bytes staged. Nothing of the metadata is in it: no
  GPS. The name is as it is only when a device made it, IMG_ and digits or
  image and digits; any other is a title someone gave it, "Sam's lab
  results.png", and goes by its length and extension alone, `{17
  chars}.png` (`SharedPhoto.Report.logged`): the log is made to be sent to
  whoever helps, and says what happened in numbers and ids, never who or
  what about (D-016). Each share's lines begin with `SHARE-BEGIN`, written
  before its first picture is read: iOS may keep the extension running
  from one share to the next, and the log is not cleared between them, so
  a transcript can hold the share before as well. The figures above are
  made up.

What still differs from Mail, and why:

- **The location is still taken off**, from every photo. Mail sends it
  unless Location is switched off. The owner, asked, 2026-10-05:
  "location is irrelevant", so it stays as it is; and of the rest of this
  list, "the rest of these concessions are fine". It is decided in one place, the two lists of what may go:
  `SharedPhoto.kept` for a JPEG made here and `SharedPhoto.keptOwn` for one
  sent as its own bytes; `SharedPhoto.keepsMoreThanReplaced` checks the
  second after it is written. A consequence of a list: the camera, the
  lens and Apple's own notes are taken off too, where Mail sends them.
- **No Mail Drop**, so a photo too large for what is left of the letter is
  shrunk, where Mail would offer to send it another way.
- **The letter was built whole in memory at Send**, about five times its
  files, in an extension allowed about 120 MB; Mail, an app, has far more.
  So a photo that would make the letter more than that memory could build
  was shrunk too. Since B-070 the letter is made as it goes onto the wire,
  from the files on the disk, and that no longer differs: a photo is
  shrunk only past the letter's 25 MB.
- **No Small, Medium, Large or Actual Size** row. Not part of this change.
- **The app's own composer** still names a photo and makes it as before
  ("The composer, looked at and not changed", above).
- A GIF or a PNG offered ahead of a JPEG is read as itself. What Mail does
  then is not known; the log will say whether Photos ever offers both.

**Tests.** `SharedPhotoTests`, 46: 25 new, three of them in place of
tests whose rule changed, and four rewritten; one, that five kept whole
always fit together, gone with the 5 MB bound. They pin the
name from the suggestion, then the file, then none, a blank or a bare
extension being none; a file's name kept as it is for its own bytes and
whole, case and all, and the one it goes with when its extension says
another type; .jpg for a JPEG made here; a suggestion as before; image0.jpeg
and image1.png, counted across types, per share, only when staged. A JPEG
read ahead of a HEIC, a TIFF, a WebP and a RAW photo, in either order, and
not ahead of a GIF or PNG offered first. The way at the room's bounds, to
the byte, a location or not: own bytes for a JPEG, whole for a GIF or PNG
over the old 5 MB, a JPEG made for everything else. The moment and the
orientation kept for its own bytes and nothing else, the file's own
orientation before ImageIO's reading of it, none out of range. The peak
for each decoder; the least factor whenever memory is plentiful, every
side to 40000 px; the factor at each bound, to the byte; left out where
even an eighth would not fit, a format decoded whole tried at its least
factor alone; a picture of no size read at 1; more memory never a larger
factor nor a picture left out, every side and type. The size asked for at
a factor the memory chose. Its own bytes written where they are staged and
counted as written; nothing begun without room; written too large, or not
at all, taken away again. The log line, each way. And the iPad's part,
read from its source: the file's name taken inside its callback and handed
on; `CopyImageSource` called once, only in `copy`, with
`kCGImageDestinationMetadata` alone, made fresh from `keptOwn`, and never
`MergeMetadata`, `ShouldExcludeGPS`, `ShouldExcludeXMP`,
`DestinationOrientation` or `AddImageFromSource`; the type the file says it
is deciding the way; a refused copy going on to the JPEG; the memory read
by `os_proc_available_memory`, then `task_info`, right before the decode,
its factor the one the JPEG is made at, and a picture it leaves out
counted; one log line for each picture, before its answer.

Sabotaged one at a time in a scratch copy, `SharedPhotoTests` and
`ShareItemsTests` run each time, counted in failures; each failed only
`SharedPhotoTests`. The name: the file's name ahead of the suggestion (2);
the file's name never taken, as before (5); a name of nothing but an
extension taken (2); its own bytes not named as the file is (2); a JPEG
made here keeping the file's extension (2); no name spelled .jpg (4, two
tests); "Photo", as before (6, two tests); the count never moving (1);
named pictures counted too (1). The type: the old order, no JPEG first
(4); a JPEG ahead of a GIF or PNG (2). The way: a JPEG never its own bytes
(5); the 5 MB bound back (3); the room not looked at (5, two tests); whole
with a location (2). What goes with it: its own bytes without the
orientation (4); with every property (3). The memory: not consulted (17,
three tests); nothing fitting read at an eighth anyway (6); a format
decoded whole halved for its JPEG's sake (1); all of what is left taken
(13, three tests); a HEIC at a JPEG's peak (5, two tests); the JPEG made
left out of the peak (14, three tests); the size asked for not the
factor's (12, four tests). The staging: its own bytes counted as expected,
not as written (8, two tests); not taken away when they fail (2); begun
without room (2). Read from the source: the metadata merged (2); merged,
with ImageIO's flag to leave out the GPS (4); the orientation as an option
beside it (2); `AddImageFromSource` (4, two tests); the memory never read
(2); `os_proc_available_memory` not asked (1); the JPEG not made at the
memory's factor (4, four tests); no line in the log (2); the file's name
not handed over (2); a refused copy left out, not shrunk (1); the way
decided by the type offered, not the file's (2, two tests); a JPEG made
here not counted when it has no name (2, two tests); the log without what
was offered (3).

**Reviewed the same day, before the iPad.** Six things were found and
changed. A photo as its own bytes made the letter at Send far larger, and
nothing weighed that (the memory at Send, above; since B-070 nothing needs to). The file written as its
own bytes went unread, its location gone only on ImageIO's word (its own
bytes read back, above). The log wrote a picture's name as it came, which
can be a title someone gave it. A picture left out for the memory read "9
MB needed at the least, 12 MB available", the peak beside what was left,
and for a picture decoded whole the peak at an eighth, which is never
tried. A transcript can hold a share before this one. And the TODO's
checks: check 4's size was the stored one, not the upright 1512 by 2016;
check 1 failed a camera photo of 4032 px for being under 4096; Pillow's
`getexif()` takes the orientation from the XMP when the EXIF has none, and
GPS was looked for in the EXIF alone; nothing tried a JPEG with GPS and no
date, nor a PNG with GPS. Those are rewritten, and three checks added
(5, 9, 10).

Tests: `SharedPhotoTests` 9 more, 55; `ShareSheetTests` 1, `OutgoingMailTests`
2. They pin the room at Send, to the byte, against the memory and what is
staged, never more than the letter's own, never below nought, and the way
it gives; why a picture did not go as itself, each reason; what is read
back, its location by either list, Apple's notes and a maker's note, and
nothing for what was kept or what ImageIO adds; a name in the log as it is
only for IMG_ or image and digits, any other by its length and extension,
a title with a person and a place in it never in the line; a line left out
for the memory needing more than was left, every size to 40000 px, every
megabyte to 1000, each kind of decoder; the Send lines, their figures, and
their place around ENVELOPE, RCPT, DATA and its reply; a file's base64 the
same text as before at every length about a line's end, its length known
before, each file's part ending as it did; and from the source, the room
at Send read before the way, the read-back between the copy and the
staging and every check in it, the memory's least from `task_info`, the
sheet handed the memory, `SHARE-BEGIN` before the first picture, and the
builder making each file's base64 only where it writes it.

Sabotaged one at a time in a scratch copy, `SharedPhotoTests`,
`ShareItemsTests`, `ShareSheetTests`, `OutgoingMailTests` and
`BoundaryTests` run each time, counted in failures. The room at Send: not
weighed (11); what is staged not taken from it (4); the way decided by the
letter's room alone (3, three tests); Send's reason never given (2); the
reason not put in the line (1). The Send lines: none once built (2); the
memory not handed to the sheet (1); the least left out (2, two tests). The
builder as it was (6), its letter the same, which is the point; the CRLF
after a file's base64 left out (7, four tests); its length one short, or
lines of 75: the run traps at the first file written. The read-back:
skipped (2); seeing nothing (6); not looking for a maker's note (1); a
file of two pictures let through (1). The name: logged as it came (4, two
tests); IMG_ and any letters taken for Photos' (3). The left-out line: the
peak, not what had to be left (2, two tests); the peak at an eighth for a
picture decoded whole (2, two tests). `SHARE-BEGIN` not written (2). On the
host, the files read, the letter built and readied for the wire, peak
memory against the files was 5.4 to 6.9 times before the builder's change
and 4.1 to 5.1 after, by how the allocator gave memory back. The whole
suite: 1377 tests, 4 skipped, 0 failures. The device build (`swift build
--swift-sdk ios165 -c release`) compiles and links, the extension with it,
and gives no new warnings.

**Seen on the iPad, 2026-10-05**, on a build installed through
TrollStore's helper, every letter to the account itself, each line read
from the extension's log and each photo that arrived read on the host:

- IMG_0776, the 48-megapixel JPEG with a GPS tag and orientation 8,
  Photos saying "Location Included": the sheet listed "IMG_0776.JPG —
  1 MB", and its line read `offered=public.jpeg read=public.jpeg
  name=file "IMG_0776.JPG" way=own bytes, metadata replaced`. It arrived
  under that name at 8064 by 6048, its picture's data byte for byte the
  original's, the orientation 8 in the EXIF, the date it was taken, and
  no GPS anywhere: not in the EXIF, the XMP or a maker's note. ImageIO
  adds a thumbnail of its own, of the same picture, and an XMP of the
  orientation and the date.
- Five at once: three of the test iPad's camera photos, kept as HEIC,
  IMG_0774, a 12-megapixel JPEG, and IMG_0776. The sheet listed
  IMG_0766.jpg, IMG_0767.jpg, IMG_0768.jpg, IMG_0776.JPG and
  IMG_0774.JPG, the names Mail gives them. Photos offered each HEIC as
  `public.jpeg,public.heic`, its JPEG first, and the JPEG was read. All
  five went as their own bytes and arrived so: 4032 by 3024, the
  orientation a tag (6 or 3), the date and its zone, the colour profile
  kept, no GPS, no maker's note. An Apple segment, APP10 `AROT`, goes
  through as it came; the photos his own iPad's Mail sends carry it too.
  At Send, with 12.7 MB of files read, 160 MB was available and 108 MB
  the least there had been: about four times the files above it.
- IMG_0777, the 64-megapixel panorama of 26 MB, too large for the
  letter: `way=JPEG at factor 4, 173 MB available (not as its own bytes:
  more than the letter's room, 25 MB left)`. It arrived as IMG_0777.jpg,
  4000 by 1000, upright in its pixels, with no orientation tag and no
  GPS.
- IMG_0775, a PNG: `read=public.png name=file "IMG_0775.PNG" way=copied
  whole`, and it arrived as IMG_0775.PNG, byte for byte the original.
- A Wikipedia page from Safari went as before: its title the subject,
  its link in the letter.
- `os_proc_available_memory` answers in the extension: 160 to 175 MB.
- iOS keeps the extension running from one share to the next, and across
  a reinstall. The first share after this build was installed came to a
  BlackmailShare the install before had started hours earlier, which said
  "Open Blackmail once, then share this again." though the app had been
  opened. Ended (`killall BlackmailShare`), the next share came up with
  the account. Only a check meets this; his iPad is installed once.

Not tried: a GIF, a picture with no name, a letter near the limit at
Send, a JPEG or PNG with a GPS tag made on the host, and the checks of
the rest of B-036.

**Not covered**, all for the iPad (checks 1 to 10 in the TODO); what the
iPad has since shown is said at the end of each:

- That `CopyImageSource` replaces as the header says: no GPS, no maker's
  note, the date and the orientation tag kept, the pixels the camera's.
  Where it does not, the read-back sends the photo the JPEG way, and the
  line says so; but the read-back sees only what ImageIO itself reads back
  of the file written. Seen 2026-10-05: as the header says, for a JPEG
  from a camera and one made elsewhere.
- Whether the orientation is written into the EXIF or only into the XMP:
  CGImageMetadata is XMP's. In the XMP alone, Gmail and a browser show the
  photo on its side. The read-back does not look; check 1 does. Seen
  2026-10-05: in the EXIF, and in the XMP as well.
- That the colour profile stays. It is none of EXIF, IPTC or XMP, and the
  header says the image data is not modified, so it should; nothing here
  proves it. Seen 2026-10-05: it stays.
- Whether `CGImageMetadataSetValueMatchingImageProperty` takes
  `OffsetTimeOriginal`. If not, the date goes without its zone. Seen
  2026-10-05: it does.
- A location kept in a maker's own JPEG segment, outside EXIF, IPTC and
  XMP, or in bytes after the picture's end: whether `CopyImageSource`
  copies such a segment is not known, and the read-back cannot see one.
  The segments of what arrives are listed in check 1.
- Which types Photos offers, in what order, for a camera photo, a
  screenshot and a GIF; the first line of the log will say. Seen
  2026-10-05: `public.jpeg,public.heic` for a camera photo, `public.jpeg`
  for a JPEG, `public.png` for a PNG; a GIF not yet.
- What name iOS gives the file of a provider made from bytes with no name.
  If it makes one up, that is the name, not image0.jpeg; the log will say
  it came from the file, by its length, and the letter will show it.
- Whether `os_proc_available_memory` answers in an extension. It says
  nought for a process that is not an app; then `task_info`, then 80 MB.
  Seen 2026-10-05: it answers.
- How near the memory's factor comes to the limit in fact: the estimate is
  built from a measure made outside an extension.
- **Send.** A photo now goes at its own size, so a letter of photos comes
  near the 25 MB far more often than a JPEG of 4096 px let it. Since
  B-070 the letter is made from the staged files as it goes, never whole,
  and what Send holds does not grow with them: under 8 MB more for a
  19 MB video on the host. The network's own buffers are not in that
  figure. Whether the extension lives through a letter near 25 MB on the
  iPad, and how low its memory went while it did, is B-070's check, from
  its `SHARE-SEND` lines; on his iPad when it can be had.
- That `ledger_phys_footprint_peak`, in `task_info`, is the extension's
  highest footprint since it started, as its name says: `M MB at the
  least` rests on it.
- Whether iOS keeps the extension running from one share to the next. If
  it does, the transcript holds the share before too, above the last
  `SHARE-BEGIN`. Seen 2026-10-05: it does, even across a reinstall.

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
and is right once the next lands. (Since B-059, the pane puts the mark on
that sweep's count when the count is the pane's before the mark, so the
Inbox does not read one too many.)

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
as before. The Cc line, added under To by B-055, is known from the row too
since 2026-10-01, from its ENVELOPE, and is there from the tap.

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
composer. Nothing moves up or down; the switch slides, see B-066. A tap
on the button while another finger is on the screen is not taken, so
nothing slides out from under that finger. `< Mailboxes` puts the keyboard away, as
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
  not-found nothing-sent`): it stays on the iPad saying "Attachment could
  not be downloaded.", in Drafts on the line under "On this iPad only"
  (`LocalDrafts.draftsRows`, which the list draws), in the Outbox as its
  reason (B-052), and in the sheet if he sends it, and is not tried again
  unasked until he changes it or the app is launched again; the letters
  after it go. Changed since and refused again for a reason a draft's row
  does not give, it says nothing: each refusal sets its own reason, or
  none, and an earlier one's does not stay behind. It is the only reason a
  row in Drafts gives. A letter a pass refused in the Outbox, too big or
  not sent, and taken back into the sheet as it stood by a Send that failed
  and closed, is a draft still carrying that refusal, and its row said the
  Outbox's reason under "On this iPad only"; it now says nothing there.
  (The composer's Send keeps the letter as a new version first, which no
  pass has refused, so it stands as it stood only when that keep could not
  be written.) The words are the spec's, the same as for a forward's file
  gone from Gmail, which a file named by folder and UID alone says, and as
  for a letter found in All Mail without the part it named
  (`MailError.attachmentsMissing` is a case of its own for the Drafts row,
  and reads as `attachmentFailed`). The first version used Mail's, as its
  users quote the alert iOS Mail puts up when a forward's attachments
  cannot be had ("Unable to Attach", "One or more attachments failed to
  load.", Apple's forums, thread 254851082, iOS 16.4.1): a sixth sentence
  beside the spec's four and the letter too big to send, and the same
  missing file read one way or the other by how it had been named. Mail
  offers Continue Anyway there; nothing here sends a letter short of a
  file.

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
has lost. The Outbox goes by the same count for an attempt that may have
reached Gmail, whose look in Sent Mail asks the new password's mailbox
(B-052, "Across a password save").

**What it sends.** A first Save Draft, an autosave and a launch send what
they always did, and a letter made and sent in one launch asks for nothing
more. What is added, each only where a kept letter names something on the
server:

- The look in Drafts before an upload of a letter tried before, `UID SEARCH
  HEADER Message-ID`, once per version tried ("Never twice in Drafts").
- `UID FETCH n (UID X-GM-MSGID)` in Drafts, after the APPEND and before
  the `UID STORE` and `UID EXPUNGE` of the copy a letter replaces, when
  nothing has been named under that UID in this launch. Another letter
  there, and the STORE and EXPUNGE are not sent.
- For a file or picture whose letter is not under its UID, `UID SEARCH
  X-GM-MSGID n` in All Mail, then the letter described and the part fetched
  there, in place of the part's FETCH in the folder it named; the FETCH
  that describes the letter in that folder is the one it always sent.
  Under a UID this launch has seen to hold another letter, nothing goes to
  that folder at all.
- The one change to a command that went before: reopening a copy the app
  itself put in Drafts in this launch, one its APPEND landed or one the
  search by its version's Message-ID found, sends `UID FETCH n (UID
  X-GM-MSGID BODY.PEEK[])` in place of `UID FETCH n (UID BODY.PEEK[])`, the
  id asked in the same FETCH, at no round trip more. Without Gmail's
  extension it sends `(UID BODY.PEEK[])` as before.
  `KeptReferencesTests.testACopyThisLaunchUploadedIsNamedWhenReopened` and
  `testACopyFoundByItsMessageIDIsNamedWhenReopened` pin the first, and
  `testWithoutGmailsExtensionNothingIsNamedAndItAllGoesAsBefore` the
  second.

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
original's being gone). Then three more, each failing the tests named:
Mail's sentence put back for a file found nowhere
(`MessageSizeTests.testEveryErrorIsOneOfSixSentences`, and the two here
that read the words on a row), a Drafts row given whatever reason its
letter was last refused for
(`OutboxTests.testADraftsRowNeverGivesTheOutboxsReason`), and the copy this
launch put in Drafts reopened with its plain FETCH (the two tests that pin
the FETCH, and the forward reopened from a copy found by its Message-ID).

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, before the branch
was merged, each case made by hand in the store with the app ended:

- A draft saved to Gmail as "test one", reopened with a connection, the
  Wi-Fi cut, changed to "test two" and saved: "On this iPad only", the
  Gmail copy under it hidden. Its `savedLetter` written one higher: Drafts
  offline listed both. Wi-Fi on, the pass: `UID SEARCH HEADER Message-ID`,
  the `APPEND` of "test two", `UID FETCH 9 (UID X-GM-MSGID)`, then
  `KEPT-UNVOUCHED folder=[Gmail]/Drafts nothing-sent` and
  `DRAFT-SUPERSEDED … not-that-letter left`, no STORE, no EXPUNGE, and both
  in Drafts. The same again with no edit ("test three"): the `APPEND`, the
  question, then `UID STORE 10 +FLAGS.SILENT (\Deleted)` and `UID EXPUNGE
  10`, one copy left.
- A forward of a letter with two PDFs sent offline, its files' UID written
  as another Inbox letter's: `CARRIED-PART folder=INBOX
  reason=another-letter`, `UID SEARCH X-GM-MSGID …` in All Mail, both parts
  fetched there, `CARRIED-PART found`, and the letter arrived with the two
  PDFs forwarded, at their own sizes.
- The same with the files' letter id written as one no letter has:
  `CARRIED-PART not-found nothing-sent`, no envelope, and the Outbox row
  "Attachment could not be downloaded."

A letter kept before the ids (the fourth case in the TODO) cannot exist on
an iPad the app is installed on fresh, and was left to the scripted server.

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
letter stays in Drafts on the iPad saying "Attachment could not be
downloaded.", where he can open it and take the file out (above, "Another
mailbox under the same address"). One kept before the ids were says nothing.
A large letter on a slow uplink may not finish in the time iOS gives as he
leaves, and then goes again from the start, looked for first, at the next
departure; Save Draft in the composer sends it at once. Move and Mark in
Edit pass over kept letters without saying so. The Edit-mode routing and the
list's handling of a landing are UIKit, and only the pieces under them are
tested here (`LocalDrafts.delete`, `ListLetters.landed`). A Send cut off by
iOS ending the app comes back as a draft, and may be a letter that went:
that is the Outbox's to settle, next, on this store (TODO).

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
Refresh there sends what waits, as Refresh in any folder does since B-072.
When the connection is back, with the app open, the letter goes by itself,
once, and leaves, and the Outbox leaves the Mailboxes with its last letter.

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
nowhere it is `attachmentsMissing`, read out as the same "Attachment could
not be downloaded.", its row's first line, which keeps the sheet as well
(B-051).
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

**Across a password save, 2026-09-30.** The look asks whatever mailbox the
password opens, and a password saved in Settings can open another mailbox
under the same address (B-033). An attempt cut off after its DATA under the
old password, looked for there, was not found, was taken for one Gmail never
had, and the letter went a second time. Found in the code, not on the iPad.
Now each attempt written down is stamped with the count of passwords saved
that its launch found (`unsettledSaves` in `letter.json`, written with the
attempt, which is then the only one unsettled since Sent Mail is asked
before a letter goes again, and carried when the letter is kept again;
absent, so 0, in a letter an older build kept), the count B-051 keeps beside
the letters. From the launch after a save, a letter with an attempt from
before it is not taken by a pass (`LocalDraftStore.unsettledBeforeASave`):
nothing is looked for and nothing sent, and the letters after it go. It
stays in the Outbox, its row's first line "May already have been sent.", and
counts among the unsent. The attempt is compared, not the letter: a letter
sent offline before a save, and cut off by the first pass after it, was cut
off under the new password, and goes as any other. Tapped and sent it goes,
his choice: Sent Mail is asked first as for any such letter, which is still
worth asking, since a password saved is usually the same mailbox, and found,
nothing more goes. Opened and put away as a draft, it keeps its attempt and
its stamp, and no pass takes it to Drafts either, where a Send later would
go with nothing looked for; Save Draft of his own takes it there once Sent
Mail has not got it, as before. The words are the app's own, where a refused
letter's reason goes: "Message was not sent." may be untrue here, and would
have him send it again for that reason. In the launch that saved the
password nothing changes, as its repository still has the old one.

**When a waiting letter goes.** By B-051's pass, and at its moments: after
a folder's newest page, on coming back after the warm-up, and as he leaves
the app, inside background time; since B-072 at his Refresh, once its page
and the folder counts have come; and at one more, the first check of the
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
go. One with an attempt from before a password save is not taken at all,
and says it may already have gone (above, "Across a password save"). A
submission server that cannot be reached while IMAP works ends the
Outbox's part of the pass, as does a "not now" from it; the drafts after it
still go up: each letter after it would cost a connect for the same
failure. Size: an Outbox letter goes over a connection of its own, so its
photos hold nothing he taps and it goes at once; what a forward or a
reopened draft has to fetch from Gmail first comes over the one IMAP
connection, and a megabyte or more of that waits for his Refresh or for him
to leave the app (`LocalDraft.fetchesLarge`). Until B-072 it waited for him
to leave, as a large draft still does. That is its rows from Gmail and
nothing else: a forward's quoted pictures that go are ones that are also
its rows, fetched once, and counting them again held a forward of 600 kB of
photographs back as 1.2 MB. Nothing sends while the app is put away
(above).

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
notice's words; across a password save, an attempt cut off before it is
neither looked for nor sent by a pass, and the letter after it goes, its row
says "May already have been sent." and it counts as unsent, and sent by him
it goes once, Sent Mail asked first; an attempt cut off by the first pass
after the save goes as before; put away as a draft, a letter with an attempt
from before the save is not taken to Drafts, and one with an attempt from
after it is. Each of these fails with its part undone in a scratch copy:
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
DATA made before MAIL FROM as well), and eight for the password save, each
failing the test named for it (a pass taking a letter held across a save;
the row without its words; his own Send held as well; the letter's stamp
compared rather than the attempt's; the attempt not stamped, or its stamp
not read back; a keep stamping it afresh, or dropping it).

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
draft does (B-051). A letter held across a password save is held whichever
mailbox the new password opens, the same one included, which is the usual
case, where the look would have settled it: the app has no sure way to tell
the two apart, and it waits for his tap rather than risk a second copy. The
sidebar's row, the Outbox's list, the notice and the watch's trigger are
UIKit and not on the host; the pieces under them are tested
(`LocalDrafts.outboxRows`, `LocalDraft.outboxRow`, `Outbox.mailbox`,
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

## B-054 — CHANGED 2026-09-30 and 2026-10-01, seen on the iPad. A stranger's letter could hang the app, or take all its memory

**Found by timing and measuring, on the development computer, everything
that reads a letter he receives.** No such letter has reached him; anyone
can write one. Nine passes over a letter's content took time that grew with
the square of its size, or with its size times its pictures, and a letter
built for it made them run for minutes, or hours:

- the reading pane taking off the sender's document wrapper
  (`DocumentWrapper`): four regular expressions, one of which, never
  closed, read to the end of the letter from every opening. 48 KB of
  `<head>` took 8.5 s in a release build and a megabyte would have taken
  about an hour, off the main thread but with no way to stop it, and, by
  reasoning rather than on the iPad, a few such letters tapped would hold
  every thread the mail runs on;
- the pane pointing the letter's pictures at its loader
  (`InlineImageRewriter`), which copied the rest of the body to search it
  for each picture: 20,000 pictures in 8 MB, 7.5 s;
- when he replies to such a letter or forwards it, on the actor that Send
  and Save Draft wait on, and again at every launch while the letter waits
  in the Outbox (B-052), the sanitiser the quote goes through
  (`QuotedMarkup`): its list of open elements, searched whole for every
  closing tag (`<div>` opened nine thousand times and then `</x>` as often,
  5 s, and a megabyte minutes); a `<head>` never closed, read to the end
  once for every head (`<head>x` over 48 KB, 16 s); a tag's attributes, each
  looked for among the ones before it (eight thousand, 2.8 s); a picture's
  reference in a style, looked for afresh from every place it might start
  (70 KB, 2 s); and, in a forward, the pictures a style shows renamed one at
  a time, each moving the rest of the style along (180,000 in 4 MB, 8 s in
  a release build), and a picture's reference written in another case than
  its Content-ID compared with every picture the forward carries (500
  pictures and 1.1 MB, 7.3 s in a release build);
- the decoder unfolding a header folded onto many lines, which copied the
  whole value for every line (20,000 lines, 2 MB, 4.7 s).

And every letter was fetched whole, whatever its size, and copied several
times over as it was read. A crafted letter of 35 MB of line breaks inside a
multipart came to 1.66 GB in a release build, which is the app killed the
moment he opens it: the decoder made a list of every line first, at 24
bytes a line. One of 25 MB of CRLF came to about 700 MB and took 14 s on the
repository's actor, most of it in the two replacements that made its line
breaks line feeds. Figures are the suite's debug build on the development
computer where not said otherwise.

**What he sees now.** On a letter of 5 MB or less, nothing: its FETCH is
the one it always was, and the pane's page, the text and HTML the decoder
gives, and the quote a reply or a forward carries are byte for byte what
they were (below). A letter above 5 MB on the server, most often a letter
of two or more photographs, opens without its files: its header, its text
and its HTML, each up to 2 MB, and its files listed in the header as
before, from its structure. A file comes when he taps it, as a file always
did when the letter was no longer to hand, and a picture the letter shows
in its body comes as the pane asks for it, so the photographs of a large
letter appear one after another rather than with it. Reply and Forward
work as before: a reply quotes what was fetched, and a forward carries
every file and picture by reference, as it always did, fetched when it is
sent. A letter whose HTML is longer than 2 MB, or whose text is when it has
no HTML, which is rare (a newsletter is 50 to 200 KB, though a sender who
writes pictures into the HTML itself can pass it, and loses the pictures
past the cut), shows "Only the beginning of this message is shown." in grey
above it, in the pane and in a conversation. Above it rather than under it:
the sender's markup is cut wherever the fetch stopped, inside a table, a
link or a tag, and anything written after it would be drawn inside that, or
not at all. A text alternative cut under HTML that came whole says
nothing, since the pane shows the HTML. A character cut in two by the fetch
is dropped, as a preview drops it, rather than making the whole of it read
as Latin-1. The words are the app's own.

**What goes on the wire** (`IMAPMailRepository.loadMessage`,
`IMAPClient.fetchLetterInPart`). In one hold of the interactive line, with
its SELECT and UIDVALIDITY check (B-039): `UID FETCH <uid> (UID
BODYSTRUCTURE BODY.PEEK[HEADER])`, then `UID FETCH <uid> (UID
BODY.PEEK[1.1]<0.2097152>)` for the text and the same for the HTML, by the
sections the structure gives them, all PEEK. Every other letter's FETCH is
what it was, `(UID BODY.PEEK[])`, the everyday wire. The size is the
RFC822.SIZE every row is fetched with already: the repository keeps it for
the letters above 5 MB it has listed in this launch (the last 2,000 of
them), and the page kept on the iPad (D-016) keeps it with their rows, so a
large row tapped at launch before its folder's first page has come is
opened in part too. There, as for a whole letter (B-053), the first FETCH
asks Gmail's id for it, `(UID X-GM-MSGID BODYSTRUCTURE BODY.PEEK[HEADER])`,
and it is compared before the text is asked for: another letter's, or none,
and nothing more is fetched, nothing is shown, the row leaves the kept page
and the log says `KEPT-UNVOUCHED folder=INBOX nothing-shown`. A copy this
launch put in Drafts is asked its id the same way, and nothing compared.
A letter with no size known to the repository is fetched whole, as before.
A draft he reopens is fetched whole however large: he may change it and
send it again, and a text cut short would go cut short. A file he taps, or
a picture the pane asks for, of the letter last opened in part is then
`UID FETCH <uid> (UID BODY.PEEK[<section>])` alone, its structure kept from
the first FETCH as a letter fetched whole is kept for its files; one of a
letter opened before it has the FETCH that describes the letter first, as a
file of a letter no longer to hand always had. Described again for each, a
large letter of 300 pictures took 603 FETCHes to open and show, each second
one carrying its whole structure. And the pictures still coming when he
taps another letter are called off (`PictureRequests`): WebKit stops them
as the page goes, the one on the wire finishes, and the rest leave the line
with nothing sent. They used to go on waiting, and then go, every one, and
the letter he had tapped came after them.

**Every pass over the content is one pass.** The wrapper comes off in one
pass over the bytes, the next `>` and the next `</head>` each looked for
once from where the last search stopped (`DocumentWrapper`). The pictures
are found in one pass (`InlineImageRewriter`). The sanitiser keeps at most
512 elements open, as WebKit builds no deeper, and one opened inside that
many loses its tag and keeps what is inside it, as an element not on its
list does; it counts the open elements by name, so a closing tag for one not
open is refused at once; a `<head>` found never to close ends every later
one where a browser ends a head never closed; attributes are checked against
a set; a style's reference is found by Knuth, Morris and Pratt's search, and
its pictures are renamed in one copy of it once all are found; a reference
in another case than its Content-ID is looked up in a table of the ids in
one case, made once, and where two ids differ only in case the first in
order is the one found, where it was whichever the comparison met first. The
decoder walks a part's lines in place, reads only a letter's header block to
read its header, unfolds a header in place, and makes line breaks line feeds
in one pass over the UTF-8. It lists at most 500 files for a letter,
wherever its parts are: 500 to a multipart, nested, was a quarter of a
million rows in the header and on the kept page. Here, now: the 48 KB
wrappers about 10 ms each; the 20,000 pictures 0.1 s; the sanitiser's cases
14 to 70 ms, the 180,000 references in a style found and renamed 1.3 s,
where they took 8.7 s, and references in another case about one and a half
times those in their own, where they took fourteen times with 500 pictures;
the folded header 80 ms; 35 MB of line breaks opened 6 MB, and fetched whole
104 MB, where it was 1.66 GB; 4 MB of CRLF 2 MB and 0.2 s, where it was 151
MB and 2.3 s. Only a letter built for it comes out otherwise, and nothing a
mailer writes does any of these: a piece of the wrapper whose `>` lies past
a `</head>`, which the four expressions, run one after another, could take
in another order; a line break with a combining accent after it, which the
replacements took as one character with it; in the pane, a `)`, a `"` or a
`>` with a combining accent after it, which now ends a picture's id, and a
`CID:` with one after it, which is now written `cid:`, where Foundation's
search took each with its accent as one character; and in a quote, a second
`<head>` after one never closed, now ended where a browser ends it, so that
what it holds is quoted as a browser shows it: `<head>A<head>B</head>C`
quotes as `ABC`, where it quoted as `AC`. And a picture's id is ended by a
carriage return as by a line feed, where a CRLF straight after it did not
end it; no body the decoder hands over has a CRLF left in it.

**The connection log** has a SEARCH's answer as how many it found, `* SEARCH
{56112 uids}`, as a literal is kept as its size. At his size, by estimate,
the answer is one line of 0.4 MB for the Inbox and one or two megabytes for
Sent Mail, All Mail or a common word, most of the 500 lines the log keeps,
and the log's screen, the one read out over the phone, would freeze on the
main thread drawing it; each send's transcript carried it too.

**Not taken, and still to do.**

- The text of an HTML letter is read a Character at a time (`HTMLText`),
  about 0.3 s a megabyte here in the debug build; Reply makes its quote on
  the main thread (`Message.quotableText`), so an HTML-only letter just
  under 5 MB can hold the screen for a second or more at the tap. Linear,
  and left.
- The pictures a large letter shows come one FETCH each, where a whole
  letter brought them all in one. How long a letter of many takes to fill
  in on his connection is for the iPad to say; none is capped. Only the
  letter last opened in part keeps its structure, so in a conversation of
  two such letters the other's pictures are two FETCHes each. A forward of
  one fetches its files and pictures as it is sent, each with the FETCH
  that describes the letter and names it first, as for any letter no longer
  to hand: behind the spinner, not in the pane.
- The quote of a letter cut short says so by the part the pane shows,
  as the pane's line does (below): a letter whose HTML was cut and whose
  text came whole says so in its plain part too, though that part quotes
  all of the text; a text cut under HTML that came whole is quoted cut in
  the plain part, with nothing to say so, under HTML that is whole. Each
  as rare as the cut itself, and left.
- The structure of a letter with a great many parts is read whole for
  every row that lists it; only the files listed from it are capped.
- Gmail's answer to `BODY.PEEK[HEADER]`, and to a section cut at 2 MB, has
  not been seen; previews have used cut sections (`BODY.PEEK[1]<0.2048>`)
  from the start.

**Decided 2026-10-01: the quote of a letter cut short says so**
(`Message.quotedWords`, `QuotedOriginal.isShortened`,
`AppleMailHTML.letter`). A reply or a forward of a letter the pane shows
only the beginning of used to quote what was fetched with nothing to say it
was cut, and a forward passed the first 2 MB on as if it were the whole
letter. Now the quote ends with the pane's own line, "Only the beginning of
this message is shown.": in the plain part, which is the composer's text,
under a blank line, marked "> " in a reply as every line of the quote is;
in the HTML, inside the quote and after the original's markup, as Mail's
blank line, `<div><br></div>`, and the line in the pane's grey, `#8e8e93`,
so that it reads as the app's and not the sender's. At the end of the
quote, where the pane has it above the letter: the quote's markup has been
through the sanitiser, which closes what the cut left open, and a paragraph
it leaves open the line's own `<div>` closes, so the line is the quote's
and not inside a table or a link of the sender's. Where the quote's HTML is
made from the words, the line is drawn once, grey, and not also as words.
Nothing more of the letter is fetched. Put down as a draft and taken up
again, the line comes back inside the stored markup and is not added a
second time; kept on the iPad for the Outbox, the quote is marked
`"shortened": true` in `letter.json`, absent from every other quote and
from one kept before, which reads as no, so no new format. If he changes
the quote, the HTML is what he left, as it always was, the line among his
words if he left it. A letter shown whole quotes byte for byte as it did.
Tested in `RichQuoteTests` (a reply and a forward of a cut letter, its
markup quoted and of plain text, and a draft of one reopened; a whole
letter's saying nothing) and `OutboxTests` (the mark kept with the letter,
and written for no other quote); six parts of it undone one at a time in a
scratch copy, each fails them.

**Checked in host tests** (`BoundedLetterTests`, `LargeLetterTests`,
`HostileLetterFuzzTests`, `DiagnosticsTests`, `PictureRequestsTests`). What
the wrapper, the pictures and the line breaks make of ordinary mail is held
against the code they replace, kept in the test as the reference; the quote,
the pane's page and the decoded letter against fingerprints of what the code
before made of 54 HTML bodies and 30 whole letters (`OrdinaryMail`: Mail,
Outlook, Gmail, newsletters, quoted-printable, base64, related, mixed,
forwarded). Each crafted letter is timed against a bound at least ten times
what it takes here, and sized so the old way goes well past it; the counted
closing tags are timed against the same tags with nothing open, and
references in another case against the same in their own; the style's
renaming is held place by place, each id read where the sender wrote it,
since timed it is only seven times the linear way in the debug build; memory
is measured by Linux's high-water mark (`PeakMemory`). A large letter is
opened over the scripted server field for field as a whole fetch gives it,
its files and pictures fetched when asked, each one FETCH, the pictures
still coming called off when he moves on, replied to and forwarded with its
files, cut with a character split at the cut, a text cut under whole HTML
not said to be cut, a copy this launch put in Drafts asked its id in the
first FETCH, and opened from the kept page at the next launch, vouched for
and refused. The fuzz mutates ordinary mail with what a stranger would reach
for, seeded: 150 cases each for markup and letters in every run, and
`BLACKMAIL_FUZZ_CASES` for as many as it says (`BLACKMAIL_FUZZ_SEED` for
another seed); no crash, every call inside 2 s, every output within what its
input allows, and the sanitiser's output only tags it keeps, no attribute
that acts, no address on a scheme mail has no use for, every closing tag
closing something it opened, nothing deeper than its limit. Run at 25,000
cases each for five seeds, a quarter of a million in all, it found nothing
in the code. Each part undone in a scratch copy, one at a time, fails the
test named for it: thirty-two undone.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, before the branch
was merged. A letter of five photographs, about 15 MB, sent to the account
itself: it opened at once, its five files listed and its words below,
from `UID FETCH 45 (UID BODYSTRUCTURE BODY.PEEK[HEADER])`, the text and
HTML parts as `BODY.PEEK[1.1.1]<0.2097152>` and `BODY.PEEK[1.1.2]<0.2097152>`,
the signature's picture as `BODY.PEEK[1.2]` and, when one was tapped, that
photograph alone as `BODY.PEEK[2]`; nothing fetched the letter whole. The
connection log said `* SEARCH {17 uids}`. Not made by hand: the slow
letters and the 35 MB one, which the suite and its fuzzing stand for, and
a part over 2 MB, which the notice and the quote's line wait on.

---

## B-055 — CHANGED 2026-09-30 and 2026-10-01, seen on the iPad. The reading pane runs no letter's script and goes nowhere by itself; links in plain letters can be tapped; Cc under To

**What was wrong.** Three things, all in the reading pane.

- The pane's web view had WebKit's default settings: every letter's script
  ran, and every navigation but a tapped link was allowed. A letter could
  send the pane to a web page of its own choosing, with no address bar, a
  false Google sign-in for one, by a `<meta http-equiv="refresh">`, a frame,
  a form sent or its own script, and it ran script on a WebKit that, once
  the app is installed, may never be updated. In a conversation, a body put
  in by the page's script could still run an `onerror=`. A comment at the
  web view's setup said remote content was blocked; nothing blocked it.
  WebKit also kept cookies, a cache and site data from the pictures letters
  load in the app's container, the one store the app did not bound.
- A link written out as words in a plain letter could not be tapped: the
  pane escaped it and nothing made it a link, WebKit's data detectors being
  off. About a third of the links he shares with himself arrive that way.
- The header never showed Cc, and wrote a recipient with no name as
  `<jane@example.com>`, or as nothing for `"" <jane@example.com>`.

**The pane, locked down** (`MessageDetailViewController`,
`PaneNavigation`, `ConversationDocument`).

- No script of a letter's runs: `allowsContentJavaScript` is off. On the
  iPad's WebKit that also has the parser drop a letter's `<script>`s, its
  `on…=` handlers and its `javascript:` links as the page is read, and as a
  conversation's body is put into its section.
- The pane's own script, which opens and closes a letter of a conversation
  and puts its body in, is no longer written into the page, where it would
  not run now either. It is a user script in the app's own content world,
  and each letter's line is wired with `addEventListener` where it had an
  `onclick`. A letter's markup cannot see it or call it, nor post to the
  `bmLetter` handler, which is registered in that world alone; a single
  letter's page gets nothing wired, whatever the letter draws. A tap does
  what it did: the line opens or closes its letter, a letter opened is
  fetched if it has not been and marked read, and the header and the
  toolbar move to it.
- The pane loads its own pages and nothing else. The one navigation allowed
  is the page the pane hands WebKit, `loadHTMLString` with no base URL,
  which WebKit loads as `about:blank` in the main frame. Every other page in
  the pane, every frame inside a letter, every form sent, back, forward and
  reload are cancelled. A tapped link does what it did: "Open this link?"
  with the site's name, then Safari, or this app's composer for `mailto:`,
  a link aimed at a new window or a frame included. A letter that sends the
  pane to `about:blank` itself can empty its own page, and do nothing else.
- Nothing of WebKit's is kept on the iPad (`websiteDataStore =
  .nonPersistent()`): the pictures' cookies and cache last as long as the
  web view does, in memory.
- Pictures from the web still load, as they always have, and a tracking
  pixel among them still tells its sender the letter was opened. Blocking
  them is the owner's to decide, and open. The comment now says so.

What he may notice: nothing, on nearly every letter. A letter that
refreshed itself or sent the pane elsewhere stays where it is, and a form's
button does nothing. A letter built by its own script, almost none in
email, shows what it has without it. On a later iOS, whose WebKit reads
`<noscript>` as markup when script is off, a letter's `<noscript>` content,
which never showed, may.

**Links in plain letters** (`TextLinks`, `PanePage`). `http://`,
`https://`, `www.` and `mailto:`, found as Mail finds them: not run on from
a word, to the first space or line break, quote, bracket or ellipsis, with
the sentence's full stop, comma or closing bracket given back to it, so
`(see https://example.com/a).` links `https://example.com/a` and a
Wikipedia address ending `_(film)` keeps its bracket. A `www.` address goes
to `http://`. In the pane's link blue for plain text, `#0A84FF`, which the
page has always set and nothing used. A tap goes where a tap on any link in
a letter goes. The text is cut into words and links before anything is
escaped, and every piece is escaped, so nothing of the sender's reaches the
page as markup, and a letter with no link in it comes out byte for byte as
it did.

In HTML letters too, in their text only: never in a tag or an attribute, a
comment, a `<script>`, `<style>`, `<textarea>` or `<title>`, and never
inside a link the sender wrote. The link is the text as it stands, so it
reads as it did. Where HTML can hold a sender's link open in ways a pass
this simple cannot see, it stops, and the rest of the letter is as it
came: at `<svg>`, `<math>`, `<noscript>`, `<select>`, `<plaintext>`, a
`<script>` with a comment in it, anything left unclosed, and after a
sender's link that encloses a table, a cell or the like. There an address
Mail would link stays words. A bare address such as `sam@example.com` is
not made a link; Mail makes it one.

Faster, as it happens: the escaping is done a byte at a time as the links
are found, not by `replacingOccurrences` on each piece. Release build on
this host: a plain letter of a megabyte with no link, 13 ms where
`replacingOccurrences` took 118; a megabyte of nothing but links, 29,000 of
them, 22 ms; an HTML megabyte, 8 ms more than it took.

**Cc** (`MessageHeaderView`, `MailFormat`). Under To, in To's font, colour
and inset: "Cc: Jane Example, sam@example.com". Names, and the address where
there is none, as Mail writes them, and the To line the same way, so
`<jane@example.com>` reads `jane@example.com`. No Cc, no line, and a letter
without one lays out as it did. The header is drawn from the list's row at
the tap, and the row carries the Cc, so the line is there from the tap
(decided 2026-10-01, below); opening another letter of a conversation moves
the stack a line when one has a Cc and the other none, as the files' rows
already do, the header changing to that letter once it has come. To and Cc
are split between addresses, not at every comma:
`"Example, Jane" <jane@example.com>` is one recipient where it was two,
`"Example` and `Jane" <jane@example.com>`, and a name whose comma is inside
an encoded word is split only once decoded. Reply All goes to each such
address once, where it put `"Example` among the letter's recipients. A
list with a quote or bracket never closed is split at every comma, as
before.

**Tested** in the host suite.

- `PaneNavigationTests`: the decision for every kind of navigation, in the
  pane, a frame and a new window, and the pane's own page the only one
  loaded. And, read from the view controller's source, which the host
  cannot build: script off and the data kept in memory, set before the web
  view is built from them, when WebKit copies them; the user script in the
  app's world; the handler and the fill there and nowhere else; every
  navigation through `PaneNavigation`.
- `ConversationDocumentTests`: no script and no handler written in the
  stack's page; the user script's wiring, and nothing wired on a letter's
  own page.
- `TextLinksTests`: the kinds, the ends, what is not a link, nothing twice,
  the escaping, HTML's text only, what is left alone, 1,500 seeded letters
  that gain links and nothing else, and the work counted on 25 letters
  built to make it grow: four times the letter is four times the steps, at
  most four steps a byte.
- `PanePageTests`: every letter with no link comes out byte for byte as
  before, the one with a link differs by its `<a>` alone, and an HTML
  letter's links in its page and its stack body.
- `ReadingPaneCcTests`: the split, the names, the lines, the header's wiring
  from its source, and a letter read by the repository from the scripted
  server, with Reply All from it.

Each of 59 sabotages (a rule reverted, a setting taken out or moved after
the web view is built, the script put back in the page, the Cc line or its
split undone) fails at least one of these. Checked outside the suite and
not kept: the stack's script run in a DOM (jsdom) on the pane's own pages,
taps opening and closing letters and telling the pane as before, a body
put in, and a line a letter draws never wired; and 18,000 generated HTML
letters, linked and read back by an HTML5 parser (html5lib), their trees
unchanged but for the links, no link inside another or outside the text.
The one difference, in 19 of them, was a space left inside a `<table>` the
parser had moved the text out of, which draws nothing.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, before the branch
was merged. Letters drew as before, a newsletter's pictures from the web
with them. In a conversation of four, a letter's line opened it, its body
came and the header moved to it, and the line closed it again. In a plain
letter the Google addresses were links, and a tap asked "Open this link?"
over "myaccount.google.com", Cancel and Open. A letter sent to the account
with the account in Cc showed its Cc line, the account's own address,
under To in the first frame after the tap, the header the same height when the letter had
come. Not made by hand: a letter that runs a script, navigates, frames or
submits, which the suite stands for.

**Decided 2026-10-01.**

- *A long press on a link* brings up WebKit's own menu and its preview, as
  a long press does in Mail, and is left so: `allowsLinkPreview` stays on,
  and nothing was changed. The preview loads the page without "Open this
  link?", for an HTML letter's links as before and for every address in a
  plain letter now.
- *The Cc line is there from the tap.* It used to arrive with the letter
  and move a conversation's stack down a line under him, where B-042 has
  the header its final height from the tap. The list's rows now carry the
  Cc (`MessageSummary.cc`) from the ENVELOPE every row is fetched with
  already, `Name <address>` or the address alone, and the header drawn at
  the tap names them as it names the Cc header's (`Message.heading`), so
  the line it lands with is the line it had: a name with a comma in it, a
  name in an encoded word, and an address with no name read the same both
  ways. The list's FETCH is what it was, `(UID FLAGS INTERNALDATE
  RFC822.SIZE ENVELOPE BODYSTRUCTURE X-GM-LABELS X-GM-THRID X-GM-MSGID)`,
  and nothing more is asked. The page kept on the iPad (D-016) keeps a
  row's Cc with it, as `"cc"` in its record, absent for a row with none and
  in a page kept before, which reads as none, so no new format: a row kept
  so gains its line as the letter lands, as every row did, until the next
  page. A Cc holding no address the ENVELOPE can give, an empty group such
  as `undisclosed-recipients:;` or a word with no domain, still gains its
  line as the letter lands, and a group's name, which the ENVELOPE leaves
  out, is in the line only once the letter has come. To still reads "To:
  me" until the letter lands, one line either way.
  Tested in `ReadingPaneCcTests` (the line at the tap word for word the
  line the letter lands with, before anything of the letter is fetched,
  and the list's FETCH as it was), `PaneLoadsTests` (the stand-in header
  carries the row's Cc) and `MailShelfTests` (kept and read back, and a
  page kept without it read); four parts of it undone one at a time in a
  scratch copy, each fails them.

**Open, for the owner.** Whether letters' pictures from the web load
(the spec asks for them blocked by default if feasible). A bare address is
not made a link.

---

## B-056 — CHANGED 2026-09-30 and 2026-10-01, seen on the iPad. A new password waited for a relaunch, a refused sign-in read as "Can't connect", and the signature could be lost for good

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
  letter. A password IMAP takes and SMTP refuses, 535, is not kept: "Gmail
  took that password for reading mail but refused it for sending. Make the
  app password while signed in to Google as <his address>. If you are sure
  it was made as <his address>, wait an hour and try again." (the last
  sentence since 2026-10-01, below). A submission server that cannot be
  reached, or says "not now", does not stop a password IMAP has just taken:
  a Wi-Fi that blocks port 465 must not leave a revoked password in place.
  Nor, since 2026-10-01, does SMTP's 534 (below). Under the Settings
  password field: "Make one at myaccount.google.com/apppasswords while
  signed in to Google as <his address>." A setup Connect whose save fails
  now says "Password could not be saved." rather than "Could not reach
  Gmail".
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
  the same of IMAP's refusal under their button. WEBALERT's address, a
  sign-in link into his account, is left out; the log keeps the whole
  line. The watch signs in
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

**Decided 2026-10-01** (`SignInCheck.outcome`, `SMTPClient.checkSignIn`).

- *SMTP's 534 at the check keeps the password.* A password IMAP had just
  taken was thrown away when the submission server answered 534, Gmail's
  "Please log in via your web browser", and the helper read only "Gmail
  refused the sign-in. Your old password is still in place.", with the old
  password, perhaps revoked, still in place. Now it is saved and signed in
  with at once, as a password that works is: Settings closes, or setup
  gives way to the mail, and the screens are built again over it. Once they
  are on the screen, an alert, "Cannot Send Mail", with OK: "Gmail accepted
  the password for reading mail but is refusing to send for now. The
  server returned the error: <Gmail's words>", or the first sentence alone
  where Gmail gave none. Gmail's words are kept as an IMAP ALERT's are
  (`SMTPClient.refusalText`): the reply's lines without their codes, run
  into one line of printable characters, at most 300, the sign-in address
  for the account Gmail writes in angle brackets left out, as WEBALERT's
  is, and the server's tag at the end, an id and "- gsmtp", left out too.
  Gmail's 534 runs over eight lines, the address broken over the first
  five of them and its ">" followed by the sentence, as Gmail's users
  quote it (Atlassian's help page for AuthenticationFailedException;
  Esko's KB182042961), so the address is left out from its "<" to its
  ">" whatever lines lie between; a "<" nothing closes is kept as written.
  It reads "Please log in via your web browser and then try again. Learn
  more at https://support.google.com/mail/answer/78754". As first built,
  only a word both opened and closed by the brackets was left out, so the
  address's pieces were kept, filled the 300 and left no room for the
  sentence; the test's 534 had the address on one line, as none of
  Gmail's quoted has, and passed. The test's is Gmail's own now, line for
  line, with a made-up token.
  Only the check carries them: a letter's 534 is said as before, "Gmail
  refused the sign-in.", and keeps every rule it had: his own Send keeps
  the sheet, and the Outbox stops at the first letter it meets until a Send
  of his goes, the app is launched again, or a password is saved.
- *SMTP's 535 at the check* is still not kept. Gmail is said to answer
  535 too while it turns away an account's sign-ins to send for a while,
  and then a password made in the right account would fail the same way,
  and so would the next. B-033 first took its afternoon's 535s for that,
  before the wrong account was found to explain every one of them, so no
  535 of that kind has been seen here; the sentence covers it all the
  same. The wrong-account sentence now ends "If you are sure it was made
  as <his address>, wait an hour and try again.", with the account's
  address, before Settings' "Your old password is still in place."

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
this one has it first, then OK. "Cannot Send Mail" is the title Mail's
alert has when its outgoing server turns it away, as its users quote it
(Apple's forums, threads 6755569 and 254409204); the 534 sentence after it,
and the 535 sentence's last, are the app's own.

**On the wire.** Nothing changes until a sign-in is refused or a password is
saved; the everyday wire is as it was. The connection log gains
`SIGN-IN CHECK host=smtp.gmail.com:465` and `SIGN-IN CHECK imap=ok
smtp=refused`, `smtp=sign-in-refused` or `smtp=not-checked`, and
`PASSWORD-SAVED signed in afresh`: no address, no password, nothing of a
letter. A password kept at a 534 logs `smtp=sign-in-refused` and then
`PASSWORD-SAVED signed in afresh`.

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
caught). Each fails with its part of the change undone. For 2026-10-01,
`SignInTests` again: Gmail's eight-line 534 at the check, the password
kept, the alert's words exact for both forms, the next LOGIN carrying it,
the Outbox stopped at the next pass and his Send refused; Gmail's words
read out of a 534, its address left out over five lines and over two, a
"<" nothing closes kept; the 535 sentence word for word; and, read from
their source, Settings and setup keeping what the check keeps and handing
on the alert, and the screens built again putting it up. Fifteen parts
of it undone one at a time in a scratch copy, each fails at least one.

**Seen on the iPad, 2026-09-30**, on carlo's mailbox, before the branch
was merged. Settings has Restore Original Signature and, under the
password, where an app password is made. "Send my signature as plain text
instead" asked "Send Signature as Plain Text?", and Restore Original
Signature asked first too; both cancelled. Sixteen wrong letters as a new
password: refused, and Refresh then said "Updated Just Now" on the old
one. That refusal was first said at the foot of the sheet, under the
keyboard, and Save seemed to do nothing; what Settings has to say is now
under the password field, the keyboard put down and the line scrolled
into view (`say`), and seen there. Not made by hand: a password revoked
and replaced, a 534 and a 535 at the check, which need the account's
Google settings.

---

## B-057 — CHANGED 2026-10-01, seen on the iPad. A crash at every launch would have ended the app for good, and so would a letter the Outbox crashed on

**Found in the code 2026-09-30**, going through what would end the app for
good once it is on his iPad with no way to update it. Nothing counted
launches, and nothing knew that a launch had crashed:

- What a launch reads before its first frame, and in the second after it,
  is what the launches before it kept: the copy of his mail and the Inbox's
  page (D-016, B-053), two panes or three (D-015), Organize by Thread, Go to
  Date's last scope and day, the layout sweep's switch, and every
  `letter.json` in Local Drafts, which Drafts, the Outbox and the sidebar's
  count read. A file that cannot be read was handled already: the copy
  deletes it, Local Drafts passes it over. A kept row, a saved choice or a
  letter that reads cleanly and trips a fault in drawing or in the code
  behind it would have crashed every launch, before anything was sent.
- The pass that takes the letters kept on the iPad to Gmail (B-051, B-052)
  runs about a second after every launch's first page. What it learned of a
  letter, a refusal, lived in memory until the next launch, and the only
  marks it wrote on disk, the version tried before an APPEND and the
  Message-ID before DATA, are written once the letter has been read and
  built. A letter whose building or sending crashed the app, a photo's file
  that breaks the builder for one, would have crashed it a second after
  every launch, and he could not have told which letter it was. B-051 declines to open the composer at
  launch for that very reason; the pass had the same shape.
- Either way the only way out was deleting the app. That takes Local Drafts
  with it, the only copy of what he has written and not yet sent, cannot be
  undone on a sideload, and needs a new app password, which he cannot make
  himself.
- A first keep that failed on a full disk left the letter's folder with its
  photos linked into it and no `letter.json`. Nothing listed it and nothing
  took it away, and once the launch's purge had emptied the staging it held
  the only link to each photo: a few megabytes each time the disk filled,
  never given back. Made on the scripted store, not on the iPad.

**What he sees now.** Nothing, as long as launches finish. A launch has
finished when the app goes to the background, however soon after it
started, when it is ended while still running, which is what a swipe in the
app switcher should be if it does not go through the background first (not
yet seen either way), or half a minute after the first page has been drawn
and the first pass over the letters on the iPad has ended. He often opens the app,
glances at it and leaves within seconds; that always sends it to the
background, so it never counts against the next launch. A crash, or iOS's
watchdog ending an app that does not answer, does none of these. After
launches in a row that never finished, the next one starts without what
they read, in steps, each with the ones before it:

- After two: no kept page. The copy of his mail is thrown away, as a
  password saved throws it away (D-016), and the view settings go back to
  their defaults: three panes, Organize by Thread on, Go to Date in the
  folder he is in and at today, the layout sweep off. The Inbox is empty
  under "Checking for Mail…" until its page comes, and the folder pane is
  names until the counts come, as at the first launch. His account, his
  address book, the signature's pictures and every letter kept on the iPad
  stay.
- After three: no pass over the letters kept on the iPad in that launch.
  Nothing in Drafts "On this iPad only" goes to Gmail by itself, and nothing
  in the Outbox is sent by itself, at the first page, on coming back, at the
  watch's check or as he leaves. His own Send and Save Draft go as ever. The
  next launch passes as usual.
- After five: the letters kept on the iPad are moved, folder and all, to a
  folder beside it, `Application Support/Local Drafts set aside 2026-10-01
  14.03.07`, the date and time of that launch on the iPad's clock, and the
  app starts with none: Drafts lists only Gmail's, and there is no Outbox.
  Nothing is deleted. Every letter, photo and quote is there as it was, file
  for file, and so is the count of passwords saved (B-051), which goes on in
  the new store as a copy, so a letter put back later compares with it as it
  did. Set aside again in the same second, the second folder's name ends
  " 2". With no letter in the store, nothing is moved. Settings then has
  Bring Back Set-Aside Letters (below).

**Where letters set aside are, and who can reach them.** In the app's own
data container on the iPad, beside `Local Drafts`, which nothing on the iPad
shows him or a helper: not Files, not iCloud, since the folder keeps the
store's exclusion from backup, and not a Mac's Finder. Before Bring Back
only a developer could reach them, with the app ended, by moving the folder
back as `Local Drafts`.

**Bring Back, decided and built 2026-10-01.** Settings has a row under
Organize by Thread, "Bring Back Set-Aside Letters", in the same blue as
Restore Original Signature and there only while a folder set aside holds a
letter, as that one is there only while there is a signature to restore.
It asks first, as Mail asks, in an alert: "Bring Back Set-Aside Letters?",
then "Letters on this iPad that were set aside when Blackmail could not
start will go back to Drafts and the Outbox.", and Cancel and Bring Back,
Bring Back not red since nothing is lost by it. Then each letter's folder,
a folder with a `letter.json` whether or not it can be read, is moved from
every folder set aside, oldest first, back into `Local Drafts`, by a rename,
file for file. Each comes back as it went: a draft to Drafts, with its own
unfinished tries, to go by the pass as any other, from the next launch when
this one holds the pass; and a letter he sent to the Outbox, with what may
already have reached Gmail still to be looked for (`unsettled`), held, as
one the pass has given up on (decided 2026-10-01, below). Its row says "Not
sent automatically. Open it and tap Send.", or "May already have been
sent." for one whose DATA went, and it goes only when he does that, once,
his Send asking Sent Mail first as ever (B-052). Taken out of the Outbox,
as first proposed, it would have sat in Drafts unsent with nothing to tell
him so. Nothing is written over. A letter whose
name is taken in `Local Drafts` comes back beside the one there, under a new
key, a UUID as the composer makes one, its `letter.json`'s key written as
that name first, where it is set aside, since the store reads a letter only
under the key it names; so does one whose `letter.json` names another key
than its folder's, which is what an end between those two writes leaves,
and which then comes back the next time. A key is made once, at random, so
a second folder of one name can only be a second copy of one letter, and
two of it in the Outbox would send it twice: such a letter comes back held,
as one the pass has given up on, and goes only when he sends it or saves
it. One that cannot be read, or is of a format this build does not know,
comes back as it is, under a new name if its own is taken, and stays
unread, as it was. A folder set aside goes once it holds no letter, with what else is in it: the
copy of the count of passwords saved, which `Local Drafts` has gone on from
since, and folders a failed first keep left, which a launch would have
removed. Nothing else is deleted, and the count of passwords saved in
`Local Drafts` is left as it is. It takes no step and leaves the launch
count as it is. A letter brought back that crashes the pass is held by its
own tries, the launches it ends charged to it (below), so it costs no stage.
One whose listing crashes the app crashes every launch: the count climbs,
five set the letters aside again, and the row is there again.

**One letter at a time.** Each try the pass makes at a letter is written
down on it, `autoAttempts` in its `letter.json`, just before the pass takes
it, and cleared when the try returns or throws, whatever came of it: what is
left after a launch is tries the app did not live through. A try that cannot
be written down is not made, and the letter waits. At three such tries, the
pass passes the letter over. It stays where it is and counts among the
unsent, and its row says so, in the Outbox as the line under whom it is to,
"Not sent automatically. Open it and tap Send.", and in Drafts under "On this
iPad only", "Not saved to Gmail automatically. Open it, tap Cancel, then Save
Draft." Save Draft is not on the composer's bar but in the sheet its Cancel
brings up, so the way there is said a tap at a time; "Open it and tap Save
Draft", as first written, would have had him look for a button the screen
does not show. The words are the app's own; Mail has no such state to copy.
A letter in the Outbox with an attempt whose DATA went, which Gmail may have
delivered and which no pass now looks for in Sent Mail, says instead "May
already have been sent.", as one cut off before a password save does
(B-052): "Not sent" would have him write it out again, and that second copy
is what B-052 is there to prevent. Decided 2026-10-01, left as it is: that
line alone, with nothing of what to do. Whether to send it is his to choose,
and his Send asks Sent Mail first either way. Opened and sent, it goes once, as any letter in the Outbox goes: one with an attempt whose
DATA went is looked for in Sent Mail first, and found there, nothing more is
sent (B-052). Save Draft, his saving it, clears the count and gives it back
to the pass. Changed and put away, which the autosave keeps, or sent with no
connection and back in the Outbox, it stays his to send: the keep in front
of his Send carries the count, so a letter whose Send ended the app is not
taken up three more times by the pass. A letter that goes takes its count
with it.

A try cut short by the background does not count. iOS suspends an app in
the background once its time is up and may end it then, with a letter on its
way, a large draft above all, which goes up only as he leaves (B-051), and
that is no fault of the letter's. As the app goes to the background the
tries on their way are taken back, each letter's count as it was before the
try, unless his Save Draft has cleared it since; a try begun in the
background is not counted at all, and coming back counts them again. The
same as the app is ended while it runs (`applicationWillTerminate`): a swipe
in the app switcher mid-send is his doing and not the letter's, and if it
does not go through the background first, three of them would otherwise
give up on an ordinary letter. Only the count is written then: what the try itself wrote down, the version
tried before an APPEND and the Message-ID before DATA, stays, and the look
in Drafts or Sent Mail goes as ever (B-051, B-052).

So a letter that goes unasked only as he leaves, a draft carrying a
megabyte or more of photos or quote, or a letter in the Outbox with a
megabyte or more of files to fetch from Gmail (`LocalDraft.isLarge`,
`fetchesLarge`), is tried where no try is counted, and the limit seldom
holds it: only a try the pass begun as he left reaches after he has come
back, while it is still going, is counted, and leaving again takes it
back. Decided 2026-10-01, left as it is. Since B-072 his Refresh takes
such a letter in the Outbox in front of him, and that try is counted as
any other. A crash in the
background cannot trap a launch, which the background has already
finished, so it cannot end the app for good; and counting those tries
would let iOS's ordinary endings of a suspended app, for memory or for its
time running out, hold good letters. One that ended the app there would be
tried again at every leave, with nothing on its row.

**A launch a letter ended is the letter's, decided and built 2026-10-01.**
Counted against the launches as well as against the letter, a letter that
crashed the pass at every launch took the launches to their second stage
before its own third try held it: the third launch started without the
kept copy and with the view settings at their defaults, for a fault that was
the letter's. Now the pass marks each try it counts, just after the letter's
count has gone up, in `Application Support/Launches/trying`, the letter's
key and nothing else, and takes the mark away as the try ends or is taken
back. A launch finding it there ended during that try: the letter has
counted it, and the launch is not counted for it. The mark is removed, and
the launch counts from the launches before that one, said in the log and
written down. So a letter that crashes the pass at every launch is held at
its third try with the count never above one: nothing wiped, nothing reset,
and the fourth launch starts as any other. A launch that ends with no try
on its way counts as ever. A mark found with no launch unfinished is from
an end after the launch had finished, which counts against no launch
anyway: it is removed, and nothing is said. The cost: a crash
elsewhere while a try is on its way, in drawing, say, is charged to the
letter too, and three of them hold it. So each letter waiting can put the
stages off by its three tries, and no more: a letter held is never tried,
so never marked, and the launches after it are counted as ever. With two
letters in the Outbox and every launch ended a moment into the pass, both
are held by the seventh launch and the second stage comes at the ninth,
not the third; with ten waiting it would come after thirty, and every one
of them is held for a fault not its own, there to be sent with Send. A
limit on the charge would need a count of its own read at launch beside
the count and the mark; the mark does one thing, naming the letter whose
try is on its way, and the launch reads the count and the mark and nothing
more before it takes its steps. Decided 2026-10-01.

**How it is kept.** `Application Support/Launches/unfinished`: the launches
in a row that never finished, the one running among them, in decimal,
written whole by an atomic write and out of iCloud backup. Not
`UserDefaults`, whose writes reach the preferences daemon later and can be
lost to the very crash being counted. Counted first thing in
`didFinishLaunching`, before the purge of opened attachments, the copy of
his mail, the panes or Local Drafts are touched; set to 0 in
`applicationDidEnterBackground`, in `applicationWillTerminate`, which Apple
documents for an app ended while running and not suspended (whether a swipe
in the switcher goes through the background first is not documented), and at
the half minute (`SafeStart`). A file that is not a count a launch could
have written, empty, garbled, a word, a negative number, one over a
thousand, a directory in its place, is no count, and the launch writes its
own over it; a directory is removed first. A count that cannot be written at
all is a launch the guard does not see; nothing in it can stop a launch.
Beside it, `safe-starts.json`: each safe start's time, count, steps
(`kept-copy-wiped`, `view-settings-reset`, `passes-held`,
`letters-set-aside`) and the folder the letters went to, the last twenty,
dates as text, for an About screen to show one day; one that cannot be read
is begun afresh. A launch charged to a letter is written down there too, as
the step `charged-to-letter`, and so are letters brought back, as
`letters-brought-back` alone with how many came back (`broughtBack`), absent
from every other start, so the file's format stays 1. Beside them,
`trying`, the mark of the pass's try on its way: the letter's key, written
whole by an atomic write after the letter's own count has gone up, and
removed as the try ends, before the count is cleared, or is taken back,
before the count is put back, so an end between the two always leaves the
try counted against the letter, and against the launch as well, never
against neither. Read at launch before the count is written, and never the
letter it names: what the letters hold is not read before the steps are
taken. It is removed then, whatever is there, before the count is written.
A mark that is not a key the app could have written, empty, garbled, a word
with a space, a path, over a hundred characters, or a directory in its
place, is no mark, and the launch is counted. One that cannot be removed is
not taken either: left, every launch after would be charged to it, and the
guard would see none. One that cannot be written does not stop the try; the
launch is counted as well, as before there was a mark. The mark holds the
key and nothing else, and nothing but the pass's try writes it.
`autoAttempts` is
optional in `letter.json`, absent from a
letter no pass has left a try on and from one kept before it existed, which
reads as none, and written as three by Bring Back on a letter it brings
back held, so the format stays 1, as for `outbox`, `unsettled` and
`cutOff`. Every launch also removes each folder in `Local Drafts` with no
`letter.json` in it, which is what a failed first keep leaves
(`LocalDraftStore.removeLeftovers`). A letter's words are only ever in its
`letter.json`, so nothing he wrote goes; a folder with one is never touched,
whatever else is in it and however it reads.

**In the connection log**, nothing of a letter: `SAFE-START
charged-to-letter` when the last launch ended in a letter's try, then
`SAFE-START unfinished=2`, then each step as it is taken, `SAFE-START
kept-copy=wiped`, `SAFE-START view-settings=reset`, `SAFE-START
automatic-pass=held` and `SAFE-START local-drafts=set-aside folder="Local
Drafts set aside 2026-10-01 14.03.07"`; `SAFE-START brought-back=3` at
Bring Back; `DRAFTS-LEFTOVERS removed=1`; and once a launch for each letter
passed over, `OUTBOX-HELD unfinished-tries=3` or `DRAFT-HELD
unfinished-tries=3`. A letter brought back into the Outbox says
`OUTBOX-HELD unfinished-tries=3` too, its three written by Bring Back and
not by tries.

**On the wire.** Nothing changes for a launch that finishes: the everyday
wire and the launch's commands are as they were. A launch after two that
did not finish sends what a launch with nothing kept sent (B-053), and one
after three no pass's commands.

**Left as it was, and why.** The account, the address book and the
signature's pictures are not reset: none is drawn in a way a layout can trip
on, the share extension is handed them, and none can be had back once gone.
A crash after the half minute, or after a return from the background, is
not counted: the guard is for launches that never get going, and a letter
that crashes the pass on coming back is counted by its own tries. A pass
that hangs without crashing holds the launch short of its half minute until
he leaves, and leaving finishes it; the hung letter's try is taken back as
he leaves, so a hang is not counted against a letter. The share extension
keeps no letters and runs no pass (B-052): its letters go at Send as they
did, and it counts and holds nothing. The figures, two, three and five
launches, three tries and half a minute, are judgement, not measurement:
two allows one crash that was nothing to do with what is kept, and three
tries allow two. A letter that crashes the pass at every launch no longer
takes the launches to their second stage before its own third try: those
launches are charged to it (above). There is
no hook to make the app crash on purpose; each
stage is made by hand on the iPad, with the app ended, by writing the count
or a letter's tries into their files (TODO).

**Tests.** `SafeStartTests`, over an Application Support of the test's own,
defaults of its own and a clock it moves: ten quick looks then leaving count
nothing; a launch that neither leaves nor reaches the half minute counts,
one that dies at twenty-nine seconds too, its wait still asleep then; the
half minute runs from the later of the first page and the end of the first
pass, and is waited for once a launch; a count empty,
garbled, a word, negative, over a thousand, the largest number there is and
one far past it, and a directory in its place, each reads as none and is
written over, and with nowhere to write it the launch still starts; one
unfinished launch changes nothing; two take the kept page and the folder
list away and the five view settings back to their defaults, leaving the
account, the book, the pictures and every letter byte for byte, the count
already up as each step is said, so a launch that crashes in its own steps
is counted; three and
four hold the pass as well; five set the letters aside, every file byte for
byte, the new store empty with the count of passwords saved, the old one
reading as it did, a second in the same second under " 2" and none when
there is nothing; the steps written down, read back, a damaged record begun
afresh and twenty kept; a folder without `letter.json` removed at launch and
one with a file cut short, of another format or with a stray file spared;
the five keys are the screens' own, read from their source; where the app
counts, finishes and tells the store, and that an end while it runs takes
the tries on their way back, read from the UIKit source; and the
share extension's sources name none of it, and what it is handed stays.
`OutboxTests`, over the scripted servers: a try on disk before the
submission server is reached and while its letter goes, cleared when it is
refused, and a draft's while its APPEND is out and once refused; a try the
app does not live through found at the next launch, the format still 1; a
try taken back as the app goes, its DATA's record kept, one begun in the
background not counted, one after coming back counted; one taken back
leaving his save's count; a try that cannot be written down not made, not
even a connection; three tries and the letter and a draft passed over,
saying so, the letter after them going, the log saying so once, and two
tries still going; the DATA cut off, two launches ended in the look in Sent
Mail, the fourth passing it over, its row saying it may already have been
sent, and his Send asking Sent Mail first and sending nothing, one letter
ever; his Send of a held letter going once, the
autosave and an offline Send keeping it held, Save Draft giving it back to
the pass; a held launch sending nothing while his Send goes; and a wait for
the pass ending only with the pass. Each fails with its part undone in a
scratch copy, fifty-three sabotages one at a time, each failing at least the
test named for it: the count not written at launch, or written only after
the steps; the background, or an end while running, not finishing the
launch; the half minute not waiting for the pass, not waited at all, cut to
five seconds or to none, or waited for twice in a launch; a count no launch writes taken at its word
(the largest number there is then crashed the launch that counted on from
it); a directory left in the count's place; each step left out, and taken a
launch early or late; the letters deleted rather than moved, the count of
passwords saved not carried, a second set aside in the same second given no
name of its own; the steps not written down; leftovers left, or taken with
their `letter.json`; a view setting under another key, or every one of his
defaults reset, the account and the book with them; the count, the
background, an end while running, the setup form, the first page, leaving,
coming back and the shared store each not wired, and an end while running
not taking the tries back; the share extension's code reaching for the
tries. And for the tries: none written down, one written
after the try, one not cleared, a held letter still taken, held after four,
either row without its words, a held letter whose DATA went saying it was
not sent, the background not taking tries back, tries
counted in the background, coming back not counting them, a try taken back
over his save, every keep clearing the tries or Save Draft carrying them, a
wait for the pass returning at once, nothing said in the log, a try that
cannot be written down made anyway, and the count not read back.

**Tests for the charge to a letter and Bring Back**, 2026-10-01.
`SafeStartTests`: a launch finding a try marked is not counted for it, the
mark taken away, said and written down, and the launches before that one
counted as ever; with none unfinished the mark goes and nothing is said; the
letter's folder is never there to be read. A mark empty, garbled, a word
with a space, a path, over a hundred characters, or a directory in its
place reads as none, the launch counted, and goes; one that cannot be
removed is not taken. Bring Back moves every letter set aside back file for
file, the one that cannot be read with them, beside one written since, the
one in the Outbox written held first (since 2026-10-01, below); the
folder goes; the store's count of passwords saved stays its own and the
launch count as it was; the lists are told; it is said and written down. A
name taken keeps both: the one there as it was, the one coming back under a
new key made as a key is, its photo byte for byte, read and held; one
written under another key comes back under its folder's name, held; one
that cannot be read and one of another format each under a new name, byte
for byte. The older folder set aside comes back first. A folder set aside
goes only once it holds no letter, with nowhere to put them every letter
stays set aside, the one in the Outbox held where it is, and a second Bring
Back brings them. The row's count is
nothing for no folder, one holding only the count of passwords saved and a
leftover, a folder of another name and a file of that name. Settings' row,
its alert's words and its wiring, and the app's `LocalDrafts` marking its
tries, are read from their source. `OutboxTests`, every one now marking its
tries as the app does: a letter ending three launches in a row, its DATA
cut off and then the look in Sent Mail twice, is held at its third try with
the count never above one, the kept copy and the view settings left, one
DATA ever, and the launch after, with no try on its way, is counted; a try
sent, refused by the submission server, refused by Gmail's Drafts, taken
back as the app goes, begun in the background, or not written down on its
letter leaves no mark, and a launch ended after them is counted; letters
set aside and brought back: the draft goes up by the pass once, and every
letter in the Outbox comes back held, saying so, and goes only by his Send,
once (since 2026-10-01, below). The held
draft's row has its new words. Each fails with its part undone in a scratch
copy, thirty-eight more sabotages one at a time, each failing at least the
test named for it: the mark not taken at launch, taken with no launch
unfinished, not said, not written down, left in place, taken when it could
not be removed, taken at its word, or its line ending kept; the pass not
marking its try, marking it before the letter's count, a try ended or taken
back leaving its mark, and the app's `LocalDrafts` marking nothing; the
held draft's row in its old words; nothing brought back, a taken name
written over or left set aside, the key not written as the new name, or
only when it was the folder's, a letter under a new name not held, one that
cannot be read left set aside on a clash, one of another format written
over; a folder set aside removed with letters in it, or kept once empty; a
folder without `letter.json` counted as a letter, a folder of any name taken
for one set aside, the newest first, no store made to bring them into; the
count of passwords saved set aside carried back; bringing back not said,
not written down, resetting the count, or not telling the lists; and
Settings' row always shown, bringing back without asking, its button red,
the lists not told, or the row left after. Not made to fail: the order of
the mark and the count in a try's end, as it is taken back, and at launch,
which only an end between two writes would show.

**Tests for the charge**, 2026-10-01. `SafeStartTests`: the mark is the
letter's key and not a byte more, written in one place; `launch` reads the
count and takes the mark and opens nothing else before its steps, a letter
that cannot be read and a stray file beside the count changing nothing it
decides. `OutboxTests`: two letters in the Outbox and every launch ended
in a try, the DATA held or the look in Sent Mail: each held at its third
try, the count at one through the seventh launch, then counted, the
second stage at the ninth and the pass held at the tenth, one DATA each.

**Tests for letters brought back held**, 2026-10-01. `SafeStartTests`:
Bring Back brings the drafts back byte for byte and the letter in the
Outbox held, its `letter.json` as it was but for its count of unfinished
tries; with nowhere to put them, the letter in the Outbox is held where it
is set aside. One whose `letter.json` cannot be written where it is set
aside stays there while the rest come back, by a folder that cannot be
written and by every write failing where a rename goes, as on a full disk,
and comes back held the next time; one held already comes back as the same
file, never written again; one whose `letter.json` cannot be read stays set
aside, and comes back held once it can be. `OutboxTests`: a draft and two
letters in the Outbox, one waiting and one held by its tries, set aside and
brought back: both letters held, both rows "Not sent automatically. Open it
and tap Send.", the draft up once and nothing of the Outbox sent at that
launch or the next; his Send of one with no connection leaves it held, with
the held notice, and nothing goes; his Send of each then goes once. The
notice is the held one for a letter held and the plain one for any other,
and the sheet asks for it by the letter's key, read from its source. Each
fails with its part undone in a scratch copy, eight sabotages one at a
time: only a letter under a new key held (15 failures), drafts held too (9),
a letter held already written again (2), its write failing and the letter
moved anyway (5), moved first and held after (5), a `letter.json` that
cannot be read moved anyway (5), the sheet's old notice (2), and the plain
notice for every letter (2).

**Not taken, and still to do.** Nothing tells him, or a helper, that a
safe start happened beyond the connection log, `safe-starts.json` and,
after five, the row in Settings; an About screen would. A crash that comes
later than the half minute in every launch is not caught by the count, only
by a letter's own tries if the pass is in it. The counting, the background,
Settings' row and its alert are UIKit and are read from their source on the
host; the pieces under them run here.

**Two questions about Bring Back, decided 2026-10-01.** A letter he sent
that began as a draft in Gmail hides that draft's row only while it is in
`Local Drafts` (`replacedInDrafts`). Set aside, the draft is listed again
and his Outbox is empty; if he opens the draft and sends it, Bring Back
would then have put the old letter back in the Outbox, unheld, and the
pass would have sent it a second time. Decided: every letter brought back
into the Outbox comes back held, the one waiting as well as the one the
pass had given up on, and goes only when he opens it and taps Send. Not
only the one whose draft in Gmail is gone: that look is made on the
server, and a letter brought back is no more sure to be wanted than the
day it was set aside, after which he may have written it again. Held is
its count of unfinished tries written as three in its `letter.json`, in
the folder it is set aside in, before the folder is moved: ended between
the two, it comes back held the next time, and one whose file cannot be
written stays set aside, never back unheld. A draft comes back as it was:
gone up twice, it is a second draft in Gmail, nothing sent. One whose
`letter.json` cannot be read when he brings them back stays set aside too,
for the next Bring Back: it may be a letter in the Outbox. His Send of a
letter held, brought back or held by its own tries, that cannot reach the
server leaves it in the Outbox, still held, and the sheet says so as it
closes: "Message is in the Outbox. It will not be sent automatically. When
the iPad is connected, open it and tap Send." (`Outbox.heldNotice`).
Before, it said the letter would be sent when the iPad was connected and
Blackmail open, which no pass would ever do.

And a fifth stage whose copy of the count of passwords saved could not be
written, on the full disk that may be what ended the launches, leaves that
count only in the folder set aside, which Bring Back removes. A password
saved after that, the store's count can equal the one stamped on a letter
whose DATA went, and the pass looks for it in a Sent Mail that may be
another mailbox's (B-033). Carrying the higher count back with the letters
does not close it alone, when the save came between: a save would also
have to count on from the highest count beside the store. Decided: left as
it is, recorded here. Bring Back leaves the count as it is, as decided
before. Since the decision above, the pass makes no look for a letter
brought back into the Outbox, which is held; his Send of one whose DATA
went still looks, under a row saying it may already have been sent.

**Seen on the iPad, 2026-10-01**, on the build before Bring Back and the
charge to a letter. A launch left on the Inbox read 1 in
`Launches/unfinished`, and 0 half a minute after its first page. A quick
look, out to the Home Screen within two seconds, read 0. Two launches ended
by `killall -9` left 2, and the third launch took the second stage. A
letter in the Outbox with `"autoAttempts":3` written into its `letter.json`
was held, its row's first line "Not sent automatically. Open it and tap
Send.", and his Send sent it once. Not yet seen: whether a swipe in the app
switcher finishes a launch, the third stage, the fifth and Bring Back, a
leftover removed, a held draft's row, three tries after a DATA that may
have gone, a try counted and one cut short by the background, and a launch
charged to a letter. The TODO says how to make each by hand.

**Seen on the iPad, 2026-10-01**, on the build with both, each case made
by hand with the app ended:

- A folder in `Local Drafts` holding only a photograph, and one holding a
  `letter.json` of one brace: the launch removed the first and left the
  second, and said `DRAFTS-LEFTOVERS removed=1`.
- A letter sent with no connection, then given `"autoAttempts":3` and an
  attempt whose DATA may have gone (`"unsettled"` with its Message-ID,
  `"unsettledSaves"` the count of passwords saved): the pass said
  `OUTBOX-HELD unfinished-tries=3` and sent nothing, made no look in Sent
  Mail, and the row read "May already have been sent." His Send then made
  the look, `UID SEARCH HEADER Message-ID` in Sent Mail, found nothing, and
  sent it once; it arrived once.
- Two drafts saved and a letter sent with no connection, their files
  summed, the count written as 5: the launch moved `Local Drafts` aside to
  `Local Drafts set aside 2026-10-01 03.42.06`, every file in it summing as
  before, wrote down the four steps, and started with no letters of his
  own. Settings showed Bring Back Set-Aside Letters at its foot; it asked
  "Bring Back Set-Aside Letters?", and Bring Back put all three back,
  every file summing as before, the set-aside folder gone, the step
  written down with `"broughtBack":3`, and the row gone with them. That
  launch held the pass, as the fifth does; at the next, the letter went
  once and the two drafts went up to Gmail once each. That was the build
  before letters brought back into the Outbox came back held (above).

**Seen on the iPad, 2026-10-01**, on the build with letters brought back
into the Outbox held. Wi-Fi off, a letter sent to the Outbox, its sheet
closing with the notice that it would be sent when the iPad was connected,
and a second saved as a draft; the app ended and the count written as 5.
The launch set both aside, every file summing as before. Bring Back put
both back: the draft summing as before, the letter's `letter.json` not,
holding `"autoAttempts":3`, the step written down with `"broughtBack":2`.
The Outbox's row read "Not sent automatically. Open it and tap Send." His
Send of it, Wi-Fi still off, closed the sheet with "Message is in the
Outbox. It will not be sent automatically. When the iPad is connected,
open it and tap Send.", the letter still in the Outbox. Wi-Fi on, the app
ended and opened: the log said `OUTBOX-HELD unfinished-tries=3`, the draft
went up to Drafts by one `APPEND`, and nothing went to the submission
server; two minutes later the letter was still in the Outbox. His Send of
it then went once, one `MAIL FROM` and one `DATA` answered 250, and it
arrived once; one copy of the draft in Drafts.

Not seen by hand: whether a swipe in the app switcher finishes a launch,
which cannot be made over SSH; a launch charged to a letter, which needs
the app ended inside a try; and a held draft's row.

---

## B-058 — CHANGED 2026-10-01 and 2026-10-03, seen on the iPad. A letter dated wrong into the future would have taken every Go to Date jump for good

**Found in the code 2026-09-30**, going through what would go wrong for
good once the app is on his iPad with no way to update it (risk 15 of that
audit). Go to Date searched `SENTSINCE <day>`, by each letter's Date, and
landed on the oldest letter matched (`PageWindow.anchor`): the lowest UID,
the first of them to have reached Gmail. A letter whose Date is wrong into
the future, from a sender whose clock said 2037, matches every day before
its date. Arrived years ago, its UID is below every letter it is matched
with, and every jump lands on it: whatever day he asks for, the list opens
on that one letter, years earlier. Nothing on the iPad clears it but
deleting that letter, which nothing would tell him to do. The audit
reproduced it over 60,000 UIDs, the letter dated wrong at the tenth. His
Inbox goes back before 2016: years of other people's clocks.

**Changed.** The same SEARCH also asks that the letter arrived no more than
a week before the day: `UID SEARCH SENTSINCE "19-Jun-2019" SINCE
"12-Jun-2019"` (`IMAPDate.sentOnOrAfter`). SINCE tests INTERNALDATE, when
Gmail took the letter. A letter cannot arrive before it is written, so one
sent on or after the day arrives on or after it, give or take a sender's
clock running fast, which the week is for (`IMAPDate.arrivalSlack`). Mail
delayed on its way still matches, however late it came, and so does mail
fetched into Gmail later, by POP from another account, whose INTERNALDATE
is when it was fetched; mail copied in with its INTERNALDATE set from its
Date matches as any other. The jump still lands by the Date (as decided
for SENTSINCE), the week counted back in his calendar, in days. One string more in
the command that went before, so no round trip more. Every jump goes
through it: a folder's, and All Mailboxes', which jumps in All Mail.

**What it costs.** A letter whose Date is more than a week ahead of its
arrival is never where a jump lands for a day more than a week after it
arrived; it is still in the list where it arrived, and still shown in a
window that reaches its UID. A jump to a day after the newest letter rightly
dated now says "No mail on or after" that day, where before it landed on the
letter dated wrong.

**Tests.** `IMAPDateTests`: the criteria, the week back across the turn of a
year and over a leap day, and an evening in New York that is the next day
in UTC. `GoToDateBoundTests`, over the shipping repository and client, the
scripted server now keeping a letter's arrival apart from its Date
(`ScriptedIMAPServer.Letter.arrived`) and searching SINCE, BEFORE and ON by
it: an Inbox with a letter that arrived in 2014 dated 2037, two letters a
year from 2015 to 2020, one delayed three days and one from a clock two
days fast. Jumps to 2015, 2018 and 2020 land on the first letter on or
after the day;
one after the newest rightly dated finds nothing that recent; the delayed
letter and the fast clock's are found on their days; the letter dated wrong
is still listed at the foot; one SEARCH carries both dates. The bound
undone: 12 failures across the two classes, every jump landing on the
letter dated wrong. The week counted as seven times 24 hours, or in UTC:
the clocks going forward in New York, 1 failure. The jump days in the
tests are the test machine's own, so they pass in any zone.

**A letter copied in with a wrong arrival, decided and built 2026-10-03.**
Whatever copies mail into Gmail by APPEND, or by Gmail's import API, may
set INTERNALDATE from the letter's Date, so a letter dated 2037 copied in
before 2016 arrived, as far as Gmail says, in 2037: it passed the bound for
every day before then and took every jump. Not known: whether his old mail
was ever copied in so, and whether Gmail takes a future date on an APPEND.
The same SEARCH now has a third key, `BEFORE` the day after a week from
today by the iPad's clock, in his calendar, so arrived no later than a
week from today: `UID SEARCH SENTSINCE "20-Sep-2026" SINCE
"13-Sep-2026" BEFORE "11-Oct-2026"`. Such a letter is left out for as long
as its date is still ahead; once 2037 has come, it takes the jumps to days
before it again, which is eleven years off. Nothing that has really
arrived is left out, but with the iPad's clock more than a week slow.

**On Gmail.** RFC 3501 says SENTSINCE reads the Date header's own day,
"disregarding time and timezone". Gmail does not: on the iPad (below) it
matched a letter dated "Sat, 19 Sep 2026 18:30:49 -0700" to `SENTSINCE
"20-Sep-2026"`, the day of that moment in UTC, which is also the day of its
INTERNALDATE, `20-Sep-2026 01:30:50 +0000`. Which of the two Gmail reads
is not known: no letter on the test account has them on different days,
and one cannot be made from here (an APPEND with an INTERNALDATE of its own
needs the test account's password away from the iPad). If it reads
INTERNALDATE, a letter dated wrong but arriving when it did never matched
on Gmail, and the bound changes nothing a jump finds there; the letter
copied in with a wrong INTERNALDATE, above, was then the only way to the
failure, which the third key closes while its date is ahead. Either way, a day on Gmail runs from midnight UTC, so on his iPad
in Boston a jump to a day matched from 8 pm the evening before (7 pm in
winter): a letter that came in that evening was where it landed, and the
status line said the day before, "Showing September 19" for a jump to the
20th. That was so before the bound.

**His day, decided and built 2026-10-03.** The SEARCH still says which
letter the window is fetched around; where the jump lands in that window is
then counted in his calendar (`PageWindow.landing`): a landing dated before
his day moves up to the nearest newer letter dated on or after it, so the
evening before is passed over and the status line says the day he asked
for, or the next day with mail when his has none. East of Greenwich, where
a day counted in UTC misses his first hours of it, a landing moves down
over the older letters dated in those hours, and no others; in Boston there
are none, and a letter below the landing dated after his midnight is one
the SEARCH left out on purpose, dated wrong, and never moved onto. A letter
dated more than a week ahead is never landed on by this: a landing that is
one moves up as one before his day does. With nothing newer on or after his
day, the landing stays where the SEARCH put it; and if that is before his
day, or dated wrong, with every newer letter in the window, there is
nothing that recent, and he is told so, "No mail on or after" the day,
rather than "Showing" the day before: today asked for, with only last
night's 9.30 pm letter since midnight UTC, said "Showing" yesterday. No
round trip more: the window is fetched as before. The repository is given
his calendar (`IMAPMailRepository.calendar`, the iPad's as it changes),
which the tests set. The review of this found the first build's downward
move unbounded, and that in Boston it could reach only letters the SEARCH
had left out, dated wrong: a letter that arrived on the 5th dated the 25th
just below the first of the 20th, and the jump said "Showing September
25". It is bounded now to the hours from his midnight to midnight UTC.

**Tests for the third key and his day**, 2026-10-03. `IMAPDateTests`: the
`BEFORE` the day after a week from today across the turn of a year and on
an evening in New York that is the next day in UTC, in every criteria
string. `GoToDateBoundTests`, the Inbox now also holding a letter copied in
first with an arrival of 2037; four letters, two either side of midnight
UTC on 20 September 2019; and one at 10 pm on the 20th in New York: neither
letter dated wrong takes a jump; in New York the 20th lands on its first
letter, not 9.30 pm on the 19th, the 19th's letter just below; in Tokyo on
the first hours of the 20th, which were the 19th in UTC; the 21st, with no
mail of its own, on the next letter, the week ahead counted from today; in
another Inbox, today with only last night's letter since midnight UTC is
nothing that recent; and a letter left out just below the landing, that
arrived on the 5th dated the 25th, is not moved onto. One SEARCH carries all
three keys, in his calendar, the date his and not UTC's. `DateJumpTests`:
the landing moves up past rows of the evening before, to the next day's
first when his has none; east of Greenwich down over the first hours and
no further, not past a row of the day before; west of it never down; a
letter at his midnight is his day's; never onto a row dated more than a
week ahead, a landing that is one moving up; and it stays with no row on or
after his day above it. All of it passes with the test machine in UTC, New
York, Pago Pago, Tokyo and Kiritimati (UTC+14), where only an older test of
the spoken day, not of this, fails.
Each fails with its part undone, twelve sabotages one at a time: no
`BEFORE` (14 failures), the landing left where the SEARCH put it (9), no
week-ahead limit on the landing (2), the landing moved only up (3), the day
counted in the test machine's calendar rather than his (7), the move down
past a row of the day before (1), the SEARCH's date in the machine's zone
(1), the week ahead counted from the day asked for (1), his midnight
counted as the day before (2), no "nothing that recent" (1), the move down
unbounded, as first built (4), and a landing dated wrong kept (1).

**Seen on the iPad, 2026-10-01.** Go to Date in the Inbox to 20 September:
`UID SEARCH SENTSINCE "20-Sep-2026" SINCE "13-Sep-2026"`, answered OK with
9 UIDs in 80 ms, one SEARCH, and the list landed on the first letter of
the 20th, "Showing September 20". In All Mailboxes to the same day: the
same SEARCH in All Mail, landing on a letter sent at 9.30 pm on the 19th,
Boston time, "Showing September 19", on that build, for the reason above. In All
Mailboxes to 1 October, with no mail that day: "No mail on or after
October 1".

**Seen on the iPad, 2026-10-03**, on the build with the third key and his
day, the iPad's clock at 11.07 pm on 2 October in Boston. Go to Date in All
Mailboxes to 20 September: `UID SEARCH SENTSINCE "20-Sep-2026" SINCE
"13-Sep-2026" BEFORE "10-Oct-2026"`, answered OK with 16 UIDs, the same 16
as without the third key on 1 October, and the list landed on the first
letter of his 20th, "Showing September 20", the letter of 9.30 pm on the
19th just below it, where the same jump had said "Showing September 19".
The same again at 11.43 pm on the build with the downward move bounded and
"nothing that recent" after the evening before.

---

## B-059 — CHANGED 2026-10-01, seen on the iPad. The folder pane drew a read mark on the Inbox alone, and a sweep that left before a mark put the letter back

**Seen on the iPad 2026-09-30**, both older than the kept copy (D-016):

- After a read mark, All Mail, Important and Sent Mail kept their old
  number on screen until the next sweep, though the count under them was
  right, and kept so. `adjustUnreadCounts` patched the cell at
  `IndexPath(row: i, section: 0)`, `i` the folder's place in the flat list
  of folders; the pane has drawn its folders in blocks since the Inbox got
  one of its own, the Inbox alone in the first, so every other folder's row
  was looked for where there is none. Seen again on 2026-10-01: Sent Mail
  said 1 after the unread letter sent to himself was read and binned.
- At launch, a letter read while the sweep that follows the first page was
  out showed the Inbox as 1, then 2, then 1. The sweep had asked STATUS of
  the Inbox before his mark reached the server and landed after it, putting
  the old count back, here and in the kept copy, until the sweep asked for
  after the mark landed. Had that one failed, with no connection, the 2
  would have stood, and been drawn at the next launch.

**Changed.** The pane's folders and counts are a `FolderCounts`, which
runs on the host:

- Where a folder is drawn is its block and its row in it
  (`FolderCounts.place`), the blocks as the pane draws them
  (`FolderCounts.blocks`), so a mark is drawn on every folder it changes.
- Every count changed here by a read or unread mark, or an unread letter
  binned, made once the server has it, is numbered with what it did to
  the count (`adjust`). A sweep notes the number it starts at (`mark`).
  When it lands, a folder changed here since, whose count in the sweep is
  exactly the pane's before those changes, gets them put on it (`land`):
  its STATUS went before them. The kept copy, which the repository has
  just given the sweep's counts, is given these. Any other count the sweep
  brings is taken, as before. The sweep the pane asks for after the mark
  (`SweepCoalescer.requestIfRunning`, as before) starts after it and says
  what the server has, taken whole. A mark at none changes nothing, and
  holds nothing. While the pane has names and no counts, before the first
  sweep with nothing kept, a nought is put a mark on only when the sweep
  says that same nought, which was then the count.
- Built first to hold the pane's count over any sweep that left before a
  mark, the review found it would hold a count kept from the last launch
  over the server's: two letters come overnight to a kept none, he reads
  one as the launch sweep goes out, and the Inbox said none, and kept
  none if the sweep after it failed. A count held only when the sweep's
  is the pane's from before is never lower than the server's. What is
  left: when new mail and his mark both fall in one sweep, the sweep's
  count is taken, one too many until the sweep after it, as before.

No command is added or taken away; the sweeps go as before. A sweep whose
count was held over a mark says so in the connection log, with how many
folders and nothing else: `FOLDER-COUNTS held-over-sweep=3`.

**Tests.** `FolderCountsTests`: each folder found in its block at its row,
with the Outbox's block and with no Inbox; a read mark changing every folder
the letter is counted in, each drawn in its block, and never below none; a
sweep that left before the mark having it put on the counts of the folders
marked and taking the rest, the owed sweep and a later one with new mail
taken whole; a sweep that left after the mark taken whole; an unread mark
held, and a mark at none holding nothing; a count kept from the last launch
giving way to the sweep, whichever side of the mark its STATUS went, never
below the server's; new mail the sweep saw taken; a mark by the role word
holding the folder it matched; names with no counts giving way to the first
sweep but where it says the same nought; and the pane's wiring, read from its source, the sweep
asked for after a mark included. Each fails with its part undone, five
sabotages one at a time: the stale sweep taken whole (9 failures), the
pane's count held over any sweep that left before a mark, as first built
(8), a mark at none put on the sweep's count (5), every folder placed in
the first block (7), and no sweep asked for after a mark (1).

**Seen on the iPad, 2026-10-01.** A read mark with no sweep after it, the
log having nothing after the `UID STORE ... (\Seen)` but the letter's
FETCH and a NOOP: the Inbox and All Mail went from 1 to none together, and
back to 2 together on Mark as Unread of a conversation of two. At launch,
the app opened by hand and an unread letter tapped 0.7 s later, on the
build that held the pane's count over any sweep that left before a mark:
the sweep after the first page asked `STATUS "INBOX"` at 52.631, the read
mark went at 52.831, and the sweep landed with `FOLDER-COUNTS
held-over-sweep=3`, for the Inbox, All Mail and Important, all three
asked before the mark. On the build as it stands, tapped 0.6 s after
opening: `STATUS "INBOX"` at 55.057, the mark at 55.106, and
`FOLDER-COUNTS held-over-sweep=1`, the Inbox alone, All Mail and
Important having been asked after the mark and so already counting it;
the sweep owed after the mark went at once, and the counts read as the
server's at the end. The second between was not caught on screen; the log
line is what says the old count was not put back. The letters' read and
unread marks were put back as they were found.

---

## B-060 — CHANGED 2026-10-03, seen on the iPad. Sent Mail and Drafts named him on every row, not whom the letter was to

**Found** in the gap review of 2026-09-30, and in the code: every row in
the message list named its sender, the ENVELOPE's From, whatever the
folder. In Sent Mail and Drafts that is him, on every row. He sends some
seventy letters a day, half of them shared from Safari and YouTube, and
keeps about 1,900 drafts, and the only way to find the letter to Jane was
to read the subjects. A draft kept on the iPad, under "On this iPad only",
named him too, by his account's name. Mail names whom the letter is to in
those mailboxes. The Outbox alone did already (B-052).

**Changed.**

- The row carries whom the letter is to, from the ENVELOPE the list fetches
  already: `MessageSummary.to` and `bcc`, beside the `cc` it has carried
  since B-055. Nothing more is asked of the server; the list's FETCH is
  what it was.
- In Sent Mail, Drafts and the Outbox the top line names them (`RowNames`,
  `MessageThread.displayRow(in:)`): To, then Cc, then Bcc, each as the
  reading pane names a recipient, the name or the address where there is
  none (`MailFormat.recipientName`), each person once by address, joined
  by commas: "Jane Example, sam@example.com". A conversation names
  everyone he wrote to in it, the newest letter's first, with its count,
  "Sam Example, Jane Example (2)", as the Inbox's rows name everyone who
  wrote.
  A draft addressed to nobody says "No Recipients", the Outbox's words
  since B-052.
  Since B-075 the line is Mail's: the To alone, one person whole, two or
  more by short names joined "Jane & Sam", and a conversation marked
  after its date in place of its count.
- Which folder a row was listed from decides it, not what the letter is.
  A search of Sent Mail alone names whom. A letter of his found by an All
  Mailboxes search is listed from All Mail, and names him, as it does in
  All Mail and, sent to himself, in the Inbox: in a list of his letters
  and other people's, his name is what tells his apart.
- The drafts kept on the iPad name whom from the letter as he left it,
  under "On this iPad only" and as the copy each becomes on the server
  until Drafts is listed again. The Outbox names them by the same rule, now
  each person once.
- VoiceOver reads the names the row shows (`MessageThread.
  accessibilityLabel(in:)`, out of the list's controller, which put the
  label together itself): "Unread, Sam Example, Jane Example, 2 messages,
  Lunch on Sunday", then the time. No "To" before them, as none is shown;
  the folder says it, as on the screen.
- The kept copy (D-016) keeps the To and the Bcc with each row, an empty To
  as empty, so a draft to nobody says "No Recipients" at the next launch
  too. A page kept by a build before reads: its rows do not know whom they
  are to, and name their sender, as before, until the folder is next
  listed. No new format, and no "No Recipients" over every kept row in
  Sent Mail at the first launch of this build.

**Not changed.** The rows' order, newest first as the server gives them:
nothing sorts or groups by the name, and what makes a conversation is what
it was. The letter's own sender, which matching it with its twin in
another mailbox goes by (`ListEdit.twins`), and which the reading pane
shows as From. The pane's header: it still reads "To: me" from the tap
until the letter lands, though the row now has its To; using it there is
another change.

**Tests.** `SentRowNamesTests`: the names, To, Cc and Bcc, each person
once whichever way he is written, as the pane names them; Sent Mail, Drafts
and the Outbox naming whom and the Inbox, All Mail, Trash and a folder of
his own naming the sender; a hit from All Mail in Sent Mail's list naming
him, a search of Sent Mail alone naming whom; "No Recipients", alone, with
a count, and giving way to a letter in the conversation that has some; a
conversation naming everyone written to; a row that does not know naming
its sender; the name the only thing changed, and the order the folder's;
VoiceOver's label in Sent Mail, for a draft kept on the iPad, and in the
Inbox; the drafts kept on the iPad, the copy one becomes, and the Outbox;
over the shipping repository and client, the scripted server now carrying
a letter's Bcc, and reading a Cc and Bcc on an APPEND: Sent Mail's rows,
Drafts' with a draft to nobody and one saved with a Bcc alone, a search of
Sent Mail and an All Mailboxes search from it, and the kept pages of both;
the kept copy, an empty To kept as empty and a page kept before the To
naming the sender; and the list's wiring, read from its source. Each fails
with its part undone, 16 sabotages one at a time, counted in failing
tests: no row naming whom (11), every row in Sent Mail's list naming whom,
All Mailboxes hits included (2), the repository's rows without their To
(1), without their Bcc (1), the kept copy not keeping the To (2), keeping
an empty To as none (2), a row that does not know saying "No Recipients"
(2), a letter to nobody named by nothing (5), each person named as often
as the letter names them (2), Cc and Bcc left out (5), a conversation
naming its newest letter's people alone (4), the drafts kept on the iPad
without their To (2), the Outbox naming as before (1), VoiceOver reading
the senders (1), the list drawing its rows as before (1), and redrawing
them so when previews come (1).

**Put to the owner,** the most Mail-like built where Mail's way is not
known:

- Who the top line names: To, Cc and Bcc, each person once (built); To
  alone, as the Mac's Mail is believed to in its To column; or To, with Cc
  and then Bcc only when it is empty.
- A draft to nobody: "No Recipients" (built), the words Mail on the Mac
  marks such a draft with and the Outbox's; what Mail on the iPad shows
  was not found written down. Or the top line empty, or his name as before.
- His letters found by an All Mailboxes search: his name, as in All Mail
  (built); or whom, for a letter Gmail labels Sent or Draft; or "To: Jane
  Example" in a list that mixes his letters with other people's.
- VoiceOver: the names as shown (built), or "To" read before them in Sent
  Mail, Drafts and the Outbox.
- A conversation's count. The top line is short, some 168 points of
  17-point semibold in three panes, the default, and some 213 in two, and
  is cut off at its end with "…". Naming To, Cc and Bcc makes it longer,
  so in Sent Mail a conversation's "(2)" is often past the end of it:
  "Jane Example, Sam Exam…" for "Jane Example, Sam Example (2)". VoiceOver
  still reads it, as "2 messages". Accept it (built), as the Inbox's rows
  already lose theirs under a long list of who wrote; name To alone, one
  of the first question's other answers, which shortens the line without
  keeping the count on it; or put the count first, or fit the names to leave it
  room, either of which changes the row's layout, frozen to the
  reference.

*Decided 2026-10-06 by the owner, for all five: "copy apple mail for
these". Built in B-075.* Who: the To alone, as Mail on the iPad names it.
A draft to nobody: "No Recipients" kept; Mail's own string for its rows
is "No Recipient". His letters found by an All Mailboxes search: his
name, as built, which is Mail's. VoiceOver: the names as shown, as
built. The count: none on the names; Mail's chevron in a circle after
the date marks a conversation, and the names cannot push it off the line.

**Known since 2026-10-03.** Gmail keeps the Bcc on its copy of a letter
sent through SMTP, though the letter as sent carries none: the ENVELOPE of
"B-060 two" in Sent Mail, sent from the app to Sam's bare address, Cc Jane
and Bcc the test account, has the test account as its Bcc. So the Bcc is
named in Sent Mail too, as it is in Drafts, after the other names and past
the end of the line the row has room for, and a letter he sent to Bcc
alone names its Bcc there, not "No Recipients". Since B-075 the row names
the To alone, so neither the Cc nor the Bcc is named there, and a letter
he sent to Bcc alone says "No Recipients".

**Seen on the iPad, 2026-10-03**, on carlo's mailbox, every letter from it
to itself, with `+jane` and `+sam` before the `@` for Jane's and Sam's
addresses, in three panes. With no connection, the first launch of the
build drew Sent Mail's kept page at once, every row naming the test account
as before, none "No Recipients". Sent Mail: "B-060 one" read "Jane";
"B-060 two" "carlo+sam@blond…", cut off there; neither the test account's
name. The pane's header of "B-060 two": From the test account, To Sam's
bare address, Cc "Jane". The reply to "B-060 one" sent to Sam: the
conversation's row "Sam, Jane (2)", whole. Drafts: "No Recipients" for a
draft to nobody; a draft To Jane saved with no connection "Jane" under "On
this iPad only", and still "Jane" once it had gone to Gmail. The Outbox:
To Jane and Cc Jane's address again, "Jane" alone; it went when the
connection came back. Sent Mail searched "B-060" in itself: "Jane", "Sam"
alone for the reply, Sam's bare address, "Jane", one row each with no
count; in All Mailboxes every one named the test account. Force-quit and
opened with no connection: Sent Mail and Drafts read as before at once.
VoiceOver was not tried: the labels it reads are the suite's.

---

## B-061 — CHANGED 2026-10-03, seen on the iPad. Reply ignored Reply-To, answered his own letters to himself, and Reply All copied him under another spelling of his address

**Found** in the gap review of 2026-09-30 ("Reply ignores Reply-To;
replying to his own letter addresses it to himself; Reply All misses his
second address"), and checked against the code. `Draft.replying` put the
letter's From in To, whatever else the letter said:

- A letter with a Reply-To was answered to its From. A mailing list sets
  Reply-To to the list, a shop to its service desk, a friend writing from
  work to the address at home. The ENVELOPE the list is fetched with has
  the Reply-To (`IMAPEnvelope.replyTo`) and nothing read it; the letter the
  pane shows, which Reply is made from, did not carry one at all.
- A letter of his own was answered to himself: in Sent Mail, in a
  conversation, and in the Inbox, where every letter he sends to his
  second address comes back, about half of what he sends.
- Reply All put everyone, the letter's To and its Cc, in Cc, took every
  name off, and left him out only as the account spells his address, so
  the same mailbox written another way, `Owner_Example@Gmail.com`,
  `o.wner_example@gmail.com` or `owner_example+lists@googlemail.com`, all
  of which Gmail delivers to him, was sent a copy of his own reply.
- A letter with no From was answered to "(unknown sender)", the pane's
  words for it, which Gmail refuses as an address.

**His second address**, read from the headers of his own mailbox, nothing
of it kept: an address on another domain that Gmail both sends as (Sent
Mail has letters from it, the latest this July) and delivers to him
(letters to it arrive in his Inbox, his own among them). So a Reply All to
a letter that names it sends it a copy of his reply, which comes back to
his Inbox. Nothing the app reads says that address is his: Mail knows such
an address only when it has been added to the account, and IMAP does not
list Gmail's send-as addresses. Learning it from the From addresses of
Sent Mail was weighed and left: one letter of someone else's moved into
Sent Mail would make that person him, and every Reply All after it would
leave them out with nothing on screen to say so. Put to the owner (below).
What the app can know is handled: every spelling Gmail delivers to the
account's own mailbox, and the account's login.

**Changed.** Whom a reply goes to is `ReplyAddressing`
(`Model/ReplyAddressing.swift`), which runs on the host, and
`Draft.replying` takes its To and Cc from it:

1. A letter with one of his addresses in its From is his own. Reply goes
   to its To, or, with nobody in To, its Cc; Reply All to its To and its
   Cc, in the same fields. Its Reply-To is not looked at: it says where he
   wanted others to answer him.
2. Any other letter: Reply goes to its Reply-To when it has one, and to
   everyone in its From otherwise, as RFC 5322 has it for a letter written
   by several. Reply All goes to the same, then the letter's To, in To,
   and its Cc, in Cc. The From is left out when there is a Reply-To, as
   Gmail and Thunderbird leave it out and Mail is believed to: the sender
   has asked for answers to go there instead.
3. Each address once, compared bare and without regard to case, To before
   Cc, with the name the letter first gave it, or a later one where the
   first had none. An entry with no address in it, `undisclosed-recipients:;`
   or the pane's "(unknown sender)", is no recipient. Each entry is one
   line (below).
4. His own addresses come out of both fields, unless that would leave the
   reply going to nobody: then it goes to him, as a letter he sent himself
   is answered to himself, and one he sent to nobody named, by Bcc alone,
   too, at his address in its From. He is never otherwise sent a copy of
   his own reply.
5. With nobody left in To but someone in Cc, the Cc move up to To, so the
   reply does not go with a Cc and no To at all.

His addresses (`OwnAddresses`) are the account's address and its login,
compared as the mailbox they reach: bare, without regard to case, and for
gmail.com and googlemail.com, which are one, without the dots in the name
or anything after a `+`, since Gmail delivers all of those to the same
mailbox. Only for Gmail's own domains: another server may give
`sam.example@example.org` and `samexample@example.org` to two people, and
taking a stranger for him would leave the stranger out, unseen.

The letter the pane shows carries its Reply-To (`Message.replyTo`), read
from the letter's own header, as its To and Cc are, and not from the
ENVELOPE, which a server fills with the From when there is none and so
cannot say whether the letter had one. In a conversation, Reply answers the
letter opened last, as before.

The names are kept. Each entry is read in every form a header writes it
(`MailFormat.recipient(in:)`): `Jane Example <jane@example.com>`, a quoted
name, a name whose comma came out of an encoded word, the old
`jane@example.com (Jane Example)`, a group's `Friends: jane@example.com;`.
It is written back as the composer's field keeps it
(`MailFormat.recipientEntry`), the name in quotes where it holds a comma or
a quote. The composer's field, and the share sheet's, are now split between
recipients and never inside quotes (`MailFormat.addresses(in:)` is
`addressList`), so `"Example, Jane" <jane@example.com>` is one recipient
where it was two, the first of them `"Example`, which mail cannot be sent
to; a quote never closed is split at every comma, as before. A draft
reopened from Drafts has its recipients written the same way
(`Draft.reopening`), so a name whose comma came out of an encoded word is
still one recipient when it comes back, and what cannot be read as an
address is left as it came, on one line (below), for him to see. A quoted
pair in a name goes out in the header once (`RFC5322Builder.recipient`),
where its backslash was doubled.

**Names broken over lines**, found in review on 2026-10-03, once the names
went into a reply's To and Cc. A letter's header can carry a line break in
a name, in an encoded word, and innocently: a Windows "…" sent as
ISO-8859-1 is byte 0x85, which decodes as U+0085, NEXT LINE. The envelope
took a recipient's address from the first line of its entry
(`SMTPClient.envelopeAddress`, which cuts there so that a line break
cannot add commands of its own), and the header from all of it, its last
`<…>`. So a To named `<other@example.net>`, a line break, then `Sam`, with
the address sam@example.org, sent the reply to other@example.net, an
address never compared with his or anyone's, with Sam's in its header; and
a From named `Jane`, U+2028, `Example` was answered with `RCPT TO:<Jane>`.
Every line break and control character in a name, anything below U+0020,
U+007F to U+009F, U+2028 and U+2029, is now a space, and any in an address
is taken out (`MailFormat.recipient(name:address:)`), so each entry of a
reply is one line and its last `<…>` is the address that was compared. A
draft reopened from Drafts has its entries made one line the same way,
with an address in them or not (`MailFormat.fieldEntry`). And the header
now reads each entry's first line as the envelope does, the two through
one function (`RFC5322Builder.recipientLine`), so whatever else puts a
line break in a field, a `mailto:` link's `%0A` among them, the To and Cc
the letter shows are whom it went to.

**A From of several**, found in the same review. `jane@example.com,
sam@example.org` was read as one entry, the whole From decoded
(`Message.sender`): Reply addressed an entry that was nobody's, which the
composer's field then split, so it went to both by accident, or, with
names, to the last alone with the others taken for its name; and a letter
of his written with someone else was not his. The letter now carries its
From an entry per address (`Message.from`), split as its To is, before
the encoded words are decoded, so a name whose comma came out of one is
still one author. Reply goes to every one of them, and the letter is his
own if any of them is him; sent by Bcc alone, it is answered to his
address in its From, and not to whoever wrote it with him.

Forward is unchanged: it goes to nobody until he says.

**What he sees.** The composer's To has the name with the address, "Jane
Example <jane@example.com>", where it had the address alone, and a name
with a comma in quotes. Reply All has the letter's sender and To in To and
its Cc in Cc, where everyone was in Cc. A name the letter broke over
lines reads on one line. No new words.

**Tests.** `ReplyAddressingTests` (32): each rule on its own, the Reply-To
(a list's, several, one that is the From, one with no address in it), his
own letter (to others, to himself, to himself and Jane, with only a Cc, by
Bcc alone, its Reply-To not followed, in every spelling of his address), a
letter from several answered to each of them, and one he wrote with Jane
his own, answered to him alone when sent by Bcc alone, his addresses in
Gmail's spellings and not in another domain's, the login, a letter with no
From, once each with names across To and Cc, every form of an entry, a
name broken by every kind of line break and control character made one
line in every form of an entry and in a reply, the field and the letter's
header giving them back, Forward; and 3,000 letters made up from awkward
entries, now and then two authors and names broken over lines among them,
Reply and Reply All of each, holding every rule at once, every entry one
line whose last `<…>` is the address compared. `ReplyAddressingRepositoryTests`
(8), over the shipping repository and the scripted server, which now
writes a letter's Reply-To and puts it in the ENVELOPE, the From in its
place when there is none (`ScriptedIMAPServer.Letter.replyTo`), and a From
of several (`alsoFrom`): the Reply-To read from the header, and none for a
letter without one; a Reply All sent, its RCPT TOs and its To and Cc with
their names; his own letter in Sent Mail; a reply saved to Drafts and
reopened with each recipient once; names broken by a line feed, by U+2028
and by an ISO-8859-1 0x85 in a letter's From, To and Cc, Reply and Reply
All sent, every RCPT TO the angle address of its entry, the header naming
the same people and no entry holding a line break; a draft saved elsewhere
with such names, and a name with no address, reopened all on one line and
sent to its addresses; a `mailto:` link with line breaks in its To and Cc,
the header naming whom the envelope sends to; and a letter from several,
its encoded name's comma kept, sent to them all, and one of his written
with Jane, his own. `ReplyAddressingWiringTests` (1), from the view
controller's source: Reply made from the letter the pane shows, with every
address of his the account has. Three tests that pinned the old shape were
changed: `ReplyForwardTests.testReplyAllNeverCCsTheSenderOfTheReply`, now
with To in To; `testReplyAllStripsDisplayNamesFromTheCCList`, now
`testReplyAllKeepsANameWithACommaAsOneRecipient`; and
`ReadingPaneCcTests.testALettersToAndCcAreReadOneAddressEach`, To and Cc
with their names. Each fails with its part undone, 32 sabotages one at a
time, the full suite each time, all of them run again on 2026-10-03 with
the tests as they stand, failures as XCTest counts them: the Reply-To not
followed (12 failures), not read from the letter (4), his own letter
answered as anyone's (16), its Reply-To followed (3), the From kept beside
a Reply-To in Reply All (5), Reply All all in Cc, as before (34), Gmail's
spellings not made one (6), the login not his (1), the app's Reply knowing
only the account's address (1), him not taken out (33), a letter to him
alone answered to nobody (9), a Cc left alone not moved up to To (3),
addresses not made once each (5), the names dropped (107), a name with a
comma not quoted (38), an entry with no address taken for a recipient
(17), a group's name taken for an address (4), a name written as a comment
taken for part of the address (4), an entry it cannot read dropped from a
reopened draft (3), the composer's field split at every comma (7), a
reopened draft's recipients taken as they came (7), a quoted pair sent
with its backslash doubled (1), a line break left in a name (78), a
control character left in an address (6), a reopened draft's entry with
no address left on two lines (2), only the characters below U+0020 taken
for line breaks, so not U+0085, U+2028 or U+2029 (53), the From read as
one entry (10), the From's entries not read from the letter (5), a letter
his only when the first in its From is him (6), his own letter by Bcc
alone answered to everyone in its From (3), the header reading an entry
past its first line, as before (2), and the envelope reading past it, so
that the two disagree again (1). `LargeLetterTests.testPicturesStillComingWhenHeMovesOnAreCalledOff`,
which fails now and then with the machine busy and has nothing to do with
replies, failed in none of these runs.

**Decided as Mail is believed to do it, put to the owner.** None of these
was checked against Mail on an iPad.

- *Reply All with a Reply-To* goes to the Reply-To in place of the From.
  Or to both.
- *Names in the composer's To*: "Jane Example <jane@example.com>". Or the
  address alone, as before, the names still going out in the letter.
- *Reply All's fields*: the letter's To in To, its Cc in Cc. Or everyone
  in Cc, as before.
- *A Cc left alone* moves up to To. Or the reply goes with a Cc and no To.
- *His own letter's Reply-To* is not followed. Or it is, as for anyone
  else's.
- *His second address*: left as it is, a copy of a Reply All going to it
  and coming back to his Inbox. Or a line in Settings where his other
  addresses are written once, as Mail's account has them under its Email;
  or the From addresses of Sent Mail taken as his at sign-in, with the
  risk above.
- *His own letter sent by Bcc alone*, whose copy in Sent Mail keeps its
  Bcc header, is answered to himself. Or to its Bcc recipients, in Bcc, or
  in To. Gmail keeps the Bcc on its copy of a letter sent from Blackmail
  too (seen 2026-10-03, B-060), so this is any letter he sent to Bcc
  alone.

**Settled 2026-10-06** by the owner's ruling, "copy apple mail" (B-076).
Reply All with a Reply-To: in place of the From, as built. The composer's
To: a bubble with the name, its address shown when it is tapped. Reply All's fields:
the Reply-To, or the From, alone in To and everyone else in Cc, the
letter's To first, as before B-061. A Cc left alone: never moved up on
anyone else's letter. His own letter's Reply-To: not followed, as built.
His second address: a list in Settings, as Mail's account has under its
Email, filled by hand. His own letter by Bcc alone: answered to himself,
as built; what Mail does could not be found out. His address is matched
as written, without regard to case, and Gmail's other spellings of it are
no longer his, as in Mail.

**Seen on the iPad, 2026-10-03**, on carlo's mailbox, every letter from it
to itself, A standing for its address. carlo's address is on a domain of
its own, not Gmail's, so a dot in the name and googlemail.com could not be
tried there: on another domain they are other people. A letter To A, Cc
A with capitals and A with `+b061`: Reply was To A alone with the Cc row
closed; Reply All left out the capitals and put the `+b061` spelling in
To alone, as the rule has it for every domain but Gmail's, though Gmail
does deliver that one to carlo. His own address is at gmail.com, where
the suite has the tag made one. A letter To `"Example, Test" <A>`, opened
in Sent Mail: Reply read `"Example, Test" <A>`, one recipient; sent, the
log had one `RCPT TO:<A>`, Gmail's ENVELOPE for it the To `("Example,
Test" NIL …)`, one name, and it arrived once. Reply All to it, a word,
Save Draft, opened from Drafts: the same To, one recipient; sent, one
`RCPT TO:<A>`, and it arrived once. Forward: To and Cc empty. The letter
sent from the draft had no In-Reply-To, though the draft had one, and
began a conversation of its own: B-064.

**Not covered.** A From of several is answered to every one of them, as
RFC 5322 has it; how Mail answers one was not checked. A Reply-To of his
on someone else's letter is followed, as the letter asks. An entry broken
over lines that a reply did not make, a `mailto:` link's `%0A`, goes to
its first line alone, as it always has, and now says so in the header.
`Sender:` and a list's `List-Post:` are not read; Mail has no Reply to
List. A suggestion picked in the field takes the place of what follows its
last comma, as it always has, so one picked while the field ends in a
quoted name cut short after its comma would take the place of the rest of
that name.

---

## B-062 — CHANGED 2026-10-03, seen on the iPad. Delete inside Trash erased a letter with nothing asked, and Edit mode's Delete and Move failed in silence

**Found in the gap review of 2026-09-30**, under the ways a letter is lost,
and confirmed in the code:

- **Delete inside Trash erased at the first tap.** Delete moves a letter to
  Trash everywhere else; inside Trash it sets `\Deleted`
  (`IMAPMailRepository.delete`), and Gmail, with its IMAP settings as they
  come, erases the letter for good at once. The reading pane's
  Delete and Edit mode's both went straight to it, and an All Mailboxes
  search reaches Trash too (B-011), so a hit from Trash went the same way
  from any list. `PRODUCT_SPEC.md`'s safeguards ask for "Confirmation
  before permanently deleting from Trash."
- **Edit mode's Delete and Move said nothing when they failed.** Each
  letter's write went with `try?`, one after another, and the list was
  fetched again once all of them had been tried. A refused write was
  dropped: the letter came back with the fetch if the fetch worked, and
  stayed off the screen as if it had gone if the connection had gone with
  it. Nothing put up an alert either way.
- **Delete said nothing while it worked.** The rows he had ticked stayed on
  the screen, ticked, in Edit mode, until every write and the fetch after
  them had come back: a second or two for a few letters on a good
  connection, half a minute for each letter on a bad one. Move already
  said "Moving…".

**Changed.**

- **A question before a Delete that erases** (`EraseQuestion`, put up by
  `EraseConfirmation`). Asked by the reading pane's Delete and by Edit
  mode's, for any letter whose own folder is Trash: an alert, "Delete
  Message?", "This message will be deleted immediately. You can't undo
  this action.", or for several "Delete 3 Messages?", "These messages will
  be deleted immediately. You can't undo this action." Cancel on the left,
  Delete in red on the right. Cancel leaves everything as it was: the
  letter in the pane, his ticks in Edit mode. The sentence is Apple's own
  for a delete that skips the bin, the Finder's "This item will be deleted
  immediately. You can't undo this action." (Apple Community thread
  251725582), with "message", Mail's word on screen, for "item". An alert,
  not an action sheet: on the iPad an action sheet is a popover, and UIKit
  leaves out a popover's Cancel. A search that ticks letters from Trash
  among others says which: "Delete 3 Messages?", "1 of them is in the
  Trash and will be deleted immediately. You can't undo this action." Not
  asked in Spam: Delete there moves the letter to Trash, as Mail's does
  from Junk, and the spec asks only for Trash.
- **Edit mode's Delete and Move go as the reading pane's do** (`ListBatch`,
  over `PaneActions`, now in three steps, `start`, `send` and `finish`, so
  both can use them). At the tap every row he ticked goes and Edit mode
  ends, as in Mail, and the line under the list says "Deleting…" or
  "Moving…" until the server has answered for every letter. The writes go
  one at a time, in list order, the rows from the top down whatever order
  he ticked them in (`ListBatch.letters(ticked:in:)`). As first built they
  went in the order he ticked them, which is the order UIKit gives them.
  Each letter the server takes is billed to the folder counts as the
  pane's Delete bills one (`removalLanded`), and the counts are swept once
  at the end if a letter moved changed one the list cannot work out, not
  once for each. The list is not fetched again, so a search, a day jumped
  to and his place in the list stay as they were.
- **A refusal is said, and nothing refused is shown as gone.** The letter
  the server did not take comes back where it stood, not ticked, and the
  letters after it are not sent and come back with it. The alert is the
  app's own for whatever was caught, as the reading pane's: "Can't connect
  to mail server.", or for a refused password Mail's "Cannot Get Mail" with
  Settings. Stopping at the first refusal is deliberate: it is nearly
  always the connection or the password, which the next letter would meet
  too, each after a connect of its own that can take half a minute, and a
  refused password sent again for every letter counts against the account
  each time. The one exception is a row kept on the iPad that the server
  says is another letter now (D-016), which has sent nothing and says
  nothing of the rest: it comes off the list as it does from the pane, the
  rest go on, and the alert says for it what the pane's says, "Can't
  connect to mail server." If he has opened another folder before the
  refusal comes, the list he left is off the screen, and the alert goes
  over what is in front in the window instead, the reading pane or a sheet
  over it (`alertHost`). Put over the list that had gone, it was dropped.
- **The reading pane empties only if it shows a letter going.** Edit
  mode's Delete and Move used to empty it whatever it showed, once the
  fetch was back; now at the tap, and only for one of his ticks or a
  letter in the conversation it shows (`clearIfShowing`), under its own id
  or another mailbox's (`ListEdit.going`): a twin as `ListEdit.twins` has
  them, or a copy with the same Gmail message id. So an All Mailboxes hit
  from All Mail deleted while the pane shows the same letter opened from
  the Inbox empties the pane, and so does the Inbox row deleted while it
  shows the hit. Matched on ids alone, as first built, the row's twin went
  from the list and the pane kept the binned letter with Reply, Move and
  Delete live, and a Delete from it then sent a MOVE for an Inbox UID that
  Gmail no longer had.
- A draft kept on the iPad that he deletes in Edit mode goes from the iPad
  at once, as before, but each on its own task: putting one away can wait
  for an upload of it still on its way (`LocalDrafts.tidy`), and the
  letters on the server no longer wait behind it.

No new error sentence: the six stand (`MessageSizeTests`). The new words
on screen are the question's, its two buttons, and "Deleting…".

**Decided here, put to the owner.**

- *What the question says.* Built: "Delete Message?" and Apple's Finder
  sentence. Or the Finder's own title, "Are you sure you want to delete
  this message?"; or the subject in it, as the Finder names the file.
- *Whether to ask for every Delete in Trash.* Built, as the spec asks. Mail
  on the iPad asks only before its Delete All in Trash and Junk; nothing
  found that describes a letter or a selection deleted there mentions a
  question. Mail's way would leave a single Delete in Trash unasked.
- *Spam.* Built: nothing asked, since Delete there goes to Trash. Or ask
  there too.
- *A batch that meets a refusal.* Built: it stops, and the rest come back
  unsent. Or try every letter whatever, which deletes what can be deleted
  when one letter alone is refused, and with no connection takes half a
  minute a letter.
- *The letters that come back.* Built: in their places, not ticked, Edit
  mode over. Or Edit mode again with them ticked, ready for a second try,
  which would change the list under him if he had moved on meanwhile.
- *The alert.* Built: the app's own sentence for what was caught, which
  does not say how many letters went. Mail's, as its users quote it, is
  "Unable to Move Message", "The message could not be moved to the mailbox
  Trash." (Apple Community thread 4014036), "The messages could not be
  moved…" for several: a seventh sentence, and Delete would say Move.

**Tests.** `EraseQuestionTests`: only a letter in Trash asks, by its
folder's id in either spelling or the role word, Spam and every other
folder not; the words for one letter, for several, and for a selection
that mixes Trash with others; and the wiring, read from the source: the
alert's two actions and their styles, the pane's Delete and Edit mode's
asking and going only on Delete, by the role of each letter's own folder.
`ListBatchTests`, over the shipping repository and the scripted server:
four letters deleted, every row off at the tap before any MOVE is
answered, one MOVE each and nothing else, the two unread billed once each
and one sweep; inside Trash one `\Deleted` and its `UID EXPUNGE` (see
"Tests of the erase" below) and no sweep, and a mixed batch
each letter by its own folder; a Move of three filing each, one sweep; the
second of four refused with the connection up, the first gone and billed,
the other three back and two of them never sent, the refusal for the
alert; a refused password, one LOGIN for five letters, all back, "Cannot
Get Mail"; a kept row that is not its letter sending nothing and the rest
still going; rows ticked out of order, a row twice, a conversation holding
another row's letter and a row past the end, taken in list order, each
letter once, and sent in that order; the pane's letter going under another
mailbox's id, an All Mailboxes hit deleted while the pane shows the Inbox's
copy and the Inbox's row deleted while it shows the hit, by a twin alone
and by the Gmail message id alone, each both ways, and a letter not ticked
left alone though it is in the same conversation; and the controller's
wiring, read from the source: the ticks taken in list order, the letters
kept on the iPad deleted from it, "Deleting…" and "Moving…" for as long as
the batch runs, Edit mode ended at the tap, the refusal put up, over what
is in front once the list has left the window, no `try?` and no fetch, the
pane emptied only for a letter going, matched by `ListEdit.going`. Each
fails with its part undone, nineteen sabotages one at a time, counted
before the erase below: the pane's Delete asking nothing (1 failure), Edit mode's asking nothing (1), Spam
asking as Trash does (4), a refused letter not put back (4), the letters
after a refusal not put back (2), every letter tried after a refusal (2),
a kept row that is not its letter stopping the rest (2), a sweep asked for
after each letter (2), every letter taken by the first one's folder (1),
the refusal not put up (1), "Deleting…" not said (1), the pane emptied
whatever it shows (1), the pane's letter matched on ids alone in
`ListEdit.going` (7), its twin left out (2), its Gmail message id left out
(2), the pane's own match by ids alone put back in `clearIfShowing` (1),
the letters kept on the iPad not deleted (1), the refusal put over the
list whether or not it is in the window (1), and the ticks taken in the
order he ticked them (3). `LargeLetterTests`'
`testPicturesStillComingWhenHeMovesOnAreCalledOff` failed besides in some
of those runs, a second picture's FETCH going before it was called off;
it touches nothing here, and fails now and then on its own, run alone:
1 run in 20 with this change, 2 in 40 on the tree before it.

**Seen on the iPad, 2026-10-03**, on a build from this branch, on
carlo's mailbox, every letter from the test account to itself, the steps
as the TODO has them.

1. In the Inbox the pane's Delete went to Trash with nothing asked. In
   Trash the alert was as written: "Delete Message?", the sentence, Cancel
   on the left, Delete in red on the right. Cancel left the letter in the
   pane and on the list, and no STORE went. Delete, then Delete: the pane
   emptied and the row went at once. The log had `UID STORE 39
   +FLAGS.SILENT (\Deleted)`, answered `* 38 FETCH (UID 39 FLAGS (\Deleted
   \Seen))` and OK, and no EXPUNGE. The next open of Trash listed the
   letter again, its FETCH saying `FLAGS (\Deleted \Seen)`, and an All
   Mailboxes search found it. The test account has Gmail's IMAP
   Auto-Expunge off. His account's setting is not known and cannot be read
   from here. See "Erased, not only marked", below.
2. Edit mode in the Inbox, "B-062 2" then "B-062 3" ticked, the lower
   first: both went at once, Edit mode ended, nothing asked; "Deleting…"
   was too quick to see. The log's first move was `UID MOVE 58`, then
   `UID MOVE 57`, the list's order, each answered with an EXPUNGE; then
   one sweep, the `LIST` and its `STATUS`es, and no fetch of the Inbox's
   page. The Inbox's count went down by two. In Trash, both ticked, Delete:
   "Delete 2 Messages?", "These messages will be deleted immediately. You
   can't undo this action." Cancel kept both ticked and Edit mode on.
   Delete, then Delete: both rows went, and both were back at Trash's next
   open, for the same reason.
3. In Spam, Delete asked nothing, and the letter was in Trash after a
   Refresh of Trash.
4. An All Mailboxes search, Edit, the Trash hit for "B-062 5" and the hit
   for "B-062 6" ticked, Delete: "Delete 2 Messages?", "1 of them is in
   the Trash and will be deleted immediately. You can't undo this action."
   Delete: both rows went. "B-062 6" went to Trash; "B-062 5" was not
   expunged, for the same reason.
5. The reading pane, all four cases: "B-062 7" stayed while "B-062 8"
   went, and the pane emptied for "B-062 7"; the same letter under two ids
   emptied it both ways, and the Inbox had no "B-062 33" after Cancel.
6. A Move to All Mail of "B-062 9" to "B-062 32", 24 letters found by a
   search in the Inbox, with Airplane Mode turned on from Control Center at
   once: six `UID MOVE`s answered (87 down to 82), the seventh (81)
   written and not answered, cut off by `DEADLINE read ordinary
   bound=30s`, and no MOVE after it. The rows from "B-062 26" down came
   back, not ticked, with "Can't connect to mail server." and OK. Airplane
   Mode off, Refresh: Gmail had carried out the seventh move, "B-062 26"
   archived and gone from the Inbox, so the letter the failure came on was
   not in fact still in the Inbox; the rest were. The same with Delete: ten
   moves answered, the eleventh, "B-062 15", cut off at 30 s and carried
   out by Gmail all the same, as the Refresh showed. That is the lost
   answer under Not covered.
7. Airplane Mode on, two ticked, Delete: both went and came back with the
   alert within a tenth of a second, and the log has no command for them.
8. Airplane Mode refuses at once and cannot make a slow refusal, so the
   Wi-Fi interface was taken down from a shell on the iPad instead, after a
   Refresh. "B-062 14" and "B-062 13" ticked, Delete, Sent opened at once:
   at about 30 s "Can't connect to mail server." came over the reading
   pane, the Inbox's list gone, and OK took it away. Interface up, the
   Inbox: both letters there. The `UID MOVE 69` written never reached
   Gmail; a new connection still listed UID 69.

Seen besides, not this item's: a letter read from its All Mailboxes hit
left the Inbox's row for it with its unread dot until the list was fetched
again, though the Inbox's count went down. In the TODO.

**Erased, not only marked. Changed 2026-10-03, after the check, and seen
on the iPad the same day.** Delete inside Trash now sends the `\Deleted` STORE and
then `UID EXPUNGE` of that letter alone, in one hold of the connection
(`IMAPClient.expunge`, which drafts already went by), and still names the
row's letter (`vouch`) and goes once (`sendingOnce`). It no longer rests on
Auto-Expunge. With it off, the EXPUNGE erases the letter. With it on,
Gmail's default, the STORE has erased it already, and the `UID EXPUNGE`
names a UID that has gone, which RFC 4315 allows. A letter left marked in
Trash by the build before, as the test account's four from steps 1, 2 and
4 are, or by another mail program, goes when he deletes it again: the
STORE changes nothing on it, and the EXPUNGE takes it.

On a server without UIDPLUS, or one whose CAPABILITY could not be read,
the EXPUNGE is the plain one, and it takes every letter in Trash marked
`\Deleted`, not his alone. Built so on purpose. In Trash a letter carries
the flag only when a mail program has asked for it to be erased: the flag
is IMAP's alone, Gmail's own Delete does not set it, and this app sets it
only with an EXPUNGE in the same hold. What goes with his letter is what
was already asked to go, and with Auto-Expunge on would have gone already.
The one thing lost is another program's chance to take its mark off
again. The flag alone there would leave his letter in Trash after he was
told it would be deleted immediately. Gmail has UIDPLUS; the log's
CAPABILITY line names it.

A refused EXPUNGE is a refusal like any other: the alert, the row back
where it stood, the rest of a batch unsent. The letter stays in Trash,
marked, and a Delete again takes it.

Seen on the iPad, 2026-10-03, on a build with the change, on carlo's
mailbox, whose Auto-Expunge is off. "B-062 1", left marked in Trash by the
build before, deleted again from the reading pane: `UID STORE 39
+FLAGS.SILENT (\Deleted)`, then `UID EXPUNGE 39`, answered `* 38
EXPUNGE` and OK. "B-062 2" and "B-062 3", marked, ticked in Edit mode in
Trash: 41 then 40, the list's order, each its STORE and its own `UID
EXPUNGE`, each answered with an EXPUNGE. An All Mailboxes search, the
Trash hit for "B-062 5" with the hit for "B-062 9" from the Inbox: "1 of
them is in the Trash…", then `UID MOVE 85` to Trash for the one and the
STORE and `UID EXPUNGE 43` for the other. And "B-062 9", just moved to
Trash and never marked, deleted from the pane: `UID EXPUNGE 60`, `* 55
EXPUNGE`. After a Refresh none of the five was in Trash nor found by a
search of it or of All Mailboxes, and Trash's count had gone down for the
one unread among them.

`ScriptedIMAPServer` now says what it models, Auto-Expunge off, as the
test account has it: a `\Deleted` STORE leaves the letter, listed and
searched; `UID EXPUNGE` takes the marked letters it names and no other;
plain `EXPUNGE` takes every marked letter in the mailbox. `autoExpunge`
turns on Gmail's default, the STORE removing the letter itself, and
`markDeleted` leaves a letter marked, as another program does.

**Tests of the erase.** `PaneActionsTests`: a letter deleted in Trash,
its STORE and `UID EXPUNGE` sent in Trash, and gone from the server; one
left marked, listed, and gone when deleted again; the `UID EXPUNGE`
refused, the refusal `.cannotConnect`, the row back, nothing billed, the
letter still there and marked, and gone at a second Delete; with
Auto-Expunge on, gone at the STORE, before any EXPUNGE, and the `UID
EXPUNGE` after it answered OK. `ListBatchTests`: Edit mode in Trash, two letters, each STORE and
`UID EXPUNGE` naming it alone, both gone, and a third marked by another
program still there and marked; the mixed All Mailboxes batch, the Trash
hit gone from the server and the other in Trash; no UIDPLUS, a plain
`EXPUNGE` taking his letter and the one marked and no letter unmarked; a
refused `UID EXPUNGE` in a batch of two, both rows back, the second
unsent, "Can't connect to mail server." for the alert, the first still
there and marked, and both gone at a second Delete. `KeptCopyTests`'
ordinary writes have the `UID EXPUNGE` after the Trash's STORE. Six
sabotages, one at a time in a scratch copy: the STORE alone put back (32
failures), the plain EXPUNGE whatever the server has (43), `UID EXPUNGE`
whatever the server has (3), a refused EXPUNGE not thrown (8), the
scripted server's `UID EXPUNGE` taking every marked letter (3), and its
Auto-Expunge on doing nothing (1). The whole suite: 1183 tests, 4 skipped,
0 failures.

**Not covered.** A batch still running when he opens another folder puts
its alert, if any, over what is in front then, as above, but the letters
that came back are on the old list, which has gone, and the folder he
left shows the server's word when he opens it again. The reading pane's
own alerts never had the trouble the list's had: the pane stays in the
window whatever folder he opens. A write whose answer was lost after it went, as on a
socket that dies while the iPad sleeps, is counted as refused: the letter
comes back on the list though Gmail may have moved it, until the next
Refresh, as from the reading pane; step 6 saw it twice. Letters marked
`\Deleted` are not left out of the list and of searches, as Mail leaves
them out. This app leaves none of its own behind now, but for one whose
EXPUNGE was refused, which comes back on the list with the alert and
should stay in sight. One marked by another program, on an account with
Auto-Expunge off, is listed and found as Gmail's IMAP lists it, and a
Delete of it now erases it. Leaving them out would need `UNDELETED` in
every SEARCH that lists, pages, jumps to a day or searches, and the
folder counts come from `STATUS`, which counts them, so an unread one
left out would still be counted. What Gmail sends with Auto-Expunge on
is not seen: the test account has it off, and the suite's model of it,
an EXPUNGE in the STORE's own answer, is a guess. Deleting from the
Outbox in Edit mode, which takes a waiting letter off the iPad for good,
asks nothing, as before; that is outside this item.

---

## B-063 — CHANGED 2026-10-03, seen on the iPad. His mailbox's size: a slow SEARCH would have failed for good, a date jump brought every letter it matched, and his files and photos stayed on the iPad between launches

**Found in the code 2026-10-03**, auditing f9a6325 for what the size of
his mailbox does to it: Inbox 60,000 to 150,000 letters, Sent Mail about
150,000, All Mail 250,000 to 400,000 and growing by about 45,000 a year,
Drafts about 1,900, in about 22 folders. The owner said not to test at
his volume with real mail, so every figure below is from synthetic
strings and buffers on this host. Five things grew with it, the first for
good:

1. **A slow answer failed every time.** Every reply was given 30 seconds
   of silence (`TLSConnection.ordinaryDeadline`). Gmail says nothing in
   answer to a SEARCH, a SELECT or a STATUS until it has worked through
   the mailbox, and a SEARCH of All Mail goes over all of it. One that
   took Gmail more than 30 seconds was cut off, the read retry's
   reconnect asked it again and was cut off again, and the folder said
   "Can't connect" at every try, for good: nothing on the iPad could
   change it, and All Mail only grows. How long Gmail takes at his size
   is not known; the log never said.
2. **A date jump brought every letter it matched, for one number.** Of
   Go to Date's dated SEARCH (B-058) only the oldest letter matched is
   used (`PageWindow.anchor`), and all of them were asked for: a jump to
   before 2016 in All Mail matched most of it, one line of about eight
   bytes a letter, megabytes over his line, beside the listing's `UID
   SEARCH ALL` of the same size.
3. **A SEARCH answer was read a character at a time.**
   `IMAPParser.parseSearch` tokenized the line, a `Character` array and
   a `String` for every number: in a release build here 87-92 ms for
   60,000 UIDs and 632-641 ms for 400,000, on every listing of All Mail from the
   top, every jump in it, and every All Mailboxes search.
4. **A long line was searched for its end once a chunk.**
   `ReadBuffer.takeLine` searched the whole buffer for CRLF after every
   chunk the socket gave, a line of n bytes in chunks of c costing about
   n²/2c: All Mail's 3 MB SEARCH answer in 16 KB chunks was 279 MB of
   searching, 453-735 ms here, and in 4 KB chunks 1.8-2.3 s.
5. **Every file he opened and every photo he attached stayed until the
   next launch.** `tmp/Attachments` was emptied only at launch
   (`AttachmentStore.purge`), and iOS can keep the app alive for days: a
   copy of every PDF or scan he opened, and every full-size photograph,
   five a letter, he attached.

**Changed.**

1. *The bound.* The reply to a SEARCH, a SELECT or a STATUS is given 90
   seconds of silence (`ReplyWait.serverWork`,
   `TLSConnection.serverWorkDeadline`), three ordinary deadlines, before
   it starts and at any pause in it up to its tagged line: Gmail may say
   a line at once, an EXISTS or EXPUNGE it owes the session, or SELECT's
   FLAGS, and work through the mailbox after it. Every other reply keeps
   30, and the read retry is as it was. A bound that fires says
   `DEADLINE read serverWork bound=90s`.

   A reply that takes more than five seconds, from the command's write
   to its tagged line, is noted in the connection log with its verb and
   two times and nothing else, `SLOW UID SEARCH ms=15000 quiet=13000`.
   `quiet` is the longest single silence between the write and the
   tagged line, one read's wait for the next bytes
   (`MailTransport.longestQuiet`, timed as the transport waits on the
   link). The bound is on each such silence, so how near Gmail's slowest
   answers come to 90 seconds is read off `quiet`, not guessed. The
   wait for the first byte alone is not that number: an answer whose
   first line came at once and whose rest came after 80 seconds had a
   first byte at nought and was 10 seconds from the bound. `ms` is the
   whole of it, the answer coming over his line included; All Mail's
   3 MB SEARCH answer can take seconds to come once Gmail has started
   it, and none of that counts against the bound while bytes keep
   coming. A `quiet` near 90,000 is the bound nearly firing; an `ms`
   near it alone is not. No note is written for a command the app
   went to the background or came back during (`Diagnostics.awayOrBack`,
   counted in `AppDelegate`): iOS suspends the app in the background,
   for hours if he leaves it there, and an answer read once he is back
   would read as hours of Gmail's.

   What it costs. The read retry is unchanged, so a Gmail answer that
   takes more than 90 seconds is about 90 seconds of waiting, a
   reconnect, and about 90 seconds again, over three minutes, before
   the folder says "Can't connect"; on the ordinary bound it was about
   one minute. There is one connection, and the command holds its gate
   for each of those waits, so a letter he opens meanwhile waits behind
   it, up to 90 seconds at a time rather than 30. And a line that dies
   while one of those three waits is given up on at 90 seconds rather
   than 30, since once the command's bytes are acknowledged TCP itself
   finds a dead peer only two minutes after the last traffic: a sweep of
   the counts whose STATUS is on the wire as the line dies holds his
   taps 90 seconds instead of 30.
2. *The jump asks for the one number.* Where the server advertises
   ESEARCH (RFC 4731), as Gmail does, the dated SEARCH goes as `UID SEARCH
   RETURN (MIN) SENTSINCE "19-Jun-2019" SINCE "12-Jun-2019" BEFORE
   "11-Oct-2026"` and is answered `* ESEARCH (TAG "a012") UID MIN 4231`,
   or with nothing after `UID` when nothing matched, which says "No mail
   on or after" the day as before (`IMAPClient.PageSearch.lowest`,
   `IMAPParser.parseSearchMinimum`). RETURN goes before any CHARSET. The
   listing's `UID SEARCH ALL` is unchanged: it is what the pages walk.
   Without ESEARCH the plain SEARCH goes as before. An answer is taken
   for what it says and no more. A MIN is the lowest, and so is the
   lowest of an `ALL` set. Nothing matched is an ESEARCH line with
   nothing after `UID`, or `COUNT 0`. A server that took no notice of
   RETURN and answered with a plain `* SEARCH` line has answered: the
   lowest of that is taken, nothing for `* SEARCH` alone, and the SEARCH
   is not sent twice. Anything else has the plain SEARCH sent in the
   same hold: a NO or BAD; an answer with neither line; an ESEARCH line
   not saying UID; one that says something, but not the lowest, `COUNT
   37` or `COUNT 12 MAX 900`; and one malformed, `UID MIN` with no
   number, a MIN of 0, a set with `*` in it. So an answer Gmail did not
   give is never taken for nothing found, and the ESEARCH line is never
   read by the plain parser, which would read it as a SEARCH that found
   nothing. Not known: whether Gmail does RETURN (MIN) as the RFC has
   it, which the fallback covers, and whether it answers any sooner for
   it.
3. *The SEARCH line read off its bytes.* A line that is exactly `* SEARCH`
   or `* SORT`, in either case, then numbers each after one space, is read
   in one pass over its bytes (`IMAPParser.plainSearchNumbers`). Any other
   line goes to the tokenizer as before: a range, CONDSTORE's `(MODSEQ
   7)`, `* 4231 EXISTS`, a second space or one at the end, a tab, a
   number of eleven digits or past `UInt32`. So for a line taken the two
   give the same numbers by construction. 400,000 UIDs, about 3.2 MB:
   632-641 → 5-7 ms in a release build here.
4. *The line's end searched once.* The buffer keeps how far a fruitless
   search got as a count of bytes from the front, used only as an offset
   into the bytes themselves, never as an index of the `Data`, which
   PERFORMANCE.md warned would desync the stream (`ReadBuffer.scanned`,
   `lineEnd`). The next search starts one byte before it, for a CR whose
   LF is the first byte of the next chunk, and the count goes back to
   nought whenever bytes leave the front, by a line or by a literal. 3 MB
   in 16 KB chunks: 453-735 → 3-4 ms; in 4 KB chunks: 1.8-2.3 s → 0.4 ms.
5. *The files go when they are done with.* The reading pane's copy of
   the last file he opened goes as the next is written, and at launch,
   so there is one on disk at most. Not as its preview closes: Print
   reads the file after its panel has closed, and a copy taken from
   under a print still reading it could print blank. A print still
   reading one file when he has closed it, tapped another and that has
   come is the one case left. A file that comes while a preview, or
   anything else, is up over the pane is not shown, as before, since
   UIKit presents nothing over a presentation, and now not written
   either. The composer records every
   photo it stages and removes them in its `deinit` (`StagedFiles`): Send,
   Save Draft, the autosave and the keep as he leaves the app each hold
   the composer, through the closure that hands them the letter, until
   their work is done, the upload and the keep and APPEND included, so it
   cannot go while one of them still reads a photo. A removal takes a
   file's directory only when that is a UUID directory directly in
   `tmp/Attachments` (`AttachmentStore.stagingDirectory`). A letter kept
   on the iPad has its photos hard-linked into its own directory
   (`LocalDraftStore.keep`), which survive the staged copies, and those,
   or any URL into that directory, are never touched. The share
   extension's staging is its own, emptied at its launch, as before.

Nothing else changes on the wire: the same commands, but for RETURN (MIN)
in a jump; the same listings, pages and landings. No new words on screen.
The new connection-log lines are `SLOW <VERB> ms=<n> quiet=<n>`, the
jump's `UID SEARCH RETURN (MIN) …` with its `* ESEARCH …` answer, and
`DEADLINE read serverWork bound=90s` if that bound ever fires.

**Tests.** `SearchLineTests`: every line on the byte path gives what the
tokenizer gives, and each kind of line that is not, a range, a trailer,
a second or trailing space, a tab, `4294967296`, eleven digits,
`SEARCH1`, `SEARCHES`, `* 4231 EXISTS`, an ESEARCH line, goes to the
tokenizer and gives what it gives; an answer's lines together keep their
order; a line with a literal is never taken; 400,000 UIDs read right in
under half a second in the suite's debug build (the test about 0.13 s);
ESEARCH's answer read for its lowest, from MIN or else from ALL's set
however it is written, none only for nothing after `UID` or `COUNT 0`,
and nil, to be asked again, for items that do not say the lowest (`COUNT
37`, `COUNT 12 MAX 900`, `MAX`, `MODSEQ`), for a malformed one (`UID
MIN`, `COUNT` alone, MIN 0, `+5`, `4294967296` or `x`, a set with `*`,
an empty part or three ends, a list for a name), and for one not saying
UID; and a plain `* SEARCH` answer told from none at all, `* SEARCH`
alone being nothing found. `ReadBufferTests`: a
long line in chunks of 1, 2, 3, 7 and 1,024 bytes and a tagged line after
it, each byte searched about once (`ReadBuffer.examined`); a CRLF split
across two chunks; a CR alone at a chunk's end with no LF after it; a
literal taken after a fruitless search, then the line after it, twice;
empty lines; forty seeded streams of lines and literals in random chunks
read as sent; and a 3 MB line in 16 KB chunks found in one pass, in
under a second. `LowestMatchTests`, the real client against the scripted
server, which now answers RETURN (MIN), MAX and COUNT with ESEARCH, and
refuses RETURN with NO when told to, or BAD without ESEARCH, or answers
it with a plain SEARCH or with items of the test's making: the jump's
SEARCH asks for its MIN and gets the lowest a plain SEARCH would have, the
listing still asked for whole and the ESEARCH line in the connection
log; no MIN is nothing matched, with nothing asked again; without ESEARCH
a plain SEARCH; a refused RETURN asked again plainly in the same hold on
the same connection; a plain `* SEARCH` answer to RETURN taken, its
lowest and its none, with nothing sent twice; an answer of the count, the
count and the highest, the highest, MIN with no number or MIN 0 asked
again plainly in the same hold and landing on the same letter; and an
answer of ALL's set, written out of order, and of a count of none, taken
with nothing asked again. `GoToDateBoundTests`: the dated SEARCH on the wire
is `UID SEARCH RETURN (MIN) …` and then `UID SEARCH ALL`; and nine jumps,
in UTC, New York and Tokyo, nothing that recent among them, land on the
same letter, the same day and the same window with ESEARCH and without
it; B-058's eleven there and the 24 of `DateJumpTests` pass as they
were. `DeadlineWireTests`, the ordinary deadline 60 ms where the device's
is 30 s: a SEARCH, a SELECT and a STATUS silent for 90 ms, the device's
45 s, are waited for, on the same connection, and so are Go to Date's
`UID SEARCH RETURN (MIN)` and the plain SEARCH sent again when a server
refuses CHARSET, each silent as long; a FETCH and a NOOP silent
as long are cut off at 60 ms; a SEARCH, a SELECT, a STATUS and the
jump's RETURN (MIN) whose untagged lines come at once and whose tagged
line comes 90 ms after the client has read them are waited for, on the
same connection, and a FETCH answered that way is cut off at 60 ms; a
SEARCH never answered is cut off at three ordinary deadlines, 180 ms,
with `DEADLINE read serverWork bound=0.18s`; answers held while a test
clock moves 41.25 s, 6.5 s and 4.9 s give `SLOW SELECT ms=41250
quiet=41250` and then `SLOW UID SEARCH ms=6500 quiet=6500`, not the
SELECT's 41250 again, without the words searched for or the mailbox,
and nothing for the third; an answer whose start comes 2 s in and whose
tagged line 13 s after gives `ms=15000 quiet=13000`, one whose start
comes at once and whose end 15 s after `quiet=15000`, one of 13 s and
then 2 s `quiet=13000`, and one of 7.5 s twice `quiet=7500`, the
longest and not the first, the last or the sum; no note for an answer
held three hours while the app went away and came back, nor for one
the app went away during, and a note again for the next; and
`AppDelegate` counting both, read from its source. `AttachmentStoreTests`: only a UUID directory
directly in the store counts as staging, not a kept letter's file, the
store, a deeper directory, one not named by a UUID, a way out of the
store or a URL that is not a file; removing one takes its directory and
nothing else; the pane's way with three files in turn leaves one copy at
most, the last, whole, until the launch's purge; a composer's photos go
and a kept letter's
hard-linked photo stays, byte for byte, with the kept file's own URL
handed in too; and the pane's and the composer's wiring, read from their
source, the pane removing a copy only as the next is written, with
nothing told when the preview closes. `ComposeActionsTests`: Send and Save Draft hold the composer, by
the letter closure, until their work is done, and let it go after.

Each fails with its part undone, sixteen sabotages one at a time, each
run once over the whole suite, serially: the byte path never taken (1,
the 400,000 UIDs taking 2.1 s; the known `LargeLetterTests` timing flake
failed in the same run, 2 in all), any byte not a digit taken for a
separator, as the naive scanner PERFORMANCE.md warned of (13), no digit
cap or overflow check (6), the line's end searched from the front every
time (6, 279 MB looked at for the 3 MB line), the search resumed where the
last stopped rather than a byte before (40), the place kept after a
literal is taken (5), the dated SEARCH sent plain (7), the ESEARCH answer
read as a plain SEARCH (23, in 16 tests, every jump landing nowhere), a
refused RETURN not asked again (1), the three on the ordinary bound (3),
every reply on the long bound (4), the SLOW note carrying the whole
command (1), any parent taken for a staging directory (8, the kept
letter's photo deleted), the pane's last copy left as the next is
written (1), the composer's photos removed as the sheet goes rather than
when it is let go of (1), and Send letting go of the letter closure once
it has the letter (1). Those sixteen were counted before the review's
fixes below.

**Reviewed 2026-10-03, and fixed.** A review of the change above found
seven things, each fixed in the text above, which says how it is now:
an answer to RETURN (MIN) that was a plain `* SEARCH` line was thrown
away and the SEARCH sent again; an ESEARCH answer with items but no MIN,
`COUNT 37`, `ALL 3:9`, `COUNT 12 MAX 900` or a malformed `UID MIN`, was
read as nothing matched, the very thing the change said could not
happen; no test held the jump's RETURN (MIN) or the SEARCH sent again
without CHARSET to the long bound; the SLOW note timed the whole answer
and was read as the margin to a bound that times only silence, and an
answer read after the app had been suspended would have noted hours as
Gmail's; the docs left out what the bound costs; the pane's copy was
deleted as the preview closed, and Print reads the file after its panel
has closed, so a print could have come out blank; and four comments
said what was no longer so.

Each of the fixes fails with its part undone, nine sabotages one at a
time, each run once over the whole suite, serially, as failures in
tests: a plain SEARCH answer to RETURN not taken (2 in 1), items that do
not say the lowest read as nothing matched (10 in 2), ALL's set not read
(5 in 2), the jump's RETURN (MIN) on the ordinary bound (1 in 1), the
SEARCH sent again without CHARSET on the ordinary bound (1 in 1), `first`
timed to the tagged line (2 in 1), the note written across the app going
away and coming back (2 in 1), `AppDelegate` not counting the return (2
in 1), and the pane's copy deleted as the preview closes again (6 in 1).
The full suite, serially, then: 1,213 tests, 4 skipped, none failing.

**Reviewed again 2026-10-03, and fixed.** A second review found two
things, each fixed in the text above. To time the answer's first byte,
the client waited for it on a read of its own, on the command's bound,
before it read the answer. Every test's silence was spent in that read.
So the rest of an answer, once its first byte had come, was on the long
bound with no test to say so: with the answer read on the ordinary bound
the whole suite passed. On the iPad that is a SEARCH or a SELECT that
says a line at once and works on for more than 30 seconds: cut off at
30, and again on the retry, "Can't connect" for good. And `first`, the
wait for that byte, was given in the code and the docs as the number
held to the bound, when the bound is on each silence. The read of its
own is gone, and `first` with it: the note gives `quiet`, the longest
single silence, timed by the transport as it waits on the link and
started afresh as each command is written. `first` is not kept beside
it. It is not what the bound is on, a second number in the note would
read as a second margin, and the read that timed it is what hid the
first finding.

Each fix fails with its part undone, seven sabotages one at a time, each
run once over the whole suite, serially, as failures in tests: the answer
read on the ordinary bound (13 in 5, 8 of them in the new test, all four
commands), the long bound on the answer's first line alone and the rest
on the ordinary, which is what went untested (8 in 1, the new test
alone), the rest of every answer on the long bound (2 in 1, the new
FETCH test alone), `quiet` timed to the first byte alone, as `first` was
(2 in 1), the silences added up (3 in 1), the last silence taken (1 in
1), and `quiet` not started afresh for each command (4 in 3). A third
look found `quiet` untested on the other commands, which are timed the
same way: a letter's FETCH whose letter came 3 seconds in and whose
tagged line 6 seconds after is `ms=9000 quiet=6000`, and `quiet` timed on
the long bound's waits alone fails that test (1 in 1). The full suite,
serially: 1,216 tests, 4 skipped, none failing. The release build for
the iPad links.

---

## B-064 — CHANGED 2026-10-03, seen on the iPad. A reply sent from Drafts began a conversation of its own

**Found on the iPad, 2026-10-03**, on carlo's mailbox, A standing for its
address, in B-061's check (its step 3, through Drafts). A Reply All to a
letter from A to A, opened in Sent Mail, a word typed, Cancel, Save Draft,
which went as an APPEND to `[Gmail]/Drafts`. In the connection log, the
ENVELOPE of the draft saved had the letter's Message-ID as its
in-reply-to, `"<485bb5a2…>"`, and Gmail had put the draft in the letter's
conversation, under its X-GM-THRID. Opened from Drafts and sent, the letter's ENVELOPE
had in-reply-to NIL, and Gmail gave it an X-GM-THRID of its own. It began a
conversation of its own, in the Inbox and in Sent Mail, and would at
everyone it went to whose mail puts a conversation together by
In-Reply-To and References, as Mail does: it had neither. He keeps about
1,900 drafts. A reply put down and finished later is an everyday thing.

**What it was.** A draft is saved as the letter it will become, threading
headers and all, so the copy in Drafts was right. Taken up again, it lost
them. `Draft.reopening`, which makes the composer's letter from the copy
fetched out of Drafts, took its recipients, subject, words, files and
quote, and not its In-Reply-To or its References. And the letter fetched
(`Message`) had no In-Reply-To to give: only its Message-ID and its
References were read from its header. To the send, a reply reopened was a
letter begun afresh, and `threadHeaders` wrote neither header. The letter
kept on the iPad (B-051) and the Outbox (B-052) keep both, and always did;
a reply reopened from Drafts had none to keep.

**Changed.**

- The letter fetched carries its In-Reply-To (`Message.inReplyTo`), read
  from its header as its Message-ID is: as written, never decoded, since
  an id has to match byte for byte to thread.
- `Draft.reopening` takes the draft's In-Reply-To and References. A
  draft's In-Reply-To names the letter it answers. Its References, as this
  app saves it, is that letter's References with that letter last.
- The builder writes only the ids in them (`RFC5322Builder.messageIDs`):
  In-Reply-To each id it holds, once; References the ids of the
  References but those, then those. So the letter answered goes into
  References once, at the end, whether the References came from that
  letter, for a reply sent at once, from the draft, which has it already,
  or from another client's draft, which may have it earlier. It used to be
  left out only when the References ended in exactly the same characters,
  which a draft of this app's does and another client's need not, and one
  listed earlier stayed where it was, not last.
- A draft begun in another client with an In-Reply-To and no References
  goes with that In-Reply-To, and the letter it names as its References,
  as a reply to a letter with no References always did.
- An In-Reply-To another client wrote is read for its ids, `<…>` each:
  several kept, each once; a comment or a quoted phrase beside them left
  out, `<id> (Jane's letter of Monday)`; an id folded over two lines put
  back together; one without its brackets bracketed, when it is the whole
  of it, one word with an `@` in it; and words with no id in them, `Your
  letter of Monday`, no id, and the letter then answers nothing. A line
  break of any kind inside an id, CR, LF, U+0085 NEXT LINE, U+2028 or
  U+2029, is taken out, and outside one it only separates: `<id>`, a CR,
  then `Bcc: someone@example.net`, goes as the id alone. Before, the value
  went as it was written, a CR or LF made a space, U+0085 and U+2028 left
  in the header, and words were bracketed as if they were an id. Every
  header is the builder's, on lines of its own, whatever the draft held.

Every way a reply comes back to be finished goes through these: a tap in
Drafts; a hit of a search of All Mailboxes made in Drafts, which is in All
Mail (the same `loadDraft`); the letter kept on the iPad; and the Outbox. A
forward this app saved has neither header, as a forward sent at once has
not, and comes back and goes with none. A draft another client saved goes
with the In-Reply-To it was saved with, whatever kind of letter it is.

**What he sees.** Nothing new. A reply finished from Drafts is in the
conversation of the letter it answers, in his Inbox, in Sent Mail and at
everyone it goes to, as one sent at once is.

**Tests.** `DraftThreadingTests` (12), through the shipping repository,
`LocalDrafts`, the composer's own Save Draft and Send (`ComposeActions`),
the scripted IMAP server, which now writes a letter's References and reads
it back from an APPEND (`ScriptedIMAPServer.Letter.references`), and a
scripted submission server, each test reading the letter as it went after
DATA. A Reply All to his letter in Sent Mail, itself a reply, saved,
reopened from Drafts and sent, as on the iPad: the copy saved and the
draft reopened name the letter answered, and the letter sent has one
In-Reply-To, the letter's id, and one References, the letter's two
ancestors and then the letter, once. The same reply found by a search of
All Mailboxes and reopened from All Mail. Saved with no connection, kept
on the iPad, opened there after a relaunch and sent. Saved with no
connection, taken to Drafts by the pass, reopened and sent. Reopened from
Drafts, sent with no connection, and sent from the Outbox by the pass. A
letter begun afresh, and a forward, saved, reopened and sent with neither
header. A draft from another client with an In-Reply-To alone, sent with
it and with it as its References. A letter's In-Reply-To read as its
header has it, an encoded word in it not decoded, and none for a letter
without one. Thirteen shapes of an In-Reply-To and References in a draft
from another client, a comment, a quoted phrase, two ids, one id twice,
folded before the id and inside it, no brackets, words alone, a CR,
U+2028 or U+0085 followed by a Bcc or a To, a CR inside the id, and a CR
in the References followed by a Bcc, each sent with its ids alone,
every line of the header a header of its own or the fold of one with no
line break in it, one To, no Bcc, and one RCPT TO, Jane's. And the builder
given References that end with the letter answered already, which it does
not add again, and References from another client with it between two
other ids, which it moves to the end.

Each fails with its part undone, the full suite each time, failures as
XCTest counts them: the draft reopened without its In-Reply-To (42
failures), without its References (10), the letter not reading its
In-Reply-To (44), the builder adding the letter answered to References
whether it is there or not (11), leaving it where another client's
References had it (1), and the builder as it was, writing the
In-Reply-To as the header held it, made safe for the header but not read
for its ids (24). `LargeLetterTests.testPicturesStillComingWhenHeMovesOnAreCalledOff`
failed in none of these runs.

**Seen on the iPad, 2026-10-03**, on carlo's mailbox. Reply to "B-061
spellings", a letter from the account to itself, a line typed, Cancel,
Save Draft: Gmail's ENVELOPE for the draft named the letter's Message-ID
as its in-reply-to. Opened from Drafts and sent, one `RCPT TO`: the
ENVELOPE of the letter in Sent Mail named it too, where the build before
had NIL, its X-GM-THRID was the letter's, and the Inbox drew the two as
one conversation, "Carlo (2)".

**Seen on the iPad, 2026-10-03**, on carlo's mailbox, a few dozen letters,
so for what it does and not for how long Gmail takes at his size. Inbox,
Sent Mail and All Mail opened and refreshed, each `UID SEARCH ALL`
answered `* SEARCH {N uids}`. Go to Date to 20 September 2015 in the
Inbox: `UID SEARCH RETURN (MIN) SENTSINCE "20-Sep-2015" SINCE
"13-Sep-2015" BEFORE "11-Oct-2026"`, answered `* ESEARCH (TAG "a131") UID
MIN 1`, then `UID SEARCH ALL`, and the list landed on its oldest letter,
"Showing August 25", as before. The same in All Mailboxes, `MIN 1` again.
In Starred, which holds nothing: `* ESEARCH (TAG "a156") UID`, no MIN,
and "No mail on or after September 20, 2015". So Gmail answers RETURN
(MIN) as RFC 4731 has it, and neither fallback was needed. An All
Mailboxes search found as before. No `SLOW` note and no `DEADLINE` in any
of it. A letter to the account itself with two photos of 3 MB each:
`tmp/Attachments` held one directory per photo while the sheet was up,
and none once it had gone; the letter arrived once, both photos with it.
The photos opened from the letter: one directory while the preview was
up, the same one still there once it closed, and the next file opened
put its own in its place, never two. The same letter written with no
connection and Save Draft: "On this iPad only" with both photos, the two
staging directories gone, and both photos there when it was opened
again. It went to Gmail, photos and all, when the app next went to the
background, not when the connection came back: six megabytes is a large
letter, which waits for him to leave the app (`LocalDraft.isLarge`), as
before. Print was not tried; there is no printer here.

**Not covered.**

- Gmail's own conversations are not in the scripted server, which puts no
  letter in another's by its In-Reply-To. That a letter with these headers
  is put in the conversation of the letter it answers is from the iPad,
  where the draft saved was; the letter sent is the check under "Blocked
  on the iPad coming back".
- A reply already sent from Drafts on an earlier build stays in a
  conversation of its own. A draft reopened and saved again on an earlier
  build was saved without the two headers, and goes without them still:
  nothing says any more what it answered. Only the test account can have
  such drafts.
- A bare id with no `@` in it, `12345`, is no longer taken for an id, and
  a reply to a letter whose Message-ID is written so answers nothing; it
  used to go in brackets. RFC 5322 has every id with an `@`, and none was
  seen without one.
- A long conversation's References grows by one id with each reply, as it
  always has. It is never shortened, which RFC 5322 allows.

---

## B-065 — CHANGED 2026-10-03, seen on the iPad. The folder pane drew Important blank while the Outbox's block was there

**Found** on the iPad on 2026-10-03, in B-060's check, and the same with
every letter put in the Outbox after it: a letter sent with no
connection, and the moment the Outbox's block came under the folders,
the Important row went blank, its icon, name and count gone and its
separators still there. It came back when the Outbox emptied.

**What it was.** The gap between two blocks of the pane is a footer
under the upper one, a plain view painted the pane's colour. There was
one footer, under the Inbox, until the Outbox's block came; then the
folders had one too. A footer in a plain table floats: while the
keyboard of the letter just sent was up, it was pinned just above the
keyboard, and when the keyboard went it stayed where it had been
pinned, at 304 points down, over Important's row at 292 to 336, as a
build that logged the pane's views showed: every cell in its place and
whole, Important's with its name, and the footer over it. Painted, it
drew the row blank; a view like any other, it took the taps on the
middle of the row.

**Changed.** The footer is clear and takes no touch
(`MailboxListViewController`). The table's own background is the
gap's colour, so it looks as before, and a footer left where the
keyboard pinned it hides nothing and stops nothing.

**Tests.** The pane is UIKit, which the suite cannot run, so its source
is read as other wiring is (`FolderCountsTests`): the footer is clear and
takes no touch, and is not painted. Put back as it was, 2 failures.

**Seen on the iPad, 2026-10-03**, on carlo's mailbox. Two letters put in
the Outbox with no connection, the keyboard up for each: Important drawn
with its count throughout, and a tap on the middle of its row opened it.

**Not covered.** The footer is still left where the keyboard pinned it,
only unseen now; the gap keeps its place, as the table keeps the room
for it.

---

## B-066 — CHANGED 2026-10-03, seen on the iPad frame by frame, not yet at speed. The switch between two panes and three jumped

**Asked for by the owner, 2026-10-03:** "We need better transition
animation between the three-panel view and the two-panel view." The view
button's switch (B-048) was one step with nothing moving, on purpose:
animated the ordinary way, the list would have slid sideways while the
letter and every row reflowed through it, all of it moving at once. He
overrides that; D-015 has the amendment. The worry stands, and the motion
is built to answer it: calm, nothing wobbling, nothing moving up or down,
the rows he was looking at staying where his eyes are.

**What he sees.** He taps the view button. The columns slide sideways for
0.4 s, easing in and out, with no bounce. Then they settle for 0.2 s: what
moved fades where it stopped, and under it are the panes with their text
wrapped to the new widths. 0.6 s in all.

- *Three to two.* The list slides left over the folders to the screen's
  edge, its bar and its bottom toolbar with it, and the letter's left edge
  comes left with it, 205.5 pt on the 11-inch. The folders do not move;
  the list covers them. At the settle the list widens by 45 pt: the dates
  move 45 pt right, and the dots, the senders and every row's height stay.
  "< Mailboxes" and the view button's twin appear in its bar, and the
  letter wraps again at 818.5 pt. The calendar, first in the list's bar,
  goes under the corner glyph over the last of the slide and is gone for
  it, then fades in to the right of "< Mailboxes" at the settle.
- *Two with the list in front, to three.* The list slides right, off the
  folders, which are underneath where he left them, the open one
  highlighted. The letter's edge goes right. At the settle the list and
  the letter wrap again and the bars change: "< Mailboxes" goes, and the
  calendar comes about 150 pt left, into the bar's first place.
- *Two with the folders in front, to three.* The folders' column draws in
  from 375 pt to its three-pane width, cut off at its right edge, never
  squeezed, and the letter's edge goes right. Between them the list is
  there, still. The counts at the column's right end go out of it as it
  draws in. At the settle the folders' counts appear at the new edge, the
  centred "Mailboxes" over them moves to the column's new middle, a long
  name gains its "…", and the letter wraps again.

In all three the view button's glyph in the corner and the letter's
actions, Flag to Compose, do not move or blink. A divider line rides every
moving edge. Nothing moves up or down, and nothing grows or shrinks.

*The letter* goes with its left edge, where its words are fastened: the
header, a plain letter's lines, "Loading…", a conversation's names and
its letters, and a letter in HTML as most people's is written. They land
where they now are, and at the settle their lines wrap again with nothing
moving. With the pane empty, "No message selected" keeps to the middle of
the pane, going half as far as its edge, and lands on the words beneath:
nothing of it changes at the settle.

**Reduce Motion, or Prefer Cross-Fade Transitions.** With either on, the
screen as it was fades into the screen as it is over 0.3 s, and nothing
travels. Read at every tap. VoiceOver and Switch Control do not change the
motion, as they do not in Apple's own apps.

**Touches.** None is taken for the 0.6 s, 0.3 s with Reduce Motion: a
second tap of a trembling finger is one switch, and a row tapped while the
list is moving opens nothing. The keyboard is not covered, so letters typed
into a search while it moves go into the field and show at the settle.

**What stays instant.** "< Mailboxes" and a folder tapped in two panes, the
launch, a turn of the iPad, a return after a while away and the date jump
across mailboxes; and the view button's switch itself, tapped while a
list or the letter is bouncing past an end (How, below). Whether "< Mailboxes" and a folder tap should slide, as
Mail's navigation does in about 0.35 s, is a question for the owner.

**How.** Pictures move; the panes do not.

- At the tap, before anything is touched, the Mailboxes, the list and the
  letter on the screen are looked at. If any is bouncing past either end,
  from a flick or a pull, the switch is made at once, as before, with
  `pane motion: bouncing; switched at once` in the connection log, and the
  bounce is left to finish. Otherwise one still coasting from a flick is
  stopped where it is, and still pictures are cut of the screen as it is
  on the glass: one of each pane, its bar and toolbar included, one of the
  letter's actions, one of "No message selected" when the pane is empty,
  and a fresh drawing of the view button's glyph.
- Then the panes are laid out in the new arrangement at once, beneath,
  exactly as a switch always laid them out, and the layout sweep runs on
  them. Only then do the pictures go over them. Everything a switch does
  is done at the tap and is final under the pictures: the choice kept,
  nothing fetched or closed, the bars dressed, VoiceOver sent to the
  button in the corner. The letter's web view is resized once, at the tap,
  and WebKit has the whole slide to wrap it again where he cannot see it.
- No real view is moved, faded, hidden late or made to ignore a touch.
  Ending the motion at any instant is taking the pictures away, and what
  is under them is right. That is done at the end of the settle; before
  anything else lays the panes out, so a second switch, or anything else,
  is laid out at once; as the iPad turns; as the app stops being in front
  (Control Centre, the Home gesture, a call); and by a deadline a second
  after the motion was due to end, which writes `pane motion: deadline` in
  the connection log.
- If the pictures cannot be trusted, a pane not where the arrangement
  puts it or a picture that could not be taken, the switch is made at
  once, as before, with a `pane motion:` line in the connection log.

`PaneMove` (built on this host) says where each picture starts and ends;
`PaneMotion` is the UIKit half, and the only place in the app that
animates a view; `RootViewController.arrange` calls them for the view
button only. The timings are binding constants in `Theme`:
`paneSlideDuration` 0.4, `paneSettleDuration` 0.2, `paneDissolveDuration`
0.3.

**Changed, after review the same day.**

- *The empty pane's words jumped at the settle.* The letter's picture
  goes the whole of its left edge's travel, and "No message selected" went
  with it, though it is centred in a pane whose right edge is the
  screen's and does not move. It went 205.5 pt on the 11-inch, landed
  102.75 pt beside the words beneath, 143.75 pt on the 13-inch, and
  jumped back as the pictures faded. It is painted out of the letter's
  picture now, in the pane's canvas, as the twin view button is out of
  the list's, and has a picture of its own, which keeps to the middle of
  the pane in every frame and lands on the words beneath
  (`PaneMove.placeholder`). Painted out and left to appear at the settle,
  the other way proposed, it would have gone from the pane at the tap, so
  the first frame would not have been the screen he tapped, and been
  missing for 0.4 s.
- *The letter itself still goes with its edge, on purpose.* What is
  fastened to the letter's left edge, its middle and its right goes the
  whole of the edge's travel, half of it and none, and one picture can go
  only one of them. Its words are fastened to the left, and it is its
  words he reads, so it goes the whole: they land where they now are, and
  only their line ends change, at the settle, as they would anyway. Held
  still, fastened to the right, with the moving edge covering or
  uncovering its left side, a conversation's dates would stay put, and
  every word he reads would stop 205.5 pt from where it belongs and move
  there at the settle; carried half as far, every word half that. Faded
  into the letter beneath at the settle, the third way proposed, is what
  the settle already does, wherever the picture has gone.
  What the app knows is fastened elsewhere is cut out and goes as it is
  fastened: the letter's actions hold still, as before, and the empty
  pane's words keep to the middle. `PaneMove.Reading` is the choice, and
  `PaneMoveTests` checks it. A conversation's dates and a sender's
  markup laid out in the middle are in WebKit's drawing with the words
  beside them, and cannot be cut out: Not covered.
- *A bounce at the tap jumped at the settle.* One coasting from a flick
  was stopped where it was, and one bouncing past an end was brought back
  inside first. But a picture cut with `afterScreenUpdates: false` is of
  the last frame drawn, before it was brought back, so its rows jumped up
  or down to the end at the settle. Now a bounce is looked for first, in
  every pane in the pictures, and turns the motion down (How, above); only
  one coasting inside its ends is stopped. Where each comes to rest is
  `PaneMove.Rest`, as UIKit reckons it: from the content's top with the
  top inset above it to its bottom with the bottom inset below it, the
  bottom end never above the top, and the same sideways. Past it by more
  than half a point, a pixel on his iPad, is a bounce; less is taken as at
  the end, and brought there as it is stopped.

**Tests.** `PaneMoveTests` (14) and `PaneArrangementTests` (3 more, and its
`PaneShell` tests now say what each change was laid out from).

- `PaneMove`, by value, at every landscape width from 1024 to 1376 pt.
  Only the view button's three switches move, and "< Mailboxes" and a
  folder tap do not. Each move written out at 1194 and 1366: every
  picture, line, backdrop and the actions' picture, in order, and the
  twin button painted over only in the list's picture from two panes. At
  the start every picture and line is where its pane and divider are, and
  at the end where they now are, worked out from the columns alone. At
  every twentieth of the slide each line is on its edge and the letter is
  on top; every picture keeps its width, and in each switch they all go
  the same way; there is no y in the model. Every half point across the
  screen is under a picture, a line or the backdrop, or in the stretch of
  the real screen meant to show, which is exactly what shows at the end.
  The backdrop between the list and the letter is never wider than the
  list's change of width, 45 pt. The actions' picture holds still, wide
  enough for the letter's own actions to stay under it. And the timeline:
  0.4 s then 0.2 s, or 0.3 s alone.
- Since the review: the letter's picture goes the whole of its edge's
  travel, in one piece, whatever the pane holds, and with words in it
  nothing is cut out; an empty pane's move is the same in every other
  part. "No message selected" starts in the middle of the letter's column
  as it was and ends in the middle of the column as it is, worked out from
  the columns alone, is in the middle at every twentieth of the slide,
  with 150 pt of room either side, and goes half as far as the letter,
  102.75 pt less at 1194 and 143.75 pt less at 1366. And where a list, the
  Mailboxes or a letter rests: a long list, a short one whose top end is
  its bottom, a letter wider than its pane with insets all round; at
  either end and inside it rests, past either end or either side by more
  than half a point it is bouncing, and less is brought to the end.
- `PaneShell`: the view button says what it switched from, from each of
  the three places it can be tapped; "< Mailboxes", a folder tap either
  way, a folder opened and a return say nothing. The test that nothing
  goes on the wire is unchanged.
- `RootViewController`, `PaneMotion` and `MessageDetailViewController`,
  which are UIKit, are read. A switch still moving is ended first thing in
  `arrange`, as the iPad turns and as the app stops being in front. The
  pictures are cut before the panes are sized and the constraints
  swapped, after coasting is stopped, with Reduce Motion asked at the tap;
  the cover goes on after the layout sweep. The buttons know nothing of
  the motion, and the container still animates nothing itself. The
  pictures are of the screen as it was; the cover takes every touch and is
  hidden from VoiceOver; frames are set sideways only, eased in and out,
  for the timeline's durations and no others, with no spring, no
  transform, nothing flexible and nothing of a real view touched; the
  deadline is stretched by the window's speed; every end acts only for
  its own cover; and the letter's bar has no title and nothing on its
  left, so its actions' picture is right at both ends. Since the review:
  the container tells the model whether the pane is empty and hands over
  "No message selected"; the motion refuses it unless it is centred where
  the model says, paints it out of the letter's picture in the canvas
  colour, and puts its own picture over the letter's and under the
  dividers, going only as far as the model's middle. The container looks
  for a bounce in the Mailboxes, the list and the letter, when there is
  one, after checking the screen is as laid out and before anything else,
  turns the motion down with its line in the log, and only then stops
  one coasting, and nothing else in it scrolls anything; the motion's
  check reads `PaneMove.Rest` from all four of UIKit's insets and does
  nothing, and its stop acts only inside the ends. The letter's pane only
  hands over its scroll view, none when it is empty, and its words.

Each of 26 sabotages fails at least one of these, one at a time in a
scratch copy, the full suite each time, failures as XCTest counts them:
the list's end off by 45 pt (207 failures), the pictures in the wrong
order (11), the backdrop left out from three to two (371), or begun at the
screen's left edge from two to three (11), the folders' column cut to 375
pt (209) or to nothing (450), the list's divider off its edge (206), the
twin painted over from three to two and not from two (22), the actions'
picture at the letter's two-pane edge (573), pictures taken after the
screen is drawn again (2), a y in the slide (1), a transform (2), a spring
(1), Reduce Motion ignored by the container (2) or by the motion (2), the
motion not ended in `arrange` (2), as the iPad turns (1) or as the app
stops being in front (2), a deadline the window's speed does not stretch
(1), the view button not saying what it switched from (5), "< Mailboxes"
saying it (3), the pictures cut after the constraints are swapped (2), the
cover put on before the layout sweep (1), a picture that stretches with
its holder (1), the cover's own alpha faded (2), and coasting not stopped
(1). `LargeLetterTests.testPicturesStillComingWhenHeMovesOnAreCalledOff`
failed once, in the first run of the backdrop left out, which counted 372;
run again, 371, as given. It failed in no other run.

After the review, 24 more, the same way, each failing at least one of the
tests above, none failing any other test, with no unexpected error: the
empty pane's words carried as far as the letter (596 failures), cut out
of a letter too (60), or not cut out at all (28); the letter's picture
held still from three to two (390); the container saying the pane always
holds a letter (1), or not handing over the words (1); the words left in
the letter's picture (2), painted out in the bars' colour (1), their
picture put under the letter's (1), carried twice as far as the model
says (1), or taken wherever they are (1); a short list's bottom end below
its top (2); the bottom inset left out (2); sideways not looked at (6);
no slack (3), or five points of it (5); the bounce not looked for (1),
looked for after coasting is stopped (2), or turned down with no line in
the log (1); the letter not looked at (1); a bounce brought back inside,
as before the review (1); a bounce read the wrong way round (1); the side
insets left out (1); and a letter looked at while the pane is empty (1).
The suite ran clean before the first of them and after the last.

**Not covered.**

- Everything the screen draws is for the iPad, and none of it has been
  seen yet; TODO has the checks. The first is the letter's picture. WebKit
  draws a letter in another process, and whether a still picture of it
  comes out whole on his iPadOS is not known. A picture that cannot be
  taken falls back to the instant switch; a blank one cannot be told from
  a white letter cheaply.
- From three to two, a strip of empty canvas opens to the right of the
  sliding list, where the list will widen, and is 45 pt wide at the end of
  the slide at 1194, 75 pt at 1024. The selected row's grey ends short of
  it until the settle.
- A subject that wraps differently moves the letter's body by a line at
  the settle, not while anything moves; a letter scrolled down shows other
  words at its top once it has wrapped again. Neither is new.
- A conversation's dates, at the right end of its rows, ride with the
  letter's picture. From three to two they stop 205.5 pt short of the
  right end on the 11-inch and are put there at the settle; from two to
  three they go off the right edge with the rows' ends and are back at
  the settle. The rows' grey previews are cut again to the new width at
  the same moment. So with anything a sender's markup lays out in the
  middle, a newsletter's column: it lands up to half the edge's travel
  from where it is, 103 pt at 1194 and 144 at 1366, and is laid out
  again at its new width at the settle anyway. WebKit draws both, in
  another process, into the same picture as the words beside them, and
  where they are is not known at the tap; holding the letter still for
  them would move every word he reads instead. Whether the dates catch
  his eye is for the iPad.
- A switch tapped while the Mailboxes, the list or the letter bounces past
  an end is instant, as every switch was before B-066. A bounce lasts
  about half a second after a flick or a pull past an end. A bounce of
  less than half a point is taken as at the end and brought there as it
  is stopped, a pixel at most, at the settle.
- A heavy letter WebKit has not finished drawing by 0.4 s shows as it
  would have without the motion.
- The glyph in the corner is drawn afresh and has to match the button's
  own pixels. If it shimmers at the settle, a picture of the corner will
  do instead, at the cost of the button looking pressed until the settle.
- Touches are not taken for 0.6 s.
- This is the first view animation in the app's sources. It is kept to
  `PaneMotion.swift`, and the tests read that file and the container for
  anything else.
- "< Mailboxes" and a folder tapped in two panes stay instant, as built.
  Whether they should slide like Mail's navigation is the owner's to say.

**Seen on the iPad, 2026-10-03, frame by frame**, on carlo's mailbox at
1194 pt, on a scratch build with the window's `layer.speed` at 0.05, the
slide 8 s and the settle 4 s, six screenshots through each switch, the
Inbox listed and the pane empty. In all three the columns travelled as
described, whole, sideways only; the corner glyph and Flag to Compose
stood still; "No message selected" kept to the middle of the pane; and
the last frame was the final screen with nothing left over it. The
settle is a cross-fade: in its middle frame the old rows and the new,
wrapped again at the new width, are both to be seen, as are the old bar
and the new. At 0.2 s that is a dissolve. The calendar went under the
glyph from three to two, and from two with the folders in front the
counts were gone from the folders' column until the settle, as above.
Not yet at speed, nor with a letter open, a conversation, Reduce Motion,
VoiceOver or a bounce: TODO's checks 2 to 12.

**For the owner** (TODO, "Blocked on the owner"). The third switch, the
folders' column drawing in, has nothing like it in Mail; its fallback is
the 0.3 s fade for that switch alone. The timing, 0.4 s and 0.2 s. The
list sliding over the folders, against later Mail's way, where the folders
slide off to the left. And "< Mailboxes" and a folder tap, above.
*Ruled 2026-10-06: "copy apple mail for these". B-077 has what was
built: one half-second motion on UIKit's spring with no settle, Mail's
rule for Reduce Motion, and "< Mailboxes" and a folder tap sliding as a
pop and a push.*

---

## B-067 — CHANGED 2026-10-04, seen on the iPad. "Save to Photos" on a picture in a letter ended the app

**Found** in the plan for the install, and on the iPad on 2026-10-04: the
app's Info.plist said nothing of Photos. A long press on a picture in a
letter, the signature's logo in a letter to the test account, offers
"Save to Photos". Tapped, the app ended at once: iOS ends any app that
asks for the photo library without saying why, and its crash report
said so, naming `NSPhotoLibraryAddUsageDescription`. "Save Image" was
missing from a file's preview: iOS leaves it out for such an app.

**Changed.** Info.plist has `NSPhotoLibraryAddUsageDescription`, which
saving a picture asks for, and `NSPhotoLibraryUsageDescription`, which
nothing in the app asks for, since the composer's photo picker runs
outside it, but whose absence would end the app the same way if a
system screen ever asked. Both say "Blackmail saves the pictures you
choose to Photos."

**Tests.** `InfoPlistTests` reads `Resources/Info.plist` as the build
copies it: both keys are there and say something. The add key taken out:
1 failure.

**Seen on the iPad, 2026-10-04**, on the build with the keys. The same
long press and "Save to Photos": the app stayed, and iOS asked
"'Blackmail' Would Like to Add to your Photos", with the words above.
Don't Allow was tapped, to leave the iPad's library as it was, and
nothing ended. With "Add Photos Only" chosen in Settings, Privacy,
Photos, Blackmail, a file's preview had "Save Image" under Copy. Then,
the owner having said the iPad's library may be used for such checks,
both were tapped: "Save Image" put the attachment, a 3 MB JPEG, in the
library, and "Save to Photos" on the logo a PNG of it, the app staying
and no crash report written.

**Not covered.** The share extension asks for nothing of Photos and has
no keys. Saving is iOS's own, once allowed.

---

## B-068 — FIXED 2026-10-05, seen in the iPadOS 18 simulator and on the iPad. A plain letter began with its own Content-Type

**Found** on 2026-10-05, in the pass on the iPadOS 18 simulator, and the
same on 17.5, so not new in 18. A letter with no HTML twin and no files,
his words under a plain signature or none, arrived with two lines above
his words: `Content-Type: text/plain; charset=utf-8` and
`Content-Transfer-Encoding: quoted-printable`. They were in the row's
preview, in the reading pane, and in any reader's client. A draft of such
a letter came back with them as words he could edit, and each save after
that wrapped them again: two lines and a blank one more each time. The
test iPad never showed it. Its signature has a logo, so every letter there
had an HTML twin. A fresh simulator has no signature.

**What it was.** `RFC5322Builder.build`. A letter of one part has its
Content-Type and transfer encoding in the message's own header. The plain
text was made once, as a part: the same two lines as a part's header, a
blank line, then the text. That is right inside a multipart/mixed, a
plain letter with files, where the part needs a header of its own. With
no boundary it was written as the body as it was, header and all. The
app's Send, the Outbox, Save Draft, Local Drafts' uploads and the share
sheet all build through it (`Submission.send`, the repository's draft
APPEND), so every path had it.

**Changed.** A letter of one part is its header, a blank line, and the
encoded text, nothing more. Nothing follows the last line, so a draft
comes back exactly as he left it. SMTP ends the line itself
(`SMTPClient.dataPayload`), so a letter sent arrives with one line break
after his last word, as before. Every shape with more than one part is
byte for byte as it was. No other code builds a letter.

**Letters already sent or saved** are left as they are. A letter sent
cannot be changed. The drafts with the lines are the test account's: his
own mailbox has never had a Blackmail draft (his 1,900 are Apple Mail's),
and Blackmail is not yet on his iPad. One reopened now keeps its lines as
words, and saving it adds no more; they can be deleted by hand, or the
draft. No code repairs them, for want of anything to repair.

**Tests.** `PlainLetterTests`, 14 tests. Built and read back with
`MIMEDecoder`, as the pane reads a letter: nine bodies come back to the
character (blank lines, a space at a line's end, `=`, a long line,
letters outside ASCII, a line of one full stop, a line that looks like a
header, nothing at all); the letter is one part, each of the two lines
said once, and the list's preview begins with his words. A plain
signature, and a signature with a picture taken out of the letter, give
no HTML twin and one part. Sent through the repository over the scripted
submission server, with no signature and with a plain one, and shared
from the share sheet as words from Notes: one part, his words first. A
draft saved and reopened three times over the scripted IMAP server,
unchanged and changed between saves: the copy stored begins with his
words, and the draft comes back as it went. And six shapes byte for byte,
with a fixed date, id and randomness: plain, mixed, alternative, related,
alternative with a file, and all of them together. The five multipart
ones were taken from the builder before the change. The fix undone: 55
failures in 9 tests, the five multipart pins passing. The two lines taken
off the part instead, for every letter: 14 failures in 6 tests, the mixed
pin among them. A line break after the last line: 13 failures in 5
tests. The round trips already in the suite (`OutgoingMailTests`,
`RepositoryWireTests`) checked only that his words were somewhere in the
body, which is how the lines passed them.

**Seen in the simulator, 2026-10-05**, an iPad (7th generation) on iOS
18.6, built from this change, signed in to the test account, with no
signature. A new letter to the test account's +sim18 address, "B068
plain letter 1", two paragraphs with an `=` in the second, Send. In the
Inbox the row's preview read "Dear Carlo, See you on Sunday at one. B068
= plain."; in the pane, "Dear Carlo," came first, then a blank line, then
the second paragraph, and no header lines.

**Seen on the iPad, 2026-10-05**, built from this change, on the test
account. Its signature has a logo, which makes an HTML twin, so the
signature was taken out of a new letter by hand, leaving two lines with an
`=` in each. Saved as a draft: the Drafts row read "First line = one.
Second line, 2 = two.". Reopened, it held the two lines and nothing above
them; a word added and saved again, it came back as left, and Gmail kept
one copy, `text/plain` with the lines as typed, `=` written `=3D`, and no
line break after the last. Sent from the draft: it arrived as one part,
the two lines and the word, one line break after the last, and the draft
was gone from Drafts. In the pane, the two lines and nothing above them.

**Not covered.** Nothing left for the iPad. Letters and drafts saved
before the change keep their lines (above).

---

## B-069 — CHANGED 2026-10-05, seen on the simulator and on the iPad. The composer and the share sheet behave as Apple Mail's

**Found** in the iPadOS 18 pass of 2026-10-05, on a simulated iPad (7th
generation) on 18.6, and the same on 17.5: ten ways the app's composer,
and the share sheet's small one, did not do what Mail does. The rule is
Mail's wherever Mail has an answer (D-012). Each is below: what was
found, what Mail does, what changed, and what the simulator showed.

The simulator is an iPad (7th generation), landscape, 1080 by 810
points, built from this branch and signed in to the test account, with a
hardware keyboard attached unless the on-screen one is said. Its
signature was set to a stand-in, "Sam" over "1 Example Street". The
screenshots named are in the pass's shots folder, not in the repo: the
letter rows behind the sheet show a real signature. Those named fx-
are from the second pass, after the review below, on a fresh simulator
with no signature set.

1. **The keyboard.** *Found:* with the on-screen keyboard up, the body
   ran on under it. It was pinned to the bottom of the sheet, and
   nothing in the composer watched the keyboard, as the set-up and
   Settings screens do. A line or two of it showed, and the caret went
   under the keyboard as he typed. *Mail:* the letter ends above the
   keyboard, the fields over it scroll away with it, and the line he
   types on stays in sight. *Changed:* the fields and the body are one
   scrolling sheet, and its bottom is the top of the keyboard
   (`keyboardLayoutGuide`), in both composers. The body is as tall as
   its words, and at least the rest of the sheet. As he types, as he
   moves the caret, and as the keyboard comes up, the line he is on is
   scrolled into sight, and the fields above it go up out of the way.
   He can scroll them back down with the keyboard still up. The list
   under an address field moves with its field. With no keyboard, or a
   hardware keyboard and its bar alone, the sheet's bottom is where it
   was, and nothing moves.

   The first build ended the body at the keyboard under fields that
   never moved. In landscape that left the body 130 points with the
   fewest fields, 42 with Cc and Bcc open, and nothing at all under a
   forward's six files, where the body dropped out of the accessibility
   tree and he typed blind (found in review).

   *Seen:* the first build, 130 points and the caret kept on the last
   line showing (b069-18 to b069-21, b069-63 on 17.5, b069-45 and
   b069-46 in the share sheet). The second pass: a forward of a letter
   with six files, on-screen keyboard, the fields went up and the caret's
   line showed just above the keyboard (fx-04). Ten lines typed, it
   stayed there (fx-06). Scrolled back down, To, Cc/Bcc and Subject
   showed with the keyboard up (fx-07), and the next key brought the
   caret back (fx-08). A new letter with Cc and Bcc open, six lines: the
   same (fx-12). The share sheet the same, over Safari with eight lines
   (fx-18) and over Photos with five photos attached (fx-37). With the
   hardware keyboard the body was 408 points tall and reached the
   sheet's bottom, as before (fx-28). A swipe down still reached
   Cancel: on the sheet's bar the question for a changed letter
   (fx-09), and in the body of one as it opened, the sheet closed.
2. **The suggestions.** *Found:* once an address was picked, the list
   opened again at once with his most used, over Cc/Bcc, Subject and
   Attach Photo. The pick refreshed the list with nothing typed after
   the comma, and nothing typed offers everyone. The same in the share
   sheet, seen on the test iPad too. *Mail:* the list closes once one is
   picked, and comes back when he types again. *Changed:* what a field
   offers is `ComposeForm.suggestions`, in both sheets. A pick closes
   the list until he types. Going into an empty field still offered his
   most used, which made his own second address one tap (B-036); a
   field that already held an address offered nothing until he typed.
   Since B-073 no field offers anything until he types, empty or not,
   as in Mail: the owner's choice, 2026-10-06.
   No address already in the field is offered again, in any spelling.
   *Seen:* To, empty, offered four; the first picked, the list closed
   and Send went blue (b069-12, b069-13). "c" typed after it offered
   four others, not the one picked, which had been first and matches
   "c" by name (b069-14). The share sheet the same (b069-32, b069-33).
   In the second pass, the list under To in the new layout, and closed
   after a pick with Send blue (fx-26, fx-27).
3. **Tapped or swiped away.** *Found:* one tap outside the sheet closed
   it at once, the letter put in Drafts with nothing asked, and a swipe
   down did the same. *Mail:* a tap outside does nothing, and a swipe
   asks what Cancel asks. *Changed:* the sheet is held throughout
   (`isModalInPresentation`), not only while a letter goes, and a swipe
   is Cancel (`presentationControllerDidAttemptToDismiss`): the question
   for a letter he changed, the sheet closed for one as it opened. While
   a letter goes a swipe does nothing, as Cancel is held then. The share
   sheet is held the same way, and a swipe there is its Cancel. A tap
   outside the share sheet is the sharing app's to answer: the
   extension's flag does not reach it, and the share goes, letter and
   all. *Seen:* a tap outside the app's sheet, on a letter untouched and
   on one with a word typed, left it as it was (b069-02, b069-03). A
   swipe on the changed letter put up Save Draft and Delete Draft
   (b069-04); on an untouched letter it closed the sheet (b069-54). The
   same on 17.5 (b069-60, b069-64). In the share sheet over Safari, a
   swipe with "x" typed in To put up Delete Draft (b069-42, b069-52),
   and on the share as it began closed it. A tap outside it closed it:
   a build that logged the extension's calls showed it told only that it
   was going, never asked (b069-34, b069-36). In the second pass, with
   the fields and body in one scroller, a tap outside the app's sheet
   still did nothing, and a swipe still asked (fx-09).
4. **Cancel on a letter never touched.** *Found:* Cancel on a new letter
   he never touched asked Save Draft or Delete Draft. The body starts as
   a blank line over his signature (`Draft.blank`), and Cancel asked
   whenever the body or the subject had anything in it. *Mail:* an
   unchanged letter closes without a word: a new one, a reply or a
   forward. *Changed:* Cancel compares the letter with how it opened,
   read back off the form as the sheet opens: the people in each field,
   the subject, the body to the character, and the files
   (`ComposeForm.asksBeforeClosing`). As it opened, or emptied by hand
   as before, the sheet closes with nothing asked
   (`ComposeActions.closeWithoutAsking`). What the sheet kept on the
   iPad goes, and words typed and taken out again are kept as they are
   now, over whatever the autosave kept of them meanwhile. A letter
   opened from the Outbox goes back to the Outbox
   (`DraftKeeping.putBack`), with whatever may already have reached
   Gmail and under the same Message-ID, so it is looked for first
   (B-052). In the first build it stayed in Drafts, never to be sent:
   kept again as he wrote, it had come out of the Outbox, and nothing
   put it back (found in review). A photo still coming in from the
   picker is a change. So is a Send from the sheet that the server
   refused: Cancel then asks, whatever the form reads
   (`ComposeActions.asksAnyway`), since the refusal took the letter out
   of the Outbox, and put back without a word it would be tried again
   by the next pass. The share sheet already measured
   against the share as it began; a file taken off now counts too.
   *Seen:* a new letter with the signature, Cancel: closed (b069-08).
   "Hello" typed, left past the autosave's pause, taken out, Cancel:
   closed, and Drafts empty (b069-05, b069-06); the same again in the
   second pass, with "x" (fx-29). An untouched reply and forward: closed
   (b069-24, b069-25). Each changed letter asked. The Outbox was not
   seen: the simulator's line is the Mac's, and cannot be taken down for
   it alone.
5. **Return and Tab from Subject.** *Found:* Return in Subject did
   nothing, and Tab into the body put the caret at the end, under the
   signature or the quoted original. *Mail:* Return in Subject goes into
   the body, the caret at its top, above the signature and the quote.
   *Changed:* Return in Subject goes to the body with the caret at its
   top, in both. The caret starts there as the sheet opens, so Tab lands
   there too, until he puts it elsewhere. In the share sheet a link or
   shared words open under an empty first line, where the caret is, as
   in Mail's share sheet (`ShareLetter.shown`). In the first build the
   caret was at the start of the link's own line, and what he typed ran
   into the address: "Yhttps://en.wikipedia.org/…" (b069-43, found in
   review). The line goes again if he leaves it empty
   (`ShareLetter.written`), so a share sent as it began is the address
   alone above his signature, as Mail sends it, and Cancel asks nothing
   of it. *Seen:* Return, then a letter typed: it was the body's first
   line, above the signature (b069-10). Tab the same (b069-11). In a
   reply, above the signature and the quote (b069-26; "Top" in fx-30).
   In the share sheet over Safari, the link under an empty line (fx-15);
   Return from Subject and "Have a look" typed, the words on their own
   line and the link under them (fx-16). Shared again and Cancel at
   once: closed with nothing asked (fx-24, fx-25).
6. **Send with no one to send to.** *Found:* Send was live with no
   recipient, and then said only "Message was not sent." *Mail:* Send is
   grey until To, Cc or Bcc holds an address. *Changed:* the same, by
   the send's own rule (`Submission.recipients`): an entry that is not
   blank. It follows the fields as he types and as he picks, in both
   sheets; the share sheet's other rules stand. *Seen:* grey as the
   sheet opened (b069-01), blue after a pick (b069-13), grey again with
   To emptied (b069-15). The share sheet grey, then blue after a pick
   (b069-32, b069-33).
7. **The title.** *Found:* both composers set the title once, as the
   sheet opened. *Mail:* its title follows the subject as typed, "New
   Message" while there is none. *Changed:* the same, in both
   (`ComposeForm.title`). *Seen:* "B-069 return" over the sheet as it
   was typed (b069-09, b069-10).
8. **Colours (D-010).** *Found:* the app composer's body was the
   system's dark grey, #1C1C1E, on the black sheet, and the share
   sheet's Cancel question drew light on the dark sheet. *Changed:* the
   body is `Theme.canvas` with `Theme.primaryText`, as the share sheet's
   is, and the fields' words are white. The share sheet's question is
   dark, and so is the extension's window, so whatever comes up over the
   sheet is dark too. *Seen:* the body black, 0,0,0, in both (b069-01,
   b069-32). The share sheet's question dark (b069-42, b069-47); the
   app's already was (b069-04).
9. **Names for VoiceOver.** *Found:* the fields and the body had no
   accessibility label; the captions are labels of their own. *Changed:*
   "To", "Cc", "Bcc", "Subject" and "Message", in both. *Seen:* the
   simulator's accessibility tree named the app's fields "To", "Cc",
   "Bcc" and "Subject" and the body "Message" (b069-55). The tree does
   not reach into the share extension; its names are read from the
   source.
10. **The paperclip (D-007).** *Found:* Attach Photo's paperclip grew
   with the iPad's text size and its words did not. *Changed:* the
   symbol is fixed at the size of its words. *Seen:* at the largest
   accessibility text size, 36 by 40 pixels, as at the standard size,
   while the folder pane's icons grew (b069-22 against b069-01).

**Decided here, put to the owner.**

- *Going back into To.* Built: a field that already holds an address
  offers nothing until he types; an empty one offers his most used as
  he goes in. Mail offers nothing until he types, in any field. Its way
  would take away the one tap to his own second address. The owner
  chose Mail's way on 2026-10-06: "match apple mail" (B-073).
- *An address in another field.* Built: an address in To is not offered
  again in To, and still is in Cc. Or in neither.
- *What counts for Send.* Built: anything typed in To, Cc or Bcc, as
  Send has counted it: "x" turns Send blue, and the server refuses it
  at Send. Or only an entry with an "@".
- *Return in Subject later on.* Built: the top of the body every time,
  after he has written too.
- *The empty line above a share.* Built: shown, and dropped again if he
  leaves it empty, so a share sent untouched is what Mail sends. Or
  keep it in the letter, which would put an empty first line above the
  address in every untouched share.

**Tests.** `ComposeLikeMailTests`, twenty. What the form decides,
run: the title; Send live only with someone in To, Cc or Bcc; Cancel
asking nothing of a new letter, a reply and a forward as they opened,
and asking for words, a subject, an address in any field or moved from
one to another, a file on or off, but not for words taken out again or
a blank; an emptied letter not asked about; the share sheet asking for a
file taken off; and the suggestions, closed after a pick, nothing on
going back into a field that holds an address, matches when he types
without what is in the field in any spelling, and his most used in an
empty field (nothing since B-073), in both sheets; and a shared link under an empty first
line, words typed there on their own line above it, the line gone again
when left empty, and a photo's blank letter shown as it is. The wiring,
read from the source of both composers: the sheet above the keyboard
and the caret brought into view as it comes up, the fields and the body
scrolling as one with the caret kept in sight and the list moving with
its field, a pick closing the list, the sheet held and a swipe going
to Cancel, which does nothing while a letter goes or with its question
up, Cancel
measured against the letter as it opened, Return in Subject and the
caret's start, Send and the title following the fields, the colours,
the names and the paperclip. `ComposeActionsTests`: Cancel on a letter
as it opened keeps nothing, keeps words typed and taken out again before
letting the letter go, keeps nothing emptied, does nothing while a
letter goes, and leaves nothing for a send or a save after it; a photo
coming in counts as a change, and so does a Send the server refused.
`OutboxTests`, four: an Outbox letter typed in, kept by the autosave,
taken back to how it opened and cancelled is in the Outbox again, not
in Drafts, and the next pass sends it; one whose attempt was cut off
after its DATA goes back under that Message-ID, still to be looked for;
a draft and a new letter are never put in the Outbox by a Cancel; and
after a Send the server refused, Cancel asks. Each fix of the first
build undone in a scratch copy, one at a time, the four suites run (79
tests), failures as XCTest counts them:
the app's body pinned to the sheet's bottom again (2 failures), the
share sheet's (2), the caret not brought into view (1); a pick offering
again (2), an address in the field offered again (3), a field holding an
address offering as he goes in (2), the app's pick refreshing as typing
does (1), the share sheet's (1); the app's sheet not held (1), its swipe
not sent to Cancel (1), the share sheet not held (1), the app's sheet
let go again after a send (1); Cancel asking whatever is in the letter
(5), the files not compared (2), the share sheet not counting a file
taken off (1), the app's Cancel back to asking whenever there are words
(1), words typed and taken out not kept before the letter is let go (2),
a close without asking while a letter goes (2); Return in Subject doing
nothing (1), the share sheet's caret left at the end (1); Send always
live (2), the app's Send not following his typing (1); the app's title
fixed at open (1), no "New Message" for an empty subject (2); the app's
body left grey (1), the share sheet's question left light (1); the app's
fields unnamed (1), the share sheet's body unnamed (1); and the
paperclip let grow (1). Twenty-nine in all. The first run of the app's
sheet not held failed nothing: the test found the navigation
controller's line in its place, and now reads the sheet's own.

The review's fixes undone the same way, the five suites run
(`ComposeLikeMailTests`, `ComposeActionsTests`, `OutboxTests`,
`ShareLetterTests`, `ShareSheetTests`, 144 tests): Cancel not putting
an Outbox letter back (9 failures), putting back any letter, a draft or
a new one (3), a refused Send not noted (2), the app's Cancel not
asking after one (1); the share sheet's body shown without the empty
line (3), the line kept in the letter when left empty (2), the sheet
showing the body as built (1), reading it back as shown (1); the app's
body scrolling by itself again (1), its fields fixed over it (4), the
sheet ending at the safe area (1), no least height for the body (1),
the caret not followed as he types (1), the list left behind as the
fields scroll (1); the share sheet's body scrolling by itself (1), its
sheet ending at the safe area (1), its caret not followed as he moves
it (1). Seventeen in all. The full suite: 1404 tests, 4 skipped, no
failures; `LargeLetterTests`' flaky test passed.

**Seen on the iPad, 2026-10-05**, built with B-071 on one branch,
installed through TrollStore's helper, every letter to the account
itself. A new letter: Send grey, the body black; Cancel at once closed it
with nothing asked. The address typed in part and picked: the list
closed and Send went blue. The subject typed: the title followed it.
Return in Subject: the caret at the top of the body, above the
signature. Thirteen lines typed with the keyboard on the screen: the
fields went up out of sight and the line being typed stayed just above
the keyboard. A tap outside the sheet: nothing. Then Send in Airplane
Mode: the letter went to the Outbox and said so. Opened from the Outbox,
a word typed, left past the autosave and taken out, Cancel: nothing
asked, and the letter back in the Outbox, not Drafts. Airplane Mode off:
it went once, one copy in the Inbox and one in Sent Mail, none in Drafts.
From Safari, the share sheet: Send grey, the list closing at the pick,
Send blue, an empty line above the link; Return in Subject and words
typed: they arrived on their own line above the link, in the plain and
the HTML alike, nothing else added.

**Not covered.**

- A tap outside the share sheet: the sharing app closes it, and the
  letter with it. The extension cannot hold it.
- A floating or split keyboard: the guide drops to the sheet's bottom
  for one (UIKit's default), and the body runs under it as before. Not
  tried.
- A very long letter in the body. The body no longer scrolls by itself,
  so its words are laid out whole to give it its height. A forward of
  a long newsletter was not timed, on the simulator or the iPad.
- The Outbox in item 4, on the simulator: its line is the Mac's. The
  host suite runs it against the scripted servers.
- Return in To, Cc and Bcc does what it did.
- The share sheet has no Attach Photo, so item 10 is the app's alone.

---

## B-070 — CHANGED 2026-10-05, seen in the iPadOS 18 simulator and on the iPad. Send built the whole letter in memory; videos could not go and photos were shrunk for it

**Found** on 2026-10-05, measuring the send path on this host for a video
of 19,000,000 bytes, a debug build: `RFC5322Builder.build` alone raised
the high-water mark by 71 MB, and the build with what goes after DATA,
the file still held, by 98 MB, about five times the file. Half of that
was held for the whole upload, minutes on his line. In the share
extension, allowed about 120 MB on his iPad, that is the sheet gone at
"Sending…" and the letter not sent. So the extension did not ask for
videos, and a photo went as its own bytes only while the letter fitted
the memory Send would build it in (`SharedPhoto.sendRoom`), shrunk past
it. The owner, the same day: "build the streaming Send that works from a
file on disk — his videos go up to 19 MB and it would let full-size
photos go too."

**What it was.** Every letter was made whole, twice. `build` read every
file into memory and made the letter as one `Data`, its base64 in it.
`SMTPClient.dataPayload` made a stuffed copy for DATA. `Submission` held
the first and the client the second until the 250. The app sends the same
way, and the share extension has no Outbox to fall back on.

**Changed.** The letter is made from its files as it goes, and never held
whole. Nothing new is written to the disk.

1. *A plan.* `RFC5322Builder.plan` makes the letter's text as bytes, every
   header, boundary, part header and line of quoted-printable, and a
   place for each file's base64 (`LetterPlan`). Its body is `build`'s, the
   boundaries drawn in the same order. Its length is known from the
   files' sizes alone. `build` is now the plan made whole, for a draft.
2. *The files held open.* Each file on the disk is opened once, by
   descriptor, before anything is said to a server (`LetterFiles`). It
   must be a regular file, and the size it was when attached where that
   is known; where it is not, its `LETTER-FILE` line says the size was
   not checked. It is read by position, so a file whose name is taken
   away while it goes, a second share's purge or a letter's folder
   tidied, goes whole. A forward's part is fetched as before and goes
   from memory.
3. *The rehearsal.* Before the connection, the whole letter is made once
   into a count (`DataStream`): every file read, every block of base64
   made, every byte stuffed. That gives SIZE its count, the progress its
   total, and each file's count and CRC-32. A file missing, not a file,
   not its size, or that reads short, fails there: "Message was not
   sent.", nothing on the wire, and the log says which (`LETTER-FILE 1
   refused …`).
4. *The wire.* After the 354 the same bytes are made again, in pieces of
   exactly 64 KiB but the last, so the progress is in the steps it
   always was. Each file's base64 is Foundation's, a block of 58,368 bytes
   at a time, 1,024 lines of 76 (`LetterBytes`). Every byte goes through
   one stuffer that carries its state from piece to piece
   (`DataStuffer`); `dataPayload` is the same stuffer, whole.
5. *The latch.* The terminating dot is made only once each file read for
   the wire gave the rehearsal's count and CRC and ended at its size, and
   the letter's counts are the rehearsal's. Otherwise the dot is withheld,
   the transport closed before anything else, a QUIT neither, and he reads
   "Message was not sent.". A server throws away a DATA that never ended,
   so nothing is delivered, and the Outbox settles the attempt: there is
   nothing to look for in Sent Mail.
6. *One write.* The transport asks for each piece outside its deadline,
   logs one `WIRE-OUT` and one `WIRE-ACK` for the letter, and never throws
   for a total that came out wrong: that is known only after the last
   piece, which holds the dot. It is logged, `WIRE-COUNT`. The write
   claims the letter before its first piece, and a letter claimed once is
   refused to any write after, with nothing written: the rest of one cut
   off part of the way never goes as a letter of its own, with no header
   and a dot. Every letter goes this way, one made already too
   (`SMTPClient.send(_ raw:)`).
7. *Drafts.* A draft's APPEND is not streamed. Its literal is byte for
   byte what it was, made through the same plan and the same blocks.
8. *The share sheet.* Videos are asked for, up to five, as photos and
   files are (`ShareInfo.plist`); QuickTime is taken where it is offered,
   so the original `.MOV` goes. A copied file is measured once it is on
   the disk, and that is the size Send checks it against, and the size
   its `SHARE-FILE` line gives: a copy larger than the room is logged as
   that, not as a file not copied. A video left out is counted, and said
   as a photo is: "The video could not be attached." in place of a
   letter of videos alone, "1 video could not be attached." over one with
   the rest, and "The photo and the video could not be attached." for one
   of each. The owner approved these words, 2026-10-05: "matching the
   photo wording exactly is the right call". Where they show is
   B-069's. `sendRoom` and `sendPeak` are gone: a photo goes as its own
   bytes whenever it fits the 25 MB, which is now the one bound. The
   decode guard for a JPEG made here stays.
9. *Readable while locked.* Every staged file is set to class C
   explicitly (`AttachmentStore.readableWhileLocked`): a video takes
   minutes to go, and a class A file cannot be read about ten seconds
   after the lock. Nothing stronger is set anywhere.
10. *The log.* `LETTER-PLAN files= file-bytes= raw= payload= ms=` before
    the connection, one `LETTER-FILE n bytes= crc=` for each file, with
    `attached=- not checked` where its size when attached is not known,
    and `LETTER-LATCH ok` or `LETTER-LATCH withheld file=n reason=…` at the
    end; a file that is not a picture shared, `SHARE-FILE`. The share's
    `SHARE-SEND` lines keep their words and order; "files read" is now
    the rehearsal's, and "sent" says the least memory at any step of the
    progress, `W MB at the least while it went`. Numbers and types only.

A plain letter of one part (B-068) is one piece of text: its header, a
blank line and his words, nothing after the last. SMTP's DATA is those
bytes, then a CRLF and the dot when his words do not end in a line break,
the dot alone when they do. Every other shape ends in its closing
boundary and a CRLF, and gets the dot alone.

**Tests.** Held to `ReferenceBuilder`, the builder frozen from master
f117c02, with B-068, copied whole into the test target and never edited.
`LetterPlanTests`, over 291 letters: every shape, eleven bodies, Bcc and
threading on and off, awkward file names among them the next boundary,
and files of every size about a line's, a block's and a piece's edge to
1,000,003 bytes. Each letter built, planned and made from bytes, and made
from the disk, is the reference's, byte for byte, with as many boundary
draws, and its plan's length its count. What goes after DATA needs no
stuffing: three bytes more, five for a plain letter that ends open. The
stream from the disk is the old payload in pieces of 64 KiB, and goes
once, to the one write that claims it. `Base64BlockTests`: a block at a time is the whole file's base64 at
every length to 400 and about each of the first three blocks, from
memory, from the disk, and with reads cut short at random. `DataStufferTests`:
every awkward letter of `DataPayloadTests` cut once at every place, twice
at every pair when short, and a byte at a time, and 20,000 random ones
cut at random, each the old stuffer's payload. `CRC32Tests`: "123456789"
is CBF43926. `StreamingSendTests`, through `Submission` and the shipping
client: a video and a note arrive as the reference letter, SIZE its
count, the progress the 64 KiB steps, the lines in their order; a file
cut short, grown, or rewritten at its size after the rehearsal ends no
letter, no dot, no QUIT, the transport closed, "Message was not sent.";
a file removed once opened goes whole; a file missing, a directory, a
pipe, a file not its size and one that reads short reach no server; a
letter one byte over the server's SIZE is refused before MAIL FROM, and
one at it goes. And
read from the source: no file read whole in Send, one in the draft's
APPEND, nothing stronger than class C anywhere, class C set where files
are staged. `StreamingSendMemoryTests`: the 19,000,000-byte video from the
disk raises the high-water mark by under 8 MB, measured before anything
else, and the letter that arrived is the reference's by count and CRC.
`OutboxTests`: a photo changed as its DATA goes is settled, refused "not
sent", and goes at the next launch with nothing looked for; a letter cut
off part of the way waits unsettled and goes later under its Message-ID,
planned afresh. `LinkTransportTests` and `TransportDeadlineTests`: one
WIRE-OUT and one WIRE-ACK for a streamed write, the deadline closing a
stalled one, a source failure closing the transport and thrown as it
came, a wrong total logged and not thrown, empty pieces passed over,
large ones cut, a slow piece made outside the deadline. `ShareSheetTests`:
a video staged on the disk arrives whole as `video/quicktime; name=
"IMG_0001.MOV"`, the three lines in their words with "while it went"; a
staged file changed since is not sent and the sheet stays.
`ShareItemsTests`: the video words in every combination, QuickTime first
whatever the order, a copy measured, and discarded past the room, its
measure what its line in the log says.
`ShareInfoPlistTests`: Movie 5, Image 5, File 5, WebURL 1, WebPage 1,
Text, `XPC!`, the principal class. `RepositoryWireTests`: a draft's
literal is the reference's with Bcc. `PlainLetterTests` pass unchanged.
Changed: the source pin `testEachFilesBase64IsMadeOnlyAsItIsWritten` is
gone, its place taken by these; `SharedPhotoTests` lose the room at
Send; two staging stubs write real files, since a copy is now measured;
a test whose photo was said to be 2,000,000 bytes and was 2,000 now is;
`ShareSheetTests` hand their files over as bytes through `openFile`.
`ShareSheet` keeps `readFile:` as a second initializer, for bytes in
memory, so `PlainLetterTests` stays as it was.
Sabotaged one at a time in a scratch copy, the whole suite run each time,
counted in failures and in tests. A block of 58,369 bytes: 66 in 15,
`LetterPlanTests` and `Base64BlockTests` among them. No CRLF between
blocks: 66 in 14, the same. The plan's length 2 bytes long: 232 in 32,
every letter with a file refused before the server, `LetterPlanTests` and
`StreamingSendTests` among them; the test of files that cannot go passes,
its five failing before any count. The CR of a split line break not
carried: 219 in 2, `DataStufferTests`. A line's start not carried: 321 in
2, the same. A CRLF before every terminator: 779 in 8, `DataStufferTests`,
`DataPayloadTests` and the pin that the builder needs no stuffing. B-068's
line undone in the plan: 231 in 10, `LetterPlanTests` and nine of
`PlainLetterTests`. The latch run after the last piece: 7 in 4, a file
rewritten at its size arriving, dot and all, in `StreamingSendTests` and
in the Outbox's twin. No read past a file's end: 9 in 1, the grown file.
Counts compared, not CRCs: 13 in 2. Files opened again by name for the
wire: 1 in 1, the file removed once opened. A file's failure said as a
lost line, the transport left open and a QUIT written: 15 in 3,
`StreamingSendTests`, the Outbox's twin and `LinkTransportTests`. A throw
for a wrong total: 2 in 2. A `WIRE-OUT` for every piece: 5 in 4. Pieces
of 64 KiB and a byte: 3 in 3, `SMTPSendTests`' progress among them. SIZE
from the payload: 1 in 1. The stream made whole before the write: 2 in 2,
the memory test at 51.6 MB. No check against the size attached: 10 in 2.
The Movie key taken out: 2 in 1. A video left out and not counted: 10 in
1. A copy's size as the sharing app said it: 3 in 1.

**Reviewed 2026-10-05, and fixed.** A review of the change above found
nine things, each fixed in the text above, which says how it is now. The
stream refused a second pass only once the first had ended or failed.
One cut off part of the way, by a deadline, would have handed a second
write the rest of the letter, with no header, and then the dot; a retry
that kept the stream would have had that delivered, and counted as sent.
No caller keeps one, so it was never live. Now the write claims the
stream before its first piece (`WriteSource.begin`), and a second claim
fails with nothing written. A file whose size when attached was not
known went unchecked, and its line read as a checked one's. Nothing on
the host read the sheet's counting of videos: with both counts taken
out, or the first type taken over QuickTime, every test passed, and a
video left out would have gone unsaid, the silent drop this change
exists to end. One photo and one video, neither attached, read "The
photos and videos could not be attached.". A copy that measured larger
than the room was logged as not copied, with the sharing app's size.
And four passages said what was not so: PERFORMANCE gave 0.3 MB for the
25 MB video, where it is 0.03 to 0.6; the builder's comment gave B-070
the change made before it; the photo change still had the room at Send;
and a test's comment cited a working note outside the repository, as
three others cited its labels.

Each fix fails with its part undone, twelve sabotages one at a time,
each run once over the whole suite, serially, as failures in tests: the
claim taken away, as before (11 in 3, a stream cut off and taken up
again, directly and through the transport); a claim that never refuses
(10 in 3); a piece made with no claim (1 in 1); the write not claiming
at all (347 in 125, every letter refused); a file of no known size
logged as checked (1 in 1); a video not counted as offered (2 in 1) or
as attached (2 in 1), and the first type taken over QuickTime (1 in 1),
each by the sheet's source; the plural for one of each (3 in 1); a
copy's measure kept only when it was staged (2 in 1), or never cleared
(3 in 1); and the line's reason from the sharing app's size (1 in 1).
The full suite, serially, then: 1,430 tests, 5 skipped, none failing.
The release build for the iPad links.

**Measured on this host**, the 19,000,000-byte video. The high-water
mark rose 3.3 to 4.9 MB in a process that had sent nothing before, the
thread pool and the allocator starting up, and 0 to 0.04 MB inside the
whole suite; built whole, it was 98 MB. It rose 0.03 to 0.6 MB for
25,000,000 bytes sent after it. The rehearsal took 432 to 436 ms in the
debug build, and 76 to 79 ms in a release build, three runs (101 to 113
ms for 25 MB). After the review: 4.0 MB alone, 0 and 0.01 MB inside the
suite, and 0.16 MB for the 25 MB video after it.

**Seen in the simulator, 2026-10-05**, an iPad (7th generation) on iOS
18.6, built from this change, signed in to the test account. A video of
19,284,661 bytes, IMG_7001.MOV, was put in Photos and shared from there.
Photos offered Blackmail for "1 Video Selected", and the sheet listed
"IMG_7001.MOV — 19.3 MB". Sent to the test account's +sim18 address,
"B070 video 19 MB from Photos": "Sending… 59%" on the way, and the sheet
closed at the 250. Its lines: `SHARE-FILE
read=com.apple.quicktime-movie name=file "IMG_7001.MOV"
mime=video/quicktime bytes=19284661 went=staged`; `LETTER-PLAN files=1
file-bytes=19284661 raw=26390251 payload=26390254 ms=101`; `LETTER-FILE 1
bytes=19284661 crc=80658926`; `MAIL FROM … SIZE=26390251`; one
`WIRE-OUT`; `LETTER-LATCH ok`; `WIRE-ACK err=none` 4.6 s after DATA; the
250 5.2 s after that. It arrived in the Inbox with IMG_7001.MOV. Opened
in the app, the file it wrote was 19,284,661 bytes, CRC 80658926, its
sha256 the original's, and it played to its end. The simulator gives no
memory figure ("memory unknown"), so there is no "while it went": it
shows the path works, not what it holds.

**Seen on the iPad, 2026-10-05**, the test iPad (180 MB for the
extension), built from this branch with master's B-069 and B-071 in it,
installed through TrollStore's helper, every letter to the account
itself. Two made-up videos, a test pattern with a tone, 18.7 and 7.9 MB,
were put in its Photos by mailing them to the account and saving them
from the preview. Each arrived file was fetched over IMAP and its CRC-32
compared with the `LETTER-FILE` line and with the original.

- *A 19 MB video alone, from Photos.* Blackmail offered; `SHARE-FILE
  read=com.apple.quicktime-movie … mime=video/quicktime bytes=18737227
  went=staged`; the sheet listed it under its own name, 18.7 MB. Send:
  `LETTER-PLAN raw=25658974 payload=25658977 ms=159`, `SIZE=25658974`,
  one `WIRE-OUT`, `LETTER-LATCH ok`, one `WIRE-ACK`, the 250 seven
  seconds after the plan. It arrived once, the same bytes as the
  original (sha256 and CRC). The memory: 173 MB available with the
  files read, 170 MB the least while it went.
- *Too large.* A 44 MB video from the camera roll alone: the words "The
  video could not be attached." in place of the letter, and nothing sent.
  The 19 and the 8 MB videos together: the sheet listed the first, with
  "1 video could not be attached." above it.
- *A video and two pictures.* The 8 MB video, a 12-megapixel JPEG and a
  PNG: the JPEG as its own bytes, the PNG whole, the video staged; three
  `LETTER-FILE` lines; it arrived once, each file's CRC its line's.
- *The app's Forward of the 19 MB letter*, the video carried from Gmail:
  the same CRC on arrival. With the Wi-Fi interface taken down for ten
  seconds after 11 MB had gone, the connection lived and the letter went
  once.
- *Cut off for good.* The same Forward, the interface taken down for 60
  seconds after 10 MB: `DEADLINE write bound=30s`, `WIRE-ACK
  err=timedOut`, no `LETTER-LATCH`, so no full stop went, and
  `OUTBOX-WAITING error=connectionLost`; the sheet said the letter was in
  the Outbox. Nothing arrived. Back in the app 18 minutes later, Sent Mail
  was searched for its Message-ID, and it went under that same
  Message-ID: one copy in the Inbox and one in Sent Mail, the video's CRC
  the original's. Gmail kept nothing of the attempt with no full stop.
  Refresh alone did not start the Outbox's pass; coming back to the app
  did, as B-052 has it. (By the code it was the pass made as the app was
  left, the one pass that took such a letter; the pass on coming back
  leaves it. Since B-072 his Refresh sends it.)
- *A draft.* The Forward with the video, Cancel, Save Draft: Gmail held
  one draft of 25.7 MB, the video's CRC the original's. Reopened and
  sent: one copy arrived, the same, and the draft was gone.

Not tried on the iPad: the iPad locked during an upload, a plain letter's
`WIRE-PAYLOAD` on this build, six items at once, and his iPad.

**Not covered.**

- **The network's own buffers.** What `NWConnection` holds behind
  `.contentProcessed` is not measured here. "While it went" is the only
  evidence, and it is the same piece-at-a-time path letters always took.
- **How Photos hands over a video** on the iPad. In the simulator Photos
  offered Blackmail, handed over QuickTime, gave no suggested name, and
  the file was the original's bytes. Not seen: the iPad's own Photos, and
  an edited, slow-motion or iCloud-only original, with a download wait in
  the extension. Whether the File key alone would have offered Blackmail
  is not known. A Live Photo still goes as its still, by the order of the
  branches.
- **Class C on a cloned staged copy** is not known to hold. The lock check
  decides it.
- **Longer uploads in the extension**, which has no Outbox: about 3.5
  minutes for 26 MB at 1 Mbit/s. Killed or suspended, the share is lost,
  as before; the exposure is larger now.
- **The rehearsal on the A10** is not measured; `ms=` will say.
- **CRC-32** finds a file changed by accident, not one changed on purpose.
- **Gmail's own limit** near 34.2 MB of letter has not been tried. His
  videos are at most 19 MB.
- **A draft** is still made whole for its APPEND. The app has no video
  picker, and a large draft goes up as he leaves the app.
- **A file that is neither a picture nor a video**, a 30 MB PDF, is still
  left out with nothing said, as before.

---

## B-071 — CHANGED 2026-10-05, seen on the simulator and on the iPad. A file's preview took the highlights, the text size moved buttons, folders and rows, and Settings and the search field had no names

**Found** on 2026-10-05, in a pass over the app on the iPadOS 18.6
simulator (iPad, 7th generation), and the same on 17.5. Four things, each
measured on master's build:

- A file's preview, closed with Done, took the highlight off the open
  letter's row in the list and off the open folder in Mailboxes. The
  letter stayed open in the pane.
- The text size in Settings moved what D-007 holds still. Two steps above
  the default, the reading pane's five buttons grew 5.5 to 7.5 pt wider
  each and Flag moved 31.5 pt left; the calendar went from 45.5 pt wide
  to 52.5; the folders' icons grew and their names moved 4.5 pt right;
  Edit mode's circles went from 26 pt to 32. At the largest accessibility
  size the folders' icons shrank to the names' height and each name began
  where its own icon ended, so a block's names were no longer on one line;
  each file's row in a letter's header went from 44 pt to 86.5, which put
  the letter 42.5 pt lower for each file; Edit mode's circles went to
  49 pt and pushed every row's words 25 pt right; the list's separators
  were drawn two pixels thick.
- In Settings the name field, the signature box, the app password field
  and the Organize by Thread switch had no name for VoiceOver. iOS offered
  "Passwords" over the signature box and the app password: a form with a
  masked field reads to it as a sign-in.
- The list's search field read as a heading with no name. The magnifier
  and the word drawn in it read as two more things called "Search".

**What it was.** A `UITableViewController` clears its highlight whenever
its view is about to appear, unless told not to. The preview covers the
whole screen, so both lists appeared again when it closed. The symbols
were left to UIKit, which sizes a symbol by the text size unless it is
given a size of its own. A folder's row and Edit mode's circles are laid
out by UIKit from the text size, which no symbol size reaches.

**Changed.**
- Neither list clears its highlight on appearing. Nothing relied on that:
  the rows let go on purpose are let go where that is decided (`letGo`,
  `openDraft`, `openWaiting`), and the folder's highlight moves by
  `select(mailboxID:)` and a tap.
- The symbols UIKit sized have a fixed size, `Theme.symbolSize`: 17 pt at
  the large scale, which is what UIKit drew them at at the default text
  size. These are the reading pane's buttons, the calendar, the folders'
  icons and a file's paperclip in a letter's header.
- The folders and the list are laid out as at the default text size,
  whatever the iPad's is (`RootViewController`, a trait override on their
  two navigation controllers). A fixed symbol size and a fixed room for
  the icon (`reservedLayoutSize`) were tried first, and at the
  accessibility sizes the names still did not line up. The reading pane
  is not held, and it does not need to be. Nor are the sheets and alerts
  these panes put up: they are presented over the whole screen and follow
  the iPad's setting as before.
- In Settings each control is called by its caption. The words beside
  the switch are not read; the switch is called by them, and the row is
  one stop, as Mail's is. The app password is
  `.newPassword` while it is masked, and the name field is `.name`. With
  `.password` instead, "Passwords" stayed over the name, the signature and
  the app password; a type on the signature box changed nothing. Unmasked,
  with no passcode, the field has no type, so as not to bring back B-009.
- The search field is called "Search" and is a search field to VoiceOver,
  as Mail's is. The magnifier and the word are not read.

**Tests.** `SteadyChromeTests` reads the wiring from the source, as
`PaneNavigationTests` does: both lists keep their highlight and nothing
else in them clears a row on appearing; the symbol size is a point size
and each symbol named above uses it; no symbol on the mail screens is left
to UIKit but in an image view of a fixed size; the two panes are held and
the reading pane is not; each control in Settings has its caption, and
the words beside the switch are not read; only the masked app password
has a password type; the search field's name, its
trait and the placeholder left unread. Each fix undone in a scratch copy:
the highlights, 2 failures; the symbols, 14; the panes held, 2; the names
in Settings, 10, and the words beside the switch read again alone, 2; the
content types, 2; the search field as it was, 8.

**Seen on the simulator, 2026-10-05**, iOS 18.6, on the test account,
each against master's build on a second simulator. The text size was set
with `simctl ui content_size` and the app started again. With a letter of
five files open, the screen below the status bar at the default size is
master's, pixel for pixel. Two steps up and at the largest accessibility
size, every frame VoiceOver reports is the same as at the default, and so
is the screenshot, pixel for pixel. The same at the three sizes on 17.5.
In Edit mode the circles stay 26 pt and the rows' words stay where they
were. Closing a file's preview leaves the screen as it was before the file
was tapped, both highlights with it, in three panes and in two, and on
17.5; "< Mailboxes" then shows the Inbox highlighted. A letter of the test
account's own, opened in All Mail and moved to Important, stayed in All
Mail with its highlight gone and the pane empty, as `letGo` has it; it is
in Trash now. The Go to Date sheet's calendar is as large at the largest
size as on master. Holding a bar button at that size still shows it
enlarged, in the list and in the reading pane. In Settings each control
has its caption for a name, and no "Passwords" is offered over the name,
the signature or the app password, with a hardware keyboard or with the
one on the screen; a typed app password left with Cancel brings no offer
to save it. Asked what is under a point, the simulator gives the switch's
row at the words beside the switch, where the same build with the words
read gives the words; it gives the search field at its magnifier and its
word. Its tree lists all three either way. Settings looks the same with
the words read or not, pixel for pixel. The search field reads "Search", a search field, and a search
typed and cancelled works as before.

**Seen on the iPad, 2026-10-05**, on the same build as B-069. A letter
with a 12-megapixel photo opened, the photo's preview opened and closed
with Done: the letter's row and Inbox stayed highlighted. In Settings,
the signature box tapped: no "Passwords" over the keyboard, only undo,
redo and paste. The text size and VoiceOver were not tried there.

**Not covered.**
- At the accessibility sizes Edit mode's circles sit 12.5 pt lower in
  their rows than at the default. Their size and the rows' words hold.
  Where UIKit puts them is its own.
- The search field still reads as a heading as well. The band is the
  list's section header, and UIKit reads whatever is in one as a heading;
  taking the trait off in the field changed nothing.
- VoiceOver itself was not run. The names are what the simulator's
  accessibility tree reports, and what is not read is what it gives for
  a point.
- The setup form has a masked field too and is not changed here. Whether
  iOS offers "Passwords" over it was not looked at.
- The composer and the share sheet are B-069's. The diagnostics screen,
  which he never sees, was not looked at.

---

## B-072 — CHANGED 2026-10-05, seen on the iPad. Refresh did not send a large letter waiting in the Outbox

**Found** on the test iPad, 2026-10-05, in B-070's check of an upload cut
off for good. A Forward of a letter with a 19 MB video waited in the
Outbox. Refresh did not send it. It went only by the pass the app makes as
it is left. The owner, the same day: "make Refresh send anything waiting
in the Outbox, matching Apple Mail".

**What it was.** Refresh fetched the folder's newest page, and after a page
the pass over the letters kept on the iPad runs (`MessageListViewController.
reload`, `LocalDrafts.uploadWaiting`). That pass was one nobody asked for,
the same as at launch or on opening a folder. It holds back a letter in the
Outbox whose files come from Gmail first, a forward's or a reopened
draft's: a megabyte or more of them, or one of no known size
(`LocalDraft.fetchesLarge`, B-052). That fetch holds the one IMAP
connection, and nothing he taps can go first. Only the pass as he leaves
the app took such a letter (`largeToo`). Refresh in the Outbox ran the
same pass, with no page.

**What Mail does.** Mail sends what waits in its Outbox by itself once
there is a connection (B-052). No page of Apple's was found on what its
Refresh does with the Outbox, and Mail was not tried for it on a device.
The owner's words are the rule here.

**Changed.**

1. *Three kinds of pass* (`LocalDrafts.Pass`). Nobody's: a page at
   launch, on opening a folder or on coming back, the app coming back to
   the front, and the watch's check. His Refresh. And leaving the app. Each
   takes what it took, but one: his Refresh takes every letter in the
   Outbox that is otherwise due, a large one too (`LocalDraft.goes(by:)`).
   A large draft still waits for him to leave. `largeToo` is gone; leaving
   asks for `.leaving`.
2. *Refresh, in any folder, the Outbox included* (`refreshTapped`,
   `RefreshTap`). The page first, with no pass of its own
   (`reload(passing: false)`). Then the folder counts, as before. Then,
   once the page's previews and the counts have come
   (`SweepCoalescer.idle`), the pass, as his Refresh's. A forward's files
   are fetched in the line his taps wait in, ahead of the previews and the
   counts' STATUS, and an exchange on the wire is never cut short
   (`IMAPClient.Priority`). Asked for first, the fetch would have held
   what he asked to see behind it. The Outbox has no page: there the
   counts' LIST and STATUS make the connection if they can, and the pass
   goes over it. Every other page sets its pass off as before.
3. *A Refresh, or leaving the app, while a pass runs* is not dropped
   (`afterThisPass`). It gets the pass it would have been, which starts
   once the running one has ended (`passEnded`). One however often they
   are asked for meanwhile, of the more asked for: leaving over his
   Refresh. Leaving asks iOS for time there and then, as the notification
   is posted, and gives it back once that pass has ended, so iOS does not
   suspend the app between the two passes. The owed pass is let go as it
   sets off, so a Refresh during a later pass is owed one of its own. A
   pass nobody asked for, asked for while one runs, is dropped as before.
   Leaving used to be dropped too. That was rare while every pass ended
   in seconds. His Refresh's pass may now fetch a video for minutes, and
   that is when he is likely to go to the Home Screen: a large draft,
   which only leaving takes, waited for the next time he left with no
   pass on its way.
4. *The log.* `OUTBOX-REFRESH large=1` when his Refresh's pass, with a
   connection up, takes letters a page's would have left, with how many.
   `OUTBOX-REFRESH owed` when his Refresh waits for a pass on its way, and
   `OUTBOX-LEAVING owed` when leaving does. Numbers only.

With no connection nothing changes: the page fails and sets no pass off,
as before. In the Outbox the counts fail, and the pass finds no connection,
sends nothing and says nothing, as before.

**What stays held.** His Refresh overrides the size and nothing else. None
of these goes at any pass, his Refresh included: a letter held after three
tries the app did not live through (B-057); one refused as it stands,
until he changes it or the app is launched again; every letter after the
password or the submission server's sign-in was refused, until his Send
goes (`sendingRefused`); one open in the composer; one with an attempt cut
off before a password save (B-052); another account's; and every letter in
a launch that holds the pass (B-057). A letter whose DATA went and whose
250 never came is looked for in Sent Mail first, and not sent again within
ten minutes of the cut, as at every pass: no letter twice. The pass still
makes no connection of its own. A try by his Refresh's pass is made in
front of him and is counted (B-057), so a letter whose fetch ended the app
three times is held, as any other.

**The cost.** While a forward's files come from Gmail the connection is
theirs, and a letter he opens then waits for the fetch. He tapped Refresh
with the letter waiting, which asks for it to go.

**Tests.** `OutboxTests`, ten, over the scripted servers. A forward
with a 2 MB file in the Inbox, sent with no connection: a page's pass
leaves it in the Outbox; his Refresh's pass sends it once, the file's
first and last lines of base64 in it, its try counted while it goes, the
log saying `OUTBOX-REFRESH large=1`, and a second Refresh finds nothing to
do. His Refresh sends the Outbox's forward, takes a small draft up to
Drafts, and leaves a draft with 2 MB of photos, which goes up as he
leaves. A forward held by its tries, one open in the composer
and one whose file is gone from Gmail: his Refresh sends none, refuses the
third, and the next Refresh sends no command at all. A refused password
goes once, and the next Refresh takes nothing. A forward cut off after its
DATA is looked for in Sent Mail first, not sent too soon after the cut,
and not sent again once Sent Mail has it. His Refresh while a page's pass
holds a small letter's 250: a pass nobody asked for is dropped, his is
not, two taps get the same pass, nothing more goes until the running pass
ends, then the forward goes once, after the small letter, and the log says
`OUTBOX-REFRESH owed`; then the same again with a second small letter and
a second forward, and the second Refresh gets a pass of its own, not the
one that has ended, and the second forward goes. Leaving while his
Refresh's pass holds the forward's 250: it is not dropped, time is asked
of iOS there and then, nothing more goes while the pass runs, then the
draft with 2 MB of photos goes up once, and the time asked for as he left
is given back after the leaving pass's own. His Refresh and then leaving,
twice each, while a page's pass holds a small letter's 250: one owed
pass, time asked for once, and it takes the forward and the large draft,
as leaving's. His Refresh with no connection: nothing sent, nothing in the
log; after a page his Refresh says `OUTBOX-REFRESH large=1` and sends it.
A launch that holds the pass sends nothing at his Refresh. `RefreshTapTests`, six: what each kind of pass takes by size, for
ten letters (the Outbox's with 2 MB, a file of no known size, exactly a
megabyte and a byte under it to fetch from Gmail, 2 MB of photos on the
iPad, and nothing; drafts with 2 MB of photos, 2 MB from Gmail, a megabyte
of quote, and nothing); the order, the page and the counts before the
pass; no pass after a page that did not come; the pass waiting for the
previews and the counts however long they take; and, read from the
source, `refreshTapped` as it is wired, `reload`'s two passes skipped only
for his Refresh, the page's previews kept, the counts handed to the list,
coming back and the watch's check still nobody's, leaving still
`.leaving`, and his Refresh the one pass of its kind in the screens'
sources. Changed: `largeToo: true` is `for: .leaving` in the tests that
passed it, and in `SafeStartTests`' pin of `leavingTheApp`.

Each part undone in a scratch copy, one at a time, the whole suite run
serially each time, counted as failures in tests. His Refresh taking no
large letter in the Outbox: 14 in 6. Taking a large draft too: 5 in 2. A
page's pass taking a large letter in the Outbox: 8 in 4, B-052's
`testOnlyWhatItFetchesFromGmailHoldsALetterBack` among them. Leaving
taking no large draft: 9 in 3, B-051's
`testALargeLetterWaitsForHimToLeaveTheApp` among them. A Refresh during a
running pass dropped: 6 in 1. Every tap owed a pass of its own: 2 in 1. A
launch that holds the pass taking his Refresh: 3 in 1. His Refresh taking
a letter held by its tries: 4 in 1; one refused as it stands: 2 in 1; one
open in the composer: 1 in 1; the Outbox after a refused password: 3 in 1.
A large letter not looked for in Sent Mail before it goes again: 5 in 1.
No `OUTBOX-REFRESH large=` line: 2 in 2. The pass before the previews and
the counts: 3 in 2. A pass after a page that did not come: 1 in 1. And,
read from the source: Refresh asking for a pass nobody asked for, 2 in 2;
its page setting its own pass off, 1 in 1; the page's previews not kept to
wait for, 1 in 1; the counts not handed to the list, 1 in 1. Nineteen in
all, with nothing else failing in any run. The full suite, serially, with
nothing undone: 1,479 tests, 5 skipped, none failing. The release build
for the iPad links.

**Reviewed 2026-10-05, and fixed.** A review of the change above found
four things, each fixed in the text above, which says how it is now.
Leaving the app while a pass ran set nothing off. It was so before, but
his Refresh's pass, minutes long with a video, made it likely: he taps
Refresh, sees "Sending…" and goes to the Home Screen, and a draft with 2 MB
of photos, which only leaving takes, stayed "On this iPad only" until a
later leave. Nothing was lost or sent twice. The owed Refresh was let go
as it set off, but no test said so: kept for good, every test passed, and
every later Refresh during a pass would have got back the pass that had
ended, and sent nothing. `OUTBOX-REFRESH large=1` was said before the pass
looked for a connection, so a Refresh in the Outbox with none said it and
sent nothing. And the TODO's first check had him look from the Inbox for
"Sending…" on the Outbox's row, which only the Outbox's own list shows.

Each fix fails with its part undone, ten sabotages one at a time, each
run once over the whole suite, serially, as failures in tests: leaving
during a pass dropped, as before (16 in 2); no time asked of iOS as he
leaves with a pass running (6 in 2); that time given back before the owed
pass has ended (2 in 2); leaving not making an owed Refresh leaving's (6
in 1); a Refresh after leaving making it his Refresh's again (6 in 2); the
owed pass never let go (5 in 1, its second round); and the large line said
before the pass looks for a connection (2 in 1). Three parts above again,
their code moved: a Refresh during a running pass dropped (22 in 2), every
ask owed a pass of its own (9 in 2), and no `OUTBOX-REFRESH large=` line
(5 in 4). One run also failed `LargeLetterTests.
testPicturesStillComingWhenHeMovesOnAreCalledOff`, which fails now and
then on this host; run again, only the sabotaged test failed. The full
suite, serially, then: 1,482 tests, 5 skipped, none failing. The release
build for the iPad links.

**Seen on the iPad, 2026-10-05**, built from this change, installed
through TrollStore's helper, on the test account. The letter with the
18.7 MB test video open, Airplane Mode on, Forward, Send: "Message is in
the Outbox…", the Outbox in the Mailboxes holding one, the log
`OUTBOX-WAITING error=cannotConnect`. Airplane Mode off, and 75 seconds
in the Inbox with nothing tapped: still one in the Outbox and nothing at
Gmail, as before this change. Refresh: the page and the counts, then
`OUTBOX-REFRESH large=1`, `LETTER-PLAN`, one `WIRE-OUT`, `LETTER-LATCH ok`
and the 250, eight seconds after the tap. One copy in the Inbox and one
in Sent Mail, none in Drafts, the video's CRC-32 the original's, and the
Outbox gone from the Mailboxes. Not tried on the iPad: Refresh from inside
the Outbox, a large draft through a Refresh, and leaving during a pass.

**Not covered.**

- Mail's own Refresh with its Outbox was not tried on a device.
- Not yet seen on the iPad. The TODO says how.
- The sheet's notice still says the letter "will be sent when the iPad is
  connected and Blackmail is open". A large forward goes at his Refresh or
  as he leaves, not by itself after a page. The words are unchanged.
- An owed leaving pass that starts after he has come back goes as
  leaving's all the same, a large draft with it, as a leaving pass on its
  way when he comes back always has.
- Neither pass outlives the time iOS gives. A video that takes longer is
  stopped with the app, as before, and what is left goes at a later pass.
- The counts waited for are every sweep running or owed, a read mark's or
  the watch's too, and a sweep that hangs holds the pass until its
  deadline. Before the launch's counts are let go the pass does not wait
  for them.
- The screens' wiring is read from the source on the host, not run. The
  pieces under it run.

---

## B-073 — CHANGED 2026-10-06, seen in the iPadOS 18 simulator and on the iPad. Going into an empty address field offered his most used; Mail offers nothing until he types

**Asked** on 2026-10-06. B-069 kept one thing unlike Mail and put it to
the owner: going into an empty To offered the addresses he uses most,
which made his own second address one tap. Mail offers nothing there.
Asked which, he answered: "match apple mail".

**What it was.** What an address field offers is `ComposeForm.suggestions`,
in both composers since B-069: the app's (`ComposeViewController.
refreshSuggestions`) and the share sheet's (`ShareSheet.suggestions`, put
up by `ShareComposeViewController.offer`). Going into a field with no
address in it offered up to four, his most used first. So did typing whenever
nothing was left after the last comma: a letter typed and taken out
again, or the letter after a pick's comma taken out. `RecipientBook.rank`
gives every entry for an empty query. The share sheet puts him straight
into To as it opens, so it opened with the list up over the letter.

**What Mail does.** An address field offers addresses only while he types
a name or an address. Going into a field offers nothing, empty or not.
Taking out what he typed, back to nothing, closes the list.

**Changed.**

1. *Only typing offers anything* (`ComposeForm.suggestions`). Going into a
   field offers nothing. A pick offers nothing. Typing offers only with
   something after the last comma, spaces taken off. Spaces alone are
   nothing typed, and so is a line break pasted in. One letter typed
   offers what matches it.
2. *Both composers* ask the form, as before, so neither has a rule of its
   own. Going into To, Cc or Bcc asks it as he goes in, which offers
   nothing and closes a list left open under another field. The share
   sheet still opens in To, with the caret there and no list. Cc/Bcc
   shows its two rows and no list. In each sheet the list is shown in
   one place, from what the form offers, and no other path shows it.
3. *`RecipientBook.rank` is unchanged.* An empty query still gives every
   entry, his most used first, and the book's own tests read it whole
   that way. The composers never ask it with one now. Its comment says
   so.

**What stays from B-069.** A pick closes the list until he types. No
address already in the field is offered again, in any spelling. Nothing
is offered once what he has typed holds an "@". The list moves with its
field as the sheet scrolls, and goes when he leaves the field. The order
is the same: the best match first, then the most used.

**The cost.** His own second address, the one most of his shared links go
to, is one letter and a tap, not one tap.

**Tests.** `ComposeLikeMailTests`, now twenty-eight, eight of them new.
Going into an empty field offers nothing. Going into one that holds an
address, one picked with its comma, or a name half typed offers nothing.
One letter offers what matches it, after a comma too, without the
address already there. Typed and taken back out, alone and after a
comma, the list closes. Spaces, a tab and a line break offer nothing. A
pick offers nothing, whatever the field reads. The share sheet the same.
Read from the source of both composers: going into an address field
asks the form as he goes in; the share sheet's start in To only gives
To the caret; the form is asked after the three events and nowhere
else; the share sheet's rule is the form's; and the list is shown in one
place in each sheet, from what the form offers. Changed, each with the
reason in its comment: B-069's `testAnEmptyFieldStillOffersHisMostUsed`
is `testAWholeAddressOrOneInTheFieldIsNotOffered`, its empty field gone;
`testThePickedListClosesUntilHeTypesAgain` expects nothing for a letter
typed after a pick and taken out; `testTheShareSheetOffersTheSame`
expects nothing going into an empty field, and matches for "e" after a
pick; `ShareSheetTests.testTheAddressFieldsOfferTheAppsBook` expects
nothing for nothing typed, and his most used first among the matches
for "e". `RecipientBookTests.testAnEmptyQueryStillOffersHisMostUsedAddresses`
is unchanged but for its comment: it is the book read whole, not the
screen.

Each part undone in a scratch copy, one at a time, the whole suite run
serially each time, counted as failures in tests. An empty field
offering his most used as he goes in, as in B-069: 4 in 3. Going into
any field offering what its last part matches: 3 in 1. Nothing after the
last comma offering his most used as he types: 12 in 5. The field's
emptiness judged, not the part after its last comma: 9 in 4. A line
break not taken off: 1 in 1. A pick offering as typing does: 3 in 2; the
first run also failed `LargeLetterTests.
testPicturesStillComingWhenHeMovesOnAreCalledOff`, which fails now and
then on this host, and run again only the two failed. B-069's rules,
under the new code: an address with an "@" offered, 1 in 1; an address
already in the field offered again, 4 in 3. The share sheet with a rule
of its own, every entry matching what follows the last comma, whatever
happened: 13 in 4. Read from the source: the app's going in asking as
typing does, 2 in 2; the share sheet's, 1 in 1; Cc/Bcc putting up his
most used under the fields, 2 in 1; the share sheet opening with its
list shown, 3 in 1. Thirteen in all, with nothing else failing in any
run but the one named. The full suite, serially, with nothing undone:
1,490 tests, 5 skipped, none failing. The release build for the iPad
links.

**Seen in the simulator, 2026-10-06**, an iPad (7th generation) on 18.6,
landscape, a hardware keyboard attached, built from this branch and
signed in to the test account. Nothing was sent. The composer, a new
letter: the empty To tapped, no list and Send grey (b073-02). "c"
typed: four rows (b073-03). Taken out: the list closed, Send grey again
(b073-04). Cc/Bcc: the two rows and no list (b073-05). The empty Cc
tapped: no list (b073-06). "c": four rows (b073-07). Taken out: closed
(b073-08). Cancel closed the letter with nothing asked. The share
sheet, from Safari on example.com: it opened in To, the caret there, no
list (b073-10). "c": four rows (b073-11). Taken out: closed (b073-12).
Cancel closed it with nothing asked (b073-13). The screenshots are in the
pass's shots folder, not in the repo: the rows show real addresses.

**Seen on the iPad, 2026-10-06**, built from this change, installed
through TrollStore's helper. In the composer: To tapped, empty, no list;
"c" typed, four rows; "c" taken out, the list gone, Send grey again; Cancel
closed it with nothing asked. In the share sheet, from a Wikipedia page in
Safari: it opened in To with no list; "c" typed, four rows; taken out, the
list gone; Cancel closed it with nothing asked. Nothing was sent.

**Not covered.**

- Mail itself was not tried for this on a device. What it does is
  B-069's finding, and the owner's ruling is the rule.
- A pick and going back into a field that holds an address were not
  tried in the simulator: a picked address makes Cancel ask, and a test
  letter could be left in Drafts. The host suite holds both.
- The on-screen keyboard was not tried in the simulator; the hardware
  one was.
- Not yet seen on the iPad. The TODO says how.

## B-074 — CHANGED 2026-10-06, seen in the iPadOS 18 simulator. A conversation ran newest first; Mail's runs oldest at the top and opens at the newest

**Asked** on 2026-10-06. B-022 built the stack newest first and said so:
a choice, not a copy, since Mail's default was not known. It was one of
the calls put to the owner under "Blocked on the owner". His ruling on
them: "copy apple mail for these".

**What Mail does.** Mail on iPadOS 18, with its factory settings: Organize
by Thread on, Collapse Read Messages on, Most Recent Message on Top off,
Complete Threads on. The defaults were read from Mail's settings module in
the iOS 18.6 simulator runtime, which the iPad and the iPhone share. A
fresh simulated iPad has none of the settings stored, so it has those.

- The oldest letter is at the top and the newest at the bottom, in date
  order. High confidence: the settings module, a first-hand report from
  an iPad in October 2024, and several guides agree.
- A letter he has read is closed to a short row: sender and time, and a
  line of the letter under them. Seen on an iPhone of iOS 16 or 17;
  medium confidence for the iPad.
- Unread letters are open in full, and so is the one opened from the list,
  the newest.
- It opens at the newest letter, with the older ones above. Low to medium
  confidence: one first-hand report from an iPad and one iPhone screenshot
  show this; other reports describe scrolling down to reach the newest.
  What it does with several unread letters is not known.

Mail itself does not run in the simulator: the runtime ships it without
its program. Nothing here was seen in Mail on an iPad.

**What it was.** `MessageDetailViewController.show(thread:)` drew the stack
in the list's order, newest first. The newest was open and every other
letter closed to its line, read or not. An unread letter kept its dot until
he opened its line. The pane opened at the top, at the newest. A letter
that came into the conversation while it was open was not added to it: the
pane kept what it showed (B-049), and the conversation opened again had it,
at the top.

**Changed.**

1. *The order* (`ConversationDocument.stack`). The oldest at the top, the
   newest at the bottom: the list's order turned over. The list's order is
   the order the letters came into the folder, which is their dates' order
   but for a letter dated wrong or put back in the folder later. Turned
   over, the letter the conversation's row stands for, the one he tapped
   the row to read, is always at the bottom.
2. *What is open.* The newest, and every letter he has not read. Every
   other letter is closed to its line. The unread ones are fetched after
   the newest, which keeps the header and the toolbar
   (`ConversationDocument.openedWithTheNewest`). The list's tap on the row
   marks them read with the newest, all at once: one redraw of the rows,
   and a STORE each (`ConversationDocument.readAtTheTap`). They are in
   front of him in full, from the top of the pane down (item 3).
3. *Where it opens* (`ConversationDocument.opensAt`). At the first open
   letter: the oldest he has not read, or the newest when he has read the
   rest. Its line goes at the top of the pane, or the line of the letter
   before it when that one is closed, so he can see there are older
   letters above. So every letter the tap marks read starts at or below
   the top of the pane, none of them above it, out of sight, and he
   scrolls down through them to the newest. What Mail does with several
   unread letters is not known (above); this is the choice. The document
   names the place in its head, and the stack's script puts it at the top
   of the pane as the document ends. The last letter, open or closed, is
   at least as tall as the pane, so any letter can be put there from the
   first frame, before the bodies have come. A short last letter, or a
   closed one, has the black of the pane under it, as a letter alone has.
   The floor is on the last letter whatever it is, so the stack never gets
   shorter under him: not when a letter goes in at the bottom closed, nor
   when he closes the newest by its line. The script holds the place, as
   bodies come in and the pane changes width, until he touches the pane
   or the pane scrolls by anything but the script: the status bar tapped,
   VoiceOver's scroll, the header changing height. The script notes where
   it put the page, and a scroll to anywhere else lets go.
4. *His place.* Once he has touched the pane, the letter at the top of the
   pane stays where it is on the glass when a letter above it grows or
   shrinks: a body coming in, its pictures loading, the letters above
   wrapping again at a new width. A letter he opens grows below its own
   line, which does not move. Inside a long letter a new width still shows
   other words at the top once it has wrapped again, as B-066 records for
   a letter alone; the place kept is the letter's, not the line's.
   WebKit's own anchoring is off in the document, so he is never moved
   twice. The header changes to the letter he opened once its body has
   come, and can change height with it, a line for a Cc, a row for each
   file. The stack is now scrolled by as much the other way, so the line
   he tapped stays under his finger (`StackPlace`). At the very top of the
   stack there is nothing to scroll, and it moves as before.
5. *New mail goes at the bottom.* A letter that comes into the
   conversation open in the pane goes in at the bottom of its stack as the
   list takes it (`ConversationDocument.arrivals`,
   `MessageDetailViewController.takeArrivals`, the list's `onRegrouped`).
   Nothing above it moves, open or closed. It is open, its body fetched,
   if he has not read it, and closed if he has, on another device say. It
   is not marked read: he did not open it and may not have seen it come.
   Its row keeps its dot, and the conversation opened again marks it. The
   header stays on the letter he had. Letters older than the
   stack's newest, as a page further down can bring, are not put in, nor
   letters of another folder or of a list that does not group. While the
   stack's page is still loading or lost to WebKit nothing is put in; the
   list offers them again as it next changes. This changes B-049 for a
   conversation: the pane keeps every letter it showed, and adds the new
   one under them.

**What stays.** A read letter closed to its line; a tap on a line opens or
closes it; opening one marks that letter read and no other; the header,
Reply, Flag, Move and Delete on the letter he opened last.

**Not changed, and not as Mail.**

- A closed letter is one line: sender, the letter's first words, time.
  Mail's is two, with the words under the sender. The stack's lines are
  as B-022 built them.
- Complete Threads: Mail brings his own replies from Sent into the
  conversation. Here a conversation holds the letters of the folder it is
  listed in, as before.
- No "N Messages" over the stack. It is seen on the iPhone; not known for
  the iPad.

**The cost.** Opening a conversation with unread letters fetches each of
them, a round trip each, after the newest. And it marks them read at the
tap, a STORE each, which nothing calls off: a letter he moves on to waits
behind them, as it does behind rows he taps past. The rows are drawn again
once for the lot. The conversation's dot goes at the tap, where before the
older unread letters kept theirs until he opened their lines. B-022 marked
one at a time so he would not lose the count for letters he had not seen;
now every unread one is open in front of him, at or below the top of the
pane.

**Tests.** `ConversationOrderTests`, twenty-seven, all new. The stack runs
oldest to newest, in date order. The row's letter is at the bottom
whatever its date. Each letter is drawn from its row. Read letters are
closed and the newest open. Unread letters are open with the newest,
wherever they are. The unread ones are the ones opened with the newest,
newest first. The tap marks the newest and the unread ones, at once. It
opens at the newest, under the closed line above it, when he has read the
rest; at the oldest letter he has not read, under the line before it,
when he has not. In every way five letters can be read or not, every
letter the tap marks is at or below where it opens, and it opens no more
than a line above the first of them. The document names that section in
its head. A letter that comes goes in at the bottom, oldest first. Older
letters that join are not put in. The conversation is found by any letter
still in it. Nothing comes from another folder, another letter under the
same id, or a list that does not group. The stack takes them only once
its page has loaded, keeps them for a redraw, and not twice. What goes in
is the stack's own sections, the sender escaped. The stack moves against
the header, within what it can scroll. Read from the source: the script
opens at the named section and holds it until a touch, or a scroll it did
not make; keeps his place as letters above grow, every section watched,
nothing scrolled in the toggle, WebKit's anchoring off; the last letter,
open or closed, is as tall as the pane; it puts letters in at the bottom
and wires their lines. The pane draws the stack in this order and fetches
the unread ones after the newest without marking them, a tap on a line
still marking its letter alone; the list marks the tap's letters with one
redraw of the rows; letters that come are put in, fetched and not marked,
the header left alone, wired from the list through the container; the
header keeps his place. No existing test was changed.

Each part undone in a scratch copy, one at a time, the whole suite run
serially each time, counted as failures in tests, and counted again after
the review below, with the tests as they are now. The stack newest first,
as before: 16 in 8. Only the newest open, as before: 34 in 3. Every letter
open: 15 in 7. Read letters opened with the newest: 13 in 3. The unread
ones not fetched as the stack opens: 1 in 1. Opening at the first open
letter with no line above it: 6 in 3. Opening at the top: 12 in 4. The
document naming no place to open at: 1 in 1. The script not holding that
place: 2 in 2. The script keeping no place: 1 in 1. No letter as tall as
the pane: 2 in 1. WebKit's anchoring left on: 1 in 1. Older letters that
join put in: 2 in 1. Letters that come put in newest first: 2 in 2. A
letter of the stack found by its id alone: 2 in 1. Letters put in while
the page loads: 2 in 1. Letters that come marked read: 2 in 1. The list
not wired to the pane: 1 in 1. The header's change of height not made up
for: 1 in 1. The stack scrolled past its ends: 4 in 1. Twenty in all,
with nothing else failing in any run.

**Reviewed 2026-10-06, and fixed.** A review of the change above found
five things, each fixed in the text above, which says how it is now. The
stack opened at the newest even when unread letters were above it, and
the tap marked those read where he could not see them. Jane writes "Can
you do Tuesday?" and then "Wednesday works too". He taps the row and sees
only the second; the dot and two of the Inbox's count go, and nothing on
screen says the first came. Now it opens at the oldest letter he has not
read. Two of the simulator notes, and the first two checks in the TODO,
described the first build, from before the pane's height rule, and gave
"medium confidence" for where Mail opens a conversation, where the
checked finding says low to medium. The floor of a pane's height was on
the last open letter, so a letter put in at the bottom closed, one read
on another device, took it away, and the stack dropped on the glass;
closing the newest by its line did the same. The hold at the opening
place let go only on a touch, a click, the wheel or a key. A tap on the
status bar, VoiceOver's scroll or the header changing height scrolled
the pane with none of them, and the next letter to grow pulled him back
to where it had opened. And each unread letter opened with the newest
was marked by the pane, one at a time, each a redraw of the list inside
the tap, with a STORE that nothing calls off; the cost said nothing of
either.

Each fix fails with its part undone, seven sabotages one at a time, each
run once over the whole suite, serially, as failures in tests: opening at
the newest, as the first build did (34 in 2); the tap marking the newest
alone, the unread ones never marked (1 in 1); the floor on the last open
letter, as before (2 in 1); the hold kept over a scroll the script did
not make (2 in 2); where the script put the page not noted (1 in 1); a
redraw of the list for each letter marked (2 in 1); and the pane marking
them one at a time, as before (3 in 2). Nothing else failed in any run.
The full suite, serially, then: 1,517 tests, 5 skipped, none failing.
The release build for the iPad links.

**Seen in the simulator, 2026-10-06**, an iPad (7th generation) on 18.6,
landscape, three panes, built from this branch and signed in to the test
account. Every letter went to the account itself, subjects beginning
"B-074": a conversation of five, one of them long and one with a Cc, one
of two, and, built again with the review's fixes, one of four, its last
reply sent and read on a second simulated iPad. The first two notes and
the last three are from that build; the rest are from the build before
it, and the review changed nothing they show.

- *Three letters, the two replies unread.* The first letter's line at the
  top of the pane, the first reply open under it, the newest open under
  that. The row lost its dot and the Inbox two from its count at the tap,
  14 to 12 (b074fx-03). Nothing in the pane moved in the seconds after
  (b074fx-04).
- *Opened again, all read.* The first reply's line at the top of the pane,
  the first letter's line above it and out of sight, the newest open under
  it, black below it (b074fx-05). That line tapped: it opened under its
  line, which did not move, and the header went to it (b074fx-06).
- *A long fourth letter sent while it was open*, the Inbox at the top.
  Within half a minute it was at the bottom of the stack, open, its body
  in. The row went to the top with "(4)" and its dot, and stayed unread
  (b074-17, b074-18). Recorded: in 19 frames over 32 seconds nothing above
  it moved by a pixel.
- *Opened again.* The third letter's line at the top of the pane, the long
  fourth open under it from its first line (b074-19). Recorded: the stack
  was drawn in that place with "Loading…", and the body came in under its
  line with nothing moving (b074-21). The first build drew the stack from
  its top for half a second and moved it up two lines when the body came;
  the newest's height of a pane at least is the fix.
- *Two short letters.* The first a line at the top, the reply open under
  it, black below (b074-24).
- *A fifth letter with a Cc*, so the header is a line taller for it. The
  stack opened at the fourth's line (b074-26). That line tapped: it opened,
  and when its body came the header lost its Cc line and the stack moved
  with it, so the line stayed where it was (b074-27; recorded).
- *The view button*, down the long fourth letter. Three panes to two and
  back: the fourth letter stayed the one at the top of the pane, its lines
  wrapped again, and other words of it were at the top in two panes; back
  in three, the same words as before (b074-28 to b074-30).
- *The newest closed by its line*, the first reply open above it at the
  top of the pane. The first reply stayed where it was, and the newest's
  line had the black of the pane under it (b074fx-07).
- *The status bar, then the view button.* The three letters opened again,
  at the first reply's line, the pane not touched (b074fx-08). The status
  bar tapped: the pane went to its top, the first letter's line
  (b074fx-09). Three panes to two, which wraps the letters again: the
  first letter's line stayed at the top (b074fx-10). Before the fix, the
  review saw the pane go back to where it had opened.
- *A fourth letter, read on another iPad first.* The three letters open at
  the first reply's line (b074fx-11). The app paused; from a second
  simulated iPad on the account, a reply sent and then opened there; the
  app let go on, and Refresh. The reply went in at the bottom as a closed
  line, and the pane above it did not change by a pixel. The row has
  "(4)" and no dot, and the Inbox count did not change (b074fx-12).

The screenshots and recordings are in the pass's folder, not in the repo:
they show the test account's address.

**Not covered.**

- Not yet seen on the iPad. The TODO says how.
- A stack drawn again after WebKit's process ended: it opens at its first
  open letter, as built, which can be one he opened by hand; not seen.
- A letter that comes in closed has no words in its line, only the sender
  and the time (b074fx-12). Not looked into.
- Pictures loading in a letter above him after he has touched the pane:
  the script keeps his place for it, not seen.
- Mail itself was not run. What it does is the finding above, and the
  owner's ruling is the rule.

---

## B-075 — CHANGED 2026-10-06, seen in the iPadOS 18 simulator, not yet on the iPad. A conversation in Sent Mail lost its count off the end of the names; Mail names the To alone and marks a conversation after the date

**Asked** in B-060, 2026-10-03, with four more questions about the rows
of Sent Mail, Drafts and the Outbox. B-060 named the To, the Cc and the
Bcc, each whole, joined by commas, and ended a conversation's line with
its count. The line is short, some 168 points in three panes, so the
count was often past its end: "Jane Example, Sam Exam…" for "Jane
Example, Sam Example (2)". The owner's answer, 2026-10-06, for all five
questions: "copy apple mail for these".

**What Mail does** on iPadOS 18. Read in Mail's own code for its list
rows, in the iOS 18.6 runtime, where Mail itself does not run; and in
guides and screenshots of Mail's list, the newest of them from 2024 and
2025, on an iPhone.

- In Sent, Drafts and the Outbox, and in a search of one of them, the
  top line names the letter's To alone. Not the Cc, not the Bcc, and no
  "To:" before the names. A search of other mailboxes names the sender,
  as every other mailbox does.
- Nobody in To: a stand-in. Mail's string for it is "No Recipient".
- One person: the whole name, the letter's name for them, or the address
  where there is none.
- Two or more: his own addresses taken out, except the first entry,
  which never is. Each person once. If one is left, the whole name.
  Otherwise each by a short name, joined "Jane & Sam", "Jane, Sam &
  Bob". No "& 2 more". The line is cut at its end.
- A name that is itself another address is shown with the real address
  after it.
- No count on any row. A conversation is marked with a small blue
  chevron in a circle, at the right end of the top line, after the date.
  A tap on the chevron opens the conversation's letters in the list. The
  names are cut before the date, so they never push the mark off.

Not found: a screenshot of an iPadOS 18 row in Sent with several names
or with a conversation; how Mail shortens the name of someone not in
Contacts (it takes the Contacts short name, "Jane" or "Jane E." by a
setting whose default was not found); whether Mail on the iPad shows its
"No Recipient" there.

**Changed.**

1. *The names* (`RowNames.line`). In Sent Mail, Drafts and the Outbox
   the top line names the To alone, by Mail's rule above. One person
   whole: "Jane Example", or "sam@example.com". A name that is only the
   address again is no name. Two or more by short names: the name's
   first word, or the word after the comma of a name written surname
   first ("Example, Jane" gives "Jane"), or the address before its "@"
   where there is no name. That rule is inferred: the app has no
   Contacts, and how Mail shortens a name it finds in none was not read.
   His own addresses are the ones Reply knows (`OwnAddresses`, B-061):
   the account's address and login, in every spelling Gmail delivers to
   him. They are taken out of two or more but for the first entry, as
   Mail's code keeps it: To him and Jane reads his short name, then "&
   Jane"; To Jane and him, "Jane Example"; to him alone, his name. Each
   address once, in any case, and a name given again at another address
   once. A name that is another address reads "jane@example.com
   <other@example.net>". An entry with no "@", a draft's half-typed
   "jan", is named as he left it. An address with a ";" after it is
   named by its address, "jane@example.com;" as "jane@example.com", and
   so is the last of a group's people. Only an entry with no address in
   it, such as the empty group "undisclosed-recipients:;", names nobody.
   The composer splits a field at commas alone, so a draft or a letter
   in the Outbox keeps a ";" he typed. The first build dropped every
   entry that ended in ";", and a draft To "jane@example.com;" read "No
   Recipients" in Drafts and the Outbox, where B-060 named it (found in
   review).
2. *A conversation* names the To of every letter in it, the newest
   letter's first, by the same rule, as B-060 had it: "Sam & Jane" for a
   letter to Sam and an older one to Jane. A letter whose row does not
   know its To, kept by a build before B-060, adds nobody; when none in
   it knows, the row names their senders, as before.
3. *No count, and the mark* (`MessageThread.marksConversation(in:)`,
   `MessageCell`). A conversation's row there has no "(2)". It ends its
   top line with Mail's chevron in a circle, `chevron.forward.circle`,
   blue, at the date's size, centred on the date's figures. A mark only:
   a tap anywhere on the row opens the conversation in the reading pane,
   as it did. Mail's chevron opens the letters in the list; that is not
   built.
4. *Nobody in To* says "No Recipients", the words of the Outbox's rows
   since B-052. A letter sent to Cc or Bcc alone says so too, where
   B-060 named them.
5. *The row's layout* (`RowTopLine`, out of the cell so the suite holds
   it). The mark ends at the text's right edge. The date's label keeps
   its left edge and ends before the mark, inside the 110 points it
   always had. The names keep their width, so they are cut where they
   were. Nothing else in the row moves, and a row without the mark is
   as it was to the point. The gap between the date and the circle is
   Mail's, 8.5 points from ink to ink, measured off Mail's list at 2x;
   that is 5 between the two frames (`Theme.conversationMarkGap`),
   measured in the simulator.
6. *The cell draws the line the row gives it.* It used to read the line
   again as one sender's, `Name <address>`, which cut a name that is
   another address at its "<". Every name on the Inbox's line was read
   so already (`participants`), and a "<" is left only where a sender
   is written `<address>` with no name, which no row from the server
   is. So the Inbox's rows read as before.
7. *VoiceOver* reads the names the row shows, then "2 messages", the
   subject and the time, as before. Mail's string table has "%@
   messages"; where Mail reads it was not found.

**Not changed.** The Inbox, All Mail, Trash, Spam and his own folders:
their rows name who wrote, keep their count, "Carlo, Margaret (3)", and
have no mark. The owner is to be asked about those separately. A
search's rows are never gathered into conversations, so they have no
count and no mark, in any folder. Which folder a row was listed from
decides it (B-060): a letter of his found by an All Mailboxes search,
listed from All Mail, names him and keeps its count. Organize by Thread
off, no row has a mark.

**Not like Mail.**

- "No Recipients", not Mail's "No Recipient". Kept as the Outbox's
  words, and one string to change (`RowNames.noRecipients`).
- His address in Gmail's other spellings was left out here too, unlike
  Mail. Since the merge with B-076 (2026-10-06) the row asks B-076's
  `OwnAddresses`, which knows only his addresses as written, his
  Settings list among them, as Mail does: To Jane and
  "owner.example+lists@gmail.com" reads "Jane & owner.example+lists".
- The mark does nothing of its own when tapped.

**Tests.** `SentRowLikeMailTests`, nineteen, all new. The name line as a
pure function: nobody, a blank entry, an empty group; an address with a
";" after it, the last of a group's people, and the Outbox's name for a
draft To one; one person whole,
by a quoted name, a name written surname first, a name that is the
address again in any case, the address alone; him alone; a half-typed
address; two, three, four and six joined, with no "more"; short names
by first word, by the word after a surname's comma, by the address
before its "@"; a name broken over lines; a name that is another
address; his own addresses left out but for the first, in Gmail's other
spellings; each person once, by address and by name. A row naming its
To alone; a conversation naming every letter's To. The mark and the
count per mailbox: Sent Mail, Drafts and the Outbox marking a
conversation with no count, and not a single letter; the Inbox, All
Mail, Trash, Spam and a folder of his keeping the count, no mark, and
the row `displayRow()` always drew; hits from All Mail in Sent Mail's
list, a search and Organize by Thread off unmarked. VoiceOver's count.
The line's geometry, with and without the mark, at four widths. The
wiring, read from the source: the list marks its rows at both places
it draws them, with his addresses from the account; the cell draws the
line as given, the chevron blue and only on a marked row, with no tap
of its own, laid out by `RowTopLine`; a tap on a conversation still
opens it in the pane. `SentRowNamesTests`, B-060's, changed, each with
B-075's reason in its comment: the To alone, short names joined, no
count, a letter to Bcc or Cc alone saying "No Recipients", the server's
rows, the kept copy and the Outbox by the new rule, and a row that does
not know adding nobody to a conversation, after the letter that knows
and, a case added, before it.

Each part undone in a scratch copy, one at a time, the whole suite run
serially each time, counted as failures in tests. The Cc and the Bcc
named with the To, as in B-060: 16 in 8. Each of several named whole,
not short: 32 in 16. Joined by commas alone: 33 in 16. His own addresses
kept: 5 in 2. His own address taken out when it is first too: 2 in 1.
One left after them named short: 6 in 3. An address named twice: 3 in 1.
A name named twice at two addresses: 1 in 1. A name that is another
address shown alone: 2 in 1. A name written surname first cut to the
surname: 2 in 1. An empty group named: 1 in 1. A half-typed address
dropped: 2 in 1. The count kept in Sent Mail, Drafts and the Outbox: 14
in 6. The count dropped everywhere: 12 in 3. The mark in every folder:
11 in 2. The mark on a single letter: 5 in 2. VoiceOver not saying how
many on a marked row: 2 in 2. A row that does not know its To adding its
sender: none at first, his name being left out after the To of the
letter that knows; with a case added where it comes first, 1 in 1. The
mark taking room from the names: 4 in 1. The date not ending before the
mark: 4 in 1. Read from the source: the list not marking its rows when
previews come, 1 in 1; the cell reading the line again as a sender's,
2 in 1; the cell never showing the mark, 1 in 1; the list without his
addresses, 1 in 1. The Outbox's own name for a letter by B-060's rule:
2 in 1. Twenty-five in all. Every failure in every run was in
`SentRowLikeMailTests` or `SentRowNamesTests`, but for the count
dropped everywhere, which failed `MessageThreadTests.
testTheCountRidesOnTheSenderLine` too.

After the review, three more, the same way. An entry that ends in ";"
dropped before its address is read, as the first build had it: 5 in 1.
An entry with a ";" and no address in it, an empty group, named as
written: 3 in 2. His address in Gmail's other spellings no longer his
(`OwnAddresses.key` without its Gmail rule): 8 in 5, of them 2 in 1 in
`SentRowLikeMailTests` and the rest in B-061's `ReplyAddressingTests`.
The full suite, serially, with nothing undone: 1,509 tests, 5 skipped,
none failing. The release build for the iPad links.

**Seen in the simulator, 2026-10-06**, an iPad (7th generation) on 18.6,
landscape, three panes, a hardware keyboard, built from this branch and
signed in to the test account, whose name there is Carlo. Every letter
to the test account's own address with a tag before the "@". Sent: To
"Jane Wolfeschlegelsteinhausen Example" at that address, Cc "Sam
Example" at it, Subject "B-075 one" (b075-04). Sent Mail's row: "Jane
Wolfeschl…", then the time at the right edge; Sam, the Cc, not named;
no mark (b075-06). Reply from it went To Jane alone; sent. Sent Mail:
the conversation's row "Jane Wolfeschl…", cut where the single row was
cut, then "9:07 AM", then the blue circled chevron at the right edge,
and no "(2)" (b075-09). Measured on the screenshots: the circle 15
points across, ending where every plain row's date ends, its centre
within a point of the date's figures. That build put 8.5 points
between the frames, which left 12 between the inks (b075-09); with 5,
the inks are 8.5 apart, as Mail's (b075-11). Another test conversation
in the same list had the mark too; the single letters around them had
none, their dates at the right edge. VoiceOver's label for the row: "Unread, Jane
Wolfeschlegelsteinhausen Example, 2 messages, Re: B-075 one, 9:07 AM".
A tap on it opened the conversation in the reading pane, the reply and
the letter under it, as before (b075-12). In Edit mode the mark stayed
after the date (b075-19). The Inbox: the same two letters, "Carlo (2)",
no mark (b075-10). A search of Sent Mail for "B-075", Current Mailbox:
two rows, each "Jane Wolfeschl…", no mark, no count; All Mailboxes:
both "Carlo" (b075-13, b075-14). A draft with Sam in Cc and nobody in
To, "B-075 nobody": "No Recipients" in Drafts (b075-15), then deleted.
The screenshots are in the pass's shots folder, not in the repo: the
rows show real addresses.

After the review, the same day, the same way: a new letter To the test
address with ";" typed after it, Subject "B-075 semicolon", Cancel, Save
Draft. Drafts: its row named the address, without the ";", cut at the
line's end, then the time; and so after Refresh. The screen does not
tell the iPad's copy of the draft from the server's. Opened from Drafts,
its To had lost the ";". With the ";" typed again, Send was refused,
"Message was not sent.", and it stayed in the composer; that is not
this change's, and why was not read. The draft was deleted.

**Not covered.**

- Mail itself was not seen with a conversation in Sent on an iPad.
  What it does is read from its code and from screenshots of an iPhone.
- Two different people on one row could not be sent in the simulator,
  where every letter goes to one address: "Jane & Sam" is the suite's.
  The iPad check in the TODO sends to two.
- Drafts and the Outbox holding a conversation were not made in the
  simulator. The suite holds both.
- A letter in the Outbox To an address with a ";" after it was not
  made. Sent with a connection, such a letter was refused and stayed in
  the composer; one sent with no connection would wait there. The suite
  holds its name in the Outbox.
- VoiceOver was read from the accessibility tree, not heard.

---

## B-076 — CHANGED 2026-10-06, seen in the iPadOS 18 simulator, not yet on the iPad. Reply All kept the letter's To in To, moved a Cc up to To, showed names as text, and could not be told his other addresses

**Asked.** B-061 addressed Reply and Reply All as Mail was believed to,
and put what it could not know to the owner: "Reply's addressing", "His
second address" and "Reply to his own letter sent by Bcc alone", in the
TODO under "Blocked on the owner". His ruling, 2026-10-06: "copy apple
mail for these".

**What Mail does**, gathered on 2026-10-06 from his own mailbox, Apple's
iPad guide and Apple's forums, and checked a second time. His mailbox
gives counts only, and cannot tell his iPad from his iPhone.

- *Reply All* (high). The sender alone in To; everyone else in Cc, the
  letter's To first, then its Cc, each in the letter's order. In about a
  hundred Reply Alls of his from Mail, 69 of 71 people in a letter's To
  went to Cc, 56 of 57 in its Cc stayed in Cc, and the order held in 21 of
  22. Apple's staff call it "expected behavior in iOS as well as OS X
  Mail". B-061's way, the letter's To kept in To, is not Mail's; the way
  before it, everyone in Cc, was.
- *A Cc left alone* (medium). Never moved up to To. In 33 of 34 Reply
  Alls to a letter whose To was him alone, the sender was in To and the
  Cc stayed in Cc. The sender always fills To, so these do not say what
  Mail does when To would be empty. One case of his suggests the reply
  then goes with no To: To would have been him, through a Reply-To of
  his. That case is inferred, its Reply-To could not be read, and the
  second check did not find it again, so it marked this uncertain.
- *Reply-To.* Reply goes to the Reply-To alone (medium). Reply All puts it
  in place of the From, not beside it (low: two cases, no header read).
- *His own letter.* Reply goes to whom it went, never to him (high: none
  of 29). Reply All on it, and a letter he sent by Bcc alone: not found
  out. The one first-hand report, from an older iPhone, has Reply All put
  the user himself in To.
- *The header* (high). "Name <address>" with the letter's name, 1,652 of
  1,864 times; the bare address where the letter's name was the address
  itself, 107 times.
- *The composer* (medium). Each recipient by name, as an atom, not as
  "Name <address>" text. No picture of iPadOS 18's composer was found.
- *His addresses* (medium). Mail leaves out of Reply All the addresses it
  knows as his: the account's, and any listed under the account's Email
  with "Add Another Email…". It fills in nothing by itself and does not
  read Gmail's send-as addresses. His address with a dot or a tag in it is
  someone else to Mail. Letter case is unsettled: one Reply All of his
  left out his address in other capitals, and an old report says Mail
  told case apart. The ruling takes it without regard to case.

**Changed.**

1. *Reply All* (`ReplyAddressing`). The Reply-To, or everyone in the From,
   alone in To; everyone else in Cc, the letter's To then its Cc, in their
   order, each once, his addresses left out, and nobody in To repeated in
   Cc. Nobody on someone else's letter moves up to To: a Reply All whose
   Reply-To is his goes with no To and the others in Cc, as one case of
   his, inferred and not found again, suggests. Reply is as it was.
2. *His own letter* is as B-061 built it, since Mail's way there was not
   found out: Reply to its To, or its Cc; Reply All to its To and its Cc
   in the same fields, with the Cc moved up when its To was only him; a
   letter by Bcc alone to him.
3. *The header* (`RFC5322Builder`, `MailFormat.recipientEntry`). A name
   that is the address again, in any letter case, goes as the bare
   address, typed or kept in a draft as well as in a reply. Every other
   name goes as before.
4. *Name bubbles* (`RecipientField`, `RecipientBubbles`), in the composer
   and the share sheet. To, Cc and Bcc show each recipient as a bubble
   with the person's name, or the address where there is none. A comma,
   Return, or leaving the field makes a bubble of what he typed; a comma
   inside a quoted name or `<…>` does not. A pick makes a bubble with the
   name the list shows. Backspace with nothing typed picks out the last
   bubble, which turns the bright tint, and a second takes it off. A tap
   on a bubble picks it out and shows a small menu, its address over
   Remove; a tap outside puts it back. A bubble is drawn 30 points tall
   and at least 44 wide, and takes a tap anywhere on its line's 44
   points, so every bubble is a 44-point target (D-007). The words, the
   address in the menu and what VoiceOver reads come from the entry's
   first line, as the header and the envelope read it (B-061). The field
   grows a line of 44 points at a time, as Mail's grows with a Reply
   All's people, and the suggestions sit under it. The words are the
   field's own size, fixed (D-007), white on the tint dimmed (D-010).

   Underneath, each bubble is one recipient, its entry as kept, and what
   he is still typing after them is split as the field's text always was
   (`RecipientField.recipients`). Send, Cancel's untouched-letter rule,
   the autosave, Drafts, the Outbox and the share sheet read that, so a
   letter goes to the people the bubbles show. B-069's and B-073's
   suggestion rules are unchanged: `ComposeForm.suggestions` matches what
   he types after the bubbles, and leaves out every bubble's address. A
   pick takes the place of everything he typed after the last bubble, a
   quoted name cut short after its comma included (B-061, "Not
   covered").
5. *His addresses* (`MailAccount.otherAddresses`, `ownAddresses`, Settings).
   Under the account's address, Settings lists his addresses as Mail's
   account lists them under Email: the account's own first, without
   Remove, then each added with "Add Another Email…", each with Remove.
   One that is not an address, or is already listed in any letter case,
   is refused, and says so. Saved with Save, stored with the account, and
   handed to the share extension with it (`ShareMirror`). Nothing is
   added by itself, and From stays the account's address.
6. *Is this address his* (`OwnAddresses(account:)`), the one place the app
   asks: every address in `MailAccount.ownAddresses`, and the account's
   login, kept from B-061, which on his account is the address. Matched
   as written, without regard to case. Gmail's other spellings of his
   mailbox, a dot, a `+` tag, googlemail.com, are no longer his, as in
   Mail. Reply All leaves every one of his out, and a letter from any of
   them is his own.

**Why bubbles built by hand, not `UISearchTextField`.** That field's
tokens, in iOS since 13, would do much of this. The app is installed once
and never updated, so what it is built on matters more than what it
saves. A search field's tokens are the system's: how backspace takes one
off, what a tap on one does, whether its text holds them, and its search
look, a magnifier and a grey well to undo. They keep to one line and
slide out of sight, so a Reply All's tenth person would be under the
first. The bubbles here are a plain text field, its `deleteBackward`,
buttons laid out by hand and an action sheet, all of which have behaved
the same for a decade; every recipient stays in sight; and what each key
and tap does is in one file and in the suite.

**For B-075.** Sent Mail's rows, built at the same time, leave out "his
own addresses" with the account's address alone. At the merge they ask
`OwnAddresses(account:)`, or read `MailAccount.ownAddresses` for the
list.

**What he sees.** To, Cc and Bcc with a dark blue bubble for each person,
the name on it. A Reply All with the sender alone in To and the others in
Cc. Settings with his addresses under his account, "Add Another Email…"
under them, and a Remove beside each one added. New words: "Email — your
addresses. Reply All leaves them out, and a letter from any of them is
yours.", "Add Another Email…", "Add Another Email", "An address of yours
that mail to you comes to.", "Add", "Remove", "That is not an email
address. Nothing was added.", "That address is already in the list."

**Tests.** `ReplyAddressingTests`, now thirty-five, three of them new:
Reply All's Cc the letter's To then its Cc in their order, the To not
repeated in Cc in any letter case, and a Cc never moved up on someone
else's letter, with its Reply-To his. Changed, each with the reason in
its comment: the Reply-To and the From each alone in To
(`testReplyAllGoesToTheReplyToAloneAndEveryoneElseInCc`,
`testReplyAllGoesToTheFromAloneAndEveryoneElseInCc`), his own letter
known in any letter case and no other spelling, his address left out in
any case and Gmail's other spellings kept, his addresses compared as
written (was `testGmailsSpellingsAreOneMailbox`), the login, a letter
from several, names broken over lines, another domain's spellings, once
each with names, the header, a letter with no From, and the 6,000 replies
made up from awkward letters, which now hold every rule with a second
address of his listed and Gmail's spellings among the others, Mail's To
and Cc in their order, and each field a bubble each.
`testACcLeftAloneMovesUpToTo` is now `…OnHisOwnLetter…`, unchanged.
`ReplyAddressingRepositoryTests`: a Reply All sent, a reply's draft
reopened, and names broken over lines, To and Cc as Mail's.
`ReplyForwardTests` (2) and `ReadingPaneCcTests` (1): Reply All as Mail's.
`ComposeLikeMailTests` (1): the fields are bubble fields.
`ReplyLikeMailTests`, twenty-six, new, four of them from the review
below: his addresses, the account's
first, each once, added and removed, refused when not an address or
listed already, stored with the account, read from an account an older
build kept, handed to the share extension; the one place that asks, the
list and the login in any case and nothing else; his second address
listed left out of Reply All and not listed kept, a letter from it his
own, his letter to it alone answered to him, and nothing filling the
list but the account's own code; the header naming a person and never
the address again; the bubbles: a bubble each and the same people
underneath, the name or the address on each, a comma, Return and leaving,
a pick and the suggestion rules through the bubbles, a pick right after
leaving, backspace picking out then taking off, a tap, Remove, and
Cancel reading the same people; and read from the source, both
composers' bubble fields, the field's backspace, Return, leaving, menu
and fixed sizes, and Settings' list.

Each part undone in a scratch copy, one at a time, the whole suite run
serially each time, counted as failures in tests: Reply All with the
letter's To kept in To, as B-061 had it, 41 in 19; its Cc with the
letter's Cc first, 28 in 14; a Cc moved up on someone else's letter, 4 in
3; the From beside the Reply-To, 8 in 6; Gmail's spellings his again, 14
in 6; his addresses compared in their letter case, 17 in 10; the list not
asked, the address and the login alone, 7 in 5; the list with the added
first, 4 in 4; the list not once each, 1 in 1; Add Another Email taking
one already listed, 2 in 1, or what is not an address, 7 in 1; Remove
matching the letter case, 1 in 1; the list not read back from the stored
account, 4 in 2; not tidied as it is saved, 2 in 2; a header name that is
the address again sent as a name, 1 in 1; a field entry keeping one in
another case, 1 in 1; a comma making no bubble, 9 in 1; a comma inside a
quoted name ending one, 5 in 1; Return or leaving making none, 8 in 2;
backspace taking a bubble off at once, 6 in 2; a pick right after leaving
keeping the half-typed name, 2 in 1; the text without the comma after the
last bubble, 2 in 2; a bubble saying the entry whole, 5 in 3; the app's
pick the address alone, 1 in 1, and the share sheet's, 1 in 1; backspace
not handed to the bubbles, 1 in 1; Remove not told to the sheet, 1 in 1;
the account's own address given a Remove, 1 in 1. Twenty-eight in all.
The first run of leaving making no bubble also failed `LargeLetterTests.
testPicturesStillComingWhenHeMovesOnAreCalledOff`, which fails now and
then on this host; run again, only the two. The full suite, serially,
with nothing undone: 1,515 tests, 5 skipped, none failing. The release
build for the iPad links.

**Reviewed 2026-10-06, and fixed.** A review of the change above found
five things, each fixed in the text above, which says how it is now. A
bubble's words, the address in its menu and what VoiceOver read came
from all of its entry, the last `<…>` on any line, where the header and
the envelope read only its first line (B-061). A `mailto:` link of
`sam@example.org%0A%3Cother@example.net%3E` showed other@example.net under
a letter that went to sam@example.org. Now the bubble reads the first
line too (`RecipientBubbles.words`, `address`). A bubble took taps only
on its 30-point pill, as narrow as its name: a tap a few points above or
below it raised the keyboard, and "Al" was 35 points wide, under the 44
D-007 binds. Now it is at least 44 wide and takes a tap on the whole of
its line (`BubbleButton`, `RecipientBubbles.touchArea`). Every change to
the field made every bubble's button again, the one a menu hung from
among them: Return under a menu left the menu pointing where the bubble
had been, and the bubble lost its tint. Now the bubbles before the first
change and after the last keep their buttons (`RecipientBubbles.
unchanged`), the bubble a menu is up for stays picked out whatever he
types or ends under it, and a backspace that takes it off takes its menu
too. Send, the letter and the suggestions read the field written out as
text and split it again at its commas: one bubble with a quote never
closed in it, `"Sam`, split every other bubble at its commas, so two
bubbles went as three recipients, the first `"Example`. Now they read a
bubble at a time (`RecipientField.recipients`), and a field opened from
a letter or a draft splits each entry on its own. And this entry and
`ReplyAddressing`'s comment stated as Mail's that a Reply All whose
Reply-To is his goes with no To, which rests on one case inferred and
not found again; they say so now, and "Not covered" has the minute's
test.

`ReplyLikeMailTests` has four tests more: a bubble naming whom the
letter goes to, from that `mailto:` link, against the header; a bubble
taking a tap on its whole line; the same people keeping their buttons,
and the menu's bubble kept picked out, from the model and the field's
source; and what the bubbles show being whom the letter goes to, with a
stray quote in one, through a draft opened again and the header. The
tests that read the field's text read its recipients now.

Each fix fails with its part undone, nine sabotages one at a time, each
run once over the whole suite, serially, as failures in tests: a bubble
read from all of its entry (8 in 2); the touch area not grown (2 in 1);
a bubble as narrow as its name (1 in 1); bubbles as plain buttons, with
no grown touch area (2 in 1); no bubble keeping its button (11 in 1);
every button thrown away at a change, as before (2 in 1); Return under a
menu not keeping its bubble picked out (2 in 2); the recipients joined
and split again, as before (3 in 1); and a field opened from a letter
joining and splitting its entries, as before (1 in 1). The sabotages of
the first pass, above, were counted before these fixes; the text they
read is gone, and with it the one that took the comma off after the
last bubble. The full suite, serially, then: 1,519 tests, 5 skipped,
none failing. The release build for the iPad links.

**Seen in the simulator, 2026-10-06**, an iPad (7th generation) on 18.6,
landscape, a hardware keyboard attached, built from this branch and
signed in to the test account, A standing for its address. The
screenshots are in the pass's shots folder, not in the repo: they show
the test account's address and its mail.

1. A new letter: A with `+jane` and a comma in To made a bubble with the
   address on it, Send blue (b076-03). A with `+sam` in Cc, then a tap on
   Subject: a bubble too. Subject "B-076 reply all" (b076-04). Sent; it
   arrived once.
2. Opened in the Inbox, Reply All: To `+jane`, Cc `+sam`, each a bubble
   (b076-06). This letter is from the account, so it is his own and
   answered as B-061 answers his own. Every letter the test account can
   make is its own; a Reply All to someone else's letter, To and Cc as
   Mail's, is the suite's.
3. In Cc with nothing typed, Delete: the `+sam` bubble turned the bright
   tint (b076-07); Delete again: gone (b076-08). A tap on the To bubble:
   picked out, and a menu with its address and Remove (b076-09); a tap
   outside: the menu gone, the bubble plain (b076-10). Tapped again,
   Remove: To empty and Send grey (b076-11).
4. "c" in To: four rows (b076-12). The first picked: a bubble saying
   "Carlo", the name the list gave; VoiceOver's tree has the button
   "Carlo" with the address as its value (b076-13). Seven more typed
   into Cc with commas, `"Example, Jane" <jane@example.com>` among them,
   and an eighth begun: seven bubbles on four lines, "Example, Jane" one
   of them, the eighth typed after them, and the list under the grown
   field (b076-14). Save Draft, which made a bubble of the eighth as the
   field was left; opened from Drafts: the same eight bubbles (b076-16).
   A word typed, Cancel, Delete Draft: Drafts empty.
5. Settings: the address, then "Email —", the address alone, and "Add
   Another Email…" (b076-17). "owner" added: "That is not an email
   address. Nothing was added." A with `+jane`, typed in capitals, added:
   listed with Remove (b076-20). Saved; Settings again: still there.
   Reply All to the letter of 1: To `+sam` alone, `+jane` left out as his
   in another letter case (b076-21). Cancel. Remove, Save; Settings
   again: the address alone (b076-22).
6. The share sheet from Safari on example.com: it opened in To. "c": the
   list; `+sam` picked: a bubble; "c" again: `+sam` not offered (b076-25). Delete twice: the "c" gone, then the bubble picked
   out (b076-26). A tap on it: the menu, dark (b076-27). A tap outside,
   Subject "B-076 share bubbles", Send: it arrived once, To `+sam`.

**Seen in the simulator after the review, 2026-10-06**, the same iPad,
on a fresh simulator built from the fixed branch, the screenshots kept as
before.

1. The `mailto:` link above, opened in the app: To one bubble,
   "sam@example.org". A tap 4 points above the pill, inside the To row:
   its menu, titled sam@example.org, with no other address in it and the
   arrow on the pill; VoiceOver's tree gives the bubble no other value
   (b76f-03, b76f-04). Cancel closed the letter without a word, as it
   had opened.
2. A new letter: `Al <al@example.com>` and a comma in To made a bubble
   "Al", 44 points wide, 30 tall, in a To row of 44 (b76f-07). A tap 4.5
   points below the pill: its menu, with the address and Remove
   (b76f-08).
3. "sa" typed after it, then the menu, then Return under it: "sa" a
   bubble after "Al", "Al" still bright, the menu still on it (b76f-09).
   The on-screen keyboard brought up under the menu moved the sheet up
   17.5 points, and the menu moved with "Al", about 13 points under it
   before and after (b76f-10, b76f-11). Delete: "Al" gone, and its menu
   with it, "sa" plain (b76f-12).
4. To A with `+sim18`; Cc `"Example, Sam"` and A with `+sam` in `<…>`:
   one bubble, "Example, Sam" (b76f-13). Subject "B-076 fix recipients",
   Send: it arrived once, To A with `+sim18`, Cc "Example, Sam"
   (b76f-15).
5. The share sheet from Safari: `Al <al@example.com>` and a comma, a
   bubble 44 wide; a tap 4 points above it: its menu (b76f-18). Remove,
   Cancel: closed without a word.

**Not covered.**

- Mail itself was not tried on an iPad. What it does is the evidence
  above, and the owner's ruling is the rule.
- His own letter's Reply All, and a letter he sent by Bcc alone, are
  answered as B-061 built them. One minute on any iPad running Mail would
  say what Mail does.
- A Reply All whose Reply-To is his goes with no To. That rests on one
  case of his, inferred and not found again. One minute on any iPad
  running Mail would settle it: a letter From A, Reply-To his address, To
  him, Cc C, then Reply All. The same letter with a Reply-To of B would
  also settle whether Mail puts the Reply-To in place of the From.
- His iPad's own Mail account was not looked at: whether it lists his
  second address under Email, or has an account for it, is one look at
  Settings > Apps > Mail > Mail Accounts on the day. His second address
  is his here only once it is added in Settings; the TODO's install-day
  line says so.
- A recipient's Contacts name, which Mail puts in the header now and
  then, is not used: the app does not read Contacts (B-017).
- Mail shows a recipient outside his domain in red, when asked to; not
  built.
- The on-screen keyboard was not tried in the simulator; the hardware one
  was. A drag of a bubble from one field to another, which Mail allows,
  is not built.
- Not yet seen on the iPad. The TODO says how.

---

## B-077 — CHANGED 2026-10-06, seen in the iPadOS 18 simulator, not yet on the iPad. The panes moved in a way of their own; now they move as Mail's

**Asked** on 2026-10-06. B-066 built the view button's motion and put
two questions to the owner (TODO, "Blocked on the owner"): keep its
motion, or later Mail's; and should "< Mailboxes" and a folder tap in two
panes slide. He answered: "copy apple mail for these".

**What Mail does.** Mail is UIKit's split view, three columns, and in a
narrow window its navigation controller; it moves as they move. Mail
itself was not filmed. UIKit was measured in the iPadOS 18.6 simulator on
2026-10-06, frame by frame and from the animations it installs.

- *The sidebar button*, three columns and two: one motion of half a
  second on a spring, mass 3 and stiffness 1000, critically damped. Half
  the way by 0.09 to 0.10 s, 90% by 0.21 s, 99% by 0.37 s, done at 0.5 s.
  Every column moves at once on the same curve. Nothing moves up or
  down, and there is no second phase. Hiding the sidebar, the list keeps
  its width and slides left over it, a shadow on its leading edge; the
  sidebar goes left at half the list's speed and darkens, black at a
  tenth; the letter's left edge goes with the list. Showing it is the
  exact reverse.
- *A push and a pop*: the new screen slides in from the right edge of its
  column, over the old, with a shadow on its leading edge; the old goes
  30% of the column to the left and darkens. A pop is the reverse. The
  same spring. The bar's title and back button cross-fade and slide over
  0.35 s on cubic(0.25, 0.1, 0.25, 1).
- *Reduce Motion* changes neither. With *Prefer Cross-Fade Transitions*
  as well, the sidebar still slides, the same spring and the same paths;
  a push and a pop become a cross-fade of 0.5 s, nothing moving.
- *The layout.* On an iPad 1194 pt wide or narrower, Mail with its
  sidebar shown pushes the letter partly off the screen and dims it. From
  1210 pt it puts the three side by side.

**What it was** (B-066). Pictures slid 0.4 s, easing in and out, then
faded 0.2 s over the panes beneath. The folders stood still; the list kept
its three-pane width, and from three to two a strip of canvas opened
beside it. With Reduce Motion or Prefer Cross-Fade Transitions, the screen
faded for 0.3 s. "< Mailboxes" and a folder tap in two panes were instant.

**Changed.**

1. *One motion, on UIKit's spring.* Half a second, mass 3, stiffness
   1000, critically damped, every picture at once (`PaneMove.progress`,
   `Theme.paneMoveDuration`). No settle. UIKit asks for a damping of
   500, which iPadOS 18 runs as critical; asked for as it is on an older
   iPadOS it might not be, so the damping given is the critical one,
   109.5.
2. *Three to two.* The list, laid out as it will be, 375 pt, slides left
   over the folders from where its right edge meets the letter's to the
   screen's edge, 205.5 pt on the 11-inch. A shadow comes on its leading
   edge. The folders go left half as far, 102.75 pt, and darken to a
   tenth. The letter's left edge goes with the list.
3. *Two to three, the list in front.* The exact reverse: the list, laid
   out as in three, 330 pt, slides right off the folders; they come back
   from 102.75 pt left, laid out, darkened, and lighten; the shadow goes.
4. *Two to three, the folders in front.* Mail has no such switch. B-066's
   shape stays, on the same spring and with no settle: the folders'
   column draws in, cut off, the letter's edge goes right, and the list
   is there between them.
5. *A folder tapped in two panes.* Its list slides in from the column's
   right edge over the folders, a shadow on its leading edge; the folders
   go 112.5 pt left, 30% of the column, and darken. Only what is under
   the bars moves. The folders' bar slides half the column left and fades
   out, the list's comes from half the column right and fades in, over
   0.35 s on UIKit's bar curve, over an empty bar that stays. The view
   button's glyph stays in the corner. Nothing goes over the letter: the
   pictures are cut off at the column.
6. *"< Mailboxes"* is the reverse: the list slides off to the right, its
   shadow going, and the folders come back from 112.5 pt left, lightening,
   the open one highlighted.
7. *Reduce Motion*, Mail's rule. The view button's switch slides whatever
   is set. "< Mailboxes" and a folder tap slide, and with Prefer
   Cross-Fade Transitions, which iOS gives only with Reduce Motion on,
   the column as it was fades for 0.5 s over the column as it is, its
   rows on UIKit's ease in and out, its bar on the bar curve, and nothing
   moves (`PaneMove.motion`, `PaneMotion.crossFading`).

**The layout is Blackmail's.** The motion is copied, not the layout. The
three panes stay side by side at every width, his own choice (D-015), where
Mail on an iPad as narrow as his pushes the letter off. So the letter's
picture keeps its left edge with the list's right edge, as Mail's does on
a 1210 pt iPad, and its right edge stays the screen's. The list is 330 pt
in three panes and 375 in two on the 11-inch, where Mail's is 375 in both;
its picture has the width it ends at, all the way.

**Not UIKit's own push.** A real push and pop were weighed first, and
do not fit. The list has a navigation controller of its own
in both arrangements, beside the Mailboxes' (D-003, D-015). Pushed onto
the Mailboxes' stack it would leave the window at every switch of the
view button, the search field and its keyboard with it, and UIKit's back
button would take the corner where the view button stays. So the push and
the pop are pictures moved on UIKit's numbers, as the view button's
switch is.

**When things change their look.** B-066's rule holds: nothing changes its
look while it moves. Pictures move; the panes are laid out anew at the
tap, beneath, as before. Then two kinds of picture:

- *Laid out anew*, for what comes or stays: the list, the folders coming
  back, a list pushed in, the bar coming. Cut from each pane after the
  layout, while a picture of the whole screen as it was covers the glass.
  So the list is at its new width, its bar dressed, from the first frame
  that moves, as UIKit lays its columns out before it moves them, and
  its last frame is the screen beneath.
- *As it was*, for what goes or is cut off: the folders going, their
  column drawing in, a list popped off, the bar going, and the letter.
  WebKit draws the letter in another process and wraps it again in its
  own time, so no picture of it at its new width can be had at the tap.
  Its words go with its left edge and land where they now are.

So the end of the motion is the screen beneath but for the letter's line
ends, which change at once as the pictures go, as at a switch made at
once, where B-066 faded them over 0.2 s; and, from two panes with the
folders in front, the folders' title and counts, which move to the
column's new width then.

**What stays from B-066.** The cover takes every touch for the half
second, and VoiceOver reads the real panes beneath, final from the tap. A
change made while a list, the folders or the letter in the pictures
bounces past an end is made at once, with `pane motion: bouncing;
switched at once` in the connection log; one coasting is stopped first.
That holds for a pane hidden at the tap too. A change made at once hides
a pane that goes on springing back, and the next can come within the half
second: the list pulled down, "< Mailboxes" tapped and the open folder
tapped at once after it. The list coming back would be pictured as laid
out, past its top, and its rows would jump as the pictures went. The
cover goes before
anything else lays the panes out, as the iPad turns, as the app stops
being in front, and at a deadline a second after the motion's end. The
letter's actions and the view button's glyph hold still. "No message
selected" keeps to the middle of the pane. The highlights are in the
pictures as the panes are laid out: the open folder as the folders come
back, the open letter's row in the list. A picture that cannot be trusted
turns the motion down with a `pane motion:` line. The launch, a return
after a while away and the date jump stay instant.

**The cost.**

- The list changes its width and its bar at the tap, then moves: 45 pt
  on the 11-inch and 75 on the 10.2-inch the simulator runs, wider over
  the folders from three to two, narrower from two to three, where the
  darkened folders show through on its left. On a 12.9-inch, where the
  list is 377 pt in three panes, it narrows from three to two, and 2 pt
  of empty canvas show beside it until it covers them.
- The letter's line ends change at once at the end, not over 0.2 s.
- Darkening at a tenth and a shadow of a few per cent are hard to see on
  the app's dark panes.
- With Reduce Motion on, the panes now slide where they faded, as Mail's
  do.
- A list pushed in is pictured as it is at the tap: rows that come during
  the half second appear as the pictures go.

**Tests.** `PaneMoveTests`, now 26, 12 more, rewritten for the new model;
`PaneArrangementTests` the same 27, five changed.

- `PaneMove`, at every landscape width from 1024 to 1376 pt. What moves:
  the view button's three switches, a folder tapped in two panes and
  "< Mailboxes"; nothing for no change. Each move written out at 1194 and
  1366, with Prefer Cross-Fade Transitions too. The list keeps its width
  and its right edge rides the letter's left edge at every twentieth of
  the way. The folders go half the list's travel the same way, and 30% of
  the column in the stack. What is darkened and what casts a shadow, from
  and to what. What is pictured as laid out and what as it was, each
  checked against the columns alone. The last frame is the screen
  beneath, or under a picture that is, or past the column's edge, but for
  the letter. The lines ride their edges; everything is rigid and
  sideways and goes one way; only the real screen meant to show shows,
  every half point, every twentieth; the backdrop at the letter's right
  from three to two; the actions' plate; the view buttons painted over;
  the letter with its left edge; the empty pane's words in its middle;
  every pane pictured looked at for a bounce, hidden or not; where a
  list rests, as before. The
  spring: 0.5 s, mass 3, stiffness 1000, damping squared four times their
  product. The curve: half the way at 0.092 s, 90% at 0.213, 99% at
  0.364, the formula at every thousandth, never back and never past the
  end. The bars, 0.35 s, (0.25, 0.1, 0.25, 1), half the column; the
  cross-fade's curve, (0.42, 0, 0.58, 1). Mail's rule for Reduce Motion
  and Prefer Cross-Fade Transitions. The product spec's rule for moving
  panes (`spec/docs/UI_SPEC.md`), read against `Theme` and the model:
  the view button, "< Mailboxes" and a folder tap, half a second on the
  spring, black at a tenth, and the cross-fade.
- `PaneShell`: the view button, "< Mailboxes" and a folder tap in two
  panes say where the panes were; a folder tap in three, "< Mailboxes"
  with the folders in front, a folder opened another way and a return say
  nothing.
- `RootViewController` and `PaneMotion`, which are UIKit, are read. The
  container asks the model with Prefer Cross-Fade Transitions read at the
  tap and Reduce Motion asked nowhere, looks at the panes the model names
  for a bounce, and hands over all three view buttons. The motion cuts the
  screen as it was only in `cut`, and the panes as laid out only in
  `play`, after the cover with the screen as it was is up, and before
  that picture goes and anything moves; checks each picture against the
  model, as it was where it was and as laid out where it is now; moves on
  Core Animation's spring with `Theme`'s mass, stiffness, critical damping
  and duration, the bars on the bar clock, the cross-fade on its curves,
  and on nothing else; darkens and shadows as the model says; draws the
  corner's glyph only when the pictures move; never touches a real view,
  and never asks Reduce Motion.

Each part undone in a scratch copy, one at a time, the whole suite run
serially each time, counted as failures in tests. The motion of 0.4 s,
as B-066 slid: 302 in 3. UIKit's damping of 500 as asked: 3 in 1. A
stiffness of 500: 509 in 2. The curve eased in and out, not the spring:
507 in 1. The folders held still under the list, as in B-066: 23 in 3.
The folders going half the column under a pushed list: 21 in 2. The
folders not darkened from three to two: 11 in 2. The list's shadow going
rather than coming from three to two: 11 in 2. The list starting with its
left edge where it was rather than its right edge on the letter's: 200
in 3. The folders coming back pictured as they were: 4 in 2. The letter
pictured as laid out from three to two: 38 in 2. A pushed list coming in
from the left: 47 in 4. The bars sliding the list's way round: 4 in 2.
The bars on the panes' half second: 2 in 1. The view button's switch
faded with Prefer Cross-Fade Transitions: 3 in 1. Prefer Cross-Fade
Transitions ignored in the stack: 110 in 2. Only the panes on the
screen looked at for a bounce, as this change first had it: 103 in 3.
The product spec's rule put back as B-066 wrote it: 7 in 1. The stack
not cut off at the column:
787 in 3. "< Mailboxes" laid out with nothing moving: 2 in 2. A folder
tapped in two panes laid out with nothing moving: 4 in 2. Read from the
source: B-066's rule, Reduce Motion fading the stack, 2 in 1; the spring
given UIKit's damping of 500, 2 in 1; the panes laid out pictured from
the glass, not drawn first, 1 in 1; the screen as it was taken away
before the pictures are in, 1 in 1; the cover put up after the panes laid
out are pictured, 1 in 1; the folders not darkened by the motion, 1 in 1;
the bars on the spring, 2 in 1; the container not asking for Prefer
Cross-Fade Transitions, 1 in 1; the container looking only at the panes
on the screen, 1 in 1; the corner's glyph drawn over a cross-fade too,
1 in 1. Thirty-one in all, each caught, with nothing failing in any run
but the tests named. The bars on the spring failed nothing at
first; the source is now read for each change's clock.

The full suite, serially, with nothing undone: 1,502 tests, 5 skipped,
none failing. The release build for the iPad links.

**Reviewed 2026-10-06, and fixed.** A review found two things, each fixed
in the text above. The product spec still gave B-066's rule: 0.6 s, no
dimming, and nothing but the view button's switch moving the panes. It
now says what is built (`spec/docs/UI_SPEC.md`, under "Do not animate
panes dramatically."), and a test reads it. And a bounce was looked for
only in the panes on the screen at the tap, where B-066 looked in every
pane it pictured. A pane hidden a moment before by a change made at once,
still springing back, was then pictured past its end and jumped as the
pictures went: a list pushed in and the folders coming back. Every pane
pictured is looked at again. The counts above are after the fixes.

**Seen in the simulator, 2026-10-06**, an iPad (7th generation) on 18.6,
1080 pt wide, landscape, signed in to the test account, built from this
branch as it is now. Each motion recorded at 60 frames a second and
stepped through frame by frame. A divider's place was found in each
frame, or, in the stack, the shift that lays the list's rows on where
they rest, and fitted to 1 - (1 + wt)e^(-wt). UIKit's spring has
w = 18.26 a second.

- *Three to two*, the pane empty and with a letter of the test account's
  own: the list, at its two-pane width with "< Mailboxes" in its bar
  from the first frame that moves, slid over the folders, which went left
  under it; the letter's edge went with it, "No message selected" in the
  middle of the pane; the corner's glyph and the letter's actions stood
  still. w = 18.15 to 18.45 in three recordings, fitting to 0.3% of the
  way; the pictures gone 0.48 s after the first frame
  that moved. With a letter, its lines wrapped again then.
- *Two to three*: the reverse; the list narrowed at the tap and the
  folders showed on its left. w = 18.30, empty and with a letter. *The
  folders in front, to three*: their column drew in and the list was
  there between; w = 18.05 and 18.10.
- *A folder tapped* and *"< Mailboxes"*: as items 5 and 6 above,
  w = 18.25 and 18.20. The letter pane did not move by a pixel in any
  frame, empty or with a letter. Earlier the same day, on a build with
  the same model, Drafts' list slid in as it was at the tap, "Checking
  for Mail…", and its "No messages" came as the pictures went.
- *Reduce Motion* on (`ReduceMotionEnabled`): all four slid, unchanged,
  w = 18.20 to 18.50. *Prefer Cross-Fade Transitions* on as well
  (`ReduceMotionReduceSlideTransitionsPreference`): the view button's
  switch slid, w = 18.40 and 18.10; "< Mailboxes" and a folder tap
  cross-faded for about half a second, nothing moving, the bar half gone by 0.15 s
  and the rows by 0.24 s.
- *Two taps* 0.15 s apart on the view button: one switch. *A flick* of
  the list past its top and the view button tapped while it sprang back:
  the switch was made at once, with no frame between.
- *Two changes made at once*, after the review, on the build with every
  pane pictured looked at. In two panes the list pulled down past its
  top, "< Mailboxes" tapped as it was let go, and the open Inbox tapped
  straight after: two `bouncing` lines 184 ms apart, no frame of either
  change moving, and the list back 4.5 pt past its top, springing back to
  rest over a quarter of a second with no jump. On the build before, the
  review saw the list pictured 17.5 to 23.5 pt past its top in the same
  steps; its rows rode that low for the whole push and jumped up as the
  pictures went. With 0.45 s between the two taps, the list was at rest
  and the push slid. The folders pulled down, the view
  button tapped as they were let go and "< Mailboxes" 0.22 s later: the
  hide at once, the folders at rest by the second tap, and the pop slid
  and landed with no jump. Then eight ordinary changes in a row, a new
  Drafts list and a new Inbox pushed in, the same Inbox pushed in again,
  three pops and both view-button switches: all eight slid, with no
  `pane motion:` line.
- *Against UIKit.* The probe of 2026-10-06, its own recording measured
  the same way: w = 17.60, to 0.3% of the way; its installed animations
  fitted at 18.15 to 18.35 for the sidebar and 18.6 to 19.1 for the push
  and pop. Blackmail's fourteen slides on this build: 18.05 to 18.50.
- *The recorder.* Within 8 ms of the tap, under half of one frame of the
  iPad's screen, the recordings hold two to four pictures: the screen as
  it was, the same under the cover, and the first frame of the motion.
  In some recordings of the view button's switch, five of twenty earlier
  in the day and two of eleven on this build, the screen as it was came
  once more, between two copies of the first frame. A build that marked
  the cover's picture of the screen in red showed that this one was not
  the cover. Nothing on the app's side can put the screen as it was back
  after the motion's first frame: by then the real panes are laid out
  anew. The stray picture comes only inside those bursts of pictures a
  few milliseconds apart, never at the screen's own pace, so it is taken
  as the recorder's. The iPad checks in the TODO look for it on the
  glass.

**Not covered.**

- Mail itself on iPadOS 18 was never filmed. What it does is UIKit's, as
  measured, and the evidence that Mail is built of UIKit's split view.
- Not yet seen on the iPad. The test iPad is on iPadOS 16.5.1; whether
  it runs this spring as 18.6 does is for the iPad.
- The darkening and the shadow are sized from UIKit's in its light
  appearance. On the app's dark panes they could not be measured.
- The bars move as two whole pictures. Mail moves the old title toward
  the back button and the new title in from the right, each on its own;
  here the buttons at the bar's right end slide with them.
- From two panes with the folders in front there is nothing of Mail's to
  copy. B-066's shape stays, with its change at the end.
- Rows that arrive for a list pushed in during the half second, the
  keyboard, and the letter WebKit is still drawing show as the pictures
  go, as before.
- The iPad was not turned in the simulator during a motion, and VoiceOver
  was not on. The host suite reads both.
