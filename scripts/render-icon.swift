#!/usr/bin/env swift
// Render the MarkDownGo app icon from Apple's official macOS app-icon template.
//
// Sources (all under design/):
//   logo.svg                 the mark (foreground), transparent background
//   official-plate.png       template layer `512@2x` (824x824, transparent background)
//   official-shadow.png      template layer `512@2x: Shadow` (878x878, transparent background)
//
// Composition follows the template's own layer placement: shadow at (70, 87), plate at (100, 100),
// the mark on top clipped to the plate silhouette. Pixel access goes through CoreGraphics buffers —
// NSBitmapImageRep.colorAt chokes on the template PNGs' colour space.
//
// Shadow fidelity: the template's `512@2x: Shadow` layer is NORMAL blend at opacity 77/255 (30.2%).
// The exported official-shadow.png already carries that opacity baked into its alpha ramp
// (max 77), and it is drawn as-is (source-over = NORMAL) — i.e. an exact replication of the
// template's shadow, no invented blur or alpha.
//
// usage: render-icon <logo.svg> <out.png> <px> [official]
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: render-icon <logo.svg> <png> <px> [official]")
    exit(2)
}
let svgPath = args[1]
let outPath = args[2]
let pixels = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024
let official = args.count > 4 && args[4] == "official"

func designURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("design").appendingPathComponent(name)
}

func loadCGImage(_ url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
        CGImageSourceCreateImageAtIndex($0, 0, nil)
    }
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                    bytesPerRow: pixels * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let unit = Double(pixels) / 1024.0

if official {
    // 1) Official drop shadow at its template position (70, 87 top-down → y-flipped here).
    if let shadow = loadCGImage(designURL("official-shadow.png")) {
        ctx.draw(shadow, in: CGRect(x: 70 * unit, y: (1024 - 87 - 878) * unit,
                                    width: 878 * unit, height: 878 * unit))
    }

    // 2) Official plate silhouette, tinted #F6F2EA through its own alpha.
    if let plate = loadCGImage(designURL("official-plate.png")) {
        let side = plate.width
        let src = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: side * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        src.draw(plate, in: CGRect(x: 0, y: 0, width: side, height: side))
        if let base = src.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) {
            let tinted = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                   bytesPerRow: side * 4, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if let dst = tinted.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) {
                for i in 0..<(side * side) {
                    let alpha = base[i * 4 + 3]
                    dst[i * 4 + 0] = UInt8(round(0.965 * 255))
                    dst[i * 4 + 1] = UInt8(round(0.949 * 255))
                    dst[i * 4 + 2] = UInt8(round(0.918 * 255))
                    dst[i * 4 + 3] = alpha
                }
            }
            if let image = tinted.makeImage() {
                ctx.draw(image, in: CGRect(x: 100 * unit, y: 100 * unit,
                                           width: 824 * unit, height: 824 * unit))
            }
        }

        // 3) The mark, clipped to the plate silhouette.
        if let mark = renderMark(svgPath: svgPath, size: pixels) {
            if let plateMask = alphaMask(plate, side: plate.width) {
                let scaled = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                       bytesPerRow: pixels * 4, space: cs,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                scaled.interpolationQuality = .high
                scaled.draw(plateMask, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                if let mask = scaled.makeImage() {
                    ctx.clip(to: CGRect(x: 0, y: 0, width: pixels, height: pixels), mask: mask)
                }
            }
            ctx.draw(mark, in: CGRect(x: 0, y: 0, width: Double(pixels), height: Double(pixels)))
        }
    }
} else {
    if let mark = renderMark(svgPath: svgPath, size: pixels) {
        ctx.draw(mark, in: CGRect(x: 0, y: 0, width: Double(pixels), height: Double(pixels)))
    }
}

// Write out through ImageIO (colour space clean, no NSBitmapImageRep involvement).
let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
CGImageDestinationFinalize(out)
print("wrote \(outPath) \(pixels)x\(pixels)\(official ? " (official template)" : "")")

// MARK: - Mark rendering (SVG needs AppKit)

func renderMark(svgPath: String, size: Int) -> CGImage? {
    guard let image = NSImage(contentsOfFile: svgPath) else { return nil }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep!)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep?.cgImage
}

// MARK: - Alpha mask

/// White pixels carrying the source's alpha — usable as `CGContext.clip(to:mask:)`.
func alphaMask(_ image: CGImage, side: Int) -> CGImage? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let src = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    src.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let base = src.data?.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4) else { return nil }

    let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: side * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    guard let dst = out.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) else { return nil }
    let sx = Double(image.width) / Double(side)
    for y in 0..<side {
        for x in 0..<side {
            let srcIndex = (Int(Double(y) * sx) * image.width + Int(Double(x) * sx)) * 4
            let alpha = base[srcIndex + 3]
            let dstIndex = (y * side + x) * 4
            dst[dstIndex + 0] = 255
            dst[dstIndex + 1] = 255
            dst[dstIndex + 2] = 255
            dst[dstIndex + 3] = alpha
        }
    }
    return out.makeImage()
}
