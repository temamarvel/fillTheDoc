//
//  EditableDTO.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//


import Foundation
import Combine

final class CompanyDetailsModel<T: LLMExtractable>: ObservableObject {

    struct FieldState: Equatable {
        var value: String
        var error: String?
        var isDirty: Bool
    }

    @Published private(set) var fields: [String: FieldState] = [:] // key -> state

    private let original: [String: String]
    private let metadata: [String: FieldMetadata]
    private let orderedKeys: [String]

    init(dto: T, metadata: [String: FieldMetadata]) {
        self.metadata = metadata
        self.orderedKeys = T.CodingKeys.allCases.map(\.stringValue)
        self.original = Self.dtoToStringMap(dto, keys: Set(self.orderedKeys))

        // создаём FieldState для всех ключей схемы
        var f: [String: FieldState] = [:]
        for key in orderedKeys {
            let v = original[key] ?? ""
            f[key] = FieldState(value: v, error: nil, isDirty: false)
        }
        self.fields = f

        // первичная валидация (не обязана, но полезна)
        validateAll()
    }

    // MARK: - Public API

    func keysInOrder() -> [String] { orderedKeys }

    func title(for key: String) -> String {
        metadata[key]?.title ?? humanize(key)
    }

    func placeholder(for key: String) -> String {
        metadata[key]?.placeholder ?? ""
    }

    func value(for key: String) -> String {
        fields[key]?.value ?? ""
    }

    func error(for key: String) -> String? {
        fields[key]?.error
    }

    func setValue(_ newValue: String, for key: String) {
        guard var st = fields[key] else { return }

        // нормализуем
        let normalized = (metadata[key]?.normalizer ?? FieldRules.trim)(newValue)

        st.value = normalized
        st.isDirty = (normalized != (original[key] ?? ""))
        st.error = (metadata[key]?.validator ?? { _ in nil })(normalized)

        fields[key] = st
    }

    func validateAll() {
        for key in orderedKeys {
            setValue(value(for: key), for: key) // прогоняем нормализатор+валидатор
        }
    }

    var hasErrors: Bool {
        fields.values.contains { ($0.error?.isEmpty == false) }
    }

    /// Собрать обратно DTO. Бросает ошибку, если есть ошибки (по умолчанию).
    func buildDTO(allowWithErrors: Bool = false) throws -> T {
        validateAll()
        if hasErrors && !allowWithErrors {
            throw ValidationError.hasErrors
        }

        // собираем dict (пустые строки — отсутствие значения)
        var dict: [String: Any] = [:]
        for key in orderedKeys {
            let raw = value(for: key)
            let trimmed = FieldRules.trim(raw)
            guard !trimmed.isEmpty else { continue }
            dict[key] = trimmed
        }

        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ValidationError.decodeFailed("\(error)")
        }
    }

    enum ValidationError: LocalizedError {
        case hasErrors
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .hasErrors: return "Исправьте ошибки в полях и попробуйте снова."
            case .decodeFailed(let msg): return "Не удалось собрать DTO из введённых значений: \(msg)"
            }
        }
    }

    // MARK: - Helpers

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

    private func humanize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
