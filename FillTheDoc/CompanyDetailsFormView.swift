//
//  ExtractedDTOFormView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//

import SwiftUI
import DaDataAPIClient

import SwiftUI
import DaDataAPIClient

struct CompanyDetailsFormView: View {
    
    typealias Key = CompanyDetails.CodingKeys
    
    @StateObject private var model: CompanyDetailsModel
    let onApply: (CompanyDetails) -> Void
    
    @State private var showErrorAlert = false
    @State private var errorText = ""
    
    // типизированный фокус
    @FocusState private var focusedKey: Key?
    
    init(
        dto: CompanyDetails,
        metadata: [Key: FieldMetadata],
        onApply: @escaping (CompanyDetails) -> Void
    ) {
        let token = Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T"
        let client = DaDataClient(configuration: .init(token: token))
        let validator = CompanyDetailsValidator()
        
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
        
        // blur обработчик: отправляем changed=old
        .onChange(of: focusedKey) { old, new in
            guard let lost = old, lost != new else { return }
            Task { await model.validateOnFocusLost(changed: lost) }
        }
        
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }
    
    // MARK: - UI parts
    
    @ViewBuilder
    private func fieldRow(key: Key) -> some View {
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
    
    private func binding(for key: Key) -> Binding<String> {
        Binding(
            get: { model.value(for: key) },
            set: { model.setValue($0, for: key) } // local внутри
        )
    }
    
    // MARK: - Styles
    
    private func borderColor(for key: Key) -> Color {
        switch model.severity(for: key) {
            case .error:
                return .red.opacity(0.85)
            case .warning:
                return .orange.opacity(0.75)
            case .none:
                return .clear
        }
    }
    
    private func borderWidth(for key: Key) -> CGFloat {
        model.severity(for: key) == .none ? 0 : 1
    }
    
    private func messageColor(for key: Key) -> Color {
        switch model.severity(for: key) {
            case .error: return .red
            case .warning: return .orange
            case .none: return .secondary
        }
    }
}

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
