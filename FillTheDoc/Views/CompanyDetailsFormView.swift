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
    
    @State private var showErrorAlert = false
    @State private var errorText = ""
    
    @FocusState private var focusedKey: Key?
    
    let onApply: (CompanyDetails) -> Void
    
    init(
        companyDetails: CompanyDetails,
        metadata: [Key: FieldMetadata],
        keys: [Key],
        onApply: @escaping (CompanyDetails) -> Void
    ) {
        let token = Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T"
        let client = DaDataClient(configuration: .init(token: token))
        let validator = CompanyDetailsValidator(dadataClient: client)
        
        _model = StateObject(
            wrappedValue: CompanyDetailsModel(
                companyDetails: companyDetails,
                metadata: metadata,
                keys: keys,
                validator: validator,
                dadata: client
            )
        )
        self.onApply = onApply
    }
    
    var body: some View {
        Form {
            ForEach(model.keysInOrder(), id: \.self) { key in
                if let state = model.fields[key] {
                    fieldRow(key: key, state: state)
                }
            }
            
            HStack {
                Spacer()
                Button("Применить") {
                    do {
                        let dto = try model.buildResult()
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
        .onAppear(){
            model.validateAllFields()
        }
        .onChange(of: focusedKey) { old, new in
            guard let lost = old, lost != new else { return }
            Task { await model.validateFieldsWithReference() }
        }
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorText)
        }
        .animation(.easeInOut(duration: 0.15), value: model.fields)
    }
    
    @ViewBuilder
    private func fieldRow(key: CompanyDetailsModel.Key, state: FieldState) -> some View {
        
        let message = state.message
        let color = messageColor(for: message)
        
        HStack(alignment: .firstTextBaseline) {
            Text(model.title(for: key))
            
            VStack(alignment: .trailing) {
                TextField("", text: binding(for: key), prompt: Text(model.placeholder(for: key)))
                    .focused($focusedKey, equals: key)
                
                
                if let message = message?.text {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(color)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background {
                if message?.severity != nil {
                    LinearGradient(
                        colors: [
                            .clear,
                            color.opacity(0.10),
                            color.opacity(0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.hasErrors)
        }
    }
    
    // MARK: - Binding
    
    private func binding(for key: Key) -> Binding<String> {
        Binding(
            get: { model.value(for: key) },
            set: { model.setValue($0, for: key) }
        )
    }
    
    private func messageColor(for message: CompanyDetailsValidator.FieldMessage?) -> Color {
        guard let message, let severity = message.severity else {
            return .clear
        }
        
        switch severity {
            case .error: return .red
            case .warning: return .orange
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
            companyDetails: requisites,
            metadata: CompanyDetails.fieldMetadata,
            keys: [.companyName, .legalForm, .ceoFullName, .ceoShortenName, .ogrn, .inn, .kpp, .email]
        ) { updated in
            requisites = updated
        }
        .frame(width: 600, height: 700)
        .padding()
    }
}
