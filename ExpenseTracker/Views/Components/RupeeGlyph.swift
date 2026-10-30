//
//  RupeeGlyph.swift
//  ExpenseTracker
//
//  A hand-drawn ₹ built from strokes, so the tail can be dashed and faded
//  independently of the head. Geometry mirrors Scripts/GenerateAppIcon.swift.
//

import SwiftUI

/// The two bars and the bowl of the ₹.
struct RupeeHead: Shape {
    func path(in rect: CGRect) -> Path {
        let p = rect.unitPoint
        var path = Path()
        // Top bar
        path.move(to: p(0.16, 0.10))
        path.addLine(to: p(0.84, 0.10))
        // Middle bar
        path.move(to: p(0.16, 0.34))
        path.addLine(to: p(0.84, 0.34))
        // Bowl
        path.move(to: p(0.30, 0.10))
        path.addLine(to: p(0.42, 0.10))
        path.addCurve(to: p(0.42, 0.58), control1: p(0.76, 0.10), control2: p(0.76, 0.58))
        path.addLine(to: p(0.18, 0.58))
        return path
    }
}

/// The diagonal leg of the ₹.
struct RupeeTail: Shape {
    static let start = UnitPoint(x: 0.20, y: 0.58)
    static let end = UnitPoint(x: 0.80, y: 0.98)

    func path(in rect: CGRect) -> Path {
        let p = rect.unitPoint
        var path = Path()
        path.move(to: p(Self.start.x, Self.start.y))
        path.addLine(to: p(Self.end.x, Self.end.y))
        return path
    }
}

private extension CGRect {
    /// Maps unit coordinates (0…1) into this rect.
    var unitPoint: (CGFloat, CGFloat) -> CGPoint {
        { x, y in CGPoint(x: minX + x * width, y: minY + y * height) }
    }
}

/// The complete ₹ in either the app-icon style (dashed, fading tail) or a bold solid style.
struct RupeeGlyph: View {
    enum Style {
        case icon
        case bold

        /// Stroke width as a fraction of the glyph's width.
        var lineWidthRatio: CGFloat {
            switch self {
            case .icon: 0.133
            case .bold: 0.18
            }
        }
    }

    var style: Style
    var color: Color = .brandNavy

    var body: some View {
        GeometryReader { geometry in
            let lineWidth = geometry.size.width * style.lineWidthRatio
            ZStack {
                RupeeHead()
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                switch style {
                case .icon:
                    // Round caps add half a line width to each dash end, so the gap must
                    // exceed one line width for the dashes to stay separate.
                    RupeeTail()
                        .stroke(
                            LinearGradient(
                                colors: [color, color.opacity(0.05)],
                                startPoint: RupeeTail.start,
                                endPoint: RupeeTail.end
                            ),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [lineWidth * 0.8, lineWidth * 1.6])
                        )
                case .bold:
                    RupeeTail()
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
        // Same proportions as the glyph area in the app icon.
        .aspectRatio(0.64 / 0.68, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 40) {
        RupeeGlyph(style: .icon)
        RupeeGlyph(style: .bold)
    }
    .frame(height: 160)
    .padding(40)
    .background(Color.brandYellow)
}
