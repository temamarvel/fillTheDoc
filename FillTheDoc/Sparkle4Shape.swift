import SwiftUI

/// Мягкая 4-лучевая “AI sparkle” звезда с вогнутыми сторонами (похожа на системную иконку).
struct SparkleCurved4Shape: Shape {
    var innerRatio: CGFloat = 0.42 // чем меньше — тем сильнее “впадины”

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)

        let outer = s * 0.5
        let inner = outer * innerRatio

        func polar(_ deg: CGFloat, _ r: CGFloat) -> CGPoint {
            let a = deg * .pi / 180
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }

        let top    = polar(-90, outer)
        let right  = polar(0, outer)
        let bottom = polar(90, outer)
        let left   = polar(180, outer)

        let tr = polar(-45, inner)
        let br = polar(45, inner)
        let bl = polar(135, inner)
        let tl = polar(225, inner)

        // Контрольные точки для кривизны.
        // k ближе к 0 -> контроль ближе к середине сегмента
        // k ближе к 1 -> контроль ближе к центру (сильнее “стеклянная” мягкость)
        let k: CGFloat = 0.22
        func ctrl(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(
                x: (a.x + b.x) * 0.5 * (1 - k) + c.x * k,
                y: (a.y + b.y) * 0.5 * (1 - k) + c.y * k
            )
        }

        var p = Path()
        p.move(to: top)

        p.addQuadCurve(to: tr, control: ctrl(top, tr))
        p.addQuadCurve(to: right, control: ctrl(tr, right))

        p.addQuadCurve(to: br, control: ctrl(right, br))
        p.addQuadCurve(to: bottom, control: ctrl(br, bottom))

        p.addQuadCurve(to: bl, control: ctrl(bottom, bl))
        p.addQuadCurve(to: left, control: ctrl(bl, left))

        p.addQuadCurve(to: tl, control: ctrl(left, tl))
        p.addQuadCurve(to: top, control: ctrl(tl, top))

        p.closeSubpath()
        return p
    }
}

struct AISparkleIndicator: View {
    var size: CGFloat = 56
    var cycleDuration: Double = 1.6

    @State private var t: Double = 0
    @State private var pulse: CGFloat = 0.97

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
            let orbitRadius = s * 0.30

            ZStack {

                // MARK: - Центральная стеклянная звезда

                SparkleCurved4Shape(innerRatio: 0.40)
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.15), location: 0.00),
                                .init(color: Color.white.opacity(0.95), location: 0.20),
                                .init(color: Color.white.opacity(0.20), location: 0.50),
                                .init(color: Color.white.opacity(0.85), location: 0.80),
                                .init(color: Color.white.opacity(0.15), location: 1.00),
                            ]),
                            center: .center,
                            angle: .degrees(t * 360)
                        )
                    )
                    .frame(width: s * 0.70, height: s * 0.70)
                    .scaleEffect(pulse)
                    .overlay(
                        SparkleCurved4Shape(innerRatio: 0.40)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .white.opacity(0.35), radius: 18)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)

                // MARK: - Маленькие звезды по четвертям

                ForEach(0..<4, id: \.self) { index in
                    let angle = Double(index) * (.pi / 2) - (.pi / 4)

                    let x = center.x + CGFloat(cos(angle)) * orbitRadius
                    let y = center.y + CGFloat(sin(angle)) * orbitRadius

                    let phase = (t * 4) - Double(index)
                    let local = phase - floor(phase)
                    let opacity = pop(local)

                    SparkleCurved4Shape(innerRatio: 0.45)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: s * 0.20, height: s * 0.20)
                        .opacity(opacity)
                        .scaleEffect(0.8 + 0.4 * opacity)
                        .shadow(color: .white.opacity(0.4 * opacity), radius: 8)
                        .position(x: x, y: y)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: cycleDuration).repeatForever(autoreverses: false)) {
                    t = 1
                }

                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = 1.05
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("AI processing")
    }

    private func pop(_ p: Double) -> Double {
        if p < 0.15 { return smooth(p / 0.15) }
        if p < 0.45 { return 1 }
        if p < 0.60 { return 1 - smooth((p - 0.45) / 0.15) }
        return 0
    }

    private func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct AIBlockingOverlay: View {
    var title: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.25))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                AISparkleIndicator(size: 64)

                Text(title)
                    .font(.headline)

                Text("Пожалуйста, подожди")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 30)
        }
        .allowsHitTesting(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        AISparkleIndicator(size: 44)
        AISparkleIndicator(size: 64)

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 260, height: 120)

            HStack(spacing: 14) {
                AISparkleIndicator(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI processing…").font(.headline)
                    Text("Extracting requisites").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
    .padding(24)
    .frame(width: 520, height: 360)
}
