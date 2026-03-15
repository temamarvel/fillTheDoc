//
//  EmptyCompanyDetailsPlaceholder.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 15.03.2026.
//


import SwiftUI

struct EmptyCompanyDetailsPlaceholder: View {
    var title: String = "Нет извлечённых данных о компании"
    var message: String = "Загрузите файл с реквизитами и выполните извлечение, чтобы здесь появилась форма для проверки и редактирования."
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack {
            Spacer(minLength: 0)

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

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: 560)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

#Preview {
    EmptyCompanyDetailsPlaceholder()
        .frame(width: 640, height: 420)
        .padding()
}
