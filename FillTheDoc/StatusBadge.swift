//
//  StatusBadge.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 09.02.2026.
//

import SwiftUI


struct StatusBadge: View {
    let isValid: Bool
    
    var body: some View {
        Text(isValid ? "OK" : "Нужно")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isValid ? Color.green.opacity(0.18) : Color.red.opacity(0.18),
                        in: Capsule())
            .foregroundStyle(isValid ? Color.green : Color.red)
    }
}

#Preview {
    VStack {
        StatusBadge(isValid: true)
        StatusBadge(isValid: false)
    }.padding(30)
}
