#!/usr/bin/env python3
# =============================================================================
# scripts/composite_quiz_logo.py — build the logo-tolerance pairs.
# =============================================================================
# The `logo_tolerance` axis asks one question: does visible branding on a
# garment put you off, or not care, or appeal? Every other axis in the quiz is
# generated as two photographs. This one is not, and the reason is worth
# stating because it makes this the most rigorous pair in the set.
#
# THE BRANDED FRAME IS THE PLAIN FRAME WITH A MARK ADDED. Same photograph, same
# man, same fold of cloth, same shadow, same pixel everywhere the mark is not.
# Generating a second frame — even from the same reference figure — would let
# the drape shift, the fabric catch the light differently, the fit read a shade
# looser. All of that is signal the man might answer, and none of it is
# branding. Compositing removes the possibility rather than measuring it.
#
# WHY THE MARK IS ASTRA'S OWN, AND NOT A REAL BRAND'S.
#
# The first attempt asked the generator for a wordmark and it returned
# HILFIGER — a real trademark, which is unshippable in a commercial app, and
# the file was deleted. Replacing it with an abstract geometric emblem fixed
# the legal problem and failed a more basic one: it looked like nothing any
# brand has ever made, which is to say it looked generated.
#
# But the decisive objection to a real brand is not legal at all, it is
# measurement. Put a real mark on the garment and the man stops answering "do I
# mind visible branding" and starts answering "do I like that company". Those
# come apart constantly — someone happy to wear a large Carhartt logo may find
# another house naff — so the quiz would record low logo tolerance for a man
# whose logo tolerance is high. That is the same class of error as a pair whose
# two frames differ in sleeve length: a second variable riding along, recorded
# as if it were the first, undetectable downstream.
#
# Astra's own monogram has neither problem. It is not a third party's mark, and
# it carries no prior brand opinion for the man answering — it is simply "a
# logo", which is exactly and only what this axis is about. It is also the one
# mark we can render identically on every garment, forever.
#
# ---------------------------------------------------------------------------
#     python3 scripts/composite_quiz_logo.py
#
# Reads `brand/quiz-imagery/logo-{n}-a.png` and `_astra-mark.png`, writes
# `logo-{n}-b.png`. Idempotent — it always composites onto the plain `-a`
# frame, never onto its own output, so re-running cannot stack marks.
#
# The mark is placed with a little blur and slightly under full opacity. A
# razor-sharp, fully opaque overlay reads as a sticker floating in front of the
# man; real chest branding is printed or embroidered INTO cloth and picks up
# some of its softness. This is the cheapest approximation that survives the
# downscale to a 720px tile, which is the only size anyone ever sees.
# =============================================================================

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Needs pillow: pip install pillow")

SOURCE = Path("brand/quiz-imagery")
MARK = SOURCE / "_astra-mark.png"

# Chest placement, MEASURED off the plain frames with a coordinate grid rather
# than guessed. The first attempt was guessed and was wrong twice over — the
# mark came out roughly twice the width of a real chest logo, and it sat at
# y 0.175-0.275, which on this framing is the stomach, not the chest.
#
# On these frames, shoulders-to-shoes:
#     y 0.05        collar / shoulder line
#     y 0.11-0.16   pec level — where a chest logo actually goes
#     y 0.22-0.32   midriff — where the first attempt put it
#     y 0.38        hem of a crew-neck sweatshirt
#
# `x` is the mark's centre. 0.605 is the wearer's LEFT chest, which is the
# viewer's right in a front-facing photograph and the standard placement for
# embroidered and printed chest branding. Centre-chest exists but reads as a
# graphic print rather than a logo, and this axis is about logos.
#
# `width` is the mark's width as a fraction of image width, and it took four
# passes to land. The arithmetic: the torso spans about 0.40 of image width
# here, so a mark of width w covers w/0.40 of the chest.
#
#     0.155  ->  39% of chest width   a graphic print across the midriff
#     0.080  ->  20%                  roughly twice a real logo
#     0.048  ->  12%                  a printed chest logo, on the large side
#     0.034  ->   8.5%                an embroidered left-chest mark
#
# The 10-12% figure the previous pass reasoned from was drawn from PRINTED
# chest graphics. Embroidered left-chest branding — which is what a monogram on
# a knit or a quarter-zip actually is — runs smaller, roughly 3.5-4.5cm against
# a 50cm front-of-chest, i.e. 7-9%. 0.034 sits inside that.
#
# The competing constraint is legibility: each option gets about 175pt on the
# quiz card, two side by side on a 402pt phone, and a mark nobody can see
# measures nothing. At 0.034 the monogram is 24px on the shipped 720px tile and
# still resolves as a mark rather than a smudge, because it is a single high-
# contrast glyph on flat cloth rather than fine lettering. That is what makes
# going this small affordable here and would not hold for a wordmark.
PLACEMENTS = {
    "logo-1": {"y": 0.118, "width": 0.034, "x": 0.600},   # crew-neck sweatshirt
    "logo-2": {"y": 0.111, "width": 0.033, "x": 0.600},   # quarter-zip, higher neckline
}

OPACITY = 0.90
BLUR = 0.5


def composite(stem: str, placement: dict) -> bool:
    plain = SOURCE / f"{stem}-a.png"
    if not plain.exists():
        print(f"  {stem}: {plain.name} missing", file=sys.stderr)
        return False
    if not MARK.exists():
        print(f"  {MARK} missing — extract it from design/mono.png", file=sys.stderr)
        return False

    base = Image.open(plain).convert("RGBA")
    mark = Image.open(MARK).convert("RGBA")
    width, height = base.size

    w = int(width * placement["width"])
    h = int(mark.height * w / mark.width)
    scaled = mark.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(BLUR))
    scaled.putalpha(scaled.split()[3].point(lambda v: int(v * OPACITY)))

    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(
        scaled,
        (int(width * placement["x"] - w / 2), int(height * placement["y"])),
        scaled,
    )

    destination = SOURCE / f"{stem}-b.png"
    Image.alpha_composite(base, layer).convert("RGB").save(destination, "PNG")
    print(f"  {destination.name}  ({w}x{h} mark on {width}x{height})")
    return True


def main() -> int:
    print(f"Compositing the Astra mark onto {len(PLACEMENTS)} plain frame(s):")
    ok = all([composite(stem, p) for stem, p in sorted(PLACEMENTS.items())])
    if ok:
        print("\nDone. Run scripts/build_quiz_imagery.py to produce the shipped tiles.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
