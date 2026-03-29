//
//  DocxTemplateCore.swift
//  FillTheDoc
//
//  Shared infrastructure for DocxTemplatePlaceholderScanner and DocxPlaceholderReplacer.
//  Contains: placeholder regex, XML text segment parsing, part location, ZIP helpers.
//

import Foundation
import ZIPFoundation

// MARK: - Placeholder regex

enum PlaceholderPattern {
    /// Matches `<!key!>` where key = [A-Za-z0-9_]+
    static let regex: NSRegularExpression = {
        let pattern = #"<\!([A-Za-z0-9_]+)\!>"#
        return try! NSRegularExpression(pattern: pattern)
    }()
}

// MARK: - Shared data types

struct PlaceholderMatch {
    let key: String
    let range: Range<String.Index>
}

struct TextSegment {
    let element: XMLElement
    let kind: Kind
    var text: String
    
    enum Kind {
        case wT
        case instrText
    }
}

// MARK: - Shared DOCX parts options

struct DocxPartsOptions {
    var includeFootnotes: Bool = true
    var includeEndnotes: Bool = true
    var includeComments: Bool = true
    var includeFieldInstructionText: Bool = false
    var selection: PartsSelection = .standard
    
    enum PartsSelection {
        case standard
        case allWordXML
    }
}

// MARK: - Shared errors

enum DocxTemplateError: Error, LocalizedError {
    case invalidDocx
    case missingMainDocumentXML
    case templateNotFound(URL)
    case xmlReadFailed(part: String)
    case xmlWriteFailed(part: String)
    case zipSlipDetected(entryPath: String)
    
    var errorDescription: String? {
        switch self {
            case .invalidDocx:
                return "Invalid DOCX archive."
            case .missingMainDocumentXML:
                return "DOCX does not contain word/document.xml."
            case .templateNotFound(let url):
                return "Template file not found at: \(url.path)"
            case .xmlReadFailed(let part):
                return "Failed to read XML part: \(part)"
            case .xmlWriteFailed(let part):
                return "Failed to write XML part: \(part)"
            case .zipSlipDetected(let entryPath):
                return "Unsafe ZIP entry path detected: \(entryPath)"
        }
    }
}

// MARK: - XML text segment collection

/// Collects `<w:t>` (and optionally `<w:instrText>`) segments from a paragraph element.
func collectTextSegments(in paragraph: XMLElement, includeFieldInstructionText: Bool) -> [TextSegment] {
    let path: String
    if includeFieldInstructionText {
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
        return TextSegment(element: element, kind: kind, text: element.stringValue ?? "")
    }
}

// MARK: - Placeholder search

/// Finds all `<!key!>` placeholders in concatenated text.
func findPlaceholders(in text: String) -> [PlaceholderMatch] {
    let ns = text as NSString
    let matches = PlaceholderPattern.regex.matches(
        in: text,
        range: NSRange(location: 0, length: ns.length)
    )
    return matches.compactMap { m in
        guard m.numberOfRanges == 2 else { return nil }
        let key = ns.substring(with: m.range(at: 1))
        guard let range = Range(m.range(at: 0), in: text) else { return nil }
        return PlaceholderMatch(key: key, range: range)
    }
}

// MARK: - XML parsing

/// Parses XML data into an XMLDocument with whitespace-preserving options.
func parseXMLDocument(data: Data, partPath: String) throws -> XMLDocument {
    do {
        return try XMLDocument(data: data, options: [.nodePreserveAll, .nodePreserveWhitespace])
    } catch {
        throw DocxTemplateError.xmlReadFailed(part: partPath)
    }
}

/// Returns all `<w:p>` paragraph elements from an XML document.
func findParagraphs(in document: XMLDocument) -> [XMLElement] {
    (try? document.nodes(forXPath: "//*[local-name()='p']") as? [XMLElement]) ?? []
}

// MARK: - Part location (from archive paths)

