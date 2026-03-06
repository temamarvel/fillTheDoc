import Foundation
import DaDataAPIClient
import Combine

@MainActor
final class CompanyDetailsModel: ObservableObject {
    
    typealias Key = CompanyDetails.CodingKeys
    typealias Validator = CompanyDetailsValidator
    typealias FieldMessage = CompanyDetailsValidator.FieldMessage
    
    enum FieldSeverity: Equatable { case none, warning, error }
    
    struct FieldState: Equatable {
        var value: String
        var message: String?
        var severity: FieldSeverity
        var isDirty: Bool
    }
    
    // UI читает одно место
    @Published private(set) var fields: [Key: FieldState] = [:]
    
    private let original: [Key: String]
    private let metadata: [Key: FieldMetadata]
    private let allFieldKeys: [Key]
    
    // Split storage (идеальная схема):
    private var localMessages: [Key: FieldMessage] = [:]
    private var remoteMessages: [Key: FieldMessage] = [:]
    
    private let validator: Validator
    private let dadata: DaDataClient
    private var remoteState = Validator.RemoteState()
    
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
            f[key] = FieldState(value: v, message: nil, severity: .none, isDirty: false)
        }
        self.fields = f
        
        // initial local pass
        validateFieldValues(fieldValues: currentFieldValues)
        applyMergedMessagesToFieldStates()
    }
    
    // MARK: - Field access (для UI)
    
    func keysInOrder() -> [Key] { allFieldKeys }
    
    func value(for key: Key) -> String { fields[key]?.value ?? "" }
    func message(for key: Key) -> String? { fields[key]?.message }
    func severity(for key: Key) -> FieldSeverity { fields[key]?.severity ?? .none }
    
    func title(for key: Key) -> String {
        metadata[key]?.title ?? key.stringValue // если нет метадаты — хотя бы json-key покажем
    }
    
    func placeholder(for key: Key) -> String {
        metadata[key]?.placeholder ?? ""
    }
    
    var hasErrors: Bool {
        fields.values.contains { $0.severity == .error }
    }
    
    // MARK: - Set value (local only)
    
    func setValue(_ newValue: String, for key: Key) {
        guard var st = fields[key] else { return }
        
        let normalized: String
        if let normalizer = metadata[key]?.normalizer {
            normalized = normalizer(newValue)
        } else {
            normalized = FieldRules.trim(newValue)
        }
        st.value = normalized
        st.isDirty = (normalized != (original[key] ?? ""))
        
        fields[key] = st
        
        // пересчёт local только для этого поля (дёшево)
        localMessages[key] = validateField(for: key, value: normalized)
        if localMessages[key] == nil { localMessages.removeValue(forKey: key) }
        
        applyMergedMessagesToFieldStates()
    }
    
    func validateAllLocal() {
        let all = currentFieldValues
        validateFieldValues(fieldValues: all)
        applyMergedMessagesToFieldStates()
    }
    
    // MARK: - Remote validation on blur
    
    /// Вызывай из UI на blur конкретного поля.
    func validateOnFocusLost(changed key: Key) async {
        // 1) гарантируем актуальный local (и meta validator тоже)
        //    (можно оптимизировать до пересчёта только key, но обычно на blur ок)
        validateAllLocal()
        
        let all = currentFieldValues
        
        // 2) remote validate (DaData)
        let (newRemote, remote) = await validator.validateOnFocusLost(
            changed: key,
            all: all,
            remote: remoteState,
            dadata: dadata
        )
        remoteState = newRemote
        remoteMessages = remote
        
        // 3) UI всегда видит merged = local + remote по правилам ниже
        applyMergedMessagesToFieldStates()
    }
    
    /// Иногда удобно дергать “общую” проверку (как раньше), если blur-key не прокинут.
    func validateOnFocusLost() async {
        validateAllLocal()
        
        let all = currentFieldValues
        let (newRemote, remote) = await validator.validateOnFocusLost(
            all: all,
            remote: remoteState,
            dadata: dadata
        )
        remoteState = newRemote
        remoteMessages = remote
        
        applyMergedMessagesToFieldStates()
    }
    
    // MARK: - Build DTO
    
    func buildDTO(allowWithErrors: Bool = false) throws -> CompanyDetails {
        validateAllLocal()
        if hasErrors && !allowWithErrors {
            // если у тебя есть свой тип ошибки — подставь его
            // throw ValidationError.hasErrors
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
    
    /// meta validator (FieldMetadata) > validator.validateLocal
    private func validateField(for key: Key, value: String) -> FieldMessage? {
        return validator.validateField(for: key, value: value)
    }
    
    private func validateFieldValues(fieldValues: [Key: String]) {
        var newFieldMessages: [Key: FieldMessage] = [:]
        newFieldMessages.reserveCapacity(fieldValues.count)
        
        for key in allFieldKeys {
            let v = fieldValues[key] ?? ""
            if let msg = validateField(for: key, value: v) {
                newFieldMessages[key] = msg
            }
        }
        localMessages = newFieldMessages
    }
    
    // MARK: - Merge (UI uses merged only)
    
    /// Правило:
    /// - local error никогда не затираем
    /// - remote важнее local warning (но не важнее local error)
    /// - если local none → берём remote
    private func mergedMessage(for key: Key) -> FieldMessage? {
        let local = localMessages[key]
        let remote = remoteMessages[key]
        
        switch (local, remote) {
            case (nil, nil):
                return nil
                
            case (let l?, nil):
                return l
                
            case (nil, let r?):
                return r
                
            case (let l?, let r?):
                // error всегда выигрывает
                if l.severity == .error { return l }
                if r.severity == .error { return r }
                
                // warning vs warning: remote приоритетнее (или можно склеить тексты)
                if l.severity == .warning, r.severity == .warning {
                    // вариант 1: remote приоритетнее
                    return r
                    
                    // вариант 2 (если хочешь склеивать):
                    // return .init(.warning, "\(l.text)\n\(r.text)")
                }
                
                // warning + none / none + warning
                if r.severity == .warning { return r }
                return l
        }
    }
    
    private func applyMergedMessagesToFieldStates() {
        for key in allFieldKeys {
            guard var st = fields[key] else { continue }
            
            if let msg = mergedMessage(for: key) {
                st.message = msg.text
                st.severity = (msg.severity == .error) ? .error : .warning
            } else {
                st.message = nil
                st.severity = .none
            }
            
            fields[key] = st
        }
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
