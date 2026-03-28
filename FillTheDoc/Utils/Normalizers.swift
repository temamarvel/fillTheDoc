//
//  Normalizers.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 26.03.2026.
//

import Foundation

/// Централизованное место для всех нормализаторов полей.
/// Структурированы по уровню: базовые, комбинированные, специализированные.
nonisolated enum Normalizers {
    
    // MARK: - Combined normalizers
    
    /// Обрезает пробелы и оставляет только цифры.
    static func trimmedDigitsOnly(_ s: String) -> String {
        s.trimmed.digitsOnly
    }
    
    // MARK: - Specialized normalizers
    
    /// Нормализует телефонный номер: убирает скобки, лишние пробелы, оставляет +, цифры и дефисы.
    static func phone(_ s: String) -> String {
        let t = s.trimmed
        // Убираем скобки и множественные пробелы, оставляем цифры, +, -
        let cleaned = t
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "–", with: "-")   // длинное тире → короткий дефис
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return cleaned
    }
    
    /// Нормализирует правовую форму: приводит к верхнему регистру после обрезки.
    /// Удаляет диакритику, кавычки, пунктуацию.
    static func legalForm(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmed
            .replacingOccurrences(of: "«", with: "")
            .replacingOccurrences(of: "»", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "  ", with: " ")
    }
    
    /// Нормализирует текст для сравнения: удаляет пунктуацию, нижний регистр, коллапсирует пробелы.
    /// Используется для Jaccard similarity, containsNormalized.
    static func forComparison(_ s: String) -> String {
        let lower = s.lowercased()
        
        let cleaned = lower.unicodeScalars.map { scalar -> Character in
            let ch = Character(scalar)
            if CharacterSet.alphanumerics.union(.whitespacesAndNewlines).contains(scalar) {
                return ch
            }
            return " "
        }
        
        let collapsed = String(cleaned)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        
        // нормализуем распространённые ОПФ
        return collapsed
            .replacingOccurrences(of: "общество с ограниченной ответственностью", with: "ооо")
            .replacingOccurrences(of: "акционерное общество", with: "ао")
            .replacingOccurrences(of: "публичное акционерное общество", with: "пао")
            .replacingOccurrences(of: "индивидуальный предприниматель", with: "ип")
    }
    
    /// Разбивает нормализованную строку на токены (слова).
    static func toTokens(_ s: String) -> Set<String> {
        Set(forComparison(s).split(separator: " ").map(String.init).filter { !$0.isEmpty })
    }
    
    /// Нормализирует большой текст для отображения: коллапсирует пустые строки, обрезает по символам.
    /// Используется при извлечении текста из документов.
    static func forDocumentDisplay(_ text: String, maxChars: Int) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        
        s = collapseBlankLines(s, maxConsecutive: 2)
        s = s.trimmed
        
        guard s.count > maxChars else { return s }
        
        let headCount = Int(Double(maxChars) * 0.65)
        let tailCount = maxChars - headCount
        
        let head = s.prefix(headCount)
        let tail = s.suffix(tailCount)
        return """
        \(head)
        
        ...[TRUNCATED]...
        
        \(tail)
        """
    }
    
    private static func collapseBlankLines(_ s: String, maxConsecutive: Int) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        
        var blanks = 0
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                blanks += 1
                if blanks <= maxConsecutive { result += "\n" }
            } else {
                blanks = 0
                result += String(line) + "\n"
            }
        }
        return result
    }
}
