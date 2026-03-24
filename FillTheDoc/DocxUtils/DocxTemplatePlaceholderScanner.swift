//
//  DocxTemplatePlaceholderScanner.swift
//  FillTheDoc
//
//  Created by Artem Denisov on 16.03.2026.
//

import Foundation
import ZIPFoundation
public import Combine

public final class DocxTemplatePlaceholderScanner: ObservableObject, Sendable {
    
    // MARK: - Public
    
    public struct Options: Sendable {
        
        public enum PartsSelection: Sendable {
            /// document.xml + headers/footers + optional notes/comments
            case standard
            
            /// All top-level .xml files inside /word
            case allWordXML
        }
        
        public var includeFootnotes: Bool = true
        public var includeEndnotes: Bool = true
        public var includeComments: Bool = true
        
        public var selection: PartsSelection = .standard
        
        /// Also scan `<w:instrText>`.
        /// Usually false, but can be enabled for exotic templates.
        public var includeFieldInstructionText: Bool = false
        
        /// Validate file existence before processing
        public var validateTemplate: Bool = true
        
        /// Optional callback for non-fatal warnings
        public var onWarning: (@Sendable (String) -> Void)? = nil
        
        public init() {}
    }
    
    public struct Report: Sendable {
        /// XML parts where at least one placeholder was found.
        public var processedParts: [String] = []
        
        /// Unique placeholder keys in order of first appearance in the document flow.
        public var orderedKeys: [String] = []
        
        /// Unique placeholder keys as a set.
        public var foundKeys: Set<String> = []
        
        /// Count of each placeholder occurrence.
        public var occurrences: [String: Int] = [:]
        
        /// XML parts by placeholder key.
        public var partsByKey: [String: Set<String>] = [:]
        
        public init() {}
        
        public var sortedKeys: [String] {
            foundKeys.sorted()
        }
    }
    
    public enum Error: Swift.Error, LocalizedError {
        case invalidDocx
        case missingMainDocumentXML
        case templateNotFound(URL)
        case xmlReadFailed(part: String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidDocx:
                return "Invalid DOCX archive."
            case .missingMainDocumentXML:
                return "DOCX does not contain word/document.xml."
            case .templateNotFound(let url):
                return "Template file not found at: \(url.path)"
            case .xmlReadFailed(let part):
                return "Failed to read XML part: \(part)"
            }
        }
    }
    
    public init() {}
    
    /// Scans a DOCX template and returns detailed placeholder report.
    public func scan(
        template: URL,
        options: Options = .init()
    ) throws -> Report {
        let fm = FileManager.default
        
        if options.validateTemplate {
            guard fm.fileExists(atPath: template.path) else {
                throw Error.templateNotFound(template)
            }
        }
        
        let archive: Archive
        
        do {
            archive = try Archive(url: template, accessMode: .read)
        } catch {
            throw Error.invalidDocx
        }
        
        let partPaths = try locatePartPaths(in: archive, options: options)
        
        guard partPaths.contains("word/document.xml") else {
            throw Error.missingMainDocumentXML
        }
        
        var report = Report()
        
        for partPath in partPaths {
            guard let entry = archive[partPath] else { continue }
            
            do {
                let data = try extractData(from: entry, in: archive)
                let partReport = try scanXMLPart(
                    data: data,
                    options: options,
                    partPathForErrors: partPath
                )
                
                if !partReport.foundKeys.isEmpty {
                    report.processedParts.append(partPath)
                }
                
                merge(partReport, from: partPath, into: &report)
            } catch {
                options.onWarning?("Failed to scan \(partPath): \(error.localizedDescription)")
            }
        }
        
        return report
    }
    
    /// Convenience API if you only need the ordered list of unique keys.
    public func scanKeys(
        template: URL,
        options: Options = .init()
    ) throws -> [String] {
        try scan(template: template, options: options).orderedKeys
    }
}

// MARK: - Private models

private struct PartScanReport {
    var foundKeys: [String] = []
    var occurrences: [String: Int] = [:]
}

// MARK: - XML scanning

private struct PlaceholderMatch {
    let key: String
    let range: Range<String.Index>
}

private struct TextSegment {
    let element: XMLElement
    let kind: Kind
    
    enum Kind {
        case wT
        case instrText
    }
    
    let text: String
}

private struct WordprocessingMLScanner {
    let options: DocxTemplatePlaceholderScanner.Options
    
    private static let placeholderRegex: NSRegularExpression = {
        // Same placeholder contract as your replacer: <!key!>
        // Current allowed key chars: A-Z a-z 0-9 _
        let pattern = #"<\!([A-Za-z0-9_]+)\!>"#
        return try! NSRegularExpression(pattern: pattern)
    }()
    
