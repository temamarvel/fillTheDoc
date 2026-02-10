//
//  PDFKitTextExtractor.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation
import PDFKit


public struct PDFKitTextExtractor: TextExtracting {
    public init() {}

    public func extract(from url: URL) throws -> (String, ExtractionResult.Method, Bool, [String]) {
        guard let doc = PDFDocument(url: url) else {
            return ("", .pdfKit, false, ["PDFDocument init failed."])
        }

        var pages: [String] = []
        pages.reserveCapacity(doc.pageCount)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let s = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !s.isEmpty { pages.append(s) }
        }

        let text = pages.joined(separator: "\n\n")
        let hasSelectableText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsOCR = !hasSelectableText

        var notes = ["PDFKit extracted selectable text: \(hasSelectableText)."]
        if needsOCR { notes.append("Likely scanned PDF; OCR recommended.") }

        return (text, .pdfKit, needsOCR, notes)
    }
}
