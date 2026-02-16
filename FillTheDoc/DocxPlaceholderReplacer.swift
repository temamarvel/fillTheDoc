//
//  DocxPlaceholderReplacer.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 17.02.2026.
//

import Foundation
import ZIPFoundation
public import Combine
// MARK: - Public

public final class DocxPlaceholderReplacer: ObservableObject, Sendable {
    
    // MARK: Options / Report
    
    public struct Options: Sendable {
        public enum MissingKeyPolicy: Sendable {
            /// Throw an error at the end if any placeholder key is not present in `values`.
            case error
            /// Leave placeholder as-is: <!key!>
            case keep
            /// Replace with empty string.
            case blank
        }
        
        /// Which parts inside DOCX to process.
        public enum PartsSelection: Sendable {
            /// document.xml + headers/footers (+ optional notes/comments)
            case standard
            /// All .xml files inside /word (plus /word/_rels and other service files are ignored automatically)
            case allWordXML
        }
        
        public var includeFootnotes: Bool = true
        public var includeEndnotes: Bool = true
        public var includeComments: Bool = true
        public var selection: PartsSelection = .standard
        
        public var missingKeyPolicy: MissingKeyPolicy = .keep
        
        /// If replacement contains leading/trailing spaces, multiple spaces, tabs or newlines,
        /// enforce `xml:space="preserve"` on the target <w:t>.
        public var preserveWhitespaceWhenNeeded: Bool = true
        
        /// Also scan `<w:instrText>` (field instructions). Usually you don't want to replace there,
        /// but some templates store placeholders inside fields.
        public var includeFieldInstructionText: Bool = false
        
        /// Validate that template file exists before processing
        public var validateTemplate: Bool = true
        
        /// Sanitize values to prevent placeholder injection (<!key!> patterns in values)
        public var sanitizeValues: Bool = true
        
        /// Optional callback for warnings/non-fatal errors
        public var onWarning: (@Sendable (String) -> Void)? = nil
        
        public init() {}
    }
    
    public struct Report: Sendable {
        public var processedParts: [String] = []          // paths inside docx
        public var foundKeys: Set<String> = []            // placeholders found in template
        public var replacedKeys: Set<String> = []         // placeholders replaced (value exists)
        public var missingKeys: Set<String> = []          // placeholders found but no value provided
        public var replacementsCount: Int = 0             // total replacements performed
        
        public init() {}
    }
    
    public enum Error: Swift.Error, LocalizedError {
        case invalidDocx
        case missingMainDocumentXML
        case cannotCreateOutputArchive
        case zipSlipDetected(entryPath: String)
        case xmlReadFailed(part: String)
        case xmlWriteFailed(part: String)
        case missingKeys([String])
        case templateNotFound(URL)
        
        public var errorDescription: String? {
            switch self {
                case .invalidDocx:
                    return "Invalid DOCX archive."
                case .missingMainDocumentXML:
                    return "DOCX does not contain word/document.xml."
                case .cannotCreateOutputArchive:
                    return "Cannot create output DOCX archive."
                case .zipSlipDetected(let entryPath):
                    return "Unsafe ZIP entry path detected: \(entryPath)"
                case .xmlReadFailed(let part):
                    return "Failed to read XML part: \(part)"
                case .xmlWriteFailed(let part):
                    return "Failed to write XML part: \(part)"
                case .missingKeys(let keys):
                    return "Template contains placeholders without values: \(keys.joined(separator: ", "))."
                case .templateNotFound(let url):
                    return "Template file not found at: \(url.path)"
            }
        }
    }
    
    public init() {}
    
    /// Replaces placeholders like <!company_name!> in a DOCX template.
    /// - Returns: Report with found/replaced/missing keys.
    public func fill(
        template: URL,
        output: URL,
        values: [String: String],
        options: Options = .init()
    ) throws -> Report {
        let fm = FileManager.default
        
        // Validation
        if options.validateTemplate {
            guard fm.fileExists(atPath: template.path) else {
                throw Error.templateNotFound(template)
            }
        }
        
        // Sanitize values if needed
        let processedValues = options.sanitizeValues ? sanitizeValuesDictionary(values) : values
        
        let tempDir = fm.temporaryDirectory.appendingPathComponent("fillthedoc-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            do {
                try fm.removeItem(at: tempDir)
            } catch {
                options.onWarning?("Failed to clean temp directory: \(error.localizedDescription)")
            }
        }
        
        // 1) Unzip (safe)
        let src = try Archive(url: template, accessMode: .read)
        try src.extractAllSafely(to: tempDir)
        
        // 2) Locate parts
        let mainDoc = tempDir.appendingPathComponent("word/document.xml")
        guard fm.fileExists(atPath: mainDoc.path) else { throw Error.missingMainDocumentXML }
        
