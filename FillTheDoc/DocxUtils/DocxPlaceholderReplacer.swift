//
//  DocxPlaceholderReplacer.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 17.02.2026.
//

import Foundation
import ZIPFoundation

// MARK: - Public

public final class DocxPlaceholderReplacer: Sendable {
    
    // MARK: Options / Report
    
    public struct Options: Sendable {
        public enum MissingKeyPolicy: Sendable {
            case error
            case keep
            case blank
        }
        
        public var includeFootnotes: Bool = true
        public var includeEndnotes: Bool = true
        public var includeComments: Bool = true
        public var selection: PartsSelection = .standard
        public var missingKeyPolicy: MissingKeyPolicy = .keep
        public var preserveWhitespaceWhenNeeded: Bool = true
        public var includeFieldInstructionText: Bool = false
        public var validateTemplate: Bool = true
        public var sanitizeValues: Bool = true
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
        public var foundKeys: Set<String> = []
        public var replacedKeys: Set<String> = []
        public var missingKeys: Set<String> = []
        public var replacementsCount: Int = 0
        
        public init() {}
    }
    
    public enum Error: Swift.Error, LocalizedError {
        case cannotCreateOutputArchive
        case missingKeys([String])
        
        public var errorDescription: String? {
            switch self {
                case .cannotCreateOutputArchive:
                    return "Cannot create output DOCX archive."
                case .missingKeys(let keys):
                    return "Template contains placeholders without values: \(keys.joined(separator: ", "))."
            }
        }
    }
    
    public init() {}
    
    /// Replaces placeholders like `<!company_name!>` in a DOCX template.
    public func fill(
        template: URL,
        output: URL,
        values: [String: String],
        options: Options = .init()
    ) async throws -> Report {
        let fm = FileManager.default
        
        if options.validateTemplate {
            guard fm.fileExists(atPath: template.path) else {
                throw DocxTemplateError.templateNotFound(template)
            }
        }
        
        let processedValues = options.sanitizeValues ? sanitizeValuesDictionary(values) : values
        
        let tempDir = fm.temporaryDirectory.appendingPathComponent("fillthedoc-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            do { try fm.removeItem(at: tempDir) }
            catch { options.onWarning?("Failed to clean temp directory: \(error.localizedDescription)") }
        }
        
        // 1) Unzip (safe)
        let src = try Archive(url: template, accessMode: .read)
        try src.extractAllSafely(to: tempDir)
        
        // 2) Locate parts
        let mainDoc = tempDir.appendingPathComponent("word/document.xml")
        guard fm.fileExists(atPath: mainDoc.path) else { throw DocxTemplateError.missingMainDocumentXML }
        
        let partURLs = try locatePartURLs(root: tempDir, mainDoc: mainDoc, options: options.coreOptions)
        
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
        var sanitized = value
        sanitized = sanitized.replacingOccurrences(of: "<!", with: "&lt;!")
        sanitized = sanitized.replacingOccurrences(of: "!>", with: "!&gt;")
        return sanitized
    }
}

// MARK: - XML replacement

private struct PartReport {
    var foundKeys: Set<String> = []
    var replacedKeys: Set<String> = []
    var missingKeys: Set<String> = []
    var replacementsCount: Int = 0
    
    init() {}
}

private func replaceInPartXML(
    partURL: URL,
    values: [String: String],
    options: DocxPlaceholderReplacer.Options,
    partPathForErrors: String
) throws -> (PartReport, Bool) {
    
    let data: Data
    do { data = try Data(contentsOf: partURL) }
    catch { throw DocxTemplateError.xmlReadFailed(part: partPathForErrors) }
    
    let doc = try parseXMLDocument(data: data, partPath: partPathForErrors)
    
    let rewriter = WordprocessingMLRewriter(options: options, values: values)
    let (report, didChange) = rewriter.rewrite(document: doc)
    
    if didChange {
        let outData = doc.xmlData(options: [.nodePreserveAll])
        do { try outData.write(to: partURL, options: [.atomic]) }
        catch { throw DocxTemplateError.xmlWriteFailed(part: partPathForErrors) }
    }
    
    return (report, didChange)
}

private struct WordprocessingMLRewriter {
    let options: DocxPlaceholderReplacer.Options
    let values: [String: String]
    
    func rewrite(document: XMLDocument) -> (PartReport, Bool) {
        var report = PartReport()
        var didChange = false
        
        for p in findParagraphs(in: document) {
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
        var segments = collectTextSegments(in: paragraph, includeFieldInstructionText: options.includeFieldInstructionText)
        guard !segments.isEmpty else { return (PartReport(), false) }
        
        let fullText = segments.map(\.text).joined()
        let matches = findPlaceholders(in: fullText)
        guard !matches.isEmpty else { return (PartReport(), false) }
        
        let lengths = segments.map { $0.text.count }
        let prefix = prefixSums(lengths)
        
        var part = PartReport()
        var changed = false
        
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
        
        if changed {
            for seg in segments {
                seg.element.stringValue = seg.text
                
                if options.preserveWhitespaceWhenNeeded, seg.kind == .wT, needsPreserveWhitespace(seg.text) {
                    ensureXMLSpacePreserve(on: seg.element)
                }
            }
        }
        
        return (part, changed)
    }
    
    private struct SegmentLocation {
        let segmentIndex: Int
        let offset: Int
    }
    
    // MARK: Offset mapping
    
    private func prefixSums(_ lengths: [Int]) -> [Int] {
        var out: [Int] = Array(repeating: 0, count: lengths.count + 1)
        for i in 0..<lengths.count {
            out[i + 1] = out[i] + lengths[i]
        }
        return out
    }
    
    private func locate(position: String.Index, in fullText: String, prefix: [Int]) -> SegmentLocation? {
        let target = fullText.distance(from: fullText.startIndex, to: position)
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
        let attrName = "xml:space"
        if wTElement.attribute(forName: attrName) == nil {
            let a = XMLNode.attribute(withName: attrName, stringValue: "preserve") as! XMLNode
            wTElement.addAttribute(a)
        } else {
            wTElement.attribute(forName: attrName)?.stringValue = "preserve"
        }
    }
}
