import Foundation
import DaDataAPIClient
import Combine

final class CompanyDetailsModel<T: LLMExtractable>: ObservableObject {
    
    enum FieldSeverity: Equatable { case none, warning, error }
    
    struct FieldState: Equatable {
        var value: String
        var message: String?
        var severity: FieldSeverity
        var isDirty: Bool
    }
    
    @Published private(set) var fields: [String: FieldState] = [:]
    
    private let original: [String: String]
    private let metadata: [String: FieldMetadata]
    private let orderedKeys: [String]
    
    // NEW:
    private let validator: CompanyDetailsValidator
    private let dadata: DaDataClient
    private var remoteState = CompanyDetailsValidator.RemoteState()
    
    init(
        dto: T,
        metadata: [String: FieldMetadata],
        validator: CompanyDetailsValidator,
        dadata: DaDataClient
    ) {
        self.metadata = metadata
        self.orderedKeys = T.CodingKeys.allCases.map(\.stringValue)
        self.original = Self.dtoToStringMap(dto, keys: Set(self.orderedKeys))
        self.validator = validator
        self.dadata = dadata
        
        var f: [String: FieldState] = [:]
        for key in orderedKeys {
            let v = original[key] ?? ""
            f[key] = FieldState(value: v, message: nil, severity: .none, isDirty: false)
        }
        self.fields = f
        
        validateAll()
    }
    
    // MARK: - Field access
    
    func keysInOrder() -> [String] { orderedKeys }
    func value(for key: String) -> String { fields[key]?.value ?? "" }
    func message(for key: String) -> String? { fields[key]?.message }
    func severity(for key: String) -> FieldSeverity { fields[key]?.severity ?? .none }
    
    var hasErrors: Bool {
        fields.values.contains { $0.severity == .error }
    }
    
    // MARK: - Set value (local validation only)
    
    func setValue(_ newValue: String, for key: String) {
        guard var st = fields[key] else { return }
        
        let normalized = (metadata[key]?.normalizer ?? FieldRules.trim)(newValue)
        st.value = normalized
        st.isDirty = (normalized != (original[key] ?? ""))
        
        // 1) твой per-field metadata validator (если нужен)
        let metaError = (metadata[key]?.validator ?? { _ in nil })(normalized)
        
        // 2) локальная форма-валидация (без сети)
        let all = currentStringMap()
        let localMsg = validator.validateLocal(key: key, value: normalized, all: all)
        
        // приоритет: metaError (обычно “жёстко”) > localMsg
        if let metaError, !metaError.isEmpty {
            st.message = metaError
            st.severity = .error
        } else if let localMsg {
            st.message = localMsg.text
            st.severity = (localMsg.severity == .error) ? .error : .warning
        } else {
            st.message = nil
            st.severity = .none
        }
        
        fields[key] = st
    }
    
    func validateAll() {
        for key in orderedKeys {
            setValue(value(for: key), for: key)
        }
    }
    
    // MARK: - Remote validation on focus lost
    
    /// Вызывай из UI только при blur поля.
    @MainActor
    func validateOnFocusLost(key: String) async {
        // 0) сначала убедимся, что локальное состояние актуально
        setValue(value(for: key), for: key)
        
        let all = currentStringMap()
        let (newRemote, msg) = await validator.validateOnFocusLost(
            key: key,
            all: all,
            remote: remoteState,
            dadata: dadata
        )
        
        remoteState = newRemote
        
        // Применяем только результат для этого поля (не трогаем другие)
        guard var st = fields[key] else { return }
        
        if let msg {
            // если у поля уже есть error от локальной/metadata — не понижаем до warning
            if st.severity != .error {
                st.message = msg.text
                st.severity = (msg.severity == .error) ? .error : .warning
            }
        } else {
            // если это поле не имеет локальных ошибок — можно очистить message
            // но осторожно: не сносим локальные предупреждения, если они есть
            // (тут простая логика: пересчитать local ещё раз)
            let localMsg = validator.validateLocal(key: key, value: st.value, all: all)
            if let localMsg {
                st.message = localMsg.text
                st.severity = (localMsg.severity == .error) ? .error : .warning
            } else if st.severity != .error {
                st.message = nil
                st.severity = .none
            }
        }
        
        fields[key] = st
    }
    
    // MARK: - Helpers
    
    private func currentStringMap() -> [String: String] {
        var result: [String: String] = [:]
        for k in orderedKeys {
            result[k] = fields[k]?.value ?? ""
        }
        return result
    }
    
    private static func dtoToStringMap(_ dto: T, keys: Set<String>) -> [String: String] {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(dto),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let dict = obj as? [String: Any]
        else { return [:] }
        
        var result: [String: String] = [:]
        for (k, v) in dict where keys.contains(k) {
            if v is NSNull { result[k] = "" }
            else { result[k] = String(describing: v) }
        }
        return result
    }
    
    /// Собрать обратно DTO. Бросает ошибку, если есть ошибки (по умолчанию).
    func buildDTO(allowWithErrors: Bool = false) throws -> T {
        validateAll()
//        if hasErrors && !allowWithErrors {
//            throw ValidationError.hasErrors
//        }
        
        // собираем dict (пустые строки — отсутствие значения)
        var dict: [String: Any] = [:]
        for key in orderedKeys {
            let raw = value(for: key)
            let trimmed = FieldRules.trim(raw)
            guard !trimmed.isEmpty else { continue }
            dict[key] = trimmed
        }
        
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        
        return try JSONDecoder().decode(T.self, from: data)
//        
//        do {
//            return try JSONDecoder().decode(T.self, from: data)
//        } catch {
////            throw ValidationError.decodeFailed("\(error)")
//            setValue(value(for: key), for: key)
//        }
    }
}
