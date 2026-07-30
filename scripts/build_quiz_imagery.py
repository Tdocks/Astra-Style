#!/usr/bin/env python3
# =============================================================================
# scripts/build_quiz_imagery.py — turn generated frames into shippable quiz tiles.
# =============================================================================
# The §6.9 preference quiz asks a man to choose between two photographs. Every
# difference between those two photographs that is NOT the axis under test is a
# reason he might pick one, and the quiz will record it as a style preference.
# That answer is then wrong in a form nothing downstream can detect: a Style DNA
# that looks valid and isn't. So the processing here is not cosmetic — each step
# removes a specific way the pair could lie.
#
# Run it on a whole pair, never on one frame:
#
#     python3 scripts/build_quiz_imagery.py \
#         --source brand/quiz-imagery \
#         --out ios/AstraStyle/Resources/QuizImagery \
#         --pair texture-1 --pair logo-1
#
# WHAT IT DOES, AND WHY EACH STEP EXISTS
#
# 1. BACKDROP NORMALISATION. Higgsfield Soul 2.0 varies its backdrop tone
#    between generations — measured across ten raw pairs on 2026-07-30, the mean
#    difference within a pair was 20.9 luma and the worst was 33.7, on a 0-255
#    scale. Side by side that is visible, and the brighter frame is the more
#    appealing photograph regardless of what it shows.
#
#    brand/quiz-imagery/README.md offers two fixes: pin the seed, or normalise
#    in post. THE FIRST IS NOT AVAILABLE — the API rejects a seed with
#    "Higgsfield Soul 2.0 does not support this parameter" — so this is the only
#    route, which is why it lives in a script rather than in a person's judgement.
#
#    The target is the MEAN of the pair, not a fixed constant. Neither frame is
#    more correct than the other; they only have to match each other, and pulling
#    both halfway keeps each closer to what the model actually produced. The gain
#    is a single scalar applied to all three channels, so hue relationships
#    inside the garments are preserved — the alternative, per-channel white
#    balancing, would quietly edit the clothes, and on a quiz with a COLOUR axis
#    that would be self-defeating.
#
#    Luma is sampled from four corner patches, which are backdrop in every frame
#    the mandated skeleton produces (centred model, full body, seamless sweep).
#
# 2. TOP 7% CROP. The generator leaves the chin and neck in frame despite the
#    prompt saying no face visible. The crop is therefore load-bearing rather
#    than aesthetic, and it belongs here rather than in a per-image judgement
#    call — a frame that ships uncropped shows a face the quiz promised not to.
#
# 3. RESIZE TO 720px WIDE. Tile width on the quiz card, doubled for retina.
#
# Sources stay full-resolution in brand/quiz-imagery/ so a pair can be
# reprocessed without regenerating it.
#
# WHAT THIS SCRIPT CANNOT FIX, and you must check by eye before accepting a pair:
#   • The man changes between A and B. Skin tone drift between the two frames of
#     a pair sank three of ten candidates in the 2026-07-30 batch. No amount of
#     post-processing repairs it; it needs reference-conditioned generation.
#   • Hands. Check at FULL resolution, per brand/quiz-imagery/README.md.
#   • A second variable riding along with the axis — trouser width, tone,
#     framing. See that README's rejects for what this looks like.
# =============================================================================

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("Needs pillow and numpy: pip install pillow numpy")

CORNER = 120       # px square sampled at each corner to estimate backdrop
CROP_TOP = 0.07    # matches the documented crop; see step 2 above
OUT_WIDTH = 720
JPEG_QUALITY = 90


def backdrop_luma(image: Image.Image) -> float:
    """Mean luma of the four corner patches, which are backdrop in every frame
    the mandated prompt skeleton produces."""
    a = np.asarray(image.convert("RGB"), dtype=float)
    h, w, _ = a.shape
    s = CORNER
    corners = [a[:s, :s], a[:s, w - s:], a[h - s:, :s], a[h - s:, w - s:]]
    return float(np.mean([c.mean() for c in corners]))


def process_pair(pair: str, source: Path, out: Path, dry_run: bool) -> bool:
    paths = {side: source / f"{pair}-{side}.jpg" for side in ("a", "b")}
    for side, path in paths.items():
        if not path.exists():
            print(f"  {pair}: missing {path.name} — a pair is both frames or neither", file=sys.stderr)
            return False

    images = {side: Image.open(path).convert("RGB") for side, path in paths.items()}
    luma = {side: backdrop_luma(im) for side, im in images.items()}
    target = sum(luma.values()) / 2
    print(f"  {pair}: backdrop A={luma['a']:.1f} B={luma['b']:.1f} "
          f"(delta {abs(luma['a'] - luma['b']):.1f}) -> {target:.1f}")

    for side, im in images.items():
        a = np.asarray(im, dtype=float) * (target / luma[side])
        result = Image.fromarray(np.clip(a, 0, 255).astype("uint8"))
        w, h = result.size
        result = result.crop((0, int(h * CROP_TOP), w, h))
        result = result.resize(
            (OUT_WIDTH, round(result.height * OUT_WIDTH / result.width)), Image.LANCZOS
        )
        destination = out / f"quiz-{pair}-{side}.jpg"
        if dry_run:
            print(f"    would write {destination}")
        else:
            result.save(destination, quality=JPEG_QUALITY, optimize=True)
            print(f"    wrote {destination.name} ({destination.stat().st_size // 1024} KB)")

    if not dry_run:
        after = {s: backdrop_luma(Image.open(out / f"quiz-{pair}-{s}.jpg")) for s in "ab"}
        delta = abs(after["a"] - after["b"])
        print(f"    residual backdrop delta {delta:.1f}")
        if delta > 3.0:
            print(f"    WARNING: {pair} still differs by {delta:.1f} after normalising. "
                  "Something other than exposure differs between these frames — look at them.",
                  file=sys.stderr)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", type=Path, default=Path("brand/quiz-imagery"))
    ap.add_argument("--out", type=Path, default=Path("ios/AstraStyle/Resources/QuizImagery"))
    ap.add_argument("--pair", action="append", dest="pairs", required=True,
                    help="Pair stem without the -a/-b suffix, e.g. texture-1. Repeatable.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.source.is_dir():
        return print(f"No such source directory: {args.source}", file=sys.stderr) or 1
    if not args.out.is_dir():
        return print(f"No such output directory: {args.out}", file=sys.stderr) or 1

    print(f"Processing {len(args.pairs)} pair(s) from {args.source}")
    ok = all([process_pair(p, args.source, args.out, args.dry_run) for p in args.pairs])
    if not ok:
        print("\nOne or more pairs failed.", file=sys.stderr)
        return 1
    print("\nDone. Check hands at full resolution in the SOURCE files before accepting, "
          "and confirm the same man appears on both sides — neither is checkable here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
