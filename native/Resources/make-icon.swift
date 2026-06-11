// Generates the SecretSauce app icon entirely in code (no design tools needed).
//
// Motif: a sauce droplet whose negative space forms a keyhole — "secret" + "sauce" —
// sitting on a vibrant purple→magenta gradient squircle in the macOS Big Sur style.
//
// Usage: swiftc make-icon.swift -o /tmp/makeicon && /tmp/makeicon <output-iconset-dir> <readme-png>
// All drawing is done in a 1024×1024 top-left coordinate space and scaled per size.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpaceCreateDeviceRGB()

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

/// Rounded-rect "squircle" tile path, inset to leave a margin for the icon shadow.
func tilePath() -> CGPath {
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    return CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)
}

/// Droplet + keyhole foreground, built as one even-odd path so the keyhole is a true
/// cut-out revealing the gradient behind it.
func dropletKeyholePath() -> CGPath {
    let p = CGMutablePath()

    // --- Outer droplet silhouette (pointed top, round bottom) ---
    let cx: CGFloat = 512
    let bottomCenter = CGPoint(x: cx, y: 612)
    let r: CGFloat = 232
    let tip = CGPoint(x: cx, y: 248)
    p.move(to: tip)
    // Left flank curving down to the left side of the bottom circle.
    p.addCurve(to: CGPoint(x: bottomCenter.x - r, y: bottomCenter.y),
               control1: CGPoint(x: cx - 36, y: 430),
               control2: CGPoint(x: bottomCenter.x - r, y: bottomCenter.y - 150))
    // Bottom semicircle (left → right, sweeping through the bottom).
    p.addArc(center: bottomCenter, radius: r,
             startAngle: .pi, endAngle: 0, clockwise: true)
    // Right flank curving back up to the tip.
    p.addCurve(to: tip,
               control1: CGPoint(x: bottomCenter.x + r, y: bottomCenter.y - 150),
               control2: CGPoint(x: cx + 36, y: 430))
    p.closeSubpath()

    // --- Keyhole cut-out: round head + tapered slot ---
    let headCenter = CGPoint(x: cx, y: 560)
    p.addEllipse(in: CGRect(x: headCenter.x - 92, y: headCenter.y - 92, width: 184, height: 184))

    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: cx - 52, y: 612))
    slot.addLine(to: CGPoint(x: cx + 52, y: 612))
    slot.addLine(to: CGPoint(x: cx + 86, y: 792))
    slot.addLine(to: CGPoint(x: cx - 86, y: 792))
    slot.closeSubpath()
    p.addPath(slot)

    return p
}

func drawIcon(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(px) / 1024.0
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: scale, y: -scale) // top-left origin, y grows downward

    // 1. Gradient-filled tile.
    ctx.saveGState()
    ctx.addPath(tilePath())
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [color(0.51, 0.34, 1.0), color(0.76, 0.23, 0.84)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 140, y: 140), end: CGPoint(x: 884, y: 884),
                           options: [])

    // 2. Soft top sheen for a glossy, dimensional look.
    let sheen = CGGradient(colorsSpace: cs,
                           colors: [color(1, 1, 1, 0.22), color(1, 1, 1, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 120), end: CGPoint(x: 512, y: 560),
                           options: [])
    ctx.restoreGState()

    // 3. White droplet/keyhole with a soft drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 34, color: color(0.05, 0.0, 0.15, 0.35))
    ctx.addPath(dropletKeyholePath())
    ctx.setFillColor(color(1, 1, 1, 0.97))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// --- Entry point ---
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: makeicon <iconset-dir> <readme-png>\n".data(using: .utf8)!)
    exit(1)
}
let iconsetDir = args[1]
let readmePNG = args[2]

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// iconset entries: (pixel size, filename)
let entries: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

var cache: [Int: CGImage] = [:]
for (size, name) in entries {
    let img = cache[size] ?? drawIcon(px: size)
    cache[size] = img
    writePNG(img, to: "\(iconsetDir)/\(name)")
}

// A standalone 512px PNG for the README.
writePNG(cache[512] ?? drawIcon(px: 512), to: readmePNG)
print("Rendered \(entries.count) iconset images + README icon.")
