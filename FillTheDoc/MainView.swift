import SwiftUI
import DaDataAPIClient
import UniformTypeIdentifiers
import OpenAIClient

struct MainView: View {
    @EnvironmentObject private var apiKeyStore: APIKeyStore
    @EnvironmentObject private var replacer: DocxPlaceholderReplacer
    
    @State private var templatePath: String = ""
    @State private var detailsPath: String = ""
    
    @State private var detailsText: String? = nil
    @State private var details: Requisites? = nil
    
    @State private var isLoading: Bool = false
    
    @State private var showExporter: Bool = false
    @State private var exportDocument: DocxFileDocument?
    @State private var exportDefaultFilename: String = "output"
    
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
                        extractDetails()
                    },
                    heightToContent: false
                ){
//                    if let text = detailsText {
//                        Text(text)
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
                    
                    if let details = details {
                        ExtractedDTOFormView(
                            dto: details,
                            metadata: Requisites.fieldMetadata
                        ) { updated in
                            // updated — уже struct Requisites
                            self.details = updated
                        } validate: {
                            
                            let token = Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T"
                            
                            let client = DaDataClient(
                                configuration: .init(token: token)
                            )
                            
                            let suggestion = try await client.findPartyFirst(innOrOgrn: details.inn!)
                            
                            let validator = PartyValidator()
                            let report = validator.validate(llm: details, api: suggestion!.data)
                            
                            print(report.verdict, report.score)
                            for i in report.issues {
                                print(i.severity, i.code, i.message)
                            }
                            
                            return report
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                
                Button {
                    Task{
                        await runFill()
                    }
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
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: UTType(filenameExtension: "docx") ?? .data,
            defaultFilename: exportDefaultFilename
        ) { result in
            switch result {
                case .success:
                    // Пользователь сохранил файл куда выбрал.
                    // Можно показать тост/алерт, сбросить состояние и т.п.
                    //errorText = nil
                    print("NEW DOC SAVED")
                //case .failure(let error):
                case .failure:
                    // Отмена пользователем приходит как ошибка? Обычно нет, но иногда может.
                    print("NEW DOC! Не удалось сохранить файл")
            }
            // cleanup
            exportDocument = nil
        }
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
    
    private func extractDetails(){
        guard let detailsURL else { return }
        
        let extractor = DocumentTextExtractorService()
        
        Task {
            await MainActor.run { isLoading = true }
            defer { Task { @MainActor in isLoading = false } }
            
            do {
                let extractedResult = try extractor.extract(from: detailsURL)
                
                print("Method:", extractedResult.method)
                print("Chars:", extractedResult.diagnostics.producedChars)
                
                // симуляция
//                try await Task.sleep(nanoseconds: 2_200_000_000)
//                print("OK")
//                
//                let fakeJSON = """
//            {
//                "company": "ООО Ромашка",
//                "director": "Иванов Иван Иванович",
//                "form": "ООО"
//            }
//            """
                let openAIClient = OpenAIClient(apiKey: apiKeyStore.apiKey ?? "", model: "gpt-4o-mini")
                
                let system = PromptBuilder.system(for: Requisites.self)
                let user = PromptBuilder.user(sourceText: extractedResult.text)
                
//                let (reqs, status) = try await openAIClient.request(
//                    system: system,
//                    user: user,
//                    as: Requisites.self
//                )
                
                // симуляция
                try await Task.sleep(nanoseconds: 2_200_000_000)
                let reqs = Requisites(companyName: "Тест компания", legalForm: "ТЕСТ_ЗАО", ceoFullName: "Тест Тестович Тестов", ceoShortenName: "Тестов Т. Т.", ogrn: "1187746707280", inn: "9731007287", kpp: "773101001", email: "test_test@test.com")
                
                let dtoText = reqs.toMultilineString()
                details = reqs
                print("DTO:", dtoText)
                detailsText = dtoText
                
            } catch {
                print("Extraction failed:", error)
            }
        }
        
    }
    
    private func makeTempOutputURL(from templateURL: URL) -> URL {
        let base = templateURL.deletingPathExtension().lastPathComponent
        // чтобы не перезаписывать при повторных запусках — добавим UUID
        let name = "\(base)_out_\(UUID().uuidString).docx"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
    
    private func runFill() async {
        
            isLoading = true
            defer { isLoading = false  }
            
            do {
                let values: [String: String] = [
                    "company": "ООО «Ромашка»",
                    "director": "Иванов Иван Иванович",
                    "inn": "7701234567"
                ]
                
                print(Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T")
                
                let token = Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T"
                
                let client = DaDataClient(
                    configuration: .init(token: token)
                )
                
                let suggestion = try await client.findPartyFirst(innOrOgrn: "6900026362")
                
                let party = suggestion?.data
                print(party)
                print(party?.name?.fullWithOpf)
                print(party?.management?.name)
                print(party?.state?.status)
                
                let tempOutURL = makeTempOutputURL(from: templateURL!)
                
                let report = try replacer.fill(
                    template: templateURL!,
                    output: tempOutURL,
                    values: values
                )
                
                exportDocument = try DocxFileDocument(fileURL: tempOutURL)
                exportDefaultFilename = "\(templateURL!.deletingPathExtension().lastPathComponent)_filled"
                
                // 4) показываем SavePanel
                showExporter = true
                
                print("missing", report.missingKeys)
                print("found", report.foundKeys)
                print("REPLACE OK")
            } catch {
                print("Replacement failed:", error)
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
