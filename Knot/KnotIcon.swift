import SwiftUI

// MARK: - Knot Icon
// Two interlocked rings representing two ropes tied together.
// The right ring passes in front of the left ring at the top,
// and behind at the bottom — creating the classic chain-link / knot look.
struct KnotIcon: View {
    var size: CGFloat = 22
    var color: Color = .black

    // Geometry
    private var r: CGFloat { size * 0.3 }          // ring radius
    private var d: CGFloat { r * 0.44 }             // half-distance between centres
    private var lw: CGFloat { size * 0.13 }         // stroke width

    // Trim fractions where the two circles intersect
    // (derived from arccos(d/r) ≈ 64°, converted to clockwise-from-top fractions)
    private let topTrim: CGFloat    = 0.072         // top intersection on left ring right side
    private let bottomTrim: CGFloat = 0.428         // bottom intersection on left ring right side
    private let rtTopTrim: CGFloat  = 0.928         // top intersection on right ring left side
    private let rtBotTrim: CGFloat  = 0.572         // bottom intersection on right ring left side

    var body: some View {
        ZStack {
            let style = StrokeStyle(lineWidth: lw, lineCap: .round)

            // 1. Right ring: left arc (goes BEHIND left ring)
            Circle()
                .trim(from: rtBotTrim, to: rtTopTrim)
                .stroke(color, style: style)
                .frame(width: r * 2, height: r * 2)
                .offset(x: d)

            // 2. Left ring: complete circle (middle layer)
            Circle()
                .stroke(color, style: style)
                .frame(width: r * 2, height: r * 2)
                .offset(x: -d)

            // 3. Right ring: right arc (goes IN FRONT of left ring)
            //    Wraps around the top, so split at trim 0/1 boundary.
            Circle()
                .trim(from: rtTopTrim, to: 1.0)
                .stroke(color, style: style)
                .frame(width: r * 2, height: r * 2)
                .offset(x: d)
            Circle()
                .trim(from: 0.0, to: rtBotTrim)
                .stroke(color, style: style)
                .frame(width: r * 2, height: r * 2)
                .offset(x: d)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 20) {
        KnotIcon(size: 18)
        KnotIcon(size: 24)
        KnotIcon(size: 36)
        KnotIcon(size: 48, color: .gray)
    }
    .padding()
}
