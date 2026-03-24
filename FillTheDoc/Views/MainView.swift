import SwiftUI
import DaDataAPIClient
import UniformTypeIdentifiers
import OpenAIClient

struct MainView: View {
    @EnvironmentObject private var apiKeyStore: APIKeyStore
    @EnvironmentObject private var replacer: DocxPlaceholderReplacer
    @EnvironmentObject private var scaner: DocxTemplatePlaceholderScanner
    
    @State private var templatePath: String = ""
    @State private var detailsPath: String = ""
    
    @State private var detailsText: String? = nil
    @State private var details: CompanyDetails? = nil
    @State private var documentData: DocumentData? = nil
    
    @State private var googleSheetsRow: String? = nil
    private var googleSheetsPreviewRow: String? {
        guard let googleSheetsRow = googleSheetsRow else { return nil}
        return googleSheetsRow
            .replacingOccurrences(of: "\t", with: " | ")
    }
    @State private var googleSheetsCopyStatus: String? = nil
    
    @State private var isLoading: Bool = false
    
    @State private var showExporter: Bool = false
    @State private var exportDocument: DocxFileDocument?
    @State private var exportDefaultFilename: String = "output"
    
    @State private var templatePlaceholders: [String] = [ ]
    
    @State private var isDataApproved: Bool = false
    
    private var templateURL: URL? { url(from: templatePath) }
    private var detailsURL: URL? { url(from: detailsPath) }
    
    private var isTemplateValid: Bool { isExistingFile(templateURL) }
    private var isDetailsValid: Bool { isExistingFile(detailsURL) }
    
    private let googleSheetsRowBuilder = GoogleSheetsRowBuilder()
    
    private var canRun: Bool { isTemplateValid && isDetailsValid && apiKeyStore.hasKey && isDataApproved }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Заполнение документа")
                .font(.title2.weight(.semibold))
            
            
            HStack(spacing: 16) {
                DropZoneCardView(
                    title: "Шаблон (DOCX)",
                    isValid: isTemplateValid,
                    path: $templatePath,
                    onDropURLs: { urls in
                        isDataApproved = false
                        if let url = urls.first { templatePath = url.path }
                        scanPlaceholders()
                    }
                )
                
                DropZoneCardView(
                    title: "Реквизиты (DOC, DOCX, PDF, XLS, XLSX)",
                    isValid: isDetailsValid,
                    path: $detailsPath,
                    onDropURLs: { urls in
                        isDataApproved = false
                        details = nil
                        googleSheetsRow = nil
                        if let url = urls.first { detailsPath = url.path }
                        extractDetails()
                    }
                )
            }
            
            
            Group {
                if let googleSheetsRow = googleSheetsRow, !googleSheetsRow.isEmpty {
                    GoogleSheetsRowPreview(
                        row: googleSheetsPreviewRow ?? "",
                        status: googleSheetsCopyStatus
                    ) {
                        googleSheetsRowBuilder.copyToPasteboard(googleSheetsRow)
                        googleSheetsCopyStatus = "Строка снова скопирована"
                    }
                } else {
                    
                    
                    if let details {
                        let keys = templatePlaceholders.compactMap {
                            CompanyDetails.CodingKeys(rawValue: $0)
                        }
                        
                        DocumentDataFormView(
                            companyDetails: details,
                            metadata: CompanyDetails.fieldMetadata,
                            keys: keys
                        ) { updated in
                            self.details = updated.companyDetails
                            self.documentData = updated
                            isDataApproved = true
                        }
                    } else {
                        EmptyCompanyDetailsPlaceholder()
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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun || isLoading)
                
                Spacer()
            }
            
            //            if !apiKeyStore.hasKey {
            //                Text("Добавь API ключ (появится окно ввода).")
            //                    .font(.footnote)
            //                    .foregroundStyle(.secondary)
            //            }
            //
            //            if !isTemplateValid || !isDetailsValid {
            //                Text("Добавь оба файла: шаблон и реквизиты.")
            //                    .font(.footnote)
            //                    .foregroundStyle(.secondary)
            //            }
            //
            //            if let err = apiKeyStore.errorText {
            //                Text(err)
            //                    .font(.footnote)
            //                    .foregroundStyle(.red)
            //            }
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
                AIWaitingIndicatorView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
    
    private func scanPlaceholders(){
        if let templateURL = templateURL {
            do {
                templatePlaceholders = try scaner.scanKeys(template: templateURL)
            } catch {
                
            }
        }
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
                
                //TODO: real request to openai
//                let openAIClient = OpenAIClient(apiKey: apiKeyStore.apiKey ?? "", model: "gpt-4o-mini")
//                let system = PromptBuilder.system(for: CompanyDetails.self)
//                let user = PromptBuilder.user(sourceText: extractedResult.text)
//                
//                let (reqs, status) = try await openAIClient.request(
//                    system: system,
//                    user: user,
//                    as: CompanyDetails.self
//                )
                
                // симуляция
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                // MARK: valid test data
                                var reqs = CompanyDetails(companyName: "Тест компания", legalForm: LegalForm.parse("ЗАО"), ceoFullName: "Тест Тестович Тестов", ceoShortenName: "Тестов Т. Т.", ogrn: "1187746707280", inn: "9731007287", kpp: "773101001", email: "test_test@test.com", address: """
                                                          город Москва, ул Горбунова, д. 2 стр. 3
                                                          """, phone: "+79991234567")
                //
                //                let token = Bundle.main.infoDictionary?["DADATA_TOKEN"] as? String ?? "N_T"
                //                let client = DaDataClient(configuration: .init(token: token))
                
                //                if let address = reqs.address {
                //                    let normalizedAddres = try await client.suggestAddressFirst(query: address)
                //                    if let na = normalizedAddres?.value {
                //                        let updated = CompanyDetails(
                //                            companyName: reqs.companyName,
                //                            legalForm: reqs.legalForm,
                //                            ceoFullName: reqs.ceoFullName,
                //                            ceoShortenName: reqs.ceoShortenName,
                //                            ogrn: reqs.ogrn,
                //                            inn: reqs.inn,
                //                            kpp: reqs.kpp,
                //                            email: reqs.email,
                //                            address: na,
                //                            phone: reqs.phone
                //                        )
                //
                //                        reqs = updated
                //                    }
                //                }
                
                //MARK: invalid test data
                //                let reqs = CompanyDetails(companyName: "Тест компания", legalForm: "ТЕСТ_ЗАО", ceoFullName: "Тест Тестович Тестов", ceoShortenName: "Тестов Т. Т.", ogrn: "11877467072801", inn: "97310107287", kpp: "7731010101", email: "test_test@test.com", address: "Город, ул. Улица, д. 8")
                
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
            let values = documentData?.asDictionary() as? [String: String]
            
            guard let values = values else { return }
            
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
            
            guard let documentData = documentData else { return }
            
            let row = googleSheetsRowBuilder.makeRow(from: documentData)
            googleSheetsRow = row
            googleSheetsRowBuilder.copyToPasteboard(row)
            googleSheetsCopyStatus = "Строка для Google Sheets скопирована в буфер обмена"
            
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
