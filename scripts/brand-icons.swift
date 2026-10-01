#!/usr/bin/env swift
// Rigenera le PNG del marchio dai sorgenti SVG di design/brand: le 10 misure di AppIcon.appiconset e il glifo
// modello della barra dei menu a 1× e 2×. Usa solo AppKit (NSImage legge gli SVG): niente da installare.
// Uso: swift scripts/brand-icons.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appending(path: "design/brand")
let assets = root.appending(path: "Bubo/Resources/Assets.xcassets")

/// Draws the SVG at `url` into a square PNG of `points` × `scale` pixels, tagged with the matching density.
func render(_ url: URL, points: Int, scale: Int, to destination: URL) throws {
    guard let image = NSImage(contentsOf: url) else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
    }
    let pixels = points * scale
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }
    let srgb = bitmap.retagging(with: .sRGB) ?? bitmap
    let size = CGSize(width: points, height: points)
    srgb.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: srgb)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = srgb.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: destination)
    print("\(destination.lastPathComponent): \(pixels) px")
}

let icon = brand.appending(path: "app-icon.svg")
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        try render(icon, points: points, scale: scale,
                   to: assets.appending(path: "AppIcon.appiconset/icon_\(points)x\(points)@\(scale)x.png"))
    }
}

let glyph = brand.appending(path: "menu-bar-glyph.svg")
for scale in [1, 2] {
    try render(glyph, points: 18, scale: scale,
               to: assets.appending(path: "MenuBarGlyph.imageset/menu-bar-glyph@\(scale)x.png"))
}
