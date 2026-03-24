//
//  EmptyCompanyDetailsPlaceholder.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 15.03.2026.
//


import SwiftUI

struct EmptyCompanyDetailsPlaceholderView: View {
    var title: String = "Нет извлечённых данных о компании"
    var message: String = "Загрузите файл с реквизитами и выполните извлечение, чтобы здесь появилась форма для проверки и редактирования."
    
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quinary.opacity(0.7))
                    .frame(width: 64, height: 64)
                
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

#Preview {
    EmptyCompanyDetailsPlaceholderView()
        .frame(width: 640, height: 420)
        .padding()
}
