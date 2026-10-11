#!/usr/bin/env swift
// Renders the app icon from scratch: a dark navy → grey-green gradient with a white, heavy system-font "Ü".
// The style is a homage to the original Bruce Studios icon (colours and letter box approximated from it:
// x 0.27–0.75, y 0.26–0.74); no original artwork is embedded or copied. Trademark-sensitive, see README.
// Writes 1024 px light (opaque), dark and tinted variants.
// Usage: swift scripts/make-icon.swift BruceiOS/Assets.xcassets/AppIcon.appiconset [preview.png]
import AppKit
import CoreText

let args = Array(CommandLine.arguments.dropFirst())
let outDir = args.first ?? "."
let preview = args.count > 1 ? args[1] : nil
let S: CGFloat = 1024

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

enum Variant: String { case light, dark, tinted }

/// "U" outline from a heavy, slightly wide system face, fitted to the original letter box,
/// plus two round dots (diameter = stem width) for the umlaut.
func letterPath() -> CGPath {
    let base = NSFont.systemFont(ofSize: 400, weight: .black)
    let desc = base.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.width: 0.15, NSFontDescriptor.TraitKey.weight: NSFont.Weight.black]])
    let font = (NSFont(descriptor: desc, size: 400) ?? base) as CTFont
    var ch: [UniChar] = Array("U".utf16), g = [CGGlyph](repeating: 0, count: 1)
    CTFontGetGlyphsForCharacters(font, &ch, &g, 1)
    let raw = CTFontCreatePathForGlyph(font, g[0], nil)!
    let b = raw.boundingBoxOfPath
    // Target: same box as the original B, nudged down to leave room for the dots (CG origin is bottom-left).
    let box = CGRect(x: 0.27 * S, y: (1 - 0.785) * S, width: 0.48 * S, height: 0.48 * S)
    var t = CGAffineTransform(translationX: box.minX, y: box.minY)
        .scaledBy(x: box.width / b.width, y: box.height / b.height)
        .translatedBy(x: -b.minX, y: -b.minY)
    let u = raw.copy(using: &t)!
    // Stem width: scan the fitted glyph at mid height from the left edge.
    var stem: CGFloat = 0.11 * S
    let y = box.midY
    var x = box.minX
    while x < box.midX { if !u.contains(CGPoint(x: x, y: y)) { stem = x - box.minX; break }; x += 1 }
    let path = CGMutablePath()
    path.addPath(u)
    let d = min(stem * 0.78, 0.105 * S), gap = 0.05 * S, cy = box.maxY + gap + d / 2
    for cx in [box.minX + stem / 2 + 0.01 * S, box.maxX - stem / 2 - 0.01 * S] {
        path.addEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
    }
    return path
}

func render(_ v: Variant) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: v == .light ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    switch v {
    case .light, .dark:
        // Vertical blend sampled from the original: navy top, slate middle, grey-green bottom.
        let stops: [(CGFloat, UInt32)] = v == .light
            ? [(0, 0x1A2C38), (0.42, 0x2E4246), (0.72, 0x667369), (1, 0xA9B099)]
            : [(0, 0x050B14), (0.5, 0x15222A), (1, 0x3E4840)]
        let g = CGGradient(colorsSpace: space, colors: stops.map { hex($0.1) } as CFArray, locations: stops.map { $0.0 })!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
        // Darker top-left corner and soft blue-slate glow on the right, as in the original.
        let corner = CGGradient(colorsSpace: space, colors: [hex(0x021226, 0.9), hex(0x021226, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(corner, startCenter: CGPoint(x: 0, y: S), startRadius: 0, endCenter: CGPoint(x: 0, y: S), endRadius: S * 0.55, options: [])
        let glow = CGGradient(colorsSpace: space, colors: [hex(0x2D4349, 0.8), hex(0x2D4349, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S, y: S * 0.6), startRadius: 0, endCenter: CGPoint(x: S, y: S * 0.6), endRadius: S * 0.45, options: [])
    case .tinted:
        let g = CGGradient(colorsSpace: space, colors: [hex(0x2A2A2A), hex(0x0A0A0A)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    }
    ctx.addPath(letterPath())
    ctx.setFillColor(hex(0xFFFFFF))
    ctx.fillPath()
    return ctx.makeImage()!
}

func png(_ img: CGImage) -> Data { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])! }

var images: [CGImage] = []
for v in [Variant.light, .dark, .tinted] {
    let img = render(v); images.append(img)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon-\(v.rawValue).png")
    try! png(img).write(to: url)
    print("wrote \(url.path)")
}
if let preview {
    // Side-by-side preview with the iOS icon mask (squircle-ish rounded rect).
    let w = 3 * 360 + 4 * 30, h = 420
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(hex(0xE9E9EE)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (i, img) in images.enumerated() {
        let r = CGRect(x: 30 + i * 390, y: 30, width: 360, height: 360)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 80, cornerHeight: 80, transform: nil)); ctx.clip()
        ctx.draw(img, in: r)
        ctx.restoreGState()
    }
    try! png(ctx.makeImage()!).write(to: URL(fileURLWithPath: preview))
    print("wrote \(preview)")
}
