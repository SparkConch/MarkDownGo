#!/usr/bin/env python3
"""Emit design/logo.svg — the MarkDownGo mark (foreground only).

The icon plate and drop shadow come from Apple's official macOS app icon template
(`macOS 圆角图标模板.psd`, layers `512@2x` + `512@2x: Shadow`), extracted to
design/official-plate.png and design/official-shadow.png and composited by
scripts/render-icon.swift. This file only draws the mark: M with a down-arrow
median stroke, congruent 240x160 triangles, seamless shaft join, optically centred
by measured ink centroid (MARK_DY below).
"""
import math

GRID = 1024
ART = 824
MARK_SCALE = ART / GRID   # 0.8046875

# Optical centring, solved by measurement (2026-11-01): equal-area centroid is the WRONG target
# for this glyph — the arrow-head triangle is far denser than the crown, so centroid-centring
# pushes the mark against the plate's bottom (gaps 220/114) and reads as "sinking". The perceived
# balance follows the bounding box instead: at MARK_DY=0 gaps are 147/187 (high), each +1 of dy
# moves the mark down 0.80 canvas px and shifts the gap delta by 1.6, so equal gaps land at
# MARK_DY = 25.0 → gaps 167/167. Re-solve empirically (render, measure, interpolate) if the
# geometry changes; do not "fix" the centroid being ~470 afterwards — that is expected.
MARK_DY = 25.0

# Mark geometry (congruent triangles, seamless shaft join) in mark-space.
T = 183.0
LEG_BOTTOM, TIP = 632.0, 792.0
TRI_W, TRI_H = 240.0, 160.0
slope = TRI_H / (TRI_W / 2)
notch = T + TRI_H
band = notch + 159.0
legs_y = band - slope * 180.0
SH = 88.0
shaft_top = band - (SH / 2) * slope
shaft_x = 512 - SH / 2

svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- MarkDownGo mark (foreground only). The plate and drop shadow are Apple's official
     macOS icon template layers (design/official-plate.png, design/official-shadow.png),
     composited by scripts/render-icon.swift. Congruent 240x160 apex-down triangles, shaft
     overlapping the head by 8px to avoid an antialiasing seam, optically centred by measured
     ink centroid (MARK_DY). -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" width="{GRID}" height="{GRID}">
  <g transform="translate(512 512) scale({MARK_SCALE:.7f}) translate(-512 -512)">
    <g transform="translate(0 {MARK_DY})">
      <path fill="#0B0B0A" d="M232 {T:.0f} L392 {T:.0f} L512 {notch:.0f} L632 {T:.0f} L792 {T:.0f} L792 {LEG_BOTTOM:.0f} L692 {LEG_BOTTOM:.0f} L692 {legs_y:.0f} L512 {band:.0f} L332 {legs_y:.0f} L332 {LEG_BOTTOM:.0f} L232 {LEG_BOTTOM:.0f} Z"/>
      <rect x="{shaft_x:.1f}" y="{shaft_top:.1f}" width="{SH:.0f}" height="{LEG_BOTTOM + 8 - shaft_top:.1f}" fill="#0B0B0A"/>
      <polygon points="392,{LEG_BOTTOM:.0f} 632,{LEG_BOTTOM:.0f} 512,{TIP:.0f}" fill="#0B0B0A"/>
    </g>
  </g>
</svg>
'''
open('design/logo.svg', 'w').write(svg)
print(f"logo.svg (mark only) written, MARK_DY={MARK_DY}")
