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
// The caller chooses the mark artwork: make-appicon.sh passes design/logo-small.svg at 16/32/64px
// and design/logo.svg above (Apple's own small icons are separate drawings too).
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

// Small sizes need their own treatment, not a miniature of the 1024 artwork:
//  · supersample so the 824-unit plate lands on whole pixels (16px → ×8, 32px → ×4, 64px → ×2),
//    then box-down once — a direct 824→12.875px draw is what made 16px look smeared;
//  · no drop shadow below 64px: the template's blur is sub-pixel there and only adds a grey fringe
//    (Apple's own 16/32px icons show no perceptible shadow either);
//  · slight artwork enlargement at 16/32px so the strokes stay legible.
let smallSize = pixels <= 64
let workFactor: Int = {
    var k = 1
    while (824.0 * Double(pixels * k) / 1024.0).truncatingRemainder(dividingBy: 1) != 0 || pixels * k < 103 {
        k *= 2
        if k > 16 { break }
    }
    return k
}()
let workPixels = pixels * workFactor
let artworkBoost: Double = pixels <= 16 ? 1.10 : (pixels <= 32 ? 1.05 : 1.0)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let work = CGContext(data: nil, width: workPixels, height: workPixels, bitsPerComponent: 8,
                     bytesPerRow: workPixels * 4, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let ctx = work
let unit = Double(workPixels) / 1024.0

if official {
    // 1) Official drop shadow at its template position (70, 87 top-down → y-flipped here).
    //    Below 64px the template blur is sub-pixel and reads as grey haze, so it is skipped.
    if !smallSize, let shadow = loadCGImage(designURL("official-shadow.png")) {
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
        // Honour the SVG the caller passed in; the size-specific artwork choice lives in
        // make-appicon.sh, not hidden here (hard-coding it broke previews and A/B renders).
        let markSource = URL(fileURLWithPath: svgPath)
        if let mark = renderMark(svgPath: markSource.path, size: workPixels) {
            // The mask must cover exactly the plate's rect (100,100,824,824). Stretching it over
            // the whole canvas made the corners 24% squarer than Apple's template.
            if let plateMask = alphaMask(plate, side: plate.width) {
                let scaled = CGContext(data: nil, width: workPixels, height: workPixels, bitsPerComponent: 8,
                                       bytesPerRow: workPixels * 4, space: cs,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                scaled.interpolationQuality = .high
                let plateRect = CGRect(x: 100 * unit, y: 100 * unit,
                                       width: 824 * unit, height: 824 * unit)
                scaled.draw(plateMask, in: plateRect)
                if let mask = scaled.makeImage() {
                    ctx.clip(to: plateRect, mask: mask)
                }
            }
            let side = Double(workPixels) * artworkBoost
            let origin = (Double(workPixels) - side) / 2
            ctx.draw(mark, in: CGRect(x: origin, y: origin, width: side, height: side))
        }
    }
} else {
    if let mark = renderMark(svgPath: svgPath, size: pixels) {
        ctx.draw(mark, in: CGRect(x: 0, y: 0, width: Double(pixels), height: Double(pixels)))
    }
}

// Box-down the supersampled canvas to the target size in one high-quality step.
let final: CGImage = {
    guard workFactor > 1, let source = work.makeImage() else { return work.makeImage()! }
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: pixels * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return ctx.makeImage()!
}()
let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, final, nil)
CGImageDestinationFinalize(out)
print("wrote \(outPath) \(pixels)x\(pixels)\(official ? " (official template, supersample ×\(workFactor)\(smallSize ? ", small-size rules" : ""))" : "")")

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
/// Pure CoreGraphics buffers: NSBitmapImageRep.colorAt mis-parses the template PNGs' colour space
/// (it silently returns wrong components), which used to widen the corners by 24%.
func alphaMask(_ image: CGImage, side: Int) -> CGImage? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let srcW = image.width, srcH = image.height
    let src = CGContext(data: nil, width: srcW, height: srcH, bitsPerComponent: 8,
                        bytesPerRow: srcW * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    src.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
    guard let srcBuf = src.data?.bindMemory(to: UInt8.self, capacity: srcW * srcH * 4) else { return nil }

    let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: side * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    guard let dstBuf = out.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) else { return nil }
    let sx = Double(srcW) / Double(side)
    let sy = Double(srcH) / Double(side)
    for y in 0..<side {
        let srcY = min(srcH - 1, Int(Double(y) * sy))
        for x in 0..<side {
            let srcX = min(srcW - 1, Int(Double(x) * sx))
            let alpha = srcBuf[(srcY * srcW + srcX) * 4 + 3]
            let dst = (y * side + x) * 4
            dstBuf[dst + 0] = 255
            dstBuf[dst + 1] = 255
            dstBuf[dst + 2] = 255
            dstBuf[dst + 3] = alpha
        }
    }
    return out.makeImage()
}
