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
    
    @State private var apiKey: String? = nil
    @State private var showAPIKeyPrompt: Bool = false
    @State private var keychainErrorText: String? = nil
    
    @State private var isLoading: Bool = false
    
    private let keychain = KeychainService()
    private let keychainAccount = "openai_api_key"
    
    private var templateURL: URL? { url(from: templatePath) }
    private var detailsURL: URL? { url(from: detailsPath) }
    
    private var isTemplateValid: Bool { isExistingFile(templateURL) }
    private var isDetailsValid: Bool { isExistingFile(detailsURL) }
    
    private var canRun: Bool { isTemplateValid && isDetailsValid }
    
    var body: some View {
        ZStack{
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
                    .disabled(!canRun || isLoading)
                    
                    Spacer()
                }
                
                if apiKey == nil || apiKey?.isEmpty == true {
                    Text("Добавь API ключ (появится окно ввода).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !canRun {
                    Text("Добавь оба файла: шаблон и реквизиты.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .onAppear {
                loadAPIKey()
            }
            // ✅ Модалка ввода ключа (не уйдёт, пока не сохраним)
            .sheet(isPresented: $showAPIKeyPrompt) {
                APIKeyPromptView { enteredKey in
                    do {
                        try keychain.saveString(enteredKey, account: keychainAccount)
                        apiKey = enteredKey
                        keychainErrorText = nil
                    } catch {
                        keychainErrorText = "Не удалось сохранить ключ в Keychain: \(error.localizedDescription)"
                        // если не сохранили — снова попросим
                        apiKey = nil
                        showAPIKeyPrompt = true
                    }
                }
            }
            
            
            if isLoading {
                AIBlockingOverlay(title: "Обрабатываю…")
                    .transition(.opacity)
            }
        }
    }
    
    private func loadAPIKey() {
        do {
            let loaded = try keychain.loadString(account: keychainAccount)
            if let loaded, !loaded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apiKey = loaded
                showAPIKeyPrompt = false
                keychainErrorText = nil
            } else {
                apiKey = nil
                showAPIKeyPrompt = true
            }
        } catch {
            apiKey = nil
            keychainErrorText = "Не удалось прочитать ключ из Keychain: \(error.localizedDescription)"
            showAPIKeyPrompt = true
        }
    }
    
    // MARK: - Actions
    
    private func runFill() {
        guard let detailsURL else { return }
        
        let extractor = DocumentTextExtractorService()
        
        Task {
            await MainActor.run { isLoading = true }
            defer { Task { @MainActor in isLoading = false } }
            
            do {
                let result = try extractor.extract(from: detailsURL)
                print("Method:", result.method)
                print("Chars:", result.diagnostics.producedChars)
                print("Needs OCR:", result.needsOCR)
                print("Notes:", result.diagnostics.notes)
                print("Errors:", result.diagnostics.errors)
                
                let client = OpenAIClient(apiKey: apiKey ?? "", model: "gpt-4o-mini")
                
                let (json, status) = try await client.request(
                    system: "Extract requisites and return ONLY a JSON object.",
                    user: result.text
                )
                
                print("JSON:", json)
                print("HTTP Status:", status.httpStatus)
                print("Description:", status.description)
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
