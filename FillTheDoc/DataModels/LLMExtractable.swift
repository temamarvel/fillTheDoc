//
//  LLMExtractable.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 20.02.2026.
//

import Foundation


protocol LLMExtractable: Codable {
    associatedtype CodingKeys: CaseIterable & CodingKey
}

extension LLMExtractable {
    static var llmSchemaKeys: [String] {
        CodingKeys.allCases.map(\.stringValue)
    }

    static var llmSchemaKeysLine: String {
        llmSchemaKeys.joined(separator: ", ")
    }
}

extension LLMExtractable {
    
    func asDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(self),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            return [:]
        }
        
        return dict
    }
    
    func toMultilineString() -> String {
        let dict = asDictionary()
        
        return dict
            .compactMap { key, value in
                guard !(value is NSNull) else { return nil }
                return "\(key): \(value)"
            }
            .sorted()
            .joined(separator: "\n")
    }
}
