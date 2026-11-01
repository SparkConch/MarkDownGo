#!/usr/bin/env swift
// Renders the vector master (design/logo.svg) to a square PNG and reports the ink bounding box,
// so icon symmetry is verified by measurement instead of by eye.
// usage: swift scripts/render-icon.swift <svg> <png> [px] [insetFraction] [shadow]
//   shadow: "shadow" adds the macOS 11 template drop shadow (alpha 0.26, blur 16, dy 6 at 1024).
//   insetFraction (optional) shrinks the artwork and centres it — used for the macOS 11 app-icon
//   grid, where the 1024 canvas holds an 824x824 icon body (100/1024 = 0.09765625).
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: render-icon <svg> <png> [px]")
    exit(2)
}
let svgURL = URL(fileURLWithPath: args[1])
let pngURL = URL(fileURLWithPath: args[2])
let pixels = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024
let inset = args.count > 4 ? (Double(args[4]) ?? 0) : 0
let wantsShadow = args.count > 5 && args[5] == "shadow"

guard let image = NSImage(contentsOf: svgURL) else {
    print("error: cannot read \(svgURL.path) — SVG must be loadable by NSImage")
    exit(1)
}
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: pixels, height: pixels)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let side = Double(pixels) * (1 - inset * 2)
let target = NSRect(x: Double(pixels) * inset, y: Double(pixels) * inset, width: side, height: side)
if wantsShadow, let context = NSGraphicsContext.current?.cgContext {
    // macOS 11 template shadow, in 1024-canvas units scaled to the render size.
    let unit = Double(pixels) / 1024.0
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6 * unit),
                      blur: 16 * unit,
                      color: NSColor.black.withAlphaComponent(0.26).cgColor)
    image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    context.restoreGState()
}
image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(at: pngURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: pngURL)

// Ink = pixels darker than mid-grey; report margins so top/bottom symmetry is checkable.
var minY = pixels, maxY = -1, minX = pixels, maxX = -1
for y in 0..<pixels {
    for x in 0..<pixels {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
        let luma = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        if luma < 0.4 {
            minY = min(minY, y); maxY = max(maxY, y)
            minX = min(minX, x); maxX = max(maxX, x)
        }
    }
}
print("wrote \(pngURL.path) \(pixels)x\(pixels)")
if maxY >= 0 {
    print("ink box: x \(minX)…\(maxX)  y \(minY)…\(maxY)")
    print("margins: top \(minY)  bottom \(pixels - 1 - maxY)  left \(minX)  right \(pixels - 1 - maxX)")
}
