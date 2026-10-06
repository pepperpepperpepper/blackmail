# UI Specification — iOS 10/11-era iPad Mail target

## Primary target
Landscape iPad, old Apple Mail visual grammar circa iOS 10–11.

## Layout
Use three persistent vertical regions on sufficiently wide iPads:

### Pane A — Mailboxes
Approximate width: 22–25% of available content width.
- White background.
- Plain table rows.
- Folder name left aligned.
- Optional unread count right aligned.
- Selected mailbox uses restrained selection treatment.
- No oversized section cards.

### Pane B — Message list
Approximate width: 28–32%.
- Sender on first line, semibold for unread.
- Subject on second line.
- Preview snippet below.
- Time/date aligned to upper-right.
- Thin separators.
- Selected row uses classic iOS selection color/treatment.
- No sender photographs or logos.

### Pane C — Message detail
Remaining width.
- White reading canvas.
- Header information at top.
- Message body below.
- HTML rendered conservatively.
- Avoid cards, floating controls, or message bubbles.

## Top chrome
Use an old-style navigation/toolbar region with fixed actions.

Primary actions, in a stable order:
1. Flag (optional in v1).
2. Move.
3. Delete.
4. Reply / Forward.
5. Compose.

The exact order should be tuned against the visual references, but once chosen it must not change contextually.

## Typography
- Use Apple system font.
- Match old iPad Mail scale rather than current oversized title styles.
- Navigation titles should be compact, not large-title navigation bars.
- Default body copy should respect Dynamic Type but cap extremes if they destroy the three-pane composition; provide a separate admin/user text-size preference if needed.

## Interaction rules
- Tap is the canonical interaction.
- Do not require long-press.
- Do not hide essential actions behind `...`.
- Do not depend on swipe actions.
- Do not use modern floating menus for core actions unless the old Mail behavior itself did.
- Do not animate panes dramatically.
  - The view button's switch, "< Mailboxes" and a folder tap in two
    panes move as Mail's do (B-066, B-077, D-015): sideways only, half a
    second on UIKit's spring, with no bounce and no scaling. A column
    going under another darkens, black at a tenth. With Prefer
    Cross-Fade Transitions, "< Mailboxes" and a folder tap fade for half
    a second instead. Nothing else moves the panes.

## Portrait mode
Portrait is secondary. The application may collapse to two panes or one pane if necessary, but:
- Keep action order identical.
- Provide obvious Back navigation.
- Never force the user to discover gestures.

## Accessibility
- VoiceOver labels for every toolbar control.
- 44x44 pt minimum hit area.
- Sufficient contrast.
- Preserve semantic headings in HTML mail where possible.
- Respect Bold Text.

## Visual acceptance target
The app does not need to illegally copy Apple artwork. It does need to reproduce:
- spatial organization,
- button placement,
- density,
- typography scale,
- separator behavior,
- selection behavior,
- navigation hierarchy,
- interaction sequence.

The product should feel like an old iPad utility, not a contemporary redesign inspired by one.
