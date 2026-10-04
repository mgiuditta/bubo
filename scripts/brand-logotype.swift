#!/usr/bin/env swift
// Rigenera design/brand/logotype.svg: «bubo» in Newsreader Medium convertito in tracciati, con la sagoma del gufo
// del glifo della barra dei menu a sinistra, alta quanto la x e poggiata sulla linea di base.
// Uso: swift scripts/brand-logotype.swift (dalla radice del repo).

import CoreText
import Foundation

let fontURL = URL(fileURLWithPath: "Bubo/Resources/Fonts/Newsreader.ttf")
var error: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) else {
    fatalError("Newsreader non registrato: \(String(describing: error?.takeRetainedValue()))")
}

let size: CGFloat = 100
let font = CTFontCreateWithName("NewsreaderRoman-Medium" as CFString, size, nil)
guard (CTFontCopyPostScriptName(font) as String) == "NewsreaderRoman-Medium" else {
    fatalError("NewsreaderRoman-Medium non trovato")
}
let xHeight = CTFontGetXHeight(font)
let ascent = CTFontGetAscent(font)
let descent = CTFontGetDescent(font)

// The owl of menu-bar-glyph.svg spans y 1.3…16.9 in its 18-pt square, x 0.4…17.6 roughly.
let owlPath = "M3.26 7.35 Q2.2 4.4 2.2 1.3 Q3.4 4.2 5.75 4.77 L9 6.3 L12.25 4.77 Q14.6 4.2 15.8 1.3 Q15.8 4.4 14.74 7.35 A6.5 6.5 0 1 1 3.26 7.35 Z M6 8 a2 2 0 1 0 0 4 a2 2 0 1 0 0 -4 Z M12 8 a2 2 0 1 0 0 4 a2 2 0 1 0 0 -4 Z M8 12.4 L10 12.4 L9 14.6 Z"
let owlTop: CGFloat = 1.3, owlBottom: CGFloat = 16.9, owlLeft: CGFloat = 2.2, owlRight: CGFloat = 15.8
let owlScale = xHeight / (owlBottom - owlTop)
let owlWidth = (owlRight - owlLeft) * owlScale
let gap = 0.4 * xHeight

// SVG coordinates: baseline at y = ascent, y grows downwards.
let baseline = ascent
let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: "bubo", attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
)
let textLeft = owlWidth + gap

func svgPath(of path: CGPath, dx: CGFloat) -> String {
    var d = ""
    func p(_ point: CGPoint) -> String {
        String(format: "%.2f %.2f", point.x + dx, baseline - point.y)
    }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: d += "M\(p(e.points[0]))"
        case .addLineToPoint: d += "L\(p(e.points[0]))"
        case .addQuadCurveToPoint: d += "Q\(p(e.points[0])) \(p(e.points[1]))"
        case .addCurveToPoint: d += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

var wordmark = ""
var textRight: CGFloat = textLeft
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    var advances = [CGSize](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(), &glyphs)
    CTRunGetPositions(run, CFRange(), &positions)
    CTRunGetAdvances(run, CFRange(), &advances)
    for index in 0..<count {
        guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
        wordmark += svgPath(of: glyphPath, dx: textLeft + positions[index].x)
        textRight = max(textRight, textLeft + positions[index].x + advances[index].width)
    }
}

let width = textRight
let height = ascent + descent
let owlX = -owlLeft * owlScale
let owlY = baseline - owlBottom * owlScale
let svg = """
<?xml version="1.0" encoding="UTF-8"?>
<!-- Logotipo di Bubo (brand kit, #690): «bubo» in Newsreader Medium in tracciati, gufo del glifo alto quanto la x.
     Generato da scripts/brand-logotype.swift: non modificare a mano. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(String(format: "%.2f %.2f", width, height))" fill="#ECEEF1">
  <path fill-rule="evenodd" transform="translate(\(String(format: "%.3f %.3f", owlX, owlY))) scale(\(String(format: "%.4f", owlScale)))" d="\(owlPath)"/>
  <path d="\(wordmark)"/>
</svg>

"""
try svg.write(toFile: "design/brand/logotype.svg", atomically: true, encoding: .utf8)
print("design/brand/logotype.svg \(Int(width))×\(Int(height))")
