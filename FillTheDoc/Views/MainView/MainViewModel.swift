import Foundation
import SwiftUI
import OpenAIClient

@MainActor
@Observable
final class MainViewModel {
    
    // MARK: - Dependencies
    
    let apiKeyStore: APIKeyStore
    let updateStore: AppUpdateStore
    private let scanner: DocxTemplatePlaceholderScanner
    private let replacer: DocxPlaceholderReplacer
    private let googleSheetsRowBuilder: GoogleSheetsRowBuilding
    private let extractorService: DocumentTextExtractorService
    
    // MARK: - State (paths)
    
    var templatePath: String = ""
    var detailsPath: String = ""
    
    // MARK: - State (data)
    
    private(set) var details: CompanyDetails?
    var documentData: DocumentData?
    private(set) var templatePlaceholders: [String] = []
    private(set) var googleSheetsRow: String?
    
    // MARK: - State (UI)
    
    private(set) var isLoading: Bool = false
    var isDataApproved: Bool = false
    
    // MARK: - Task management
    
    private var extractTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var extractionGeneration: Int = 0
    
    // MARK: - State (exporter)
    
    var showExporter: Bool = false
    var exportDocument: DocxFileDocument?
    var exportDefaultFilename: String = "output"
    
    // MARK: - Computed
    
    var templateURL: URL? { url(from: templatePath) }
    var detailsURL: URL? { url(from: detailsPath) }
    
    var isTemplateValid: Bool { isExistingFile(templateURL) }
    var isDetailsValid: Bool { isExistingFile(detailsURL) }
    
    var canRun: Bool {
        isTemplateValid && isDetailsValid && apiKeyStore.hasKey && isDataApproved
    }
    
    // MARK: - Init
    
    init(
        apiKeyStore: APIKeyStore,
        updateStore: AppUpdateStore,
        scanner: DocxTemplatePlaceholderScanner,
        replacer: DocxPlaceholderReplacer,
        googleSheetsRowBuilder: GoogleSheetsRowBuilding,
        extractorService: DocumentTextExtractorService
    ) {
        self.apiKeyStore = apiKeyStore
        self.updateStore = updateStore
        self.scanner = scanner
        self.replacer = replacer
        self.googleSheetsRowBuilder = googleSheetsRowBuilder
        self.extractorService = extractorService
    }
    
    /// Convenience init with default dependencies for production use.
    convenience init() {
        let updateStore = AppUpdateStore(
            service: AppUpdateService(
                owner: "temamarvel",
                repo: "FillTheDoc"
            )
        )
        
        let apiKeyStore = APIKeyStore()
        
        self.init(
            apiKeyStore: apiKeyStore,
            updateStore: updateStore,
            scanner: DocxTemplatePlaceholderScanner(),
            replacer: DocxPlaceholderReplacer(),
            googleSheetsRowBuilder: GoogleSheetsRowBuilder(),
            extractorService: DocumentTextExtractorService()
        )
    }
    
    // MARK: - Actions
    
    func handleTemplateDrop(_ urls: [URL]) {
        isDataApproved = false
        if let url = urls.first { templatePath = url.path }
        scanPlaceholders()
    }
    
    func handleDetailsDrop(_ urls: [URL]) {
        isDataApproved = false
        details = nil
        googleSheetsRow = nil
        if let url = urls.first { detailsPath = url.path }
        extractDetails()
    }
    
    func applyDocumentData(_ updated: DocumentData) {
        details = updated.companyDetails
        documentData = updated
        isDataApproved = true
    }
    
    func handleExportResult(_ result: Result<URL, any Error>) {
        switch result {
            case .success:
                print("NEW DOC SAVED")
            case .failure:
                print("NEW DOC! Не удалось сохранить файл")
        }
        exportDocument = nil
    }
    
    // MARK: - Scan placeholders (IO off main thread)
    
    func scanPlaceholders() {
        guard let templateURL else { return }
        let scanner = self.scanner
        
        scanTask?.cancel()
        scanTask = Task {
            do {
                let keys = try await scanner.scanKeys(template: templateURL)
                try Task.checkCancellation()
                self.templatePlaceholders = keys
            } catch is CancellationError {
                // игнорируем отмену
            } catch {
                print("Scan failed:", error)
            }
        }
    }
    
