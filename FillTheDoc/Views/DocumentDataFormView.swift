//
//  ExtractedDTOFormView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//

import SwiftUI
import DaDataAPIClient

struct DocumentDataFormView: View {
    
    typealias Key = CompanyDetails.CodingKeys
    
    @State private var model: CompanyDetailsModel
    
    @State private var errorText = ""
    @State private var fee = ""
    @State private var minFee = ""
    @State private var docNumber = ""
    
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
        
        _model = State(
            initialValue: CompanyDetailsModel(
                companyDetails: companyDetails,
                metadata: metadata,
                keys: keys,
                validator: validator,
                dadata: client
            )
        )
        self.onApply = onApply
    }
    
    private var docNumberError: String? {
        docNumber.isEmpty ? "Номер договора не может быть пустым" : nil
    }
    
    private var feeError: String? {
        Validators.percentage(fee)
    }
    
    private var minFeeError: String? {
        Validators.percentage(minFee)
    }
    
    var body: some View {
        VStack{
            Form {
                Section("Документ"){
                    DocumentDataRowView(title: "Номер договора", placeholder: "yyyy-mm-#", text: $docNumber, errorColor: .red, errorText: docNumberError, focusedKey: $focusedKey, key: .address)
                }
                
                Section("Комиссия"){
                    DocumentDataRowView(title: "Комиссия, %", placeholder: "10", text: $fee, errorColor: .red, errorText: feeError, focusedKey: $focusedKey, key: .address)
                    
                    DocumentDataRowView(title: "Мин. комиссия, руб", placeholder: "10", text: $minFee, errorColor: .red, errorText: minFeeError, focusedKey: $focusedKey, key: .address)
                }
                
                Section("Реквизиты компании") {
                    
                    ForEach(model.keysInOrder(), id: \.self) { key in
                        if let state = model.fields[key] {
                            fieldRow(key: key, state: state)
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Валидация с ФНС") {
                    Task{
                        await model.validateFieldsWithReference()
                    }
                }
                Spacer()
                Button("Применить") {
                    do {
                        let validatedCompanyDatails = try model.buildResult()
                        let result = DocumentData(docNumber: docNumber, fee: fee.trimmed, minFee: minFee.trimmed, companyDetails: validatedCompanyDatails)
                        onApply(result)
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                .disabled(model.hasErrors || feeError != nil || minFeeError != nil || docNumberError != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .onChange(of: focusedKey) { old, new in
            guard let lost = old, lost != new else { return }
            model.scheduleReferenceValidation()
        }
        .animation(.easeInOut(duration: 0.15), value: model.fields)
        .animation(.easeInOut(duration: 0.15), value: feeError)
        .animation(.easeInOut(duration: 0.15), value: minFeeError)
    }
    
    @ViewBuilder
    private func fieldRow(key: CompanyDetailsModel.Key, state: FieldState) -> some View {
        let issue = state.issue
        let color = issueColor(for: issue)
        
        DocumentDataRowView(
            title: model.title(for: key),
            placeholder: model.placeholder(for: key),
            text: binding(for: key),
            errorColor: color,
            errorText: issue?.text,
            focusedKey: $focusedKey,
            key: key
        )
    }
    
    // MARK: - Binding
    
    private func binding(for key: Key) -> Binding<String> {
        Binding(
            get: { model.value(for: key) },
            set: { model.setValue($0, for: key) }
        )
    }
    
    private func issueColor(for issue: FieldIssue?) -> Color {
        guard let issue else { return .clear }
        
        switch issue.severity {
            case .error: return .red
            case .warning: return .orange
        }
    }
}

#Preview {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var result: DocumentData? = nil
    @State private var requisites = CompanyDetails(
        companyName: "ООО «Ромашка»",
        legalForm: LegalForm.parse("OOO"),
        ceoFullName: "Иванов Иван Иванович",
        ceoFullGenitiveName: "Иванова Ивана Ивановича",
        ceoShortenName: "Иванов И.И.",
        ogrn: "1234567890123",
        inn: "7701234567",
        kpp: "770101001",
        email: "info@romashka.ru",
        address: "ТЕСТ Адрес",
        phone: "+79991234567"
    )
    
    var body: some View {
        DocumentDataFormView(
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