        let partURLs = try locateParts(root: tempDir, main: mainDoc, options: options)
        
        // 3) Replace
        var report = Report()
        for url in partURLs {
            let rel = relativeDocxPath(fromExtractedURL: url, extractedRoot: tempDir)
            
            do {
                let (partReport, didChange) = try replaceInPartXML(
                    partURL: url,
                    values: processedValues,
                    options: options,
                    partPathForErrors: rel
                )
                
                // write only if changed (small perf win, less churn in serialized XML)
                if didChange {
                    report.processedParts.append(rel)
                }
                
                report.foundKeys.formUnion(partReport.foundKeys)
                report.replacedKeys.formUnion(partReport.replacedKeys)
                report.missingKeys.formUnion(partReport.missingKeys)
                report.replacementsCount += partReport.replacementsCount
            } catch {
                options.onWarning?("Failed to process \(rel): \(error.localizedDescription)")
            }
        }
        
        // 4) Missing policy error
        if options.missingKeyPolicy == .error, !report.missingKeys.isEmpty {
            throw Error.missingKeys(report.missingKeys.sorted())
        }
        
        // 5) Zip back
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        let out = try Archive(url: output, accessMode: .create)
        try out.addDirectoryContents(of: tempDir)
        
        return report
    }
    
    // MARK: - Sanitization
    
    private func sanitizeValuesDictionary(_ values: [String: String]) -> [String: String] {
        values.mapValues { sanitizeValue($0) }
    }
    
    private func sanitizeValue(_ value: String) -> String {
        // Prevent placeholder injection by escaping placeholder markers
        var sanitized = value
        sanitized = sanitized.replacingOccurrences(of: "<!", with: "&lt;!")
        sanitized = sanitized.replacingOccurrences(of: "!>", with: "!&gt;")
        return sanitized
    }
}

// MARK: - Parts location

