#!/usr/bin/env python3
"""Build the iOS app icon: brand marble, full bleed, with the traced monogram.

WHY THIS SCRIPT EXISTS
----------------------
The first `AppIcon.png` was derived by hand from `brand/assets/app-icon-marble.jpg`
and shipped a **marketing mockup** rather than icon artwork: an already-rounded,
already-shadowed marble tile floating on the mockup's off-white page, letterboxed
to a square canvas with black bars. Measured on that file: 64px of black top and
bottom, the tile filling only 70% x 69% of the canvas, and 128-177px of off-white
page on every edge.

iOS masks an app icon to a squircle and composites whatever it is handed, so on
the owner's home screen that page background read as a white border and the icon
visibly failed to fill its tile.

A second re-export by hand would fix today's icon and leave the next one exactly
as exposed, so the fix is this script instead. It also fixes a defect the border
was hiding: in the mockup the mark is *embossed* — its gold is a rim light, not a
fill — which looks handsome at 1024px and disappears entirely below about 120px.
The mark is therefore re-rendered from `AstraMonogram.swift`'s traced geometry and
filled solid champagne, which is what the splash screen already shows on marble.

That geometry is the single source of truth for the mark's shape. Reading it here
rather than re-tracing means the icon cannot drift from the in-app monogram — the
same reason `check_contrast.py` parses `AstraColor.swift` instead of keeping its
own table of hex values.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
It does not round the corners, add a shadow, or inset the artwork. All three are
the system's job, and doing any of them here double-applies them: art with a 187px
corner radius under a 229px squircle mask leaves four light wedges, which is what
a naive "just crop the tile" fix produces.

It does not re-position or re-scale the mark either. The vector is mapped onto the
bounding box of the artwork's own embossed mark, so the mark keeps the size and
the ~2%-left-of-centre placement the designer gave it.

USAGE
-----
    python3 scripts/build_app_icon.py            # write the icon
    python3 scripts/build_app_icon.py --check    # verify the shipped icon, exit 1 on drift

Requires `pillow` and `numpy` (same dependency as the quiz-imagery pipeline).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover - dependency guidance, not logic
    sys.exit("build_app_icon.py needs pillow and numpy: pip3 install pillow numpy")

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "brand" / "assets" / "app-icon-marble.jpg"
MONOGRAM_SWIFT = (
    REPO_ROOT / "ios" / "AstraStyle" / "Core" / "DesignSystem" / "Components" / "AstraMonogram.swift"
)
DESTINATION = (
    REPO_ROOT
    / "ios"
    / "AstraStyle"
    / "Resources"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon.png"
)

SIDE = 1024
CONTOUR_NAMES = ("letterform", "rightLegLower", "star")

# Dark-mode champagne. The marble is black stone in both schemes and the splash
# renders the mark under `.astraOnMarble()`, so this is the value the user
# already sees on this background — not light mode's #B8914E.
CHAMPAGNE = (0xD7, 0xB4, 0x6A)

# Luminance below which a pixel is marble rather than the mockup's page. The
# page is ~248, the marble centre ~23, and the drop shadow between them never
# falls below ~150. 90 sits in open space, not on a cliff edge.
MARBLE_LUMA_MAX = 90


def gold_mask(pixels: np.ndarray) -> np.ndarray:
    """Pixels belonging to the artwork's champagne rim light."""
    red, green, blue = pixels[..., 0], pixels[..., 1], pixels[..., 2]
    return (red > 110) & (green > 85) & (blue < 130) & ((red - blue) > 35)


def bounds(mask: np.ndarray, what: str) -> tuple[int, int, int, int]:
    if not mask.any():
        sys.exit(f"No {what} found in {SOURCE} — is this still the master artwork?")
    rows, columns = np.nonzero(mask)
    return int(columns.min()), int(rows.min()), int(columns.max()), int(rows.max())


