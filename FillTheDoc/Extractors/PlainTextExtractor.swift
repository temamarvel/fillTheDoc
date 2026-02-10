//
//  PlainTextExtractor.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation


public struct PlainTextExtractor: TextExtracting {
    public init() {}

    public func extract(from url: URL) throws -> (String, ExtractionResult.Method, Bool, [String]) {
        let data = try Data(contentsOf: url)
        let text = TextDecoding.decodeBestEffort(data)
        return (text, .plainText, false, ["TXT decoded with fallbacks."])
    }
}
