//
//  Validators.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 26.03.2026.
//

import Foundation

/// Централизованное место для всех валидаторов полей.
/// Структурированы по типам: формат, диапазон, синтаксис, подобие.
enum Validators {
    
    // MARK: - Generic helpers
    
    /// Валидатор, который пропускает пустые значения.
    static func optional(_ validate: @escaping (String) -> String?) -> (String) -> String? {
        { raw in
            let v = raw.trimmed
            guard !v.isEmpty else { return nil }
            return validate(v)
        }
    }
    
    // MARK: - Format validators (for specific document IDs)
    
    /// Валидирует ИНН (10 или 12 цифр с контрольной суммой).
    static func inn(_ innRaw: String) -> FieldIssue? {
        let inn = innRaw.digitsOnly
        var isValid: Bool = false
        if inn.count == 10 {
            isValid = innChecksum10(inn)
        }
        if inn.count == 12 {
            isValid = innChecksum12(inn)
        }
        return isValid ? nil : .error("Не верный ИНН")
    }
    
    private static func innChecksum10(_ inn: String) -> Bool {
        guard inn.count == 10, let digits = innDigits(inn) else { return false }
        let weights = [2,4,10,3,5,9,4,6,8]
        let sum = zip(weights, digits.prefix(9)).map(*).reduce(0,+)
        let check = (sum % 11) % 10
        return check == digits[9]
    }
    
    private static func innChecksum12(_ inn: String) -> Bool {
        guard inn.count == 12, let digits = innDigits(inn) else { return false }
        let w1 = [7,2,4,10,3,5,9,4,6,8,0]
        let w2 = [3,7,2,4,10,3,5,9,4,6,8,0]
        
        let sum1 = zip(w1, digits.prefix(11)).map(*).reduce(0,+)
        let c1 = (sum1 % 11) % 10
        
        let sum2 = zip(w2, digits.prefix(11)).map(*).reduce(0,+)
        let c2 = (sum2 % 11) % 10
        
        return c1 == digits[10] && c2 == digits[11]
    }
    
    private static func innDigits(_ s: String) -> [Int]? {
        let arr = s.compactMap { Int(String($0)) }
        return arr.count == s.count ? arr : nil
    }
    
    /// Валидирует КПП (ровно 9 цифр).
    static func kpp(_ kppRaw: String) -> FieldIssue? {
        if kppRaw.isEmpty {
            return .warning("КПП не введен")
        }
        
        let kpp = kppRaw.digitsOnly
        let isValid = kpp.count == 9
        return isValid ? nil : .error("Не верный КПП")
    }
    
    /// Валидирует ОГРН/ОГРНИП (13 или 15 цифр с контрольной суммой).
    static func ogrn(_ ogrnRaw: String) -> FieldIssue? {
        let ogrn = ogrnRaw.digitsOnly
        var isValid: Bool = false
        if ogrn.count == 13 { isValid = ogrnChecksum(ogrn, modBase: 11) }
        if ogrn.count == 15 { isValid = ogrnChecksum(ogrn, modBase: 13) }
        
        return isValid ? nil : .error("Не верный ОГРН")
    }
    
    private static func ogrnChecksum(_ ogrn: String, modBase: Int) -> Bool {
        guard ogrn.count >= 2 else { return false }
        let body = String(ogrn.dropLast())
        guard let bodyNumber = Int(body),
              let last = Int(String(ogrn.last!))
        else { return false }
        
        let check = (bodyNumber % modBase) % 10
        return check == last
    }
    
    // MARK: - Syntax validators
    
    /// Валидирует email-адрес.
    static func email(_ value: String) -> FieldIssue? {
        if value.isEmpty {
            return .warning("E-main не введен")
        }

        // NSDataDetector на macOS работает нормально, быстрее и надёжнее большинства regex.
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: value, options: [], range: range) ?? []
        
