import SwiftUI

struct GradePad: View {
    let kind: ActiveGradeSurface
    let style: GradeStyle
    let accent: AccentColor
    let point: CGPoint
    let onActivate: () -> Void
    let onChange: (CGPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                padBackground
                DottedPaletteGrid()
                Circle()
                    .stroke(.white.opacity(0.34), lineWidth: 1)
                    .frame(width: 8, height: 8)
                    .position(x: size.width / 2, y: size.height / 2)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().stroke(.black.opacity(0.32), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.50), radius: 5, y: 2)
                    .position(
                        x: 11 + point.x * max(0, size.width - 22),
                        y: 11 + point.y * max(0, size.height - 22)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onActivate()
                        onChange(CGPoint(
                            x: min(1, max(0, value.location.x / size.width)),
                            y: min(1, max(0, value.location.y / size.height))
                        ))
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        onActivate()
                        withAnimation(.snappy(duration: 0.2)) {
                            onChange(CGPoint(x: 0.5, y: 0.5))
                        }
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var padBackground: some View {
        switch kind {
        case .style:
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.56), style.tint.opacity(0.76), style.tint],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RadialGradient(
                    colors: [style.tint.mix(with: .orange, by: 0.28).opacity(0.54), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 150
                )
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.78), location: 0),
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.88), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .accent:
            let base = accent.color
            ZStack {
                LinearGradient(
                    colors: [base.mix(with: .blue, by: 0.42), base, base.mix(with: .orange, by: 0.38)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.72), location: 0),
                        .init(color: .clear, location: 0.40),
                        .init(color: .black.opacity(0.86), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

private struct DottedPaletteGrid: View {
    var body: some View {
        Canvas { context, size in
            let columns = 11
            let rows = 11
            let inset = size.width * 0.09
            let usableWidth = size.width - inset * 2
            let usableHeight = size.height - inset * 2

            for row in 0..<rows {
                for column in 0..<columns {
                    let x = inset + usableWidth * CGFloat(column) / CGFloat(columns - 1)
                    let y = inset + usableHeight * CGFloat(row) / CGFloat(rows - 1)
                    let radius: CGFloat = row > 7 ? 1.65 : 1.35
                    let opacity = 0.36 + Double(row) / Double(rows - 1) * 0.42
                    let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension Color {
    func mix(with other: Color, by amount: CGFloat) -> Color {
        let lhs = UIColor(self)
        let rhs = UIColor(other)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return Color(
            red: lr + (rr - lr) * amount,
            green: lg + (rg - lg) * amount,
            blue: lb + (rb - lb) * amount
        )
    }
}