    func scan(document: XMLDocument) -> PartScanReport {
        var report = PartScanReport()
        
        let paragraphs: [XMLElement]
        do {
            paragraphs = try document.nodes(forXPath: "//*[local-name()='p']") as? [XMLElement] ?? []
        } catch {
            return report
        }
        
        for paragraph in paragraphs {
            let segments = collectTextSegments(in: paragraph)
            guard !segments.isEmpty else { continue }
            
            let fullText = segments.map(\.text).joined()
            let matches = findPlaceholders(in: fullText)
            guard !matches.isEmpty else { continue }
            
            for match in matches {
                report.foundKeys.append(match.key)
                report.occurrences[match.key, default: 0] += 1
            }
        }
        
        return report
    }
    
    private func collectTextSegments(in paragraph: XMLElement) -> [TextSegment] {
        let path: String
        if options.includeFieldInstructionText {
            path = ".//*[local-name()='t' or local-name()='instrText']"
        } else {
            path = ".//*[local-name()='t']"
        }
        
        let nodes: [XMLElement]
        do {
            nodes = try paragraph.nodes(forXPath: path) as? [XMLElement] ?? []
        } catch {
            return []
        }
        
        return nodes.map { element in
            let local = element.localName ?? element.name ?? ""
            let kind: TextSegment.Kind = (local == "instrText") ? .instrText : .wT
            return TextSegment(
                element: element,
                kind: kind,
                text: element.stringValue ?? ""
            )
        }
    }
    
    private func findPlaceholders(in text: String) -> [PlaceholderMatch] {
        let ns = text as NSString
        let matches = Self.placeholderRegex.matches(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        )
        
        return matches.compactMap { match in
            guard match.numberOfRanges == 2 else { return nil }
            let key = ns.substring(with: match.range(at: 1))
            guard let range = Range(match.range(at: 0), in: text) else { return nil }
            return PlaceholderMatch(key: key, range: range)
        }
    }
}

// MARK: - XML part scan

private func scanXMLPart(
    data: Data,
    options: DocxTemplatePlaceholderScanner.Options,
    partPathForErrors: String
) throws -> PartScanReport {
    
    let document: XMLDocument
    do {
        document = try XMLDocument(
            data: data,
            options: [.nodePreserveAll, .nodePreserveWhitespace]
        )
    } catch {
        throw DocxTemplatePlaceholderScanner.Error.xmlReadFailed(part: partPathForErrors)
    }
    
    let scanner = WordprocessingMLScanner(options: options)
    return scanner.scan(document: document)
}

// MARK: - Report merge

private func merge(
    _ partReport: PartScanReport,
    from partPath: String,
    into report: inout DocxTemplatePlaceholderScanner.Report
) {
    for key in partReport.foundKeys {
        if report.foundKeys.insert(key).inserted {
            report.orderedKeys.append(key)
        }
        
        report.partsByKey[key, default: []].insert(partPath)
    }
    
    for (key, count) in partReport.occurrences {
        report.occurrences[key, default: 0] += count
    }
}

// MARK: - ZIP helpers

private func extractData(from entry: Entry, in archive: Archive) throws -> Data {
    var data = Data()
    _ = try archive.extract(entry) { chunk in
        data.append(chunk)
    }
    return data
}

private func locatePartPaths(
    in archive: Archive,
    options: DocxTemplatePlaceholderScanner.Options
) throws -> [String] {
    
    let allPaths = archive.map(\.path)
    
    switch options.selection {
    case .standard:
        var result: [String] = []
        
        if allPaths.contains("word/document.xml") {
            result.append("word/document.xml")
        }
        
        result += allPaths
            .filter { path in
                let name = (path as NSString).lastPathComponent
                return path.hasPrefix("word/")
                    && path.hasSuffix(".xml")
                    && name.hasPrefix("header")
            }
            .sorted()
        
        result += allPaths
            .filter { path in
                let name = (path as NSString).lastPathComponent
                return path.hasPrefix("word/")
                    && path.hasSuffix(".xml")
                    && name.hasPrefix("footer")
            }
            .sorted()
        
        if options.includeFootnotes, allPaths.contains("word/footnotes.xml") {
            result.append("word/footnotes.xml")
        }
        
        if options.includeEndnotes, allPaths.contains("word/endnotes.xml") {
            result.append("word/endnotes.xml")
        }
        
        if options.includeComments, allPaths.contains("word/comments.xml") {
            result.append("word/comments.xml")
        }
        
        return Array(Set(result)).sorted()
        
    case .allWordXML:
        let paths = allPaths
            .filter { $0.hasPrefix("word/") }
            .filter { $0.hasSuffix(".xml") }
            .filter { !$0.contains("/_rels/") }
            .filter { !($0 as NSString).lastPathComponent.hasSuffix(".rels") }
            .sorted()
        
        if paths.contains("word/document.xml") {
            return paths
        } else {
            return ["word/document.xml"] + paths
        }
    }
}
