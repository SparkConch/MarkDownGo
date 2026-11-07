#!/usr/bin/env python3
"""Emit the MarkDownGo mark sources.

Two artworks sharing one geometry (the small one only thickens the shaft and arrow head for 16px):
  design/logo.svg        standard artwork, used from 128px up
  design/logo-small.svg  small-size artwork, used at 16/32/64px

The icon plate and drop shadow are NOT drawn here: they are Apple's official macOS app icon
template layers (design/official-plate.png, design/official-shadow.png), extracted from
`macOS 圆角图标模板.psd` and composited by scripts/render-icon.swift.

Optical centring is solved by measurement, not by centroid: equal-area centroid is the wrong target
for this glyph (the arrow head is far denser than the crown, so centroid-centring pins the mark to
the plate's bottom). Bounding-box balance is what the eye follows — see MARK_DY below.
"""
import math

GRID = 1024
ART = 824
MARK_SCALE = ART / GRID  # 0.8046875

# Measured 2026-11-01: dy=0 → gaps 147/187 (high); +1 dy moves 0.80px down, gap delta 1.6. Equal
# bounding-box gaps (dy=25 → 167/167) READ high: heavy flat crown vs a thin arrow point the eye
# discounts, so the point must sit closer to the edge. Tuned by eye against the real 824px plate in a
# clean A/B (no guides): dy=37 → 177/157, dy=45 → 183/150, dy=65 → 200/134 chosen by the designer
# (the small 37/45 steps were visually imperceptible; 65 is a clearly lower, settled position).
# Ink centroid ~498, leave it alone.
MARK_DY = 65.0

# Standard geometry (congruent triangles, seamless shaft join) in mark space.
T = 183.0          # crown
LEG_BOTTOM = 632.0  # leg bottoms = arrow head's top plane
TIP = 792.0        # arrow tip
TRI_W, TRI_H = 240.0, 160.0
slope = TRI_H / (TRI_W / 2)
notch = T + TRI_H
band = notch + 159.0
legs_y = band - slope * 180.0
SH = 88.0
shaft_top = band - (SH / 2) * slope
shaft_x = 512 - SH / 2

# Small-size artwork keeps the SAME M/arrow geometry as the standard mark; only the shaft and the
# arrow head are heavier so they survive 16/32px. Derived from the constants above so the two files
# can never drift apart (an earlier "separate drawing" with a V-stroke produced a crown, not an M).
SMALL_SH = 112.0
small_shaft_top = band - (SMALL_SH / 2) * slope
small_shaft_x = 512 - SMALL_SH / 2
SMALL_ARROW_W, SMALL_ARROW_H = 300.0, 180.0

HEADER_COMMON = """The plate and drop shadow are Apple's official macOS icon template layers
     (design/official-plate.png, design/official-shadow.png), composited by scripts/render-icon.swift.
     The mark is optically balanced: the arrow tip sits closer to the bottom edge than the crown does to
     the top edge, because a thin point reads as smaller than a heavy flat bar (equal bounding-box gaps
     look high). The ink centroid is not the target."""

STANDARD = f"""  <g transform="translate(512 512) scale({MARK_SCALE:.7f}) translate(-512 -512)">
    <g transform="translate(0 {MARK_DY})">
      <path fill="#0B0B0A" d="M232 {T:.0f} L392 {T:.0f} L512 {notch:.0f} L632 {T:.0f} L792 {T:.0f} L792 {LEG_BOTTOM:.0f} L692 {LEG_BOTTOM:.0f} L692 {legs_y:.0f} L512 {band:.0f} L332 {legs_y:.0f} L332 {LEG_BOTTOM:.0f} L232 {LEG_BOTTOM:.0f} Z"/>
      <rect x="{shaft_x:.1f}" y="{shaft_top:.1f}" width="{SH:.0f}" height="{LEG_BOTTOM + 8 - shaft_top:.1f}" fill="#0B0B0A"/>
      <polygon points="392,{LEG_BOTTOM:.0f} 632,{LEG_BOTTOM:.0f} 512,{TIP:.0f}" fill="#0B0B0A"/>
    </g>
  </g>"""

# Small sizes (16/32/64px) use the standard geometry with a heavier shaft and arrow head; the
# renderer supersamples and enlarges slightly, which keeps the M legible at 16px.
SMALL = f"""  <g transform="translate(512 512) scale({MARK_SCALE:.7f}) translate(-512 -512)">
    <g transform="translate(0 {MARK_DY})">
      <path fill="#0B0B0A" d="M232 {T:.0f} L392 {T:.0f} L512 {notch:.0f} L632 {T:.0f} L792 {T:.0f} L792 {LEG_BOTTOM:.0f} L692 {LEG_BOTTOM:.0f} L692 {legs_y:.0f} L512 {band:.0f} L332 {legs_y:.0f} L332 {LEG_BOTTOM:.0f} L232 {LEG_BOTTOM:.0f} Z"/>
      <rect x="{small_shaft_x:.1f}" y="{small_shaft_top:.1f}" width="{SMALL_SH:.0f}" height="{LEG_BOTTOM + 8 - small_shaft_top:.1f}" fill="#0B0B0A"/>
      <polygon points="{512 - SMALL_ARROW_W / 2:.0f},{LEG_BOTTOM:.0f} {512 + SMALL_ARROW_W / 2:.0f},{LEG_BOTTOM:.0f} 512,{LEG_BOTTOM + SMALL_ARROW_H:.0f}" fill="#0B0B0A"/>
    </g>
  </g>"""


def write(path: str, comment: str, body: str) -> None:
    svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- MarkDownGo mark. {comment}
     {HEADER_COMMON} -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" width="{GRID}" height="{GRID}">
{body}
</svg>
"""
    open(path, "w").write(svg)
    print(f"wrote {path}")


write("design/logo.svg", "Standard artwork, used from 128px up.", STANDARD)
write("design/logo-small.svg", "Small-size artwork, used at 16/32/64px (same geometry, heavier shaft/arrow).", SMALL)
print(f"MARK_DY={MARK_DY}")
