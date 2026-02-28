//
//  ExtractedDTOFormView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//

import SwiftUI
import DaDataAPIClient

struct CompanyDetailsFormView<T: LLMExtractable>: View {
    
    @StateObject private var model: CompanyDetailsModel<T>
    let onApply: (T) -> Void
    
    @State private var showErrorAlert = false
    @State private var errorText = ""
    
    // NEW: фокус по ключу поля
    @FocusState private var focusedKey: String?
    
    init(dto: T, metadata: [String: FieldMetadata], onApply: @escaping (T) -> Void) {
        
        let token = Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T"
        
        let client = DaDataClient(configuration: .init(token: token))
        let validator = CompanyDetailsValidator() // <-- новый валидатор
        
        _model = StateObject(
            wrappedValue: CompanyDetailsModel(
                dto: dto,
                metadata: metadata,
                validator: validator,
                dadata: client
            )
        )
        self.onApply = onApply
    }
    
    var body: some View {
        List {
            ForEach(model.keysInOrder(), id: \.self) { key in
                fieldRow(key: key)
            }
            
            HStack {
                Spacer()
                Button("Применить") {
                    do {
                        let dto = try model.buildDTO()
                        onApply(dto)
                    } catch {
                        errorText = error.localizedDescription
                        showErrorAlert = true
                    }
                }
                .disabled(model.hasErrors)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
        .onChange(of: focusedKey) { old, new in
            // DaData валидация — только для поля, которое потеряло фокус
            guard let old else { return }
            Task { await model.validateOnFocusLost(key: old) }
        }
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }
    
    // MARK: - UI parts
    
    @ViewBuilder
    private func fieldRow(key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.title(for: key))
                .font(.subheadline.weight(.medium))
            
            TextField(model.placeholder(for: key), text: binding(for: key))
                .focused($focusedKey, equals: key)
                .textFieldStyle(.roundedBorder)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor(for: key), lineWidth: borderWidth(for: key))
                )
            
            if let msg = model.message(for: key), !msg.isEmpty {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(messageColor(for: key))
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Binding
    
    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { model.value(for: key) },
            set: { model.setValue($0, for: key) } // локальная валидация внутри setValue
        )
    }
    
    // MARK: - Styles
    
    private func borderColor(for key: String) -> Color {
        switch model.severity(for: key) {
            case .error:
                return .red.opacity(0.85)
            case .warning:
                // более “macOS-like”, чем чисто желтый
                return .orange.opacity(0.75)
            case .none:
                return .clear
        }
    }
    
    private func borderWidth(for key: String) -> CGFloat {
        model.severity(for: key) == .none ? 0 : 1
    }
    
    private func messageColor(for key: String) -> Color {
        switch model.severity(for: key) {
            case .error: return .red
            case .warning: return .orange
            case .none: return .secondary
        }
    }
}

// MARK: - Preview

#Preview("Interactive") {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var requisites = CompanyDetails(
        companyName: "ООО «Ромашка»",
        legalForm: "ООО",
        ceoFullName: "Иванов Иван Иванович",
        ceoShortenName: "Иванов И.И.",
        ogrn: "1234567890123",
        inn: "7701234567",
        kpp: "770101001",
        email: "info@romashka.ru"
    )
    
    var body: some View {
        CompanyDetailsFormView(
            dto: requisites,
            metadata: CompanyDetails.fieldMetadata
        ) { updated in
            requisites = updated
        }
        .frame(width: 600, height: 700)
        .padding()
    }
}
