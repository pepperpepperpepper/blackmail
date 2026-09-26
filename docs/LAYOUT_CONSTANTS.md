# Layout constants

Measured from the iOS 10 12.9-inch iPad Pro reference screenshot
(2732x2048 -> 1366x1024 pt) unless the derivation column says otherwise.
These become `ios/Theme/CMTheme.h`; nothing else in the app may hard-code a
number.

**Scaling rule.** Only pane widths vary by screen. Row heights, font sizes,
insets and the unread dot are absolute points on every iPad - the density is
the product.

**The reference image itself must never be committed or shipped.** Measurements
are facts about a layout; the screenshot is someone else's copyrighted asset.

| Constant | Value | Derivation |
|---|---|---|
| `CM_BUNDLE_ID` | wtf.uhoh.blackmail | Covered by the existing wildcard ad-hoc profile — verified in a previously shipped IPA; no new App ID needed |
| `CM_THEOS_TARGET_LINE` | TARGET := iphone:clang:16.5:14.0 ; ARCHS := arm64 ; PACKAGE_FORMAT := ipa | The proven Makefile line from the existing theos pipeline |
| `CM_MINIMUM_OS_VERSION` | 14.0 | MinimumOSVersion in a previously shipped app's Info.plist; no UISplitViewController dependency so no iOS 14 floor is forced by API |
| `CM_DEVICE_FAMILY` | UIDeviceFamily = [2]  (iPad only for v1) | PROJECT_SETUP.md:5; shipped apps use [1,2] but Classic Mail is iPad-only |
| `CM_INFO_PLIST_SHAPE` | No UIApplicationSceneManifest; UIRequiresFullScreen=YES; LSRequiresIPhoneOS=YES; UILaunchScreen={}; loose-PNG CFBundleIconFiles / CFBundleIcons~ipad; UIRequiredDeviceCapabilities=['arm64'] | plistlib dump of a previously shipped app's Info.plist (verified) + UIRequiresFullScreen deprecated only in iPadOS 26, so safe against the 16.5 SDK |
| `CM_SIGNED_ENTITLEMENTS` | application-identifier = JGLH7HX44Y.wtf.uhoh.<app>; com.apple.developer.team-identifier = JGLH7HX44Y; get-task-allow = false | Entitlements blob extracted from a previously shipped app binary (verified) |
| `CM_PROFILE_AND_CERT_EXPIRY` | 2027-09-18 10:22:36 UTC (both, simultaneously) | openssl smime on the ad-hoc profile in the signing directory (TimeToLive 364) and openssl x509 on the distribution certificate; re-confirmed inside the shipped IPA's embedded.mobileprovision |
| `CM_PROVISIONED_DEVICES_NOW` | 1 (the dev iPad; the target user's iPad is NOT included) | ProvisionedDevices count in both the on-disk profile and the shipped IPA |
| `CM_LIBETPAN_DEFINES` | -DHAVE_CONFIG_H=1 -DHAVE_CFNETWORK=1 -DHAVE_COREFOUNDATION_CHARCONV=1  (do NOT define USE_SASL, HAVE_OPENSSL, HAVE_GNUTLS; HAVE_JMAP=0 to drop curl+json-c) | libetpan Package.swift cSettings + build-spm/config/config.h |
| `CM_LIBETPAN_SOURCES` | 200 .c files, enumerated verbatim in the `sources:` array of libetpan's Package.swift — no autotools run needed | grep -c '\.c",' on libetpan Package.swift |
| `CM_LIBETPAN_HEADER_PATHS` | build-spm/config, build-spm/include, build-spm/include/libetpan, include, ., src/data-types, src/driver/{interface,tools}, src/low-level/{imap,imf,mime,smtp,pop3,nntp,gmail,maildir,mbox,mh,feed,pgp}, src/engine, src/main (~35 entries) | libetpan Package.swift cSettings headerSearchPath entries |
| `CM_FRAMEWORKS` | UIKit WebKit QuickLook CFNetwork Security CoreFoundation (all present in the theos sparse iPhoneOS16.5 SDK) | libetpan Package.swift linkerSettings + ARCHITECTURE.md WKWebView/Quick Look requirements |
| `CM_SYSTEM_LIBS` | -lz -liconv -lxml2 -lresolv (libz.tbd, libiconv.tbd, libxml2.tbd, libresolv.tbd all present in iPhoneOS16.5.sdk/usr/lib; libsasl2 is NOT present and is not needed) | gh api repos/theos/sdks/contents/iPhoneOS16.5.sdk/usr/lib |
| `CM_REF_CANVAS_PT` | CGSize(1366, 1024)  — 12.9" iPad Pro landscape | MEASURED. Reference image 2732x2048 px at @2x, so 1 px = 0.5 pt |
| `CM_PANE_A_WIDTH_PT` | 287.0 (fixed) | MEASURED. Divider column at x=574 px. Fraction 0.21010 — note this is BELOW UI_SPEC's stated 22% floor |
| `CM_PANE_B_WIDTH_PT` | 375.0 (fixed) | MEASURED. (1325-575) px / 2. Fraction 0.27452 — below UI_SPEC's stated 28% floor |
| `CM_PANE_C_WIDTH_PT` | remainder (703.0 on a 1366 pt screen; 531.0 on the 1194 pt dev iPad) | MEASURED 703.0 on the reference; A + 0.5 + B + 0.5 + C = 1366.0 exactly |
| `CM_PANE_DIVIDER_WIDTH_PT` | 0.5 | MEASURED. Exactly 1 device px at @2x; neighbouring columns are pure white |
| `CM_PANE_DIVIDER_COLOR` | #8E8E93 (142,142,147) opaque | MEASURED. Per-channel std 0.00 over 1500 rows; identical over white and over #D9D9D9, so opaque |
| `CM_LIST_SEPARATOR_COLOR` | #C8C7CC (200,199,204) opaque | MEASURED. Exact single pixel value in BOTH pane A and pane B (600/600 and 360/360 pixels) |
| `CM_LIST_SEPARATOR_HEIGHT_PT` | 0.5 | MEASURED. 1 device px |
| `CM_DETAIL_RULE_COLOR` | #C8C8C8 (200,200,200) — deliberately NOT #C8C7CC | MEASURED. Pane C header rules at y=224/372/655 px |
| `CM_BAR_HAIRLINE` | #000000 at 30% alpha, 0.5 pt | MEASURED. Reads (178,178,178) over white -> alpha 0.302; (167,167,171) over #EFEFF4 -> 0.301 |
| `CM_STATUS_BAR_HEIGHT_PT` | 20.0 | INFERRED from measurement. Bar fill continuous 0..64 pt; the 17 pt title baseline at 48.0 pt only centres in a 44 pt bar starting at 20 pt |
| `CM_NAV_BAR_HEIGHT_PT` | 44.0 | MEASURED/INFERRED. Top chrome hairline at 64.0 pt minus the 20 pt status bar |
| `CM_TOP_CHROME_HEIGHT_PT` | 64.0 | MEASURED. Bar fill runs y 0..127 px; hairline at y=128 px |
| `CM_BOTTOM_TOOLBAR_HEIGHT_PT` | 44.0  (panes A and B only; pane C has NO bottom toolbar) | MEASURED. Top hairline at y=1959 px = 979.5 pt; no hairline or bar at x=2000/2600 |
| `CM_BAR_FILL_OPAQUE` | #F9F9F9 (249,249,249) | MEASURED over white content. The real bar is translucent (#F5F5F8/#F6F6F8 over the section gap); use #F9F9F9 for a frozen opaque clone |
| `CM_BOTTOM_BAR_FILL` | #F8F8F8 (pane A) / #F5F5F5-#F6F6F6 (pane B) | MEASURED. Difference is translucency over different content |
| `CM_MAILBOX_ROW_PITCH_PT` | 44.5  (build as a 44 pt row + 0.5 pt separator below) | MEASURED. 89 px on 15 of 17 gaps; mean 88.94 px over the 17-row section |
| `CM_MAILBOX_ROW_CONTENT_HEIGHT_PT` | 44.0 | DERIVED. 44.5 pitch minus the 0.5 pt separator; matches UITableView's classic default |
| `CM_MAILBOX_SEPARATOR_INSET_LEFT_PT` | 55.0 | MEASURED. First #C8C7CC pixel at x=110 px on every top-level row |
| `CM_MAILBOX_SUBFOLDER_SEPARATOR_INSET_LEFT_PT` | 86.0 | MEASURED. First #C8C7CC pixel at x=172 px on Important/Starred/BFFs/Bills and Finance/Shopping |
| `CM_MAILBOX_INDENT_STEP_PT` | 31.0 | DERIVED. 86.0 - 55.0; text left edges agree (87.0 vs 56.5 = 30.5) |
| `CM_MAILBOX_ICON_CENTER_X_PT` | 29.25 (top level), 65.0 (indented) | MEASURED. Inbox and Drafts icon ink both centre on 58.5 px; Important on 130 px |
| `CM_MAILBOX_ICON_TINT` | #007AFF | MEASURED. Counter over the Inbox icon region -> [((0,122,255), 314)] |
| `CM_SECTION_GAP_HEIGHT_PT` | 28.0  (first gap, directly under the nav bar: 27.5) | MEASURED. Grey bands y 129..183 px (27.5 pt) and y 362..417 px (28.0 pt), each >=90% exact #EFEFF4 |
| `CM_SECTION_GAP_FILL` | #EFEFF4 (239,239,244), bounded above and below by FULL-WIDTH (zero inset) 0.5 pt #C8C7CC rules | MEASURED. Bounding separators at y=184/361/418 all report cover=1.00, xfirst=0 |
| `CM_MESSAGE_ROW_HEIGHT_PT` | 104.0 | MEASURED. Separator pitch exactly 208 px at 423/631/839/1047/1255/1463/1671/1879, zero jitter. (Starter's 74 is wrong.) |
| `CM_MESSAGE_SEPARATOR_INSET_LEFT_PT` | 29.0 | MEASURED. First #C8C7CC pixel at pane-relative x=58 px on every message row |
| `CM_MESSAGE_TEXT_LEFT_PT` | 29.0 | MEASURED. Sender/subject/preview ink all start at pane-relative 28.5-29.0 pt, coinciding with the separator inset |
| `CM_ROW_TEXT_RIGHT_INSET_PT` | 16.0  (container edge 359 pt in pane B, 271 pt in pane A) | MEASURED. Right-aligned timestamp ink ends 358.0-358.5 pt on 5 rows; pane A unread count ends 271.0-271.5 |
| `CM_UNREAD_DOT_DIAMETER_PT` | 12.0 | MEASURED. Blue-mask bbox 24x24 px; 460 blue pixels -> area-equivalent diameter 12.10 pt |
| `CM_UNREAD_DOT_LEFT_INSET_PT` | 8.0 | MEASURED. Leftmost blue pixel x=591 px; pane B origin x=575 px |
| `CM_UNREAD_DOT_CENTER_X_PT` | 14.0 | DERIVED. 8.0 + 12.0/2; sits in the gutter left of the 29 pt text column |
| `CM_UNREAD_DOT_CENTER_Y_FROM_ROW_TOP_PT` | 22.0 | MEASURED. Dot y 248..271 px in a row starting at y=216 px; centres on the sender line's cap height |
| `CM_TINT_BLUE` | #007AFF (0,122,255) | MEASURED. Identical value for the unread dot, mailbox icons, Edit buttons, toolbar glyphs, Unsubscribe and Details links |
| `CM_SELECTION_COLOR` | #D9D9D9 (217,217,217), FULL-BLEED, text stays #000000, adjacent separators suppressed | MEASURED. Dominant colour of the selected 'Junk' (pane A) and 'Gilt City NYC' (pane B) rows; the #C8C7CC detector finds no separator at their boundaries |
| `CM_SENDER_BASELINE_FROM_ROW_TOP_PT` | 27.5 | MEASURED. Flat-bottom 'T' of TUMI ends y=1726 px in a row starting y=1672 px |
| `CM_SUBJECT_BASELINE_FROM_ROW_TOP_PT` | 48.0 | MEASURED. Flat-bottom 'A' of Alpha ends y=1767 px |
| `CM_PREVIEW_LINE1_BASELINE_FROM_ROW_TOP_PT` | 67.5 | MEASURED. Flat-bottom 'A' of Additional ends y=1806 px |
| `CM_PREVIEW_LINE2_BASELINE_FROM_ROW_TOP_PT` | 87.5  (leaves 16.5 pt below) | MEASURED. Flat-bottom 'T' of 'To view' ends y=1846 px |
| `CM_FONT_NAV_TITLE` | 17 pt semibold, #000000, centred in its pane, baseline y=48.0 pt | MEASURED. 'M' of Mailboxes cap 24 px; stems 4 px vs regular's 3 px; ink centre 143.75 vs pane centre 143.5 |
| `CM_FONT_BAR_BUTTON` | 17 pt regular, #007AFF | MEASURED. 'E' of Edit cap 24 px in both panes |
| `CM_FONT_MAILBOX_NAME` | 17 pt regular, #000000 | MEASURED. 'I' of Inbox cap 24 px, 'n' x-height 18 px, stems 3 px |
| `CM_FONT_MAILBOX_COUNT` | 17 pt regular, #808080 (128,128,128), right-aligned | MEASURED. '6' digit height 24 px; Counter over the ink -> (128,128,128) |
| `CM_FONT_LIST_SENDER` | 17 pt SEMIBOLD, #000000 — FOR READ AND UNREAD ALIKE (contradicts UI_SPEC.md:20) | MEASURED. Flat caps 24 px on Misfit/TUMI/Gilt City NYC; identical 5 px stems; ink density 0.38 (read) vs 0.41 (unread) vs 0.27 (regular) |
| `CM_FONT_LIST_SUBJECT` | 15 pt regular, #000000 | MEASURED. Flat caps 21 px (A/N/E/W/U/T), x-height 16 px -> 14.87/15.11 pt |
| `CM_FONT_LIST_PREVIEW` | 15 pt regular, #8E8E8E (142,142,142), 2 lines | MEASURED. 'A' of Additional cap 21 px; Counter over the ink -> (142,142,142) |
| `CM_FONT_LIST_TIMESTAMP` | 15 pt regular, #8E8E8E, right-aligned ON THE SENDER BASELINE | MEASURED. '1' and 'A' of AM both 21 px cap; ink bottom 271 px == sender baseline |
| `CM_FONT_DETAIL_SENDER` | 17 pt semibold, #000000, baseline y=144.5 pt | MEASURED. 'N' of NYC cap 24 px; ink bottom 288 px |
| `CM_FONT_DETAIL_META` | 15 pt — To: line, Details link, date line; baselines 166.5 / 166.5 / 292.5 pt | MEASURED. 'M' of McGarry 21 px, 'D' of Details 21 px (right ink 1300.0 pt), '1' of 10:02 21 px |
| `CM_FONT_DETAIL_SUBJECT` | 22 pt bold, #000000, baselines 242.5 and 270.5 pt | MEASURED. Flat caps A/E/T all 31 px -> 21.99 pt. Round caps O/S/C measure 33 px from overshoot — do not use those |
| `CM_DETAIL_SUBJECT_LINE_PITCH_PT` | 28.0  (needs EXPLICIT leading; UIFont's default for 22 pt SF is ~26.2 pt) | MEASURED. Baseline delta 541-485 = 56 px |
| `CM_FONT_STATUS_BAR` | 12 pt semibold | MEASURED. Status bar digits 17 px cap -> 12.06 pt |
| `CM_FONT_TOOLBAR_STATUS` | 11 pt (+/-1) — 'Updated Just Now' #000000, 'n Unread' #8E8E93 | MEASURED. Flat 'N' cap 16 px and flat 'w' x-height 12 px both give 11.3 pt |
| `CM_SEARCH_BAR_HEIGHT_PT` | 43.0 | MEASURED. Container y 129..214 px = 86 px |
| `CM_SEARCH_BAR_FILL` | #C9C9CE (201,201,206) | MEASURED. Exact value above and below the white field, full pane width |
| `CM_SEARCH_FIELD_HEIGHT_PT` | 28.0, white, vertically centred in the container | MEASURED. White region y 144..199 px; both centres at y=171.5 px |
| `CM_SEARCH_FIELD_SIDE_INSET_PT` | 8.0  (field 359 pt wide in a 375 pt pane) | MEASURED. White field spans pane-relative 8.0..367.0 pt |
| `CM_MESSAGE_LIST_TOP_PT` | 108.0 | MEASURED. First list pixel row after the search bar's bottom hairline at y=215 px |
| `CM_DETAIL_CONTENT_INSET_LEFT_PT` | 20.0  (header rules start at exactly 21.0 pt) | MEASURED/INFERRED. Header text ink starts at 20.5-21.0 pt pane-relative |
| `CM_DETAIL_HEADER_RULE_Y_PT` | 186.0 and 327.5  (0.5 pt #C8C8C8, inset 21 pt left, flush right) | MEASURED |
| `CM_DETAIL_BANNER_HEIGHT_PT` | 47.5 + 0.5 pt rule = 48.0  (mailing-list/unsubscribe banner) | MEASURED. y 129..224 px including the bottom rule |
| `CM_DETAIL_BANNER_FILL` | #F3F3F8 (243,243,248) | MEASURED. Exact value across the banner |
| `CM_DETAIL_BANNER_FONT` | 13 pt semibold title; 13 pt regular #007AFF 'Unsubscribe' (+/-0.5 pt) | MEASURED. 'T' of This and 'U' of Unsubscribe both cap 18 px -> 12.77 pt |
| `CM_DETAIL_AVATAR_DIAMETER_PT` | 36.0 — MEASURED BUT MUST NOT BE DRAWN | MEASURED (bbox 72x72 px, right edge 1356 pt, centre y 148.5 pt). UI_SPEC.md:26 and PRODUCT_SPEC.md:80 ban sender avatars; the ban wins over the reference |
| `CM_TOOLBAR_ACTION_ORDER` | [prev, next] … [Flag, Move, Delete, Reply, Compose] — all #007AFF, chevrons leading, action group trailing | MEASURED from the reference; CONFIRMS UI_SPEC.md:39-45, so it can be frozen |
| `CM_TOOLBAR_ICON_CENTERS_PT` | prev 712, next 751 \| flag 1123, move 1174, delete 1230, reply 1280, compose 1334 (absolute on a 1366 pt screen, vertically centred at y~41) | MEASURED. Blue-cluster ink-bbox centres |
| `CM_TOOLBAR_ICON_PITCH_PT` | ~52.8 (measured 51.3 / 55.0 / 51.0 / 54.0; variance is glyph asymmetry, not layout) | MEASURED, with the caveat that actual button frames are NOT recoverable from pixels |
| `CM_TOOLBAR_RIGHT_INSET_PT` | 20.0 | MEASURED. Compose glyph right ink edge at 1346 pt on a 1366 pt screen |
| `CM_MIN_HIT_TARGET_PT` | 44.0 x 44.0 — from the accessibility requirement, NOT from the reference | UI_SPEC.md:70, PRODUCT_SPEC.md:95, BRIEF.md:60. All measured toolbar numbers are glyph ink boxes only |
| `CM_SECONDARY_TEXT_COLOR` | #8E8E8E (142,142,142) | MEASURED. Preview and timestamp ink. THREE distinct greys are in play: #8E8E8E (secondary text), #808080 (mailbox counts), #8E8E93 (pane divider and 'n Unread') |
| `CM_EDIT_BUTTON_INSET_PT` | 16.0 in BOTH panes (deliberate deviation) | MEASURED 8.5 pt in pane A vs 16.5 pt in pane B; cause undetermined from one screenshot, and copying it faithfully would read as a defect |
| `CM_SCALING_RULE` | ONLY pane widths may vary by screen. Row heights (44.5/104), font sizes (17/15/22/13/12/11), insets (29/55/86/16/20) and the 12 pt dot are ABSOLUTE POINTS on every iPad. | INFERRED from iOS layout semantics. Scaling type by screen width would wreck the legibility this product exists for |
| `CM_REFERENCE_IMAGE` | https://images.techhive.com/images/article/2016/07/ios-10-ipad-mail-100669665-orig.png (2732x2048, sha256 1fa636e3197cbefdebaf34551916d07891d4a7453f6e65110d8a152080e15c5f) | The -orig.png suffix is undocumented; the URL in REFERENCE_SCREENSHOTS.md returns only 580x435. Macworld/IDG copyright — measurements are safe to hard-code, the IMAGE must never ship |

---

# Addendum — the measured pass (2026-09-19)

Everything above this line was derived from the 12.9-inch techhive screenshot
of a **different iPad**. Five independent measurement passes then worked from
the owner's own reference, and the numbers below supersede it where they
disagree. The screen rect and scale that all of them depend on are in
`spec/references/OWNER_SCREENSHOT_GEOMETRY.md` — read that first, because the
reference is a photo of a whole iPad and the screen is a sub-rectangle.

## Settled — three or more methods converging

| constant | value | evidence |
|---|---|---|
| `messageRowHeight` | **96** | 95.67 / 96.09 / 95.80 by parabola-fit separators, a six-row least-squares baseline fit, and timestamp centroids. The strongest number in the exercise. |
| `leftColumnFraction` | **31%** | divider centroid 321 pt; holds under both candidate screen origins |
| baselines | **24 / 44 / 64 / 84** | sender read 23.8 / 25.4 / 22.9; internal pitch 19.8-20.1 on all three |
| `detailContentInsetLeft` | **26** | five separate elements share one ink column, read 26.0 / 26.2 / 24-26 |
| `searchFieldHeight` | **28** | 28.2 / 28.2 / 27.8 |
| detail header stack | 24.5 / 44.8 / 64.5 / 88 / 109.5 / 129.8 | three passes inside 1.5 pt — the best-behaved block in the reference |

## Deliberately NOT changed, and why

- **`messageTextLeft` / `messageSeparatorInset`, both 29.** The screen's left
  edge is unresolvable to better than 1.5 px (67.14 forcing exact 4:3, 68.6
  pinning on the nav/search insets), so every "distance from the pane's left
  edge" carries ±3.5 pt. The separator itself read 22.6 / 26.1 / 29.9 — a 7 pt
  spread. There is no number in there to move to.
- **The detail sender avatar.** Present in the reference, banned by the brief.
  A reference having something does not overturn a product rule.
- **`rowTextRightInset` 13.** One pass suggested it; the other two read 15.0
  and 14.6. Went to 15.

## Device facts that cost layout, and cannot be recovered

The reference iPad spends **64 pt** on top chrome (20 status + 44 nav). An
11-inch iPad spends **74** — a 24 pt safe-area status bar and UIKit's 50 pt
regular-width nav bar — and adds a **~21 pt home indicator**. About 25 pt of
list budget, a quarter of a row, is gone before the app draws anything.
`navBarHeight` and `bottomToolbarHeight` used to sit in `Theme` asserting 44;
they controlled nothing and nothing read them, so they are gone. See B-005.

## What this image CANNOT settle

At 0.4326 px/pt one pixel is 2.31 pt. **Type sizes, hairline widths and text
greys are not recoverable** — a 15 pt stem is under half a pixel and the
darkest text bottoms out around 81/255, so greys carry ±40 levels. No type or
colour fault should ever be quoted from this reference.
