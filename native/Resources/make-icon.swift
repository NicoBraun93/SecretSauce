// Generates the SecretSauce app icon entirely in code (no design tools needed).
//
// Motif: a sauce droplet with an empty keyhole cut into it — "secret" + "sauce".
// Styled per the brand design system (Design_System/foundations): electric-blue
// droplet on a near-black brand surface, no gradients, a subtle blue glow as the
// signature elevation cue.
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

// --- Brand palette (Design_System/foundations/tokens.css) ---
let brandSurface = color(0.051, 0.059, 0.071) // #0d0f12 — app canvas / dark surface
let brandStroke  = color(0.16, 0.18, 0.235)   // subtle tile edge for definition on dark Docks
let brandBlue    = color(0.231, 0.510, 0.961)  // #3b82f5 — electric blue (primary)

/// Rounded-rect "squircle" tile path, inset to leave a margin for the icon shadow/glow.
func tilePath() -> CGPath {
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    return CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)
}

/// Outer droplet silhouette (pointed top, round bottom).
/// Sits slightly above the tile's vertical center so the top/bottom margins
/// feel balanced (108 vs 120 px in the 1024 space).
func dropletPath() -> CGPath {
    let p = CGMutablePath()
    let cx: CGFloat = 512
    let bottomCenter = CGPoint(x: cx, y: 572)
    let r: CGFloat = 232
    let tip = CGPoint(x: cx, y: 208)
    p.move(to: tip)
    p.addCurve(to: CGPoint(x: bottomCenter.x - r, y: bottomCenter.y),
               control1: CGPoint(x: cx - 36, y: 390),
               control2: CGPoint(x: bottomCenter.x - r, y: bottomCenter.y - 150))
    p.addArc(center: bottomCenter, radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
    p.addCurve(to: tip,
               control1: CGPoint(x: bottomCenter.x + r, y: bottomCenter.y - 150),
               control2: CGPoint(x: cx + 36, y: 390))
    p.closeSubpath()
    return p
}

/// Keyhole = round head + tapered slot. Built from two overlapping subpaths that
/// are merged with NON-ZERO winding (not even-odd), so the overlap does not cancel
/// out — giving one clean empty keyhole with no seam line.
func keyholePath() -> CGPath {
    let p = CGMutablePath()
    let cx: CGFloat = 512
    // Head circle centered exactly on the droplet's round bulb (572).
    let headCenter = CGPoint(x: cx, y: 572)
    let headR: CGFloat = 86
    p.addEllipse(in: CGRect(x: headCenter.x - headR, y: headCenter.y - headR,
                            width: headR * 2, height: headR * 2))
    // Slot starts at the head's center so it fuses smoothly into the circle;
    // it ends 60 px above the bulb's bottom edge (804) to keep a solid rim.
    p.move(to: CGPoint(x: cx - 30, y: headCenter.y))
    p.addLine(to: CGPoint(x: cx + 30, y: headCenter.y))
    p.addLine(to: CGPoint(x: cx + 53, y: 744))
    p.addLine(to: CGPoint(x: cx - 53, y: 744))
    p.closeSubpath()
    return p
}

func drawIcon(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(px) / 1024.0
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: scale, y: -scale) // top-left origin, y grows downward

    // 1. Solid dark brand tile with a faint edge stroke for definition on dark backdrops.
    ctx.saveGState()
    ctx.addPath(tilePath())
    ctx.setFillColor(brandSurface)
    ctx.fillPath()
    ctx.addPath(tilePath())
    ctx.setStrokeColor(brandStroke)
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // 2. Electric-blue droplet, with a soft blue glow (the brand's elevation cue).
    ctx.saveGState()
    ctx.addPath(tilePath())
    ctx.clip() // keep the glow inside the tile
    ctx.setShadow(offset: .zero, blur: 46, color: color(0.231, 0.510, 0.961, 0.55))
    ctx.addPath(dropletPath())
    ctx.setFillColor(brandBlue)
    ctx.fillPath()
    ctx.restoreGState()

    // 3. Punch the empty keyhole by filling it with the tile colour (non-zero winding,
    //    so the circle+slot overlap merges cleanly with no seam).
    ctx.saveGState()
    ctx.addPath(keyholePath())
    ctx.setFillColor(brandSurface)
    ctx.fillPath()
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
