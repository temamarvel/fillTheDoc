//
//  Sparkle4Shape.swift
//  FillTheDoc
//
//  Created by Artem Denisov on 13.02.2026.
//


import SwiftUI

// 4-point sparkle/star shape (ромб с “впадинами” на сторонах)
struct Sparkle4Shape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let c = CGPoint(x: rect.midX, y: rect.midY)

        let outer = min(w, h) * 0.50
        let inner = outer * 0.38

        // Точки по кругу: outer (0°), inner (45°), outer (90°), inner (135°) ...
        func pt(_ angleDeg: CGFloat, _ radius: CGFloat) -> CGPoint {
            let a = angleDeg * .pi / 180
            return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
        }

        let points: [CGPoint] = [
            pt(-90, outer),
            pt(-45, inner),
            pt(0, outer),
            pt(45, inner),
            pt(90, outer),
            pt(135, inner),
            pt(180, outer),
            pt(225, inner)
        ]

        var p = Path()
        p.move(to: points[0])
        for i in 1..<points.count { p.addLine(to: points[i]) }
        p.closeSubpath()
        return p
    }
}

struct Shimmer: ViewModifier {
    @State private var x: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.0), location: 0.0),
                            .init(color: .white.opacity(0.55), location: 0.5),
                            .init(color: .white.opacity(0.0), location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: w * 0.65, height: h * 1.2)
                    .rotationEffect(.degrees(20))
                    .offset(x: x * w * 1.6)
                    .blendMode(.screen)
                    .onAppear {
                        x = -1.0
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            x = 1.0
                        }
                    }
                }
                .allowsHitTesting(false)
            )
            .mask(content)
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

struct AIProcessingIndicator: View {
    @State private var rotation: Angle = .degrees(0)
    @State private var pulse: CGFloat = 0.92

    var size: CGFloat = 44

    var body: some View {
        Sparkle4Shape()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.10), location: 0.00),
                        .init(color: .white.opacity(0.95), location: 0.20),
                        .init(color: .white.opacity(0.20), location: 0.45),
                        .init(color: .white.opacity(0.85), location: 0.70),
                        .init(color: .white.opacity(0.10), location: 1.00),
                    ]),
                    center: .center
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(rotation)
            .scaleEffect(pulse)
            .shimmer()
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
            .onAppear {
                rotation = .degrees(0)
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = .degrees(360)
                }

                pulse = 0.92
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = 1.06
                }
            }
            .accessibilityLabel("AI processing")
    }
}

struct AIBlockingOverlay: View {
    var title: String

    var body: some View {
        ZStack {
            // блокируем UI и визуально “гасим” фон
            Rectangle()
                .fill(.black.opacity(0.35))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                AIProcessingIndicator(size: 52)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.top, 2)

                Text("Пожалуйста, подожди")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .allowsHitTesting(true) // важно: блокируем клики по UI под оверлеем
    }
}

#Preview {
    VStack(spacing: 24) {
        AIProcessingIndicator(size: 28)
        AIProcessingIndicator(size: 44)
        AIProcessingIndicator(size: 72)

        Divider().frame(width: 220)

        HStack(spacing: 18) {
            AIProcessingIndicator(size: 36)
            Text("AI is working…")
                .font(.headline)
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .padding(24)
    .frame(width: 420, height: 360)
}
