# The owner's reference screenshot — screen rectangle and scale

`owner-ipad.jpeg` (sha256 `8e13dbd7…`; kept locally and never committed,
because it is Apple's marketing image) is the layout this product is copying. Everything measured from it must start
here.

## It is not a screenshot. It is a picture of an iPad.

580 × 425 JPEG of a whole silver iPad in landscape, bezels and all, on a white
page. **The screen is a sub-rectangle.** Measuring against the image bounds
inflates every number by 31% and silently corrupts the whole exercise, so this
file exists to stop anyone re-deriving it.

    screen border   x 67 .. 510,  y 44 .. 377
    screen size     443 × 333 px   =   1024 × 768 pt
    scale           0.4326 px/pt   (1 px = 2.31 pt)

Converting a pixel coordinate to a point coordinate on the screen:

    x_pt = (x_px - 67) / 0.4326
    y_pt = (y_px - 44) / 0.4326

## Why this rectangle is trustworthy

Not because it looks right — because **width and height agree**. 443/1024 =
0.43262 px/pt and 333/768 = 0.43359 px/pt, a disagreement of 0.23%. Two
independent derivations of the same constant landing on top of each other is
the test; a wrong rectangle fails it loudly.

Three approaches that FAILED, all of which found the **device body** rather
than the screen, and all of which announced themselves by breaking that test
(0.526 vs 0.495 px/pt — 6% apart, and an aspect of 1.42 against 4:3's 1.3333):

- column/row **variance** — the bezel is white on a white page, so the only
  strong edge is the silver device outline
- **non-white ink** counting — same trap, the outline is ink
- thresholding for the **screen's dark border** across the full image — the
  outline is darker than the border in places

What worked: magnify a corner 12× and *look* at it, then scan for the darkest
column/row in a ±8 px window around what the eye found, averaging along the
edge so app content cannot drag the mean.

## The precision ceiling — read this before quoting a number

At 0.4326 px/pt **one pixel is 2.31 pt**. Therefore, from this image:

- **Recoverable:** pane widths, row pitch, bar heights, margins — anything
  large, and anything that repeats. Measure a repeating distance across many
  rows and divide; that averages the error down to well under a point.
- **NOT recoverable:** type sizes, hairlines, and baselines to the half point.
  A 17 pt font has a cap-height of about 5 px here.

So constants such as `senderBaseline 27.5` cannot have come from this image and
must not be "confirmed" against it. They came from the 12.9-inch techhive
reference, which is a different device at a different size — see
`REFERENCE_SCREENSHOTS.md`. Where the two disagree, **this one wins**: it is
the iPad he actually used, and the layout his hands know.
