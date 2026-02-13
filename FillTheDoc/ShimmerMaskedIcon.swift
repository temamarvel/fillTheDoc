import SwiftUI

struct ShimmerMaskedIcon: View {
    let assetName: String
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var backgroundMaterial: Material = .ultraThinMaterial
    
    @State private var phase: CGFloat = -1
    
    var body: some View {
        ZStack {
//            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
//                .fill(backgroundMaterial)
            
            // База (скелетон-слой)
            Image(assetName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary.opacity(0.2))
            
            // Shimmer
            shimmerLayer
                .mask(
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                )
                .blendMode(.plusLighter)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
        .onDisappear {
            phase = -1
        }
    }
    
    private var shimmerLayer: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .red.opacity(0.3), location: 0.45),
                    .init(color: .red.opacity(0.9), location: 0.5),
                    .init(color: .red.opacity(0.3), location: 0.55),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: w * 1.6, height: h * 1.6)
            .offset(x: phase * w, y: phase * h)
        }
    }
}

struct AppleShimmerMaskedIcon: View {
    let assetName: String
    
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var backgroundMaterial: Material = .ultraThinMaterial
    
    /// Скорость перелива
    var duration: Double = 1.25
    
    @State private var phase: CGFloat = -1
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundMaterial)
            
            // База — “скелетон”
            Image(assetName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary.opacity(0.16))
            
            appleShimmer
                .mask(
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                )
                .blendMode(.screen)
                .opacity(0.9)
        }
        .frame(width: size, height: size)
        .onAppear {
            phase = -1
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
        .onDisappear { phase = -1 }
    }
    
    private var appleShimmer: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            
            // Узкая, мягкая “лента”
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .white.opacity(0.10), location: 0.44),
                    .init(color: .white.opacity(0.32), location: 0.50),
                    .init(color: .white.opacity(0.10), location: 0.56),
                    .init(color: .clear, location: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Чуть больше контейнера, чтобы лента заходила/выходила плавно
            .frame(width: w * 1.8, height: h * 1.8)
            .offset(x: phase * w, y: phase * h)
            // Немного сглаживаем, чтобы было “Apple-like”
            .blur(radius: max(1, min(w, h) * 0.03))
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        
        ShimmerMaskedIcon(assetName: "ai_sparkle", size: 48)
        AppleShimmerMaskedIcon(assetName: "ai_sparkle", size: 48)
        
    }
    .padding(40)
    .frame(width: 300, height: 300)
    .background(.background)
}
