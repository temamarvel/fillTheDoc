import SwiftUI
import UniformTypeIdentifiers

struct DocxFileDocument: FileDocument {
    // Для exporter важнее writableContentTypes
    static var writableContentTypes: [UTType] { [.docxSafe] }
    static var readableContentTypes: [UTType] { [.docxSafe, .data] } // можно и так
    
    var data: Data
    
    init(fileURL: URL) throws {
        self.data = try Data(contentsOf: fileURL)
    }
    
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static var docxSafe: UTType {
        UTType(filenameExtension: "docx")
        ?? UTType("org.openxmlformats.wordprocessingml.document")
        ?? .data
    }
}
