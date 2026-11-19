import SwiftUI

/// Two-pixel Win98 bevel: outer and inner edges, each split into top-left and bottom-right colors.
struct Bevel: ViewModifier {
    let outerTL: Color, outerBR: Color, innerTL: Color, innerBR: Color

    func body(content: Content) -> some View {
        content
            .padding(2)
            .overlay(
                Canvas { ctx, size in
                    func edge(_ inset: CGFloat, _ tl: Color, _ br: Color) {
                        let r = CGRect(origin: .zero, size: size).insetBy(dx: inset + 0.5, dy: inset + 0.5)
                        var a = Path()
                        a.move(to: CGPoint(x: r.minX, y: r.maxY)); a.addLine(to: CGPoint(x: r.minX, y: r.minY)); a.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                        var b = Path()
                        b.move(to: CGPoint(x: r.maxX, y: r.minY)); b.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); b.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                        ctx.stroke(a, with: .color(tl), lineWidth: 1)
                        ctx.stroke(b, with: .color(br), lineWidth: 1)
                    }
                    edge(0, outerTL, outerBR)
                    edge(1, innerTL, innerBR)
                }
                .allowsHitTesting(false)
            )
    }
}

extension Bevel {
    static let raised = Bevel(outerTL: AIMColors.highlight, outerBR: AIMColors.darkShadow, innerTL: AIMColors.light, innerBR: AIMColors.shadow)
    static let sunken = Bevel(outerTL: AIMColors.shadow, outerBR: AIMColors.highlight, innerTL: AIMColors.darkShadow, innerBR: AIMColors.light)
}

extension View {
    func bevelRaised() -> some View {
        modifier(Bevel.raised)
    }

    func bevelSunken() -> some View {
        modifier(Bevel.sunken)
    }

    /// A one-pixel etched line group frame, as used around AIM's panels.
    func etched() -> some View {
        modifier(Bevel(outerTL: AIMColors.shadow, outerBR: AIMColors.highlight, innerTL: AIMColors.highlight, innerBR: AIMColors.shadow))
    }
}