/// Locates DOCX XML part paths inside a ZIP archive based on options.
func locatePartPaths(in archive: Archive, options: DocxPartsOptions) -> [String] {
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
                    return path.hasPrefix("word/") && path.hasSuffix(".xml") && name.hasPrefix("header")
                }
                .sorted()
            
            result += allPaths
                .filter { path in
                    let name = (path as NSString).lastPathComponent
                    return path.hasPrefix("word/") && path.hasSuffix(".xml") && name.hasPrefix("footer")
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

/// Locates DOCX XML part URLs on the filesystem (for extracted archives).
func locatePartURLs(root: URL, mainDoc: URL, options: DocxPartsOptions) throws -> [URL] {
    let fm = FileManager.default
    
    switch options.selection {
        case .standard:
            var urls: [URL] = [mainDoc]
            
            let wordDir = root.appendingPathComponent("word", isDirectory: true)
            if fm.fileExists(atPath: wordDir.path) {
                let items = try fm.contentsOfDirectory(at: wordDir, includingPropertiesForKeys: nil)
                urls += items
                    .filter { $0.lastPathComponent.hasPrefix("header") && $0.lastPathComponent.hasSuffix(".xml") }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                urls += items
                    .filter { $0.lastPathComponent.hasPrefix("footer") && $0.lastPathComponent.hasSuffix(".xml") }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
            
            if options.includeFootnotes {
                let f = root.appendingPathComponent("word/footnotes.xml")
                if fm.fileExists(atPath: f.path) { urls.append(f) }
            }
            if options.includeEndnotes {
                let e = root.appendingPathComponent("word/endnotes.xml")
                if fm.fileExists(atPath: e.path) { urls.append(e) }
            }
            if options.includeComments {
                let c = root.appendingPathComponent("word/comments.xml")
                if fm.fileExists(atPath: c.path) { urls.append(c) }
            }
            
            return Array(Set(urls)).sorted { $0.path < $1.path }
            
        case .allWordXML:
            let wordDir = root.appendingPathComponent("word", isDirectory: true)
            guard fm.fileExists(atPath: wordDir.path) else { return [mainDoc] }
            
            let urls = try fm.contentsOfDirectory(at: wordDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "xml" }
                .filter { !$0.lastPathComponent.hasSuffix(".rels") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            let set = Set(urls + [mainDoc])
            return set.sorted { $0.path < $1.path }
    }
}

// MARK: - ZIP helpers

/// Extracts data from a single ZIP entry.
func extractEntryData(from entry: Entry, in archive: Archive) throws -> Data {
    var data = Data()
    _ = try archive.extract(entry) { chunk in
        data.append(chunk)
    }
    return data
}

extension Archive {
    
    /// Safe extraction that prevents Zip Slip (path traversal).
    func extractAllSafely(to directory: URL) throws {
        let fm = FileManager.default
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        
        for entry in self {
            let entryPath = entry.path
            
            let comps = entryPath.split(separator: "/").map(String.init)
            if comps.contains("..") || entryPath.hasPrefix("/") || entryPath.hasPrefix("\\") {
                throw DocxTemplateError.zipSlipDetected(entryPath: entryPath)
            }
            
            let outURL = root.appendingPathComponent(entryPath, isDirectory: false)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            
            let outPath = outURL.path
            let rootPath = root.path.hasSuffix("/") ? root.path : (root.path + "/")
            if !outPath.hasPrefix(rootPath) && outPath != root.path {
                throw DocxTemplateError.zipSlipDetected(entryPath: entryPath)
            }
            
            try fm.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            _ = try extract(entry, to: outURL)
        }
    }
    
    /// Re-packs a directory into this archive.
    func addDirectoryContents(of directory: URL) throws {
        let fm = FileManager.default
        let basePath = directory.path
        
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            
            let relPath = fileURL.path.replacingOccurrences(of: basePath + "/", with: "")
            try addEntry(with: relPath, fileURL: fileURL, compressionMethod: .deflate)
        }
    }
}

/// Returns relative path of an extracted file within the extraction root.
func relativeDocxPath(fromExtractedURL url: URL, extractedRoot: URL) -> String {
    let base = extractedRoot.standardizedFileURL.path
    let p = url.standardizedFileURL.path
    if p.hasPrefix(base + "/") {
        return String(p.dropFirst((base + "/").count))
    }
    return url.lastPathComponent
}
