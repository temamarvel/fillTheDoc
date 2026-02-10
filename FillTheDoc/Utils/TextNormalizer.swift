//
//  TextNormalizer.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//


import Foundation
enum TextNormalizer {
    static func normalize(_ text: String, maxChars: Int) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")

        s = collapseBlankLines(s, maxConsecutive: 2)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

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
