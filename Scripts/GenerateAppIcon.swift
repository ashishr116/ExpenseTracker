#!/usr/bin/env swift
//
//  GenerateAppIcon.swift
//  ExpenseTracker
//
//  Renders the 1024×1024 app icon PNGs (light, dark, tinted) into the asset catalog.
//  The ₹ geometry here mirrors `RupeeShape` in the app so the icon and splash match.
//
//  Usage (from any directory):  swift Scripts/GenerateAppIcon.swift
//

import AppKit
import CoreGraphics

let size: CGFloat = 1024

/// Resolve the asset catalog relative to this script (Scripts/ → repo root),
/// so the script works no matter which directory it is run from.
let outputDirectory = URL(fileURLWithPath: #filePath)
    .standardizedFileURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("ExpenseTracker/Assets.xcassets/AppIcon.appiconset")

guard FileManager.default.fileExists(atPath: outputDirectory.path) else {
    print("error: AppIcon.appiconset not found at \(outputDirectory.path)")
    exit(1)
}

let navy = CGColor(red: 0.043, green: 0.165, blue: 0.357, alpha: 1)      // #0B2A5B
let yellow = CGColor(red: 1.0, green: 0.788, blue: 0.235, alpha: 1)      // #FFC93C
let lightYellow = CGColor(red: 1.0, green: 0.878, blue: 0.478, alpha: 1) // #FFE07A

// MARK: - ₹ geometry (unit square, origin top-left)

/// Inset so the glyph sits comfortably inside the icon's rounded mask.
let glyphRect = CGRect(x: 0.18, y: 0.16, width: 0.64, height: 0.68)

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    // Map unit coordinates into the glyph rect, then flip Y for Core Graphics.
    let px = (glyphRect.minX + x * glyphRect.width) * size
    let py = (glyphRect.minY + y * glyphRect.height) * size
    return CGPoint(x: px, y: size - py)
}

func headPath() -> CGPath {
    let path = CGMutablePath()
    // Top bar
    path.move(to: point(0.16, 0.10))
    path.addLine(to: point(0.84, 0.10))
    // Middle bar
    path.move(to: point(0.16, 0.34))
    path.addLine(to: point(0.84, 0.34))
    // Bowl
    path.move(to: point(0.30, 0.10))
    path.addLine(to: point(0.42, 0.10))
    path.addCurve(to: point(0.42, 0.58), control1: point(0.76, 0.10), control2: point(0.76, 0.58))
    path.addLine(to: point(0.18, 0.58))
    return path
}

func tailPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: point(0.20, 0.58))
    path.addLine(to: point(0.80, 0.98))
    return path
}

// MARK: - Rendering

let lineWidth = 0.085 * size

func renderIcon(background: [CGColor], glyph: CGColor, fileName: String) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Could not create context") }

    // Background: subtle diagonal gradient.
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: background as CFArray, locations: nil)!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(lineWidth)

    // Solid head of the ₹.
    ctx.setStrokeColor(glyph)
    ctx.addPath(headPath())
    ctx.strokePath()

    // Dashed tail that fades out: clip to the dashed stroke, then fill with an alpha gradient.
    ctx.saveGState()
    ctx.addPath(tailPath())
    // Round caps add half a line width to each end of a dash, so the gap must exceed
    // one line width for the dashes to stay visibly separate.
    ctx.setLineDash(phase: 0, lengths: [lineWidth * 0.8, lineWidth * 1.6])
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let fade = CGGradient(
        colorsSpace: colorSpace,
        colors: [glyph, glyph.copy(alpha: 0.05)!] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(fade, start: point(0.20, 0.58), end: point(0.80, 0.98), options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fatalError("Could not render image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    let url = outputDirectory.appendingPathComponent(fileName)
    do {
        try data.write(to: url)
        print("Wrote \(url.path)")
    } catch {
        print("error: could not write \(url.path): \(error.localizedDescription)")
        exit(1)
    }
}

// Light: navy ₹ on yellow.
renderIcon(background: [yellow, lightYellow], glyph: navy, fileName: "AppIcon.png")
// Dark: yellow ₹ on deep navy.
renderIcon(
    background: [CGColor(red: 0.02, green: 0.07, blue: 0.16, alpha: 1), navy],
    glyph: yellow,
    fileName: "AppIcon-Dark.png"
)
// Tinted: the system tints a grayscale glyph on black.
renderIcon(
    background: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1)],
    glyph: CGColor(gray: 1, alpha: 1),
    fileName: "AppIcon-Tinted.png"
)
