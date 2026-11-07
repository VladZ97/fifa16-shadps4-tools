// SPDX-License-Identifier: GPL-2.0-or-later
// Original app icon for the F16 launcher: teal gradient, a ring badge with a football on top,
// "F 16" in heavy italics below. Drawn here from scratch: no game artwork, no logos, no
// trademarked word marks.
//   swift draw_icon.swift <out.png> [size]      (default 1024)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = CGFloat(CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024)
let s = size / 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let space = CGColorSpaceCreateDeviceRGB()

// Rounded square (macOS icon shape)
let inset = 100 * s
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)); ctx.clip()

// Teal gradient, lighter top-left, deeper bottom-right
let teal = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.16, green: 0.72, blue: 0.80, alpha: 1),
    CGColor(red: 0.07, green: 0.56, blue: 0.68, alpha: 1),
    CGColor(red: 0.04, green: 0.44, blue: 0.58, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(teal, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

// Faint diagonal light streaks
ctx.saveGState()
ctx.setBlendMode(.plusLighter)
for (i, (x, w, a)) in [(0.05, 0.38, 0.06), (0.30, 0.20, 0.04), (0.62, 0.30, 0.05), (0.86, 0.10, 0.04)].enumerated() {
    let p = CGMutablePath()
    let x0 = rect.minX + CGFloat(x) * rect.width, w0 = CGFloat(w) * rect.width
    let skew = rect.height * (i % 2 == 0 ? 0.55 : -0.35)
    p.move(to: CGPoint(x: x0, y: rect.minY)); p.addLine(to: CGPoint(x: x0 + w0, y: rect.minY))
    p.addLine(to: CGPoint(x: x0 + w0 + skew, y: rect.maxY)); p.addLine(to: CGPoint(x: x0 + skew, y: rect.maxY)); p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(CGColor(gray: 1, alpha: CGFloat(a))); ctx.fillPath()
}
ctx.restoreGState()
ctx.restoreGState()

// Ring badge with a football inside
let bc = CGPoint(x: size / 2, y: rect.maxY - 265 * s), br = 150 * s
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(30 * s)
ctx.strokeEllipse(in: CGRect(x: bc.x - br, y: bc.y - br, width: 2 * br, height: 2 * br))
func pentagon(_ centre: CGPoint, _ radius: CGFloat, _ rot: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for k in 0..<5 {
        let a = rot + CGFloat(k) * 2 * .pi / 5
        let pt = CGPoint(x: centre.x + radius * cos(a), y: centre.y + radius * sin(a))
        k == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath(); return p
}
let ballR = 92 * s
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: bc.x - ballR, y: bc.y - ballR, width: 2 * ballR, height: 2 * ballR))
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: bc.x - ballR, y: bc.y - ballR, width: 2 * ballR, height: 2 * ballR)); ctx.clip()
ctx.setFillColor(CGColor(red: 0.04, green: 0.44, blue: 0.58, alpha: 1))
ctx.addPath(pentagon(bc, 36 * s, .pi / 2)); ctx.fillPath()
for k in 0..<5 {
    let a = .pi / 2 + CGFloat(k) * 2 * .pi / 5 + .pi / 5
    let centre = CGPoint(x: bc.x + 100 * s * cos(a), y: bc.y + 100 * s * sin(a))
    ctx.addPath(pentagon(centre, 30 * s, a + .pi)); ctx.fillPath()
}
ctx.setStrokeColor(CGColor(red: 0.04, green: 0.44, blue: 0.58, alpha: 1)); ctx.setLineWidth(5 * s)
for k in 0..<5 {
    let a = .pi / 2 + CGFloat(k) * 2 * .pi / 5
    ctx.move(to: CGPoint(x: bc.x + 36 * s * cos(a), y: bc.y + 36 * s * sin(a)))
    ctx.addLine(to: CGPoint(x: bc.x + 72 * s * cos(a), y: bc.y + 72 * s * sin(a)))
}
ctx.strokePath()
ctx.restoreGState()

// "F" white and "16" yellow, heavy italic, bottom
func draw(_ text: String, at origin: CGPoint, color: NSColor, pt: CGFloat) -> CGFloat {
    let font = NSFont(name: "Helvetica-BoldOblique", size: pt) ?? NSFont.boldSystemFont(ofSize: pt)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: -pt * 0.04]
    let str = NSAttributedString(string: text, attributes: attrs)
    str.draw(at: origin)
    return str.size().width
}
let pt = 265 * s
let fw = NSAttributedString(string: "F", attributes: [.font: NSFont(name: "Helvetica-BoldOblique", size: pt) ?? NSFont.boldSystemFont(ofSize: pt), .kern: -pt * 0.04]).size().width
let nw = NSAttributedString(string: "16", attributes: [.font: NSFont(name: "Helvetica-BoldOblique", size: pt) ?? NSFont.boldSystemFont(ofSize: pt), .kern: -pt * 0.04]).size().width
let total = fw + nw + 10 * s
let x0 = size / 2 - total / 2, y0 = rect.minY + 70 * s
_ = draw("F", at: CGPoint(x: x0, y: y0), color: .white, pt: pt)
_ = draw("16", at: CGPoint(x: x0 + fw + 10 * s, y: y0), color: NSColor(red: 1.0, green: 0.85, blue: 0.15, alpha: 1), pt: pt)

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(Int(size))x\(Int(size))")
