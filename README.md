# Blackmail

An iPad email client for a 90-year-old man, built so the things he needs are
always in the same place. The layout is modelled on iOS 10/11-era Apple Mail,
because that is the arrangement he already knows and every redesign since has
moved his controls.

`spec/` is the brief as received, apart from `spec/references/`, which also
holds the project's own reference measurements. It is the requirements document,
not the plan of record — where the build departs from it, the departure and its
reason are in `docs/DECISIONS.md`.

## What this is actually optimising for

**Layout, not appearance.** The goal is not a pixel-faithful reproduction of a
2016 screenshot; it is that the mailbox list, the message list, the message, and
every action button sit where his hands expect them, and never move. Where
period fidelity and usability disagree — type size being the obvious case — the
90-year-old wins.

That distinction decides real things. It means the measured constants in
`docs/LAYOUT_CONSTANTS.md` are binding on *positions, densities and ordering*
and advisory on colours and hairline shades. It also means we do not need to
fight the operating system's own look, which removes the main argument for
pinning an old SDK.

## Non-negotiables, from the brief and from the user

- Controls never move. Not between messages, not between folders, not between
  portrait and landscape.
- Tap is the only interaction required. No swipe actions, no long-press, no
  gesture discovery.
- Nothing essential hidden behind `...`.
- 44×44 pt minimum hit targets, whatever the glyph size.
- Plain-language errors. Raw IMAP text goes to an admin log he never sees.

## How it gets built and onto a device

    source  ->  Swift, compiled on Linux for arm64-apple-ios
            ->  zsign (Apple ad-hoc distribution cert + wildcard profile)
            ->  AltStore-format OTA source
            ->  ad-hoc OTA install onto registered devices

No Mac anywhere. See `docs/TOOLCHAIN.md`. The distribution half is already
working and proven.

## Status

Working on a development iPad: the three-pane layout, IMAP reading and
search across mailboxes, compose, reply and forward with attachments over
SMTP, his signature, and the calendar jump. What is left is in
`docs/TODO.md`; known defects are in `docs/KNOWN_ISSUES.md`.
