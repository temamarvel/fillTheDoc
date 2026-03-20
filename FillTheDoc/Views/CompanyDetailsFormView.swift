//
//  ExtractedDTOFormView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//

import SwiftUI
import DaDataAPIClient

struct CompanyDetailsFormView: View {
    
    typealias Key = CompanyDetails.CodingKeys
    
    @StateObject private var model: CompanyDetailsModel
    
    @State private var showErrorAlert = false
    @State private var errorText = ""
    @State private var discount = ""
    @State private var minDiscount = ""
    
    @FocusState private var focusedKey: Key?
    
    let onApply: (DocumentData) -> Void
    
    init(
        companyDetails: CompanyDetails,
        metadata: [Key: FieldMetadata],
        keys: [Key],
        onApply: @escaping (DocumentData) -> Void
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
    
    private var discountError: String? {
        validateNumericRequired(discount)
    }
    
    private var minDiscountError: String? {
        validateNumericRequired(minDiscount)
    }
    
    private func validateNumericRequired(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return "Поле обязательно для заполнения"
        }
        
        if !trimmed.allSatisfy(\.isNumber) {
            return "Разрешены только цифры"
        }
        
        guard let number = Int(trimmed) else {
            return "Некорректное число"
        }
        
        if number < 0 || number > 100 {
            return "Значение должно быть от 0 до 100"
        }
        
        return nil
    }
    
    var body: some View {
        VStack{
            HStack{
                LabeledContent {
                    VStack(alignment: .trailing){
                        TextField("10%", text: $discount)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                        
                        if let discountError = discountError {
                            Text(discountError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                } label: {
                    Text("Discount")
                }
                .padding(4)
                .background {
                    ZStack{
                        Rectangle().fill(.ultraThinMaterial)
                        
                        if discountError != nil {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .red.opacity(0.10),
                                    .red.opacity(0.22)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                
                LabeledContent {
                    VStack(alignment: .trailing){
                        TextField("10 руб", text: $minDiscount)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                        
                        if let minDiscountError = minDiscountError {
                            Text(minDiscountError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                } label: {
                    Text("Min Discount")
                }.padding(4)
                    .background {
                        ZStack{
                            Rectangle().fill(.ultraThinMaterial)
                            
                            if minDiscountError != nil {
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .red.opacity(0.10),
                                        .red.opacity(0.22)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
            }
            .animation(.easeInOut(duration: 0.15), value: discountError)
            .animation(.easeInOut(duration: 0.15), value: minDiscountError)
                
            Divider()
            
            Form {
                ForEach(model.keysInOrder(), id: \.self) { key in
                    if let state = model.fields[key] {
                        fieldRow(key: key, state: state)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Применить") {
                    do {
                        let dto = try model.buildResult()
                        let result = DocumentData(discount: discount, minDiscount: minDiscount, companyDetails: dto)
                        onApply(result)
                    } catch {
                        errorText = error.localizedDescription
                        showErrorAlert = true
                    }
                }
                .disabled(model.hasErrors)
                .keyboardShortcut(.defaultAction)
            }
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
    @State private var result: DocumentData? = nil
    @State private var requisites = CompanyDetails(
        companyName: "ООО «Ромашка»",
        legalForm: LegalForm.parse("OOO"),
        ceoFullName: "Иванов Иван Иванович",
        ceoShortenName: "Иванов И.И.",
        ogrn: "1234567890123",
        inn: "7701234567",
        kpp: "770101001",
        email: "info@romashka.ru",
        address: "ТЕСТ Адрес",
        phone: "+79991234567"
    )
    
    var body: some View {
        CompanyDetailsFormView(
            companyDetails: requisites,
            metadata: CompanyDetails.fieldMetadata,
            keys: [.companyName, .legalForm, .ceoFullName, .ceoShortenName, .ogrn, .inn, .kpp, .email]
        ) { updated in
            result = updated
        }
        .frame(width: 600, height: 700)
        .padding()
    }
}
