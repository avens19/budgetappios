#!/usr/bin/env swift
//
// Builds the iOS app icon from the Android launcher artwork, so the two stores
// show the same icon rather than two drawings of the same idea.
//
//   swift Tools/MakeAppIcon.swift <foreground.png> <output.png>
//
// Two details that matter:
//
//   * Android's adaptive icon only ever shows the middle 72 of its 108dp
//     foreground; the rest is bleed for the launcher mask and parallax. iOS's
//     squircle crops far less than Android's circle, so that bleed is drawn as
//     padding rather than scaled away — at 1:1 the glyph fills about two thirds
//     of the canvas, which is the proportion iOS icons normally use. Scaling it
//     up to match Android's crop left the $ touching the top and bottom edges.
//   * iOS icons must be fully opaque with no alpha channel and square corners.
//     The system applies the rounded mask; baking one in gets the build
//     rejected, and an alpha channel gets it rejected too.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: MakeAppIcon.swift <foreground.png> <out.png>\n".utf8))
    exit(2)
}

let size = 1024
/// The Android foreground is not transparent: it carries its own blue panel
/// inside a transparent margin, and that blue is not exactly the declared
/// `ic_launcher_background`. Filling with the declared colour left a visible
/// square seam where the two met, so the fill is sampled from the artwork
/// itself and the join disappears.
func sampledBackground(from image: CGImage) -> CGColor {
    let fallback = CGColor(red: 0x09 / 255.0, green: 0x64 / 255.0, blue: 0xC5 / 255.0, alpha: 1)
    var pixel: [UInt8] = [0, 0, 0, 0]

    // The buffer has to outlive the context, so the pointer is held for the
    // whole draw rather than passed as a temporary.
    let sampled: CGColor? = pixel.withUnsafeMutableBytes { raw -> CGColor? in
        guard let probe = CGContext(
            data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // A point inside the panel but clear of the glyph: horizontally
        // centred, a fifth of the way down from the top.
        let width = Double(image.width), height = Double(image.height)
        let x = width / 2, y = height / 5
        probe.draw(image, in: CGRect(x: -x, y: -(height - y), width: width, height: height))

        let bytes = raw.bindMemory(to: UInt8.self)
        guard bytes[3] > 200 else { return nil }
        return CGColor(red: Double(bytes[0]) / 255.0, green: Double(bytes[1]) / 255.0,
                       blue: Double(bytes[2]) / 255.0, alpha: 1)
    }

    if sampled == nil {
        FileHandle.standardError.write(Data("warning: could not sample, using the declared colour\n".utf8))
    }
    return sampled ?? fallback
}

guard let source = NSImage(contentsOfFile: arguments[1]),
      let foreground = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("could not read \(arguments[1])\n".utf8))
    exit(1)
}

guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    // noneSkipLast: opaque, and no alpha channel in the output.
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create the bitmap context\n".utf8))
    exit(1)
}

context.setFillColor(sampledBackground(from: foreground))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

context.interpolationQuality = .high
// The artwork's opaque panel covers about 77% of its own canvas. Scaling by
// 1/0.77 makes that panel reach every edge, so every pixel in the output comes
// from the same image through the same colour conversion. Filling a background
// and drawing the panel on top left a faint but visible square seam: the PNG
// carries a colour profile and converts slightly differently from a flat fill.
let scale = 1.0 / 0.77
let drawn = Double(size) * scale
let offset = (Double(size) - drawn) / 2
context.draw(foreground, in: CGRect(x: offset, y: offset, width: drawn, height: drawn))

guard let image = context.makeImage() else { exit(1) }
let out = URL(fileURLWithPath: arguments[2])
guard let destination = CGImageDestinationCreateWithURL(
    out as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }

print("wrote \(out.path) at \(size)x\(size)")
