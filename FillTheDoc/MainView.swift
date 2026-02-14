import SwiftUI
import OpenAIClient

struct MainView: View {
    @EnvironmentObject private var apiKeyStore: APIKeyStore
    
    @State private var templatePath: String = ""
    @State private var detailsPath: String = ""
    
    @State private var isLoading: Bool = false
    
    private var templateURL: URL? { url(from: templatePath) }
    private var detailsURL: URL? { url(from: detailsPath) }
    
    private var isTemplateValid: Bool { isExistingFile(templateURL) }
    private var isDetailsValid: Bool { isExistingFile(detailsURL) }
    
    private var canRun: Bool { isTemplateValid && isDetailsValid && apiKeyStore.hasKey }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Заполнение документа")
                .font(.title2.weight(.semibold))
            
            VStack(spacing: 16) {
                DropZoneCard(
                    title: "Шаблон (DOCX)",
                    isValid: isTemplateValid,
                    path: $templatePath,
                    onDropURLs: { urls in
                        if let url = urls.first { templatePath = url.path }
                    },
                    heightToContent: true
                )
                
                DropZoneCard(
                    title: "Реквизиты (DOC, DOCX, PDF, XLS, XLSX)",
                    isValid: isDetailsValid,
                    path: $detailsPath,
                    onDropURLs: { urls in
                        if let url = urls.first { detailsPath = url.path }
                    },
                    heightToContent: false
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
            
            if !apiKeyStore.hasKey {
                Text("Добавь API ключ (появится окно ввода).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            if !isTemplateValid || !isDetailsValid {
                Text("Добавь оба файла: шаблон и реквизиты.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            if let err = apiKeyStore.errorText {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .sheet(isPresented: $apiKeyStore.isPromptPresented) {
            APIKeyPromptView { enteredKey in
                apiKeyStore.save(enteredKey)
            }
            .interactiveDismissDisabled(true) // модалка не закрывается свайпом/esc пока нет ключа
        }
        .overlay {
            if isLoading {
                AIWaitingIndicator()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
    
    private func runFill() {
        guard apiKeyStore.hasKey else {
            apiKeyStore.isPromptPresented = true
            return
        }
        guard let detailsURL else { return }
        
        let extractor = DocumentTextExtractorService()
        
        Task {
            await MainActor.run { isLoading = true }
            defer { Task { @MainActor in isLoading = false } }
            
            do {
                let result = try extractor.extract(from: detailsURL)
                
                // пример: реальный клиент
                // let client = OpenAIClient(apiKey: apiKeyStore.apiKey ?? "", model: "gpt-4o-mini")
                // let (json, status) = try await client.request(
                //     system: "Extract requisites and return ONLY a JSON object.",
                //     user: result.text
                // )
                
                print("Method:", result.method)
                print("Chars:", result.diagnostics.producedChars)
                
                // симуляция
                try await Task.sleep(nanoseconds: 2_200_000_000)
                print("OK")
            } catch {
                print("Extraction failed:", error)
            }
        }
    }
    
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
