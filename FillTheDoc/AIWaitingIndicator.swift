//
//  AIWaitingIndicator.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 13.02.2026.
//

import SwiftUI
import Shimmer

struct AIWaitingIndicator: View {
    var size: CGFloat = 160
    
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
    AIWaitingIndicator()
        .frame(width: 300, height: 300)
}