    // MARK: - Extract details (IO + OpenAI off main thread)
    
    func extractDetails() {
        guard let detailsURL else { return }
        let extractorService = self.extractorService
        
        extractTask?.cancel()
        extractionGeneration += 1
        let generation = extractionGeneration
        
        extractTask = Task { [weak self] in
            guard let self else { return }
            
            self.isLoading = true
            defer { Task { @MainActor [weak self] in self?.isLoading = false } }
            
            do {
                let extractedDetails = try await extractorService.extract(from: detailsURL)
                try Task.checkCancellation()
                
                //let companyDetails = try await self.fakeOpenAICall(extractedDetails: extractedDetails)
                let companyDetails = try await self.callOpenAI(extractedDetails: extractedDetails)
                try Task.checkCancellation()
                
                // Защита от out-of-order: записываем только если нет более свежей задачи
                guard generation == self.extractionGeneration else { return }
                self.details = companyDetails
                print("DTO:", companyDetails.toMultilineString())
            } catch is CancellationError {
                // нормальная отмена — ничего не делаем
            } catch {
                print("Extraction failed:", error)
            }
        }
    }
    
    // MARK: - Fill template (IO off main thread)
    
    func runFill() async {
        guard let templateURL else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let values = documentData?.asDictionary() else { return }
            
            let tempOutURL = makeTempOutputURL(from: templateURL)
            
            let report = try await replacer.fill(
                template: templateURL,
                output: tempOutURL,
                values: values
            )
            
            exportDocument = try DocxFileDocument(fileURL: tempOutURL)
            exportDefaultFilename = "\(templateURL.deletingPathExtension().lastPathComponent)_filled"
            showExporter = true
            
            if let documentData {
                let row = googleSheetsRowBuilder.makeRow(from: documentData)
                googleSheetsRow = row
                googleSheetsRowBuilder.copyToPasteboard(row)
            }
            
            print("missing", report.missingKeys)
            print("found", report.foundKeys)
            print("REPLACE OK")
        } catch {
            print("Replacement failed:", error)
        }
    }
    
    // MARK: - Private
    
    private func callOpenAI(extractedDetails: ExtractionResult) async throws -> CompanyDetails {
        let openAIClient = OpenAIClient(apiKey: apiKeyStore.apiKey ?? "", model: "gpt-4o-mini")
        let system = PromptBuilder.system(for: CompanyDetails.self)
        let user = PromptBuilder.user(sourceText: extractedDetails.text)
        
        let (companyDetails, _) = try await openAIClient.request(
            system: system,
            user: user,
            as: CompanyDetails.self
        )
        
        return companyDetails
    }
    
    private func fakeOpenAICall(extractedDetails: ExtractionResult) async throws -> CompanyDetails {
        // симуляция
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // MARK: valid test data
        return CompanyDetails(companyName: "Тест компания", legalForm: LegalForm.parse("ЗАО"), ceoFullName: "Тест Тестович Тестов", ceoFullGenitiveName: "Теста Тестовича Тестова", ceoShortenName: "Тестов Т. Т.", ogrn: "1187746707280", inn: "9731007287", kpp: "773101001", email: "test_test@test.com", address: "город Москва, ул Горбунова, д. 2 стр. 3", phone: "+79991234567")
        
        //MARK: invalid test data
        // return CompanyDetails(companyName: "Тест компания", legalForm: "ТЕСТ_ЗАО", ceoFullName: "Тест Тестович Тестов", ceoShortenName: "Тестов Т. Т.", ogrn: "11877467072801", inn: "97310107287", kpp: "7731010101", email: "test_test@test.com", address: "Город, ул. Улица, д. 8")
    }
    
    private func makeTempOutputURL(from templateURL: URL) -> URL {
        let base = templateURL.deletingPathExtension().lastPathComponent
        let name = "\(base)_out_\(UUID().uuidString).docx"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
    
    private func url(from path: String) -> URL? {
        let trimmed = path.trimmed
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
