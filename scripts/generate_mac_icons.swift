#!/usr/bin/env swift

import SwiftUI
import AppKit
import Foundation

// Generates the macOS app icon set from a single square source image.
//
// macOS icons (unlike iOS, which the system auto-masks) must ship the Big Sur
// "squircle" baked in: an 824pt rounded-square body centered in a 1024pt canvas
// with continuous corner curvature, a subtle drop shadow, and transparent
// margins/corners. This renders each catalog size natively (not downscaled from
// one master) for crisp anti-aliasing, and writes 16/32/64/128/256/512/1024.
//
// Re-run this whenever app_icon.png changes.
//
// Usage:
//   scripts/generate_mac_icons.swift [source.png] [outDir]
//
// Defaults (relative to the repo root) reproduce the committed icon set:
//   source = app_icon.png
//   outDir = mac_client/DJukeboxMac/DJukeboxMac/Assets.xcassets/AppIcon.appiconset

let defaultSource = "app_icon.png"
let defaultOutDir = "mac_client/DJukeboxMac/DJukeboxMac/Assets.xcassets/AppIcon.appiconset"

let args = CommandLine.arguments
let srcPath = args.count > 1 ? args[1] : defaultSource
let outDir = args.count > 2 ? args[2] : defaultOutDir

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard let srcNS = NSImage(contentsOfFile: srcPath) else {
    fail("cannot load source image: \(srcPath)")
}
let srcImage = Image(nsImage: srcNS)

// Big Sur macOS icon grid, expressed in a normalized 1024pt canvas.
let canvasSize: CGFloat = 1024
let bodySize: CGFloat = 824          // rounded-square body (100pt margin each side)
let radius: CGFloat = 185.4          // continuous corner radius (~0.225 * body)

struct IconView: View {
    let image: Image
    var body: some View {
        image
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: bodySize, height: bodySize)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 8)
            .frame(width: canvasSize, height: canvasSize)
    }
}

// mac idiom pixel sizes referenced by the asset catalog's Contents.json.
let sizes = [16, 32, 64, 128, 256, 512, 1024]

MainActor.assumeIsolated {
    for p in sizes {
        let renderer = ImageRenderer(content: IconView(image: srcImage))
        renderer.scale = CGFloat(p) / canvasSize
        guard let cg = renderer.cgImage else { fail("render failed at \(p)px") }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: p, height: p)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fail("png encode failed at \(p)px")
        }
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(p).png")
        do {
            try data.write(to: url)
            print("wrote \(url.lastPathComponent) (\(cg.width)x\(cg.height))")
        } catch {
            fail("write failed \(url.path): \(error)")
        }
    }
}
