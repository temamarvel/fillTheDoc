import Foundation
import DaDataAPIClient

public struct ValidationError: Error {
    let message: String
}

@MainActor
@Observable
final class CompanyDetailsModel {
    
    typealias Key = CompanyDetails.CodingKeys
    typealias Validator = CompanyDetailsValidator
    
    // UI читает одно место
    private(set) var fields: [Key: FieldState] = [:]
    
    private let metadata: [Key: FieldMetadata]
    private let allFieldKeys: [Key]
    
    private var validator: Validator
    private let dadata: DaDataClient
    
    // MARK: - Debounce / cancellation state
    
    private var validationTask: Task<Void, Never>?
    private var lastLookupKey: String?
    
    init(
        companyDetails: CompanyDetails,
        metadata: [Key: FieldMetadata],
        keys: [Key],
        validator: Validator,
        dadata: DaDataClient
    ) {
        self.metadata = metadata
        self.allFieldKeys = keys
        self.validator = validator
        self.dadata = dadata
        self.fields = Self.createFields(companyDetails: companyDetails, allFieldKeys: allFieldKeys, metadata: metadata)
        validateAllFields()
    }
    
    private static func createFields(
        companyDetails: CompanyDetails,
        allFieldKeys: [Key],
        metadata: [Key: FieldMetadata]
    ) -> [Key: FieldState] {
        var fields: [Key: FieldState] = [:]
        for key in allFieldKeys {
            let raw = companyDetails[key]
            let normalized = raw.flatMap { value in
                metadata[key].map { $0.normalizer(value) } ?? value.trimmedNilIfEmpty
            }
            fields[key] = FieldState(value: normalized, issue: nil)
        }
        return fields
    }
    
    // MARK: - Field access (для UI)
    
    func keysInOrder() -> [Key] { allFieldKeys }
    func value(for key: Key) -> String { fields[key]?.value ?? "" }
    func issue(for key: Key) -> FieldIssue? { fields[key]?.issue }
    func title(for key: Key) -> String { metadata[key]?.title ?? key.stringValue }
    func placeholder(for key: Key) -> String { metadata[key]?.placeholder ?? "" }
    var hasErrors: Bool { fields.values.contains { $0.issue?.severity == .error } }
    
    // MARK: - Set value (local only)
    
    func setValue(_ newValue: String, for key: Key) {
        guard var fieldState = fields[key] else { return }
        
        let normalized: String
        if let normalizer = metadata[key]?.normalizer {
            normalized = normalizer(newValue)
        } else {
            normalized = newValue.trimmed
        }
        fieldState.value = normalized
        fieldState.issue = validateField(for: key, state: fieldState)
        
        fields[key] = fieldState
    }
    
    // MARK: - Remote validation on blur (debounced + cancellation-aware)
    
    /// Вызывается из View при потере фокуса полем.
    /// Запускает удалённую проверку с задержкой 300 мс; предыдущая задача отменяется.
    func scheduleReferenceValidation() {
        let lookupKey =
        fields[.ogrn]?.value?.trimmedNilIfEmpty ??
        fields[.inn]?.value?.trimmedNilIfEmpty
        guard let lookupKey, !lookupKey.isEmpty else { return }
        
        // Не запускаем повторно по тому же ключу
        if lookupKey == lastLookupKey { return }
        
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Debounce 300 мс
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                
                let newFields = await self.validator.validateFieldsWithReference(fields: self.fields)
                try Task.checkCancellation()
                
                self.fields = newFields
                self.lastLookupKey = lookupKey
            } catch is CancellationError {
                // нормальная отмена
            } catch {
                print("Reference validation failed:", error)
            }
        }
    }
    
    /// Немедленная удалённая проверка (без debounce). Оставлена для обратной совместимости.
    func validateFieldsWithReference() async {
        fields = await validator.validateFieldsWithReference(fields: fields)
    }
    
    func validateAllFields() {
        for key in keysInOrder() {
            if var fieldState = fields[key] {
                fieldState.issue = validateField(for: key, state: fieldState)
                fields[key] = fieldState
            }
        }
    }
    
    // MARK: - Build DTO
    
    func buildResult() throws -> CompanyDetails {
        if hasErrors {
            // если у тебя есть свой тип ошибки — подставь его
            throw ValidationError(message: "В форме есть ошибки")
        }
        
        return CompanyDetails(
            companyName: value(for: .companyName).trimmedNilIfEmpty,
            legalForm: LegalForm.parse(value(for: .legalForm)),
            ceoFullName: value(for: .ceoFullName).trimmedNilIfEmpty,
            ceoFullGenitiveName: value(for: .ceoFullGenitiveName).trimmedNilIfEmpty,
            ceoShortenName: value(for: .ceoShortenName).trimmedNilIfEmpty,
            ogrn: value(for: .ogrn).trimmedNilIfEmpty,
            inn: value(for: .inn).trimmedNilIfEmpty,
            kpp: value(for: .kpp).trimmedNilIfEmpty,
            email: value(for: .email).trimmedNilIfEmpty,
            address: value(for: .address).trimmedNilIfEmpty,
            phone: value(for: .phone).trimmedNilIfEmpty
        )
    }
    
    // MARK: - Local messages policy
    
    private func validateField(for key: Key, state: FieldState) -> FieldIssue? {
        return validator.validateField(for: key, state: state)
    }
}
