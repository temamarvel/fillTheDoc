//
//  DocxTemplatePlaceholderScanner.swift
//  FillTheDoc
//
//  Created by Artem Denisov on 16.03.2026.
//

import Foundation
import ZIPFoundation

public final class DocxTemplatePlaceholderScanner: Sendable {
    
    // MARK: - Public types
    
    public struct Options: Sendable {
        public var includeFootnotes: Bool = true
        public var includeEndnotes: Bool = true
        public var includeComments: Bool = true
        public var selection: PartsSelection = .standard
        public var includeFieldInstructionText: Bool = false
        public var validateTemplate: Bool = true
        public var onWarning: (@Sendable (String) -> Void)? = nil
        
        public enum PartsSelection: Sendable {
            case standard
            case allWordXML
        }
        
        public init() {}
        
        var coreOptions: DocxPartsOptions {
            DocxPartsOptions(
                includeFootnotes: includeFootnotes,
                includeEndnotes: includeEndnotes,
                includeComments: includeComments,
                includeFieldInstructionText: includeFieldInstructionText,
                selection: selection == .allWordXML ? .allWordXML : .standard
            )
        }
    }
    
    public struct Report: Sendable {
        public var processedParts: [String] = []
        public var orderedKeys: [String] = []
        public var foundKeys: Set<String> = []
        public var occurrences: [String: Int] = [:]
        public var partsByKey: [String: Set<String>] = [:]
        
        public init() {}
        
        public var sortedKeys: [String] { foundKeys.sorted() }
    }
    
    public init() {}
    
    // MARK: - Public API
    
    public nonisolated func scan(
        template: URL,
        options: Options = .init()
    ) async throws -> Report {
        let fm = FileManager.default
        
        if options.validateTemplate {
            guard fm.fileExists(atPath: template.path) else {
                throw DocxTemplateError.templateNotFound(template)
            }
        }
        
        let archive: Archive
        do {
            archive = try Archive(url: template, accessMode: .read)
        } catch {
            throw DocxTemplateError.invalidDocx
        }
        
        let partPaths = locatePartPaths(in: archive, options: options.coreOptions)
        
        guard partPaths.contains("word/document.xml") else {
            throw DocxTemplateError.missingMainDocumentXML
        }
        
        var report = Report()
        
        for partPath in partPaths {
            guard let entry = archive[partPath] else { continue }
            
            do {
                let data = try extractEntryData(from: entry, in: archive)
                let document = try parseXMLDocument(data: data, partPath: partPath)
                let partResult = scanDocument(document, options: options)
                
                if !partResult.foundKeys.isEmpty {
                    report.processedParts.append(partPath)
                }
                
                merge(partResult, from: partPath, into: &report)
            } catch {
                options.onWarning?("Failed to scan \(partPath): \(error.localizedDescription)")
            }
        }
        
        return report
    }
    
    public nonisolated func scanKeys(
        template: URL,
        options: Options = .init()
    ) async throws -> [String] {
        let report = try await scan(template: template, options: options)
        return report.orderedKeys
    }
    
    // MARK: - Private
    
    private struct PartScanResult {
        var foundKeys: [String] = []
        var occurrences: [String: Int] = [:]
    }
    
    private func scanDocument(_ document: XMLDocument, options: Options) -> PartScanResult {
        var result = PartScanResult()
        
        for paragraph in findParagraphs(in: document) {
            let segments = collectTextSegments(in: paragraph, includeFieldInstructionText: options.includeFieldInstructionText)
            guard !segments.isEmpty else { continue }
            
            let fullText = segments.map(\.text).joined()
            let matches = findPlaceholders(in: fullText)
            
            for match in matches {
                result.foundKeys.append(match.key)
                result.occurrences[match.key, default: 0] += 1
            }
        }
        
        return result
    }
    
    private func merge(_ partResult: PartScanResult, from partPath: String, into report: inout Report) {
        for key in partResult.foundKeys {
            if report.foundKeys.insert(key).inserted {
                report.orderedKeys.append(key)
            }
            report.partsByKey[key, default: []].insert(partPath)
        }
        
        for (key, count) in partResult.occurrences {
            report.occurrences[key, default: 0] += count
        }
    }
}
