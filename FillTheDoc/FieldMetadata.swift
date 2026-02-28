//
//  FieldMetadata.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//


import Foundation

struct FieldMetadata: Sendable {
    let title: String
    let placeholder: String
    let normalizer: @Sendable (String) -> String
    let validator: @Sendable (String) -> String?   // return error text or nil
}

enum FieldRules {

    // MARK: - Normalizers

    static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func digitsOnly(_ s: String) -> String {
        String(s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    }

    static func lowercased(_ s: String) -> String {
        trim(s).lowercased()
    }

    // MARK: - Validators

    static func optional(_ validate: @escaping @Sendable (String) -> String?) -> @Sendable (String) -> String? {
        { raw in
            let v = trim(raw)
            guard !v.isEmpty else { return nil }
            return validate(v)
        }
    }

    static func lengthIn(_ allowed: Set<Int>, label: String) -> @Sendable (String) -> String? {
        { value in
            guard allowed.contains(value.count) else {
                let list = allowed.sorted().map(String.init).joined(separator: " или ")
                return "\(label) должен содержать \(list) цифр"
            }
            return nil
        }
    }

    static func email() -> @Sendable (String) -> String? {
        { value in
            // NSDataDetector на macOS работает нормально, быстрее и надёжнее большинства regex.
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector?.matches(in: value, options: [], range: range) ?? []

            let ok = matches.contains { m in
                guard m.resultType == .link, let url = m.url else { return false }
                return url.scheme == "mailto" && m.range.length == range.length
            }
            return ok ? nil : "Некорректный email"
        }
    }

    static func legalForm() -> @Sendable (String) -> String? {
        { value in
            let allowed: Set<String> = ["ООО","ИП","АО","ПАО","НКО","ГУП","МУП"]
            return allowed.contains(value) ? nil : "Допустимые значения: \(allowed.sorted().joined(separator: ", "))"
        }
    }
}

extension CompanyDetails {
    /// Единая таблица метаданных. Ключи — JSON keys (snake_case).
    static let fieldMetadata: [String: FieldMetadata] = [
        "company_name": FieldMetadata(
            title: "Название организации",
            placeholder: "ООО «Ромашка»",
            normalizer: FieldRules.trim,
            validator: FieldRules.optional { _ in nil }
        ),
        "legal_form": FieldMetadata(
            title: "Орг. форма",
            placeholder: "ООО / ИП / АО ...",
            normalizer: FieldRules.trim,
            validator: FieldRules.optional(FieldRules.legalForm())
        ),
        "ceo_full_name": FieldMetadata(
            title: "Руководитель (ФИО)",
            placeholder: "Иванов Иван Иванович",
            normalizer: FieldRules.trim,
            validator: FieldRules.optional { _ in nil }
        ),
        "ceo_shorten_name": FieldMetadata(
            title: "Руководитель (кратко)",
            placeholder: "Иванов И.И.",
            normalizer: FieldRules.trim,
            validator: FieldRules.optional { _ in nil }
        ),
        "ogrn": FieldMetadata(
            title: "ОГРН / ОГРНИП",
            placeholder: "13 или 15 цифр",
            normalizer: { FieldRules.digitsOnly(FieldRules.trim($0)) },
            validator: FieldRules.optional(FieldRules.lengthIn([13, 15], label: "ОГРН/ОГРНИП"))
        ),
        "inn": FieldMetadata(
            title: "ИНН",
            placeholder: "10 или 12 цифр",
            normalizer: { FieldRules.digitsOnly(FieldRules.trim($0)) },
            validator: FieldRules.optional(FieldRules.lengthIn([10, 12], label: "ИНН"))
        ),
        "kpp": FieldMetadata(
            title: "КПП",
            placeholder: "9 цифр",
            normalizer: { FieldRules.digitsOnly(FieldRules.trim($0)) },
            validator: FieldRules.optional(FieldRules.lengthIn([9], label: "КПП"))
        ),
        "email": FieldMetadata(
            title: "Email",
            placeholder: "name@company.ru",
            normalizer: FieldRules.lowercased,
            validator: FieldRules.optional(FieldRules.email())
        )
    ]
}