        let ok = matches.contains { m in
            guard m.resultType == .link, let url = m.url else { return false }
            return url.scheme == "mailto" && m.range.length == range.length
        }
        return ok ? nil : .error("Некорректный email")
    }
    
    // MARK: - Enum validators
    
    /// Валидирует правовую форму компании.
    static func legalForm(_ value: String) -> String? {
        guard let form = LegalForm.parse(value) else {
            let allowed = LegalForm.allCases
                .map(\.shortName)
                .sorted()
                .joined(separator: ", ")
            
            return "Допустимые значения: \(allowed)"
        }
        
        return nil
    }
    
    // MARK: - Content heuristics
    
    /// Эвристика: проверяет, похожа ли строка на адрес (буквы + цифры + маркеры).
    static func looksLikeAddress(_ s: String) -> Bool {
        let normalized = Normalizers.forComparison(s)
        guard normalized.count >= 8 else { return false }
        
        let hasDigit = normalized.contains(where: { $0.isNumber })
        let hasLetter = normalized.contains(where: { $0.isLetter })
        
        let markers = ["г", "город", "ул", "улица", "пр", "проспект", "д", "дом", "корп", "кв", "обл", "респ", "край", "р-н", "район", "пер", "проезд", "ш", "шоссе"]
        let hasMarker = markers.contains { normalized.contains($0) }
        
        return hasDigit && hasLetter && hasMarker
    }
    
    // MARK: - Similarity validators
    
    /// Вычисляет коэффициент Jaccard (0...1) между двумя строками.
    static func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let ta = Normalizers.toTokens(a)
        let tb = Normalizers.toTokens(b)
        guard !ta.isEmpty || !tb.isEmpty else { return 1 }
        let inter = ta.intersection(tb).count
        let union = ta.union(tb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }
    
    /// Проверяет, содержит ли одна нормализованная строка другую.
    static func containsNormalized(_ a: String, _ b: String) -> Bool {
        let na = Normalizers.forComparison(a)
        let nb = Normalizers.forComparison(b)
        return na.contains(nb) || nb.contains(na)
    }
    
    // MARK: - Field-specific convenience validators
    
    /// Простая валидация непустого текста.
    static func nonEmpty(_ v: String) -> FieldIssue? {
        let t = v.trimmed
        return t.isEmpty ? .error("Поле не может быть пустым") : nil
    }
    
    /// Валидация ФИО: минимум 2 слова, только буквы и дефисы.
    static func fullName(_ v: String) -> FieldIssue? {
        let t = v.trimmed
        guard !t.isEmpty else { return .error("Поле не может быть пустым") }
        
        let words = t.split(separator: " ").filter { !$0.isEmpty }
        if words.count < 2 {
            return .warning("Ожидается минимум Фамилия и Имя")
        }
        
        let hasInvalidChars = t.contains(where: { !$0.isLetter && $0 != " " && $0 != "-" })
        if hasInvalidChars {
            return .warning("ФИО обычно содержит только буквы")
        }
        
        return nil
    }
    
    /// Валидация краткого ФИО: формат «Фамилия И.О.» или «Фамилия И.».
    static func shortenName(_ v: String) -> FieldIssue? {
        let t = v.trimmed
        guard !t.isEmpty else { return .error("Поле не может быть пустым") }
        
        // Паттерн: одно или несколько слов (фамилия), затем инициалы с точками
        // Примеры: " И.И. Иванов", " И. И. Иванов-Петров", " И. Иванов"
        let pattern = #"^[А-ЯЁA-Z]\.\s*(?:[А-ЯЁA-Z]\.\s*)?[А-ЯЁA-Z][а-яёa-zА-ЯЁA-Z\-]+$"#
        let matches = t.range(of: pattern, options: .regularExpression) != nil
        
        if !matches {
            return .warning("Ожидается формат «И.О. Фамилия»")
        }
        
        return nil
    }
    
    /// Валидация правовой формы (возвращает FieldValidationResult).
    static func legalFormField(_ v: String) -> FieldIssue? {
        let t = v.trimmed
        guard !t.isEmpty else { return .error("Поле не может быть пустым") }
        
        if let error = legalForm(t) {
            return .error(error)
        }
        return nil
    }
    
    /// Валидация адреса (мягкая эвристика — warning, не error).
    static func address(_ v: String) -> FieldIssue? {
        let t = v.trimmed
        guard !t.isEmpty else { return .error("Поле не может быть пустым") }
        
        if t.count < 10 {
            return .warning("Адрес выглядит слишком коротким")
        }
        
        if !looksLikeAddress(t) {
            return .warning("Не похоже на адрес (нет маркеров: г., ул., д. и т.п.)")
        }
        
        return nil
    }
    
    /// Валидация телефона: должен начинаться с + или 8, содержать 10-11 цифр.
    static func phone(_ v: String) -> FieldIssue? {
        if v.isEmpty {
            return .warning("Телефон не введен")
        }
        
        let t = v.trimmed
        guard !t.isEmpty else { return .error("Поле не может быть пустым") }
        
        let digits = t.digitsOnly
        
        guard digits.count >= 10 && digits.count <= 15 else {
            return .warning("Телефон обычно содержит 10–11 цифр")
        }
        
        // Проверяем допустимые символы: цифры, +, -, (, ), пробел
        let allowed = CharacterSet(charactersIn: "0123456789+()-– ").union(.whitespaces)
        let hasInvalid = t.unicodeScalars.contains { !allowed.contains($0) }
        if hasInvalid {
            return .warning("Телефон содержит необычные символы")
        }
        
        return nil
    }
    
    /// Валидация: число (включая дробное) в диапазоне 0–100
    static func percentage(_ value: String) -> String? {
        let trimmed = value.trimmed
        
        if trimmed.isEmpty {
            return "Поле обязательно для заполнения"
        }
        
        // Нормализация: запятая → точка
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        
        // Проверка допустимых символов
        let allowedChars = CharacterSet(charactersIn: "0123456789.")
        if normalized.rangeOfCharacter(from: allowedChars.inverted) != nil {
            return "Разрешены только цифры и разделитель (точка или запятая)"
        }
        
        // Не больше одной точки
        if normalized.filter({ $0 == "." }).count > 1 {
            return "Некорректный формат числа"
        }
        
        guard let number = Double(normalized) else {
            return "Некорректное число"
        }
        
        if number < 0 || number > 100 {
            return "Значение должно быть от 0 до 100"
        }
        
        return nil
    }
}
