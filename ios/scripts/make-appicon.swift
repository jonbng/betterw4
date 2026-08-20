#!/usr/bin/env swift

//  make-appicon.swift
//  BetterW4
//
//  Renders Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png from the same vector the
//  Icon Composer document uses, so the two never drift apart.
//
//  Why this exists at all: `AppIcon.icon` is an Icon Composer document, and Icon Composer
//  shipped with Xcode 26. Under Xcode 16.4 the folder is copied into the app bundle verbatim
//  as an inert resource — no `Assets.car`, no `CFBundleIcons`, no icon. App Store Connect
//  rejects that upload with ITMS-90022 ("missing required icon file"), and the simulator shows
//  a grey placeholder. Until the project moves to Xcode 26 the asset catalogue is the icon that
//  actually ships; `AppIcon.icon` is kept so the vector source and its layer recipe are not lost.
//
//  The colours below are read off `AppIcon.icon/icon.json`: an automatic gradient over
//  display-p3 (0.93693, 0.98782, 1.00000) with the glyph solid black in the light appearance.
//  A single 1024×1024 opaque PNG is all iOS 18 needs; the system derives every other size.
//
//  Usage:  ios/scripts/make-appicon.swift        (from the repository root, or anywhere)

import AppKit
import Foundation

let side = 1024.0

/// Fraction of the canvas height the glyph's ink is allowed to occupy. The remainder is the
/// margin that keeps the mark clear of the superellipse mask iOS applies to every icon.
let glyphHeightFraction = 0.68

let scriptURL = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
let iosRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let svgURL = iosRoot.appendingPathComponent("AppIcon.icon/Assets/logo 1.svg")
let outputDirectory = iosRoot.appendingPathComponent("BetterW4/Assets.xcassets/AppIcon.appiconset")
let outputURL = outputDirectory.appendingPathComponent("AppIcon-1024.png")

guard FileManager.default.fileExists(atPath: svgURL.path) else {
    FileHandle.standardError.write(Data("error: no SVG at \(svgURL.path)\n".utf8))
    exit(1)
}

// NSImage has read SVG natively since macOS 11, which is why this script needs no third-party
// rasteriser. It is also why it is a macOS script and not part of the iOS build.
guard let glyph = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("error: could not decode \(svgURL.lastPathComponent) as an image\n".utf8))
    exit(1)
}

/// Renders the glyph large, then measures the tightest box containing a non-transparent pixel.
///
/// The artwork's `viewBox` is 512×512 but its ink only spans part of that, and it is not centred
/// inside it. Laying the icon out from the viewBox would leave the mark visibly high and left.
/// Measuring the ink is what makes it sit where the eye expects.
func inkBounds(of image: NSImage, probeSide: Int) -> CGRect? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: probeSide,
        pixelsHigh: probeSide,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: probeSide * 4,
        bitsPerPixel: 32
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let box = NSRect(x: 0, y: 0, width: Double(probeSide), height: Double(probeSide))
    image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.bitmapData else { return nil }
    var minX = probeSide, minY = probeSide, maxX = -1, maxY = -1
    for y in 0..<probeSide {
        for x in 0..<probeSide {
            // Anything above a whisper of alpha counts; anti-aliased edges are ink too.
            if data[y * bitmap.bytesPerRow + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }

    // NSBitmapImageRep rows run top-down; NSGraphicsContext draws bottom-up. Flip y back.
    return CGRect(
        x: Double(minX),
        y: Double(probeSide - 1 - maxY),
        width: Double(maxX - minX + 1),
        height: Double(maxY - minY + 1)
    )
}

let probeSide = 1024
guard let ink = inkBounds(of: glyph, probeSide: probeSide) else {
    FileHandle.standardError.write(Data("error: the SVG rendered no visible pixels\n".utf8))
    exit(1)
}

guard let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side),
    pixelsHigh: Int(side),
    bitsPerSample: 8,
    samplesPerPixel: 3,          // Three colour samples, no alpha: an App Store icon must be
    hasAlpha: false,             // opaque, and a fully-opaque alpha channel is still rejected.
    isPlanar: false,             // Padded to 32bpp because CoreGraphics has no packed 24-bit
    colorSpaceName: .deviceRGB,  // backing store — the fourth byte is ignored, not alpha.
    bytesPerRow: Int(side) * 4,
    bitsPerPixel: 32
) else {
    FileHandle.standardError.write(Data("error: could not allocate the 1024×1024 canvas\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
guard let context = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write(Data("error: no drawing context\n".utf8))
    exit(1)
}

// Background: the icon.json fill, warmed very slightly at the bottom so the flat PNG keeps a
// hint of the automatic gradient Icon Composer would have produced.
let top = NSColor(displayP3Red: 0.93693, green: 0.98782, blue: 1.00000, alpha: 1)
let bottom = NSColor(displayP3Red: 0.80000, green: 0.91000, blue: 0.98000, alpha: 1)
if let gradient = NSGradient(starting: top, ending: bottom) {
    gradient.draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: -90)
} else {
    top.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
}

// Scale the glyph so its *ink* is `glyphHeightFraction` of the canvas, then centre that ink.
// `glyph.draw` positions the whole 512-unit viewBox, so the destination rect is the viewBox
// expressed in the coordinate system that puts the ink where we want it.
let probeScale = side / Double(probeSide)
let inkOnCanvas = CGRect(
    x: ink.origin.x * probeScale,
    y: ink.origin.y * probeScale,
    width: ink.width * probeScale,
    height: ink.height * probeScale
)
let scale = (side * glyphHeightFraction) / inkOnCanvas.height
let scaledViewBox = side * scale
let destination = NSRect(
    x: (side - inkOnCanvas.width * scale) / 2 - inkOnCanvas.origin.x * scale,
    y: (side - inkOnCanvas.height * scale) / 2 - inkOnCanvas.origin.y * scale,
    width: scaledViewBox,
    height: scaledViewBox
)

context.interpolationQuality = .high
glyph.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let png = canvas.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("error: PNG encoding failed\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try png.write(to: outputURL)

print("wrote \(outputURL.path) — \(Int(side))×\(Int(side)), opaque, \(png.count) bytes")
