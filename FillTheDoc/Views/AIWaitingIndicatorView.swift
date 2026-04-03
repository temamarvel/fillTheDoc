//
//  AIWaitingIndicator.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 13.02.2026.
//

import SwiftUI
import Shimmer

struct AIWaitingIndicatorView: View {
    var size: CGFloat = 100
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(.tint)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            Image(.aiSparkle)
                .resizable()
                .scaledToFit()
                .padding(size * 0.15)
                .foregroundStyle(.tint)
                .shimmering()
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    AIWaitingIndicatorView()
        .frame(width: 300, height: 300)
}
