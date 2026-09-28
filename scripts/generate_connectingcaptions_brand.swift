#!/usr/bin/env swift

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func makeImage(width: Int, height: Int, opaque: Bool = false, draw: (NSRect) -> Void) -> NSImage {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Could not create bitmap \(width)x\(height)\n", stderr)
        exit(1)
    }

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(rep)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    if opaque {
        NSColor(srgbRed: 0.027, green: 0.055, blue: 0.086, alpha: 1).setFill()
        rect.fill()
    } else {
        NSColor.clear.setFill()
        rect.fill()
    }
    draw(rect)

    NSGraphicsContext.restoreGraphicsState()
    return image
}

func savePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("Failed to encode \(url.lastPathComponent)\n", stderr)
        exit(1)
    }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

/// Caption gold. Matches AccentColor.
let captionGold = NSColor(srgbRed: 0.910, green: 0.647, blue: 0.294, alpha: 1)
/// "I speak" amber (#E8A04A) and "Show as" teal (#3ECFB8). Matches b-link.svg.
let linkAmber = NSColor(srgbRed: 0.910, green: 0.627, blue: 0.290, alpha: 1)
let linkTeal = NSColor(srgbRed: 0.243, green: 0.812, blue: 0.722, alpha: 1)
let plateTop = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.196, alpha: 1)
let plateBottom = NSColor(srgbRed: 0.039, green: 0.059, blue: 0.090, alpha: 1)

/// Concept B "Link": two Cs woven like chain links. Geometry is in the
/// 1024-unit, y-down space of b-link.svg. Matches `ConnectingCaptionsLinkMark`.
enum LinkMark {
    static let bounds = CGRect(x: 236, y: 327, width: 532, height: 370)
    static let amberCenter = CGPoint(x: 421, y: 512)
    static let tealCenter = CGPoint(x: 611, y: 512)
    static let radius: CGFloat = 142
    static let strokeWidth: CGFloat = 86
    static let cutWidth: CGFloat = 150

    static func draw(in rect: CGRect, amber: NSColor, teal: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        // Amber C, mouth open to the right. Cut where teal passes over it at the bottom crossing.
        strokeRing(ctx, center: amberCenter, from: 40, to: 320, color: amber.cgColor,
                   cutCenter: tealCenter, cutFrom: 100, cutTo: 164, cutCap: .butt)
        // Teal C, wider mouth so the opening survives an 18pt template.
        // Cut where amber passes over it at the top crossing.
        strokeRing(ctx, center: tealCenter, from: 37, to: 323, color: teal.cgColor,
                   cutCenter: amberCenter, cutFrom: -78, cutTo: -22, cutCap: .round)
        ctx.restoreGState()
    }

    private static func strokeRing(
        _ ctx: CGContext, center: CGPoint, from: CGFloat, to: CGFloat, color: CGColor,
        cutCenter: CGPoint, cutFrom: CGFloat, cutTo: CGFloat, cutCap: CGLineCap
    ) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round)
        ctx.setLineWidth(strokeWidth)
        ctx.addArc(center: center, radius: radius, startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: false)
        ctx.strokePath()
        ctx.setBlendMode(.clear)
        ctx.setLineCap(cutCap)
        ctx.setLineWidth(cutWidth)
        ctx.addArc(center: cutCenter, radius: radius, startAngle: cutFrom * .pi / 180, endAngle: cutTo * .pi / 180, clockwise: false)
        ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

/// App icon on the macOS grid: 824/1024 plate, 185/1024 corner radius.
func drawCaptionIcon(in rect: NSRect, size: CGFloat) {
    let unit = size / 1024
    let canvas = rect.insetBy(dx: 100 * unit, dy: 100 * unit)
    let corner = 185 * unit
    let plate = NSBezierPath(roundedRect: canvas, xRadius: corner, yRadius: corner)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: plate, angle: -90)
    // Mark sits at the same place as in b-link.svg (x 236-768 of 1024).
    let mark = NSRect(
        x: rect.minX + LinkMark.bounds.minX * unit,
        y: rect.minY + (1024 - LinkMark.bounds.maxY) * unit,
        width: LinkMark.bounds.width * unit,
        height: LinkMark.bounds.height * unit
    )
    LinkMark.draw(in: mark, amber: linkAmber, teal: linkTeal)
}

