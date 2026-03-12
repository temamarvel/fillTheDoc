import Foundation
import DaDataAPIClient
import Combine

public struct ValidationError: Error {
    let message: String
}

@MainActor
final class CompanyDetailsModel: ObservableObject {
    
    typealias Key = CompanyDetails.CodingKeys
    typealias Validator = CompanyDetailsValidator
    typealias FieldMessage = CompanyDetailsValidator.FieldMessage
    
    
    // UI читает одно место
    @Published private(set) var fields: [Key: FieldState] = [:]
    
    private let original: [Key: String]
    private let metadata: [Key: FieldMetadata]
    private let allFieldKeys: [Key]
    
    private var validator: Validator
    private let dadata: DaDataClient
    
    init(
        dto: CompanyDetails,
        metadata: [Key: FieldMetadata],
        validator: Validator,
        dadata: DaDataClient
    ) {
        self.metadata = metadata
        self.allFieldKeys = Key.allCases
        self.original = Self.dtoToMap(dto)
        self.validator = validator
        self.dadata = dadata
        
        var f: [Key: FieldState] = [:]
        for key in allFieldKeys {
            let v = original[key] ?? ""
            f[key] = FieldState(value: v, message: nil)
        }
        self.fields = f
    }
    
    // MARK: - Field access (для UI)
    
    func keysInOrder() -> [Key] { allFieldKeys }
    func value(for key: Key) -> String { fields[key]?.value ?? "" }
    func message(for key: Key) -> FieldMessage? { fields[key]?.message }
    func title(for key: Key) -> String { metadata[key]?.title ?? key.stringValue } // если нет метадаты — хотя бы json-key покажем
    func placeholder(for key: Key) -> String { metadata[key]?.placeholder ?? "" }
    var hasErrors: Bool { fields.values.contains { $0.message != nil } }
    
    // MARK: - Set value (local only)
    
    func setValue(_ newValue: String, for key: Key) {
        guard var fieldState = fields[key] else { return }
        
        let normalized: String
        if let normalizer = metadata[key]?.normalizer {
            normalized = normalizer(newValue)
        } else {
            normalized = FieldRules.trim(newValue)
        }
        fieldState.value = normalized
        fieldState.message = validateField(for: key, state: fieldState)
        
        fields[key] = fieldState
    }
    
    // MARK: - Remote validation on blur

    func validateFieldsWithReference() async {
        fields = await validator.validateFieldsWithReference(fields: fields)
    }
    
    // MARK: - Build DTO
    
    func buildResult() throws -> CompanyDetails {
        if hasErrors {
            // если у тебя есть свой тип ошибки — подставь его
            throw ValidationError(message: "В форме есть ошибки")
        }
        
        return CompanyDetails(
            companyName: present(value(for: .companyName)),
            legalForm: present(value(for: .legalForm)),
            ceoFullName: present(value(for: .ceoFullName)),
            ceoShortenName: present(value(for: .ceoShortenName)),
            ogrn: present(value(for: .ogrn)),
            inn: present(value(for: .inn)),
            kpp: present(value(for: .kpp)),
            email: present(value(for: .email))
        )
    }
    
    // MARK: - Local messages policy
    
    private func validateField(for key: Key, state: FieldState) -> FieldMessage? {
        return validator.validateField(for: key, state: state)
    }
    
    
    // MARK: - Helpers
    
    private var currentFieldValues: [Key: String] {
        var result: [Key: String] = [:]
        result.reserveCapacity(allFieldKeys.count)
        
        for k in allFieldKeys {
            result[k] = fields[k]?.value ?? ""
        }
        
        return result
    }
    
    private static func dtoToMap(_ dto: CompanyDetails) -> [Key: String] {
        [
            .companyName: dto.companyName ?? "",
            .legalForm: dto.legalForm ?? "",
            .ceoFullName: dto.ceoFullName ?? "",
            .ceoShortenName: dto.ceoShortenName ?? "",
            .ogrn: dto.ogrn ?? "",
            .inn: dto.inn ?? "",
            .kpp: dto.kpp ?? "",
            .email: dto.email ?? ""
        ]
    }
    
    private func present(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