private func locateParts(root: URL, main: URL, options: DocxPlaceholderReplacer.Options) throws -> [URL] {
    let fm = FileManager.default
    
    switch options.selection {
        case .standard:
            var urls: [URL] = [main]
            urls += try listXMLParts(in: root, subdir: "word", prefix: "header", suffix: ".xml")
            urls += try listXMLParts(in: root, subdir: "word", prefix: "footer", suffix: ".xml")
            
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
            
            // Stable order for deterministic output/reporting
            return Array(Set(urls)).sorted { $0.path < $1.path }
            
        case .allWordXML:
            let wordDir = root.appendingPathComponent("word", isDirectory: true)
            guard fm.fileExists(atPath: wordDir.path) else { return [main] }
            
            let urls = try fm.contentsOfDirectory(at: wordDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "xml" }
            // skip relationships and service files if they appear as XML in other dirs
                .filter { !$0.lastPathComponent.hasSuffix(".rels") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            // Ensure main is included even if odd templates
            let set = Set(urls + [main])
            return set.sorted { $0.path < $1.path }
    }
}

private func listXMLParts(in root: URL, subdir: String, prefix: String, suffix: String) throws -> [URL] {
    let dir = root.appendingPathComponent(subdir, isDirectory: true)
    let fm = FileManager.default
    guard fm.fileExists(atPath: dir.path) else { return [] }
    
    let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    return items
        .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func relativeDocxPath(fromExtractedURL url: URL, extractedRoot: URL) -> String {
    let base = extractedRoot.standardizedFileURL.path
    let p = url.standardizedFileURL.path
    if p.hasPrefix(base + "/") {
        return String(p.dropFirst((base + "/").count))
    }
    return url.lastPathComponent
}

// MARK: - XML replacement (WordprocessingML with DOM parsing)

private struct PartReport {
    var foundKeys: Set<String> = []
    var replacedKeys: Set<String> = []
    var missingKeys: Set<String> = []
    var replacementsCount: Int = 0
}

private struct PlaceholderMatch {
    let key: String
    let range: Range<String.Index>   // in concatenated paragraph text
}

/// Represents one editable text segment in a paragraph, backed by an XML element (usually <w:t>).
private struct TextSegment {
    let element: XMLElement
    let kind: Kind
    enum Kind { case wT, instrText }
    
    var text: String   // decoded, mutable
}

/// Replace placeholders inside a single XML part file.
/// Returns (PartReport, didChange)
private func replaceInPartXML(
    partURL: URL,
    values: [String: String],
    options: DocxPlaceholderReplacer.Options,
    partPathForErrors: String
) throws -> (PartReport, Bool) {
    
    let data: Data
    do { data = try Data(contentsOf: partURL) }
    catch { throw DocxPlaceholderReplacer.Error.xmlReadFailed(part: partPathForErrors) }
    
    // Preserve original encoding as UTF-8 on write (Word is fine with UTF-8).
    // Use nodePreserveAll to avoid reformatting too aggressively.
    let doc: XMLDocument
    do {
        doc = try XMLDocument(data: data, options: [.nodePreserveAll, .nodePreserveWhitespace])
    } catch {
        throw DocxPlaceholderReplacer.Error.xmlReadFailed(part: partPathForErrors)
    }
    
    let rewriter = WordprocessingMLRewriter(options: options, values: values)
    let (report, didChange) = rewriter.rewrite(document: doc)
    
    if didChange {
        let outData: Data
        // Avoid pretty print: it can change whitespace/line breaks significantly
        outData = doc.xmlData(options: [.nodePreserveAll])
        
        do { try outData.write(to: partURL, options: [.atomic]) }
        catch { throw DocxPlaceholderReplacer.Error.xmlWriteFailed(part: partPathForErrors) }
    }
    
    return (report, didChange)
}

private struct WordprocessingMLRewriter {
    let options: DocxPlaceholderReplacer.Options
    let values: [String: String]
    
    // Cached regex for performance
    private static let placeholderRegex: NSRegularExpression = {
        let pattern = #"<\!([A-Za-z0-9_]+)\!>"#
        return try! NSRegularExpression(pattern: pattern)
    }()
    
    func rewrite(document: XMLDocument) -> (PartReport, Bool) {
        var report = PartReport()
        var didChange = false
        
        // Find all paragraphs <w:p> anywhere in the doc.
        // Using XPath with namespaces is more verbose; local-name() works reliably.
        // Note: XMLDocument supports XPath on macOS.
        let paragraphs: [XMLElement]
        do {
            paragraphs = try document.nodes(forXPath: "//*[local-name()='p']") as? [XMLElement] ?? []
        } catch {
            return (report, false)
        }
        
        for p in paragraphs {
            let (r, changed) = rewriteParagraph(p)
            report.foundKeys.formUnion(r.foundKeys)
            report.replacedKeys.formUnion(r.replacedKeys)
            report.missingKeys.formUnion(r.missingKeys)
            report.replacementsCount += r.replacementsCount
            if changed { didChange = true }
        }
        
        return (report, didChange)
    }
    
    private func rewriteParagraph(_ paragraph: XMLElement) -> (PartReport, Bool) {
        // Collect segments in document order: primarily w:t; optionally w:instrText
        var segments = collectTextSegments(in: paragraph)
        guard !segments.isEmpty else { return (PartReport(), false) }
        
        let fullText = segments.map(\.text).joined()
        let matches = findPlaceholders(in: fullText)
        guard !matches.isEmpty else { return (PartReport(), false) }
        
        // Prefix sums for offset mapping (no O(n^2) joined inside locate)
        let lengths = segments.map { $0.text.count }
        let prefix = prefixSums(lengths)
        
        var part = PartReport()
        var changed = false
        
        // Replace from end to keep offsets stable within the snapshot
        for m in matches.reversed() {
            part.foundKeys.insert(m.key)
            
            let replacement: String?
            if let v = values[m.key] {
                replacement = v
                part.replacedKeys.insert(m.key)
            } else {
                part.missingKeys.insert(m.key)
                switch options.missingKeyPolicy {
                    case .error: replacement = nil
                    case .keep:  replacement = nil
                    case .blank: replacement = ""
                }
            }
            
            guard let repl = replacement else { continue }
            
            guard let start = locate(position: m.range.lowerBound, in: fullText, prefix: prefix),
                  let end   = locate(position: m.range.upperBound, in: fullText, prefix: prefix)
            else { continue }
            
            applyReplacement(segments: &segments, start: start, end: end, replacement: repl)
            part.replacementsCount += 1
            changed = true
        }
        
        // Write back into DOM
        if changed {
            for seg in segments {
                // CRITICAL FIX: Don't use xmlEscape() here!
                // XMLElement.stringValue automatically escapes when serializing
                seg.element.stringValue = seg.text
                
                if options.preserveWhitespaceWhenNeeded, seg.kind == .wT, needsPreserveWhitespace(seg.text) {
                    ensureXMLSpacePreserve(on: seg.element)
                }
            }
        }
        
        return (part, changed)
    }
    
    private func collectTextSegments(in paragraph: XMLElement) -> [TextSegment] {
        var segments: [TextSegment] = []
        segments.reserveCapacity(16)
        
        // Collect <w:t> nodes under paragraph (any depth), in order.
        // Also optionally include <w:instrText>.
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
        
        for el in nodes {
            let local = el.localName ?? el.name ?? ""
            let kind: TextSegment.Kind = (local == "instrText") ? .instrText : .wT
            
            // stringValue returns decoded content, but may be nil.
            let raw = el.stringValue ?? ""
            segments.append(TextSegment(element: el, kind: kind, text: raw))
        }
        
        return segments
    }
    
    private func findPlaceholders(in text: String) -> [PlaceholderMatch] {
        let ns = text as NSString
        let ms = Self.placeholderRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return ms.compactMap { m in
            guard m.numberOfRanges == 2 else { return nil }
            let key = ns.substring(with: m.range(at: 1))
            guard let r = Range(m.range(at: 0), in: text) else { return nil }
            return PlaceholderMatch(key: key, range: r)
        }
    }
    
    // MARK: Mapping offsets -> segment location
    
    private struct SegmentLocation {
        let segmentIndex: Int
        let offset: Int
    }
    
    private func prefixSums(_ lengths: [Int]) -> [Int] {
        var out: [Int] = Array(repeating: 0, count: lengths.count + 1)
        for i in 0..<lengths.count {
            out[i + 1] = out[i] + lengths[i]
        }
        return out
    }
    
    private func locate(position: String.Index, in fullText: String, prefix: [Int]) -> SegmentLocation? {
        let target = fullText.distance(from: fullText.startIndex, to: position)
        // Find first i such that prefix[i] <= target <= prefix[i+1]
        // Linear scan is ok for typical paragraphs; can binary-search if you want.
        for i in 0..<(prefix.count - 1) {
            let start = prefix[i]
            let end = prefix[i + 1]
            if target >= start && target <= end {
                return SegmentLocation(segmentIndex: i, offset: target - start)
            }
        }
        return nil
    }
    
    private func applyReplacement(segments: inout [TextSegment], start: SegmentLocation, end: SegmentLocation, replacement: String) {
        let si = start.segmentIndex
        let ei = end.segmentIndex
        
        if si == ei {
            let t = segments[si].text
            let pre = t.prefix(start.offset)
            let suf = t.dropFirst(end.offset)
            segments[si].text = String(pre) + replacement + String(suf)
            return
        }
        
        let first = segments[si].text
        let last = segments[ei].text
        
        let pre = first.prefix(start.offset)
        let suf = last.dropFirst(end.offset)
        
        segments[si].text = String(pre) + replacement + String(suf)
        
        if si + 1 <= ei {
            for k in (si + 1)...ei {
                segments[k].text = ""
            }
        }
    }
    
    // MARK: Whitespace preserve
    
    private func needsPreserveWhitespace(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        if s.first == " " || s.last == " " { return true }
        if s.contains("  ") { return true }
        if s.contains("\n") || s.contains("\t") { return true }
        return false
    }
    
    private func ensureXMLSpacePreserve(on wTElement: XMLElement) {
        // Word expects xml:space="preserve" on <w:t> to keep whitespace.
        // Namespace for xml is fixed.
        let attrName = "xml:space"
        if wTElement.attribute(forName: attrName) == nil {
            let a = XMLNode.attribute(withName: attrName, stringValue: "preserve") as! XMLNode
            wTElement.addAttribute(a)
        } else {
            wTElement.attribute(forName: attrName)?.stringValue = "preserve"
        }
    }
}

// MARK: - ZIP helpers (safe extract + repack)

private extension Archive {
    
    /// Safe extraction that prevents Zip Slip (path traversal).
    func extractAllSafely(to directory: URL) throws {
        let fm = FileManager.default
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        
        for entry in self {
            // Reject absolute paths and traversal
            let entryPath = entry.path
            
            // Normalize path components
            let comps = entryPath.split(separator: "/").map(String.init)
            if comps.contains("..") || entryPath.hasPrefix("/") || entryPath.hasPrefix("\\") {
                throw DocxPlaceholderReplacer.Error.zipSlipDetected(entryPath: entryPath)
            }
            
            let outURL = root.appendingPathComponent(entryPath, isDirectory: false)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            
            // Ensure extracted file stays within root
            let outPath = outURL.path
            let rootPath = root.path.hasSuffix("/") ? root.path : (root.path + "/")
            if !outPath.hasPrefix(rootPath) && outPath != root.path {
                throw DocxPlaceholderReplacer.Error.zipSlipDetected(entryPath: entryPath)
            }
            
            try fm.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            _ = try extract(entry, to: outURL)
        }
    }
    
    func addDirectoryContents(of directory: URL) throws {
        let fm = FileManager.default
        let basePath = directory.path
        
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            
            let relPath = fileURL.path.replacingOccurrences(of: basePath + "/", with: "")
            try addEntry(with: relPath, fileURL: fileURL, compressionMethod: .deflate)
        }
    }
}
