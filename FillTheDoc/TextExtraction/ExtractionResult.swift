//
//  ExtractionResult.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//


import Foundation

public struct ExtractionResult: Sendable {
    public enum Method: Sendable {
        case plainText
        case pdfKit
        case textutil
        case failed
    }

    public let text: String
    public let method: Method
    public let needsOCR: Bool
    public let diagnostics: Diagnostics

    public struct Diagnostics: Sendable {
        public var originalURL: URL
        public var fileExtension: String
        public var fileSizeBytes: Int64?
        public var producedChars: Int
        public var notes: [String]
        public var errors: [String]
    }
}

public enum TextExtractionError: Error {
    case unsupportedExtension(String)
    case emptyResult
}