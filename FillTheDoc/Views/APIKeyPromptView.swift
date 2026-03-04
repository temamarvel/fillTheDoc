//
//  APIKeyPromptView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 12.02.2026.
//


import SwiftUI

struct APIKeyPromptView: View {
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var errorText: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Нужен API ключ")
                .font(.title3.weight(.semibold))
            
            Text("Введи ключ для доступа к модели. Он будет сохранён в Keychain этого Mac и дальше не будет запрашиваться.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            
            HStack {
                Spacer()
                
                Button("Сохранить") {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        errorText = "Ключ не может быть пустым."
                        return
                    }
                    onSave(trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
