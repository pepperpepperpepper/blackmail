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
whose reply is lost in flight remains ambiguous. The residue is small and
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
`PAIR`, `DATA-REPLY-CODE`, `BUILD-SIZE`-era learnings) exist to keep
this investigation in numbers.

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

A `-fail` suffix means the send threw; `-ok` means it reached 221. Read
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

## B-036 — OPEN. He shares to email constantly, and the app cannot receive a share

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

---

## B-037 — OPEN. No way to switch between the two-panel and three-panel view

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
host cannot build, and none of it has been seen on the iPad yet. The TODO
says what to look at.

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
