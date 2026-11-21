#!/usr/bin/env swift
// Draws the app icon (an original running figure, not AOL's art) and writes Resources/AppIcon.icns.
//   swift scripts/make-icon.swift
import AppKit

let yellow = CGColor(red: 1.00, green: 0.82, blue: 0.10, alpha: 1)
let yellowBack = CGColor(red: 0.88, green: 0.66, blue: 0.00, alpha: 1)
let ink = CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)

func draw(_ ctx: CGContext) {
    // macOS icon grid: an 824pt rounded square centered on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [CGColor(red: 0.27, green: 0.55, blue: 0.97, alpha: 1),
                                  CGColor(red: 0.07, green: 0.20, blue: 0.58, alpha: 1)] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Speed streaks behind the runner.
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
    ctx.setLineWidth(26)
    for (y, x0, x1) in [(640.0, 200.0, 330.0), (540.0, 170.0, 300.0), (440.0, 210.0, 300.0)] {
        ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // The runner, y up. Back limbs first and a shade darker, then torso, front limbs, head.
    func limb(_ pts: [CGPoint], _ color: CGColor) {
        for (w, c) in [(104.0, ink), (68.0, color)] {
            ctx.setLineWidth(w); ctx.setStrokeColor(c)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addLines(between: pts); ctx.strokePath()
        }
    }
    let shoulder = CGPoint(x: 572, y: 640), hip = CGPoint(x: 488, y: 468)
    limb([shoulder, CGPoint(x: 458, y: 596), CGPoint(x: 396, y: 516)], yellowBack)          // back arm
    limb([hip, CGPoint(x: 400, y: 362), CGPoint(x: 300, y: 330)], yellowBack)               // back leg
    limb([CGPoint(x: 586, y: 668), hip], yellow)                                             // torso
    limb([hip, CGPoint(x: 610, y: 392), CGPoint(x: 590, y: 256), CGPoint(x: 650, y: 248)], yellow) // front leg
    limb([shoulder, CGPoint(x: 676, y: 584), CGPoint(x: 730, y: 660)], yellow)              // front arm
    let head = CGRect(x: 560, y: 712, width: 136, height: 136)
    ctx.setFillColor(ink); ctx.fillEllipse(in: head.insetBy(dx: -18, dy: -18))
    ctx.setFillColor(yellow); ctx.fillEllipse(in: head)
}

func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try png(pt).write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try png(pt * 2).write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try p.run(); p.waitUntilExit()
if CommandLine.arguments.contains("--preview") {
    try png(1024).write(to: URL(fileURLWithPath: CommandLine.arguments.last!))
}
try? FileManager.default.removeItem(at: set)
print(p.terminationStatus == 0 ? out.path : "iconutil failed")