def fill_page_bleed(tile: np.ndarray) -> np.ndarray:
    """Replace the mockup's page background with marble.

    The tile's corners are rounded in the artwork, so a rectangular crop of it
    carries four wedges of off-white page — the "white border" itself. Marble is
    a near-uniform dark field at the corners and no vein crosses one, so the fill
    only has to be *continuous*, not clever: seed the masked pixels with the
    marble's own mean, then widen it inward three times, compositing each blur
    back only inside the mask. An inpainting library would be a dependency bought
    for four dark corners.
    """
    luminance = tile.mean(axis=2)
    page = luminance >= MARBLE_LUMA_MAX
    if not page.any():
        return tile

    filled = tile.copy()
    filled[page] = tile[~page].mean(axis=0)

    image = Image.fromarray(filled.astype(np.uint8))
    mask = Image.fromarray((page * 255).astype(np.uint8))
    for radius in (12, 32, 64):
        blurred = image.filter(ImageFilter.GaussianBlur(radius))
        image = Image.composite(blurred, image, mask)
    return np.asarray(image).astype(int)


def monogram_contours() -> list[list[tuple[float, float]]]:
    """Read the traced monogram out of `AstraMonogram.swift` as polylines.

    The Swift side stores each contour as a flat `[CGFloat]` on a 0-100 grid:
    two leading values for the start point, then six per cubic segment. That
    layout is not decorative — the file records that an array of enum cases
    carrying CGPoints made the Swift type checker give up — so parsing it is
    parsing a stable, documented shape rather than scraping incidental syntax.
    """
    source = MONOGRAM_SWIFT.read_text()
    contours: list[list[tuple[float, float]]] = []
    for name in CONTOUR_NAMES:
        match = re.search(rf"static let {name}: \[CGFloat\] = \[(.*?)\]", source, re.S)
        if match is None:
            sys.exit(f"Could not find contour '{name}' in {MONOGRAM_SWIFT.name}")
        values = [float(v) for v in match.group(1).replace("\n", " ").split(",") if v.strip()]
        if len(values) < 8 or (len(values) - 2) % 6 != 0:
            sys.exit(f"Contour '{name}' is malformed: expected 2 + 6n values, got {len(values)}")
        contours.append(flatten_cubics(values))
    return contours


def flatten_cubics(values: list[float], steps: int = 120) -> list[tuple[float, float]]:
    """Sample a flat cubic-Bezier contour into a polyline.

    120 samples per segment is far past the point of visible difference at 4x
    supersampled 1024px — the shortest segment in the mark spans under a pixel —
    and the whole mark is ~100 segments, so precision is free here.
    """
    points = [(values[0], values[1])]
    start_x, start_y = values[0], values[1]
    for index in range(2, len(values), 6):
        c1x, c1y, c2x, c2y, end_x, end_y = values[index : index + 6]
        for step in range(1, steps + 1):
            t = step / steps
            u = 1 - t
            points.append(
                (
                    u * u * u * start_x + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * end_x,
                    u * u * u * start_y + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * end_y,
                )
            )
        start_x, start_y = end_x, end_y
    return points


def monogram_mask(target: tuple[int, int, int, int]) -> Image.Image:
    """Render the mark, mapped onto the artwork's own mark bounding box.

    Drawn at 4x and downsampled rather than drawn at 1x: the swoosh tapers to a
    point finer than one pixel, and an aliased taper is the difference between a
    mark that looks engraved and one that looks like a screenshot.

    The dilation afterwards is not cosmetic. The vector is the mark's silhouette,
    while the artwork's version is embossed — its shadow sits a few pixels
    *outside* that silhouette. Without the widening, that shadow survives as a
    dark halo down the left leg. `MaxFilter(9)` covers it; the light blur that
    follows puts back the soft edge the max filter squares off.
    """
    contours = monogram_contours()
    every_point = [point for contour in contours for point in contour]
    source_x0 = min(x for x, _ in every_point)
    source_x1 = max(x for x, _ in every_point)
    source_y0 = min(y for _, y in every_point)
    source_y1 = max(y for _, y in every_point)

    left, top, right, bottom = target
    scale_x = (right - left) / (source_x1 - source_x0)
    scale_y = (bottom - top) / (source_y1 - source_y0)

    supersample = 4
    mask = Image.new("L", (SIDE * supersample, SIDE * supersample), 0)
    draw = ImageDraw.Draw(mask)
    for contour in contours:
        draw.polygon(
            [
                (((x - source_x0) * scale_x + left) * supersample, ((y - source_y0) * scale_y + top) * supersample)
                for x, y in contour
            ],
            fill=255,
        )
    mask = mask.resize((SIDE, SIDE), Image.LANCZOS)
    mask = mask.filter(ImageFilter.MaxFilter(9))
    return mask.filter(ImageFilter.GaussianBlur(1.2))


