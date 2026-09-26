# Classic Mail — Project Package

Goal: build a private iPad mail client whose interaction model is intentionally frozen to the classic Apple Mail experience (target: iOS 10/11-era iPad Mail), for an older user who is confused by modern Mail UI changes.

This package is designed to be handed directly to a developer.

## Start here
1. Read `BRIEF.md`.
2. Read `docs/PRODUCT_SPEC.md`.
3. Read `docs/UI_SPEC.md` and `references/REFERENCE_SCREENSHOTS.md`.
4. Read `docs/ARCHITECTURE.md`.
5. Follow `docs/IMPLEMENTATION_PLAN.md` in order.
6. Do not redesign the UI. Stability and familiarity outrank novelty.

## Core technical direction
- Native iPadOS app.
- UIKit first, not SwiftUI-first.
- `UISplitViewController` / explicit pane controllers for deterministic layout.
- Mail transport via SwiftMail (IMAP + SMTP) unless the target provider forces a different auth path.
- Local cache for fast startup and offline reading.
- Private distribution to registered iPad(s), not App Store distribution.

## Non-goals
- No AI features.
- No inbox categories.
- No smart sorting.
- No visual redesign.
- No feature churn.
- No account-management complexity exposed to the user.
- No attempt to reproduce Apple-owned icons/assets pixel-for-pixel if those assets are not available as system symbols.

## Package contents
- `BRIEF.md` — the brief; start here.
- `docs/PRODUCT_SPEC.md` — behavioral requirements.
- `docs/UI_SPEC.md` — visual and interaction target.
- `docs/ARCHITECTURE.md` — components and data flow.
- `docs/IMPLEMENTATION_PLAN.md` — ordered build plan.
- `docs/ACCEPTANCE_TESTS.md` — exact success criteria.
- `docs/SECURITY_AND_AUTH.md` — credential handling and provider notes.
- `docs/DISTRIBUTION.md` — private iPad installation path.
- `references/REFERENCE_SCREENSHOTS.md` — period-correct visual references.
- `starter/` — initial UIKit source skeleton.
