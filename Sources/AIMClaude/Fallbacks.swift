import SwiftUI

/// An original stick-figure runner used when no logo.png is in the skin folder.
struct FallbackRunner: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            ctx.fill(Path(ellipseIn: CGRect(origin: p(52, 4), size: CGSize(width: 20 * s, height: 20 * s))), with: .color(.yellow))
            var body = Path()
            body.move(to: p(58, 28)); body.addLine(to: p(46, 60))   // torso
            body.move(to: p(55, 34)); body.addLine(to: p(78, 44))   // front arm
            body.move(to: p(55, 34)); body.addLine(to: p(30, 36))   // back arm
            body.move(to: p(46, 60)); body.addLine(to: p(66, 78)); body.addLine(to: p(60, 96)) // front leg
            body.move(to: p(46, 60)); body.addLine(to: p(30, 80)); body.addLine(to: p(12, 82)) // back leg
            ctx.stroke(body, with: .color(.yellow), style: StrokeStyle(lineWidth: 9 * s, lineCap: .round, lineJoin: .round))
            ctx.stroke(body, with: .color(.black), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round, lineJoin: .round))
        }
    }
}
