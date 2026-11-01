#!/usr/bin/env python3
"""Emit the MarkDownGo mark sources.

Two artworks, because one drawing cannot serve 16px and 1024px:
  design/logo.svg        standard artwork, used from 64px up
  design/logo-small.svg  small-size artwork, used at 16px and 32px

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

# Measured 2026-11-01: at dy=0 the mark's gaps inside the plate are 147/187 (sitting high); each +1
# of dy moves it 0.80 canvas px down and shifts the gap delta by 1.6, so equal gaps land at 25.0.
# Final result: top 167 / bottom 167. The ink centroid ends up ~459 — expected, leave it alone.
MARK_DY = 25.0

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

HEADER_COMMON = """The plate and drop shadow are Apple's official macOS icon template layers
     (design/official-plate.png, design/official-shadow.png), composited by scripts/render-icon.swift.
     The mark is balanced by bounding box (equal gaps inside the plate), not by ink centroid."""

STANDARD = f"""  <g transform="translate(512 512) scale({MARK_SCALE:.7f}) translate(-512 -512)">
    <g transform="translate(0 {MARK_DY})">
      <path fill="#0B0B0A" d="M232 {T:.0f} L392 {T:.0f} L512 {notch:.0f} L632 {T:.0f} L792 {T:.0f} L792 {LEG_BOTTOM:.0f} L692 {LEG_BOTTOM:.0f} L692 {legs_y:.0f} L512 {band:.0f} L332 {legs_y:.0f} L332 {LEG_BOTTOM:.0f} L232 {LEG_BOTTOM:.0f} Z"/>
      <rect x="{shaft_x:.1f}" y="{shaft_top:.1f}" width="{SH:.0f}" height="{LEG_BOTTOM + 8 - shaft_top:.1f}" fill="#0B0B0A"/>
      <polygon points="392,{LEG_BOTTOM:.0f} 632,{LEG_BOTTOM:.0f} 512,{TIP:.0f}" fill="#0B0B0A"/>
    </g>
  </g>"""

# At 16px the standard arrow head is ~1.9px wide and the notch ~3.8px: nothing can keep that crisp.
# The small variant therefore drops the notch and the shaft and works with heavier masses — two thick
# legs, a bold V wedge, a wide arrow — inside the same outer box, so the optical centre still holds.
SMALL = f"""  <g transform="translate(512 512) scale({MARK_SCALE:.7f}) translate(-512 -512)">
    <g transform="translate(0 {MARK_DY})">
      <g fill="#0B0B0A">
        <rect x="232" y="{T:.0f}" width="150" height="{LEG_BOTTOM - T:.0f}"/>
        <rect x="642" y="{T:.0f}" width="150" height="{LEG_BOTTOM - T:.0f}"/>
        <path d="M232 {T:.0f} L512 430 L792 {T:.0f}" fill="none" stroke="#0B0B0A" stroke-width="210"
              stroke-linecap="butt" stroke-linejoin="miter"/>
        <polygon points="362,600 662,600 512,{TIP:.0f}"/>
      </g>
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


write("design/logo.svg", "Standard artwork, used from 64px up.", STANDARD)
write("design/logo-small.svg", "Small-size artwork, used at 16px and 32px (redrawn, not scaled).", SMALL)
print(f"MARK_DY={MARK_DY}")
