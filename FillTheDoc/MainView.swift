//
//  ContentView.swift
//  FillTheDoc
//
//  Created by Artem Denisov on 09.02.2026.
//

import SwiftUI
import OpenAIClient

// MARK: - Main screen

struct MainView: View {
    @State private var templatePath: String = ""
    @State private var detailsPath: String = ""
    
    private var templateURL: URL? { url(from: templatePath) }
    private var detailsURL: URL? { url(from: detailsPath) }
    
    private var isTemplateValid: Bool { isExistingFile(templateURL) }
    private var isDetailsValid: Bool { isExistingFile(detailsURL) }
    
    private var canRun: Bool { isTemplateValid && isDetailsValid }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Заполнение документа")
                .font(.title2.weight(.semibold))
            
            HStack(spacing: 16) {
                DropZoneCard(
                    title: "Шаблон (DOCX)",
                    subtitle: "Перетащи сюда файл шаблона",
                    isValid: isTemplateValid,
                    path: $templatePath,
                    onDropURLs: { urls in
                        // Берем первый файл
                        if let url = urls.first {
                            templatePath = url.path
                        }
                    }
                )
                
                DropZoneCard(
                    title: "Реквизиты",
                    subtitle: "Перетащи сюда файл с реквизитами (pdf/doc/xls/…)",
                    isValid: isDetailsValid,
                    path: $detailsPath,
                    onDropURLs: { urls in
                        if let url = urls.first {
                            detailsPath = url.path
                        }
                    }
                )
            }
            
            Divider()
            
            HStack {
                Spacer()
                
                Button {
                    runFill()
                } label: {
                    Text("Извлечь реквизиты и заполнить шаблон")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
                
                Spacer()
            }
            
            if !canRun {
                Text("Добавь оба файла: шаблон и реквизиты.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
    
    // MARK: - Actions
    
    private func runFill() {
        guard let detailsURL else { return }
        
        let extractor = DocumentTextExtractorService()
        
        Task {
            do {
                let result = try extractor.extract(from: detailsURL)
                print("Method:", result.method)
                print("Chars:", result.diagnostics.producedChars)
                print("Needs OCR:", result.needsOCR)
                print("Notes:", result.diagnostics.notes)
                print("Errors:", result.diagnostics.errors)
                
                //TODO: real api key
                let apiKey = ""
                let client = OpenAIClient(apiKey: apiKey, model: "gpt-4.1-mini")
                
                let (json, status) = try await client.request(
                    system: "Extract requisites and return ONLY a JSON object.",
                    user: result.text
                )
            } catch {
                print("Extraction failed:", error)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func url(from path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed)
    }
    
    private func isExistingFile(_ url: URL?) -> Bool {
        guard let url else { return false }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }
}

#Preview {
    MainView()
}
