//
//  DocumentTextExtractorService.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation


public struct DocumentTextExtractorService {

    public struct Configuration {
        public var maxChars: Int = 60_000
        public var officeTimeout: TimeInterval = 15
        public var requireNonEmptyText: Bool = false
        public init() {}
    }

    private let config: Configuration
    private let security: SecurityScopedAccessing
    private let tempStore: TempFileStoring
    private let txtExtractor: TextExtracting
    private let pdfExtractor: TextExtracting
    private let officeExtractor: TextExtracting

    // ✅ Designated init for DI / tests
    public init(
        config: Configuration = .init(),
        security: SecurityScopedAccessing,
        tempStore: TempFileStoring,
        txtExtractor: TextExtracting,
        pdfExtractor: TextExtracting,
        officeExtractor: TextExtracting
    ) {
        self.config = config
        self.security = security
        self.tempStore = tempStore
        self.txtExtractor = txtExtractor
        self.pdfExtractor = pdfExtractor
        self.officeExtractor = officeExtractor
    }

    // ✅ Convenience init for production (config only)
    public init(config: Configuration = .init()) {
        let runner = DefaultProcessRunner()
        self.init(
            config: config,
            security: DefaultSecurityScopedAccessor(),
            tempStore: DefaultTempFileStore(),
            txtExtractor: PlainTextExtractor(),
            pdfExtractor: PDFKitTextExtractor(),
            officeExtractor: TextutilOfficeExtractor(runner: runner, timeout: config.officeTimeout)
        )
    }

    public func extract(from originalURL: URL) throws -> ExtractionResult {
        var diagnostics = ExtractionResult.Diagnostics(
            originalURL: originalURL,
            fileExtension: originalURL.pathExtension.lowercased(),
            fileSizeBytes: FileInfo.fileSizeBytes(originalURL),
            producedChars: 0,
            notes: [],
            errors: []
        )

        return try security.withAccess(originalURL) {
            let tempURL = try tempStore.copyToTemp(originalURL)
            defer { tempStore.cleanup(forTempCopy: tempURL) }

            let ext = tempURL.pathExtension.lowercased()

            do {
                let (rawText, method, needsOCR, notes): (String, ExtractionResult.Method, Bool, [String]) = try {
                    switch ext {
                    case "txt":
                        return try txtExtractor.extract(from: tempURL)
                    case "pdf":
                        return try pdfExtractor.extract(from: tempURL)
                    case "doc", "docx", "xls", "xlsx":
                        return try officeExtractor.extract(from: tempURL)
                    default:
                        throw TextExtractionError.unsupportedExtension(ext)
                    }
                }()

                diagnostics.notes.append(contentsOf: notes)

                let normalized = TextNormalizer.normalize(rawText, maxChars: config.maxChars)
                let finalText = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                diagnostics.producedChars = finalText.count

                let finalNeedsOCR = needsOCR || (ext == "pdf" && finalText.isEmpty)
                if finalText.isEmpty {
                    diagnostics.notes.append("Text is empty after normalization.")
                    if config.requireNonEmptyText { throw TextExtractionError.emptyResult }
                }

                return ExtractionResult(
                    text: finalText,
                    method: method,
                    needsOCR: finalNeedsOCR,
                    diagnostics: diagnostics
                )
            } catch {
                diagnostics.errors.append("Extractor error: \(String(describing: error))")
                let needsOCR = (ext == "pdf")
                let result = ExtractionResult(
                    text: "",
                    method: .failed,
                    needsOCR: needsOCR,
                    diagnostics: diagnostics
                )
                if config.requireNonEmptyText { throw TextExtractionError.emptyResult }
                return result
            }
        }
    }
}