/// Menu bar mark, 22×18pt template. The Link mark in a single ink.
func drawMenuBarIcon(in rect: NSRect) {
    LinkMark.draw(in: rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.04), amber: .black, teal: .black)
}

func wordmarkName(fontSize: CGFloat) -> NSAttributedString {
    let name = NSMutableAttributedString()
    name.append(NSAttributedString(
        string: "Connecting ",
        attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
    ))
    name.append(NSAttributedString(
        string: "Captions",
        attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: linkAmber,
        ]
    ))
    return name
}

func drawWordmark(in rect: NSRect) {
    let available = rect.width * 0.88
    var fontSize = rect.height * 0.42
    var name = wordmarkName(fontSize: fontSize)
    var nameSize = name.size()
    let markAspect = LinkMark.bounds.width / LinkMark.bounds.height
    var markWidth = nameSize.height * markAspect
    var gap = nameSize.height * 0.28
    while markWidth + gap + nameSize.width > available, fontSize > 12 {
        fontSize *= 0.94
        name = wordmarkName(fontSize: fontSize)
        nameSize = name.size()
        markWidth = nameSize.height * markAspect
        gap = nameSize.height * 0.28
    }
    let total = markWidth + gap + nameSize.width
    let originX = (rect.width - total) / 2
    let originY = (rect.height - nameSize.height) / 2
    let markRect = NSRect(x: originX, y: originY, width: markWidth, height: nameSize.height)
    LinkMark.draw(in: markRect, amber: linkAmber, teal: linkTeal)
    name.draw(at: NSPoint(x: originX + markWidth + gap, y: originY))
}

let iconDir = repoRoot.appendingPathComponent("Sources/ConnectingCaptions/Assets.xcassets/AppIcon.appiconset")
let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon-16@1x.png", 16, 1),
    ("icon-16@2x.png", 16, 2),
    ("icon-32@1x.png", 32, 1),
    ("icon-32@2x.png", 32, 2),
    ("icon-128@1x.png", 128, 1),
    ("icon-128@2x.png", 128, 2),
    ("icon-256@1x.png", 256, 1),
    ("icon-256@2x.png", 256, 2),
    ("icon-512@1x.png", 512, 1),
    ("icon-512@2x.png", 512, 2),
]

for spec in sizes {
    let pixels = Int(spec.points * spec.scale)
    savePNG(
        makeImage(width: pixels, height: pixels, opaque: false) { rect in
            drawCaptionIcon(in: rect, size: CGFloat(pixels))
        },
        to: iconDir.appendingPathComponent(spec.name)
    )
}

let menuDir = repoRoot.appendingPathComponent("Sources/ConnectingCaptions/Assets.xcassets/MenuBarIcon.imageset")
for (name, scale) in [("menubar-icon.png", 1), ("menubar-icon@2x.png", 2), ("menubar-icon@3x.png", 3)] {
    savePNG(
        makeImage(width: 22 * scale, height: 18 * scale) { rect in
            drawMenuBarIcon(in: rect)
        },
        to: menuDir.appendingPathComponent(name)
    )
}

let wordDir = repoRoot.appendingPathComponent("Sources/ConnectingCaptions/Assets.xcassets/BrandWordmark.imageset")
savePNG(
    makeImage(width: 1024, height: 512, opaque: true) { rect in
        drawWordmark(in: rect)
    },
    to: wordDir.appendingPathComponent("BrandWordmark.png")
)
savePNG(
    makeImage(width: 2048, height: 1024, opaque: true) { rect in
        drawWordmark(in: rect)
    },
    to: wordDir.appendingPathComponent("BrandWordmark@2x.png")
)

print("Generated Connecting Captions brand assets.")
