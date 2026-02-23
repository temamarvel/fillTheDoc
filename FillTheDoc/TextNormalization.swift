//
//  TextNormalization.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 23.02.2026.
//

import Foundation


enum TextNormalization {
    static func normalize(_ s: String) -> String {
        let lower = s.lowercased()

        // убрать кавычки/ёлочки и пунктуацию, заменить на пробел
        let cleaned = lower.unicodeScalars.map { scalar -> Character in
            let ch = Character(scalar)
            if CharacterSet.alphanumerics.union(.whitespacesAndNewlines).contains(scalar) {
                return ch
            }
            return " "
        }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // нормализуем распространённые ОПФ
        return collapsed
            .replacingOccurrences(of: "общество с ограниченной ответственностью", with: "ооо")
            .replacingOccurrences(of: "акционерное общество", with: "ао")
            .replacingOccurrences(of: "публичное акционерное общество", with: "пао")
            .replacingOccurrences(of: "индивидуальный предприниматель", with: "ип")
    }

    static func tokens(_ s: String) -> Set<String> {
        Set(normalize(s).split(separator: " ").map(String.init).filter { !$0.isEmpty })
    }

    /// 0...1
    static func jaccard(_ a: String, _ b: String) -> Double {
        let ta = tokens(a)
        let tb = tokens(b)
        guard !ta.isEmpty || !tb.isEmpty else { return 1 }
        let inter = ta.intersection(tb).count
        let union = ta.union(tb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    static func containsNormalized(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)
        return na.contains(nb) || nb.contains(na)
    }
}
