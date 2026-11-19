import AIMCore
import Foundation
import SwiftUI

enum Fallbacks {
    /// Original tones, not AOL's sounds: (frequency Hz, duration s) segments.
    static func tone(for cue: SoundCue) -> Data {
        switch cue {
        case .buddyIn: wav([(660, 0.08), (880, 0.12)])
        case .buddyOut: wav([(880, 0.08), (520, 0.14)])
        case .message: wav([(990, 0.06), (0, 0.03), (990, 0.06)])
        case .welcome: wav([(523, 0.1), (659, 0.1), (784, 0.16)])
        case .goodbye: wav([(784, 0.1), (659, 0.1), (523, 0.16)])
        }
    }

    /// 8-bit mono PCM WAV, 22.05 kHz, with a short fade on each segment.
    static func wav(_ segments: [(Double, Double)]) -> Data {
        let rate = 22050
        var samples: [UInt8] = []
        for (freq, dur) in segments {
            let n = Int(Double(rate) * dur)
            for i in 0..<n {
                let fade = min(1, Double(min(i, n - i)) / 200)
                let v = freq == 0 ? 0 : sin(2 * .pi * freq * Double(i) / Double(rate)) * 0.35 * fade
                samples.append(UInt8(clamping: Int(128 + v * 127)))
            }
        }
        var d = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + samples.count)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate); u16(1); u16(8)
        d.append(contentsOf: Array("data".utf8)); u32(samples.count)
        d.append(contentsOf: samples)
        return d
    }
}

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
