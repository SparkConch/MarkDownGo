#!/usr/bin/env python3
"""Emit design/logo.svg using Apple's macOS 11 app-icon grid.

Grid (Apple developer forums answer for macOS icons, fitted against six shipping system icons):
  canvas 1024 · squircle body 824 centred (100pt margins) · corner radius 185.4
  · continuous curvature ("corner smoothing" 0.7) · template drop shadow, composited by the renderer.

macOS does not mask third-party icons, so this silhouette has to be baked in: the plate, its
curvature and its shadow are part of the artwork.
"""
import math

GRID = 1024
ART = 824
INSET = (GRID - ART) / 2          # 100
RADIUS = 185.4
SMOOTHING = 0.7

# The mark, authored in 1024-space, is scaled into the 824 art box about the canvas centre.
MARK_SCALE = ART / GRID


def squircle(side: float, radius: float, smoothing: float, x: float = 0.0, y: float = 0.0) -> str:
    """Rounded square with Apple-style continuous corners (Figma corner-smoothing construction)."""
    r, s = radius, smoothing
    p = (1 + s) * r
    arc_measure = 90 * (1 - s)
    arc = math.sin(math.radians(arc_measure / 2)) * r * math.sqrt(2)
    angle_alpha = (90 - arc_measure) / 2
    angle_beta = 45 * s
    c = r * math.tan(math.radians(angle_alpha / 2)) * math.cos(math.radians(angle_beta))
    d = c * math.tan(math.radians(angle_beta))
    b = (p - arc - c - d) / 3
    a = 2 * b

    def n(v: float) -> str:
        return f"{v:.4f}"

    return " ".join([
        f"M {n(x + side - p)} {n(y)}",
        f"c {n(a)} 0 {n(a + b)} 0 {n(a + b + c)} {n(d)}",
        f"a {n(r)} {n(r)} 0 0 1 {n(arc)} {n(arc)}",
        f"c {n(d)} {n(c)} {n(d)} {n(b + c)} {n(d)} {n(a + b + c)}",
        f"L {n(x + side)} {n(y + side - p)}",
        f"c 0 {n(a)} 0 {n(a + b)} {n(-d)} {n(a + b + c)}",
        f"a {n(r)} {n(r)} 0 0 1 {n(-arc)} {n(arc)}",
        f"c {n(-c)} {n(d)} {n(-(b + c))} {n(d)} {n(-(a + b + c))} {n(d)}",
        f"L {n(x + p)} {n(y + side)}",
        f"c {n(-a)} 0 {n(-(a + b))} 0 {n(-(a + b + c))} {n(-d)}",
        f"a {n(r)} {n(r)} 0 0 1 {n(-arc)} {n(-arc)}",
        f"c {n(-d)} {n(-c)} {n(-d)} {n(-(b + c))} {n(-d)} {n(-(a + b + c))}",
        f"L {n(x)} {n(y + p)}",
        f"c 0 {n(-a)} 0 {n(-(a + b))} {n(d)} {n(-(a + b + c))}",
        f"a {n(r)} {n(r)} 0 0 1 {n(arc)} {n(-arc)}",
        f"c {n(c)} {n(-d)} {n(b + c)} {n(-d)} {n(a + b + c)} {n(-d)}",
        "Z",
    ])


# Mark geometry, in 1024-space (unchanged from v6: congruent triangles, seamless shaft join).
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
<!-- MarkDownGo icon master. Apple macOS 11 grid: 1024 canvas, 824 squircle centred,
     corner radius 185.4 with continuous curvature (smoothing 0.7), template drop shadow added by
     scripts/render-icon.swift. The notch and the arrow head are congruent 240x160 apex-down
     triangles on the same centre line; the shaft meets the V underside flush and overlaps the head
     by 8px so no antialiasing seam shows. The mark is centred by measured area centroid. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" width="{GRID}" height="{GRID}">
  <path d="{squircle(ART, RADIUS, SMOOTHING, INSET, INSET)}" fill="#F6F2EA"/>
  <g transform="translate(512 512) scale({MARK_SCALE:.7f}) translate(-512 -512)">
    <path fill="#0B0B0A" d="M232 {T:.0f} L392 {T:.0f} L512 {notch:.0f} L632 {T:.0f} L792 {T:.0f} L792 {LEG_BOTTOM:.0f} L692 {LEG_BOTTOM:.0f} L692 {legs_y:.0f} L512 {band:.0f} L332 {legs_y:.0f} L332 {LEG_BOTTOM:.0f} L232 {LEG_BOTTOM:.0f} Z"/>
    <rect x="{shaft_x:.1f}" y="{shaft_top:.1f}" width="{SH:.0f}" height="{LEG_BOTTOM + 8 - shaft_top:.1f}" fill="#0B0B0A"/>
    <polygon points="392,{LEG_BOTTOM:.0f} 632,{LEG_BOTTOM:.0f} 512,{TIP:.0f}" fill="#0B0B0A"/>
  </g>
</svg>
'''
open('design/logo.svg', 'w').write(svg)
print(f"logo.svg: art {ART} @ inset {INSET:.0f}, radius {RADIUS}, smoothing {SMOOTHING}, mark scale {MARK_SCALE:.4f}")