def build_icon() -> Image.Image:
    if not SOURCE.exists():
        sys.exit(f"Master artwork missing: {SOURCE}")

    pixels = np.asarray(Image.open(SOURCE).convert("RGB")).astype(int)
    left, top, right, bottom = bounds(pixels.mean(axis=2) < MARBLE_LUMA_MAX, "marble")
    tile = fill_page_bleed(pixels[top : bottom + 1, left : right + 1])

    # The master tile is 733x725 — the mockup's own perspective, not a mistake
    # to correct. Resampling to a square stretches it by 1.1%, below the point
    # at which anything in the mark is measurably distorted.
    background = Image.fromarray(tile.astype(np.uint8)).resize((SIDE, SIDE), Image.LANCZOS)

    mark_box = bounds(gold_mask(np.asarray(background).astype(int)), "monogram")
    icon = Image.composite(Image.new("RGB", (SIDE, SIDE), CHAMPAGNE), background, monogram_mask(mark_box))

    # RGB, never RGBA: App Store review rejects an icon with an alpha channel,
    # and iOS composites transparent pixels over white — which is the border
    # this whole script exists to remove.
    return icon.convert("RGB")


def report(icon: Image.Image) -> None:
    """Print the measurements that would have caught the original defect."""
    pixels = np.asarray(icon).astype(int)
    corners = [pixels[0, 0], pixels[0, -1], pixels[-1, 0], pixels[-1, -1]]
    brightest = max(int(corner.mean()) for corner in corners)
    mark = gold_mask(pixels)
    left, top, right, bottom = bounds(mark, "monogram")

    print(f"  canvas          {icon.size[0]}x{icon.size[1]}, mode {icon.mode}")
    print(f"  brightest corner luminance {brightest} (page bleed would read ~248)")
    print(
        f"  mark            {right - left + 1}x{bottom - top + 1}px "
        f"({(right - left + 1) / SIDE:.0%} x {(bottom - top + 1) / SIDE:.0%} of canvas), "
        f"{mark.sum() / mark.size:.1%} coverage"
    )

    if brightest > MARBLE_LUMA_MAX:
        sys.exit(
            f"  A corner is brighter than marble ({brightest}) — the page background "
            "survived the fill. Do not ship this."
        )
    # An embossed mark covers ~4% of the canvas in rim light alone; a filled one
    # covers ~13%. This is the assertion that would have caught an icon whose
    # mark vanishes below 120px.
    if mark.sum() / mark.size < 0.08:
        sys.exit("  The mark covers too little of the canvas to read at 60px — is it filled?")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build or verify the iOS app icon.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the shipped icon rather than rewriting it",
    )
    arguments = parser.parse_args()

    if arguments.check:
        if not DESTINATION.exists():
            sys.exit(f"No icon at {DESTINATION}")
        shipped = Image.open(DESTINATION)
        print(f"Checking {DESTINATION.relative_to(REPO_ROOT)}")
        if shipped.size != (SIDE, SIDE):
            sys.exit(f"  Expected {SIDE}x{SIDE}, found {shipped.size[0]}x{shipped.size[1]}")
        if shipped.mode not in {"RGB", "L"}:
            sys.exit(f"  Icon has an alpha channel (mode {shipped.mode}) — App Store review rejects that")
        report(shipped.convert("RGB"))
        print("  App icon OK.")
        return 0

    icon = build_icon()
    report(icon)
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    icon.save(DESTINATION, format="PNG", optimize=True)
    print(f"Wrote {DESTINATION.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
