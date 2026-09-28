import AppKit
import SwiftUI

/// Concept B "Link": two Cs woven like chain links, amber for "I speak" and
/// teal for "Show as". Geometry is in the 1024-unit, y-down space of
/// `docs/brand/concepts/b-link.svg`. Matches `LinkMark` in
/// `scripts/generate_connectingcaptions_brand.swift`.
enum ConnectingCaptionsLinkMark {
    /// #E8A04A. Close to caption gold, light enough to hold at 16pt.
    static let amber = NSColor(srgbRed: 0.910, green: 0.627, blue: 0.290, alpha: 1)
    /// #3ECFB8. Deeper than the first lockup so it separates from the amber.
    static let teal = NSColor(srgbRed: 0.243, green: 0.812, blue: 0.722, alpha: 1)

    /// Tight bounds of both rings, strokes included.
    static let bounds = CGRect(x: 236, y: 327, width: 532, height: 370)
    static var aspectRatio: CGFloat { self.bounds.width / self.bounds.height }

    private static let amberCenter = CGPoint(x: 421, y: 512)
    private static let tealCenter = CGPoint(x: 611, y: 512)
    private static let radius: CGFloat = 142
    private static let strokeWidth: CGFloat = 86
    private static let cutWidth: CGFloat = 150

    /// Draws the mark aspect-fit and centered in `rect` (y-up context).
    static func draw(in rect: CGRect, context ctx: CGContext, amber: CGColor, teal: CGColor) {
        let scale = min(rect.width / self.bounds.width, rect.height / self.bounds.height)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -self.bounds.midX, y: -self.bounds.midY)
        // Amber C, mouth open to the right. Cut where teal passes over it at the bottom crossing.
        self.strokeRing(
            ctx, center: self.amberCenter, from: 40, to: 320, color: amber,
            cutCenter: self.tealCenter, cutFrom: 100, cutTo: 164, cutCap: .butt
        )
        // Teal C, wider mouth so the opening survives an 18pt template.
        // Cut where amber passes over it at the top crossing.
        self.strokeRing(
            ctx, center: self.tealCenter, from: 37, to: 323, color: teal,
            cutCenter: self.amberCenter, cutFrom: -78, cutTo: -22, cutCap: .round
        )
        ctx.restoreGState()
    }

    private static func strokeRing(
        _ ctx: CGContext,
        center: CGPoint,
        from: CGFloat,
        to: CGFloat,
        color: CGColor,
        cutCenter: CGPoint,
        cutFrom: CGFloat,
        cutTo: CGFloat,
        cutCap: CGLineCap
    ) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round)
        ctx.setLineWidth(self.strokeWidth)
        ctx.addArc(center: center, radius: self.radius, startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: false)
        ctx.strokePath()
        // Knock out the crossing so the other ring reads as passing over this one.
        ctx.setBlendMode(.clear)
        ctx.setLineCap(cutCap)
        ctx.setLineWidth(self.cutWidth)
        ctx.addArc(center: cutCenter, radius: self.radius, startAngle: cutFrom * .pi / 180, endAngle: cutTo * .pi / 180, clockwise: false)
        ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

/// Menu bar mark, 22×18pt. The Link mark in a single ink.
/// Matches `drawMenuBarIcon` in `scripts/generate_connectingcaptions_brand.swift`.
enum TheaterMenuBarMark {
    static let pointSize = NSSize(width: 22, height: 18)

    static func draw(in rect: CGRect, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ConnectingCaptionsLinkMark.draw(
            in: rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.04),
            context: ctx,
            amber: color.cgColor,
            teal: color.cgColor
        )
    }
}

/// The Link mark as a SwiftUI view. Two-tone by default; pass `color` for a single ink.
struct FluidIcon: View {
    let size: CGFloat
    let color: Color?

    init(size: CGFloat = 24, lineWidth _: CGFloat = 2.5, color: Color? = nil) {
        self.size = size
        self.color = color
    }

    var body: some View {
        Canvas { context, canvasSize in
            let ink = self.color.map { NSColor($0).cgColor }
            context.withCGContext { cg in
                // Canvas is y-down; the mark draws in a y-up space.
                cg.translateBy(x: 0, y: canvasSize.height)
                cg.scaleBy(x: 1, y: -1)
                ConnectingCaptionsLinkMark.draw(
                    in: CGRect(origin: .zero, size: canvasSize),
                    context: cg,
                    amber: ink ?? ConnectingCaptionsLinkMark.amber.cgColor,
                    teal: ink ?? ConnectingCaptionsLinkMark.teal.cgColor
                )
            }
        }
        .frame(width: self.size, height: self.size)
        .accessibilityHidden(true)
    }
}

struct FluidIconFilled: View {
    let size: CGFloat
    let color: Color?
    let backgroundColor: Color
    let cornerRadius: CGFloat

    init(size: CGFloat = 32, color: Color? = nil, backgroundColor: Color = .blue, cornerRadius: CGFloat = 8) {
        self.size = size
        self.color = color
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .fill(self.backgroundColor)
                .frame(width: self.size, height: self.size)

            FluidIcon(size: self.size * 0.66, color: self.color)
        }
        .accessibilityHidden(true)
    }
}

/// Sidebar identity. The Link mark is the product, not a dictation waveform.
struct TheaterSidebarIdentity: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            FluidIcon(size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(ConnectingCaptionsProduct.displayName)
                    .font(self.theme.typography.sidebarItem)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("Live captions")
                    .font(self.theme.typography.sidebarSection)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ConnectingCaptionsProduct.displayName), live captions")
    }
}

#Preview("Connecting Captions mark") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            FluidIcon(size: 24)
                .background(Color.black.opacity(0.3))
            FluidIcon(size: 32, color: .blue)
            FluidIcon(size: 48)
        }
        HStack(spacing: 20) {
            FluidIconFilled(size: 32, color: .white, backgroundColor: Color(red: 0.91, green: 0.65, blue: 0.29))
            FluidIconFilled(size: 48, backgroundColor: Color(red: 0.04, green: 0.09, blue: 0.14), cornerRadius: 12)
            FluidIconFilled(size: 80, backgroundColor: .black, cornerRadius: 16)
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
