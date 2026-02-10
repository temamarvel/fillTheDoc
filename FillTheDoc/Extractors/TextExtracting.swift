//
//  TextExtracting.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//


import Foundation

public protocol TextExtracting {
    /// Возвращает (text, method, needsOCR, notes)
    func extract(from url: URL) throws -> (String, ExtractionResult.Method, Bool, [String])
}
