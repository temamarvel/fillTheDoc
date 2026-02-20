//
//  OpenAIPromptBuilder.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 20.02.2026.
//


enum PromptBuilder {
    
    static func system<T: LLMExtractable>(for type: T.Type) -> String {
        
        let base = """
        You are a precision information extraction engine for Russian legal entity requisites.
        Return ONLY a JSON object.
        
        Hard rules:
        - Output must be a single JSON object. No markdown. No comments. No extra keys.
        - Use exactly these keys: \(type.llmSchemaKeysLine)
        - If a value is missing in the text, return null.
        - Do not guess or invent values.
        - Preserve original spelling from the source when possible.
        - For number identifiers (INN/KPP/OGRN): return digits only (no spaces, no separators).
        - Email must be a valid email if present; otherwise null.
        - legal_form must be one of: "ООО", "ИП", "АО", "ПАО", "НКО", "ГУП", "МУП", or null.
        - ceo_shorten_name must be in format "Фамилия И.О." if ceo_full_name is present; otherwise null.
        """
        
        let hints: [String: String] = [
            "inn": "INN must contain 10 or 12 digits.",
            "kpp": "KPP must contain 9 digits.",
            "ogrn": "OGRN must contain 13 digits (or 15 digits for OGRNIP).",
            "email": "Email must match a valid email format.",
            "ceo_full_name": "CEO full name should be Russian full name (Surname Name Patronymic) if present."
        ]
        
        let activeHints = type.llmSchemaKeys.compactMap { key in
            hints[key].map { "- \(key): \($0)" }
        }
        
        guard !activeHints.isEmpty else { return base }
        
        return base + """
        
        Field hints:
        \(activeHints.joined(separator: "\n"))
        """
    }

    static func user(sourceText: String) -> String {
        """
        Extract requisites from the SOURCE TEXT below.

        Notes:
        - Requisites often appear near labels like: "Реквизиты", "ИНН", "КПП", "ОГРН/ОГРНИП", "Генеральный директор/Директор", "E-mail/Email".
        - If multiple companies are present, prefer the main organization (often "Исполнитель/Поставщик/Продавец" depending on document type).

        SOURCE TEXT:
        ---
        \(sourceText)
        ---
        """
    }
}
