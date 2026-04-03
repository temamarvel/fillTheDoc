import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @State private var viewModel: MainViewModel
//    @State private var apiKeyStore: APIKeyStore
    
    init() {
        //let apiKeyStore = APIKeyStore()
        let viewModel = MainViewModel()
        
        //_apiKeyStore = State(initialValue: apiKeyStore)
        _viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Заполнение документа")
                .font(.title2.weight(.semibold))
            
            HStack(spacing: 16) {
                DropZoneCardView(
                    title: "Шаблон (DOCX)",
                    isValid: viewModel.isTemplateValid,
                    path: viewModel.templatePath,
                    onDropURLs: { viewModel.handleTemplateDrop($0) }
                )
                
                DropZoneCardView(
                    title: "Реквизиты (DOC, DOCX, PDF, XLS, XLSX)",
                    isValid: viewModel.isDetailsValid,
                    path: viewModel.detailsPath,
                    onDropURLs: { viewModel.handleDetailsDrop($0) }
                )
            }
            
            Group {
                if let googleSheetsRow = viewModel.googleSheetsRow, !googleSheetsRow.isEmpty {
                    CodeBlockView(content: googleSheetsRow)
                } else {
                    if let details = viewModel.details {
//                        let keys = viewModel.templatePlaceholders.compactMap {
//                            CompanyDetails.CodingKeys(rawValue: $0)
//                        }
                        
                        DocumentDataFormView(
                            companyDetails: details,
                            metadata: CompanyDetails.fieldMetadata,
                            keys: CompanyDetails.CodingKeys.allCases
                        ) { updated in
                            viewModel.applyDocumentData(updated)
                        }
                    } else {
                        EmptyCompanyDetailsPlaceholderView()
                    }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                
                Button {
                    Task { await viewModel.runFill() }
                } label: {
                    Text("Заполнить шаблон")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canRun || viewModel.isLoading)
                
                Spacer()
            }
            
            HStack{
                Spacer()
                
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("v\(version) (\(build))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if let updateInfo = viewModel.updateStore.updateInfo {
                    UpdateBadgeView(updateInfo: updateInfo)
                }
            }
        }
        .task {
            await viewModel.updateStore.checkForUpdates()
        }
        .task {
            await viewModel.apiKeyStore.load()
        }
        .padding(20)
        .fileExporter(
            isPresented: $viewModel.showExporter,
            document: viewModel.exportDocument,
            contentType: UTType(filenameExtension: "docx") ?? .data,
            defaultFilename: viewModel.exportDefaultFilename
        ) { result in
            viewModel.handleExportResult(result)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.apiKeyStore.isPromptPresented },
            set: { viewModel.apiKeyStore.isPromptPresented = $0 }
        )) {
            APIKeyPromptView { enteredKey in
                Task {
                    await viewModel.apiKeyStore.save(enteredKey)
                }
            }
            .interactiveDismissDisabled(true)
        }
        .overlay {
            if viewModel.isLoading {
                AIWaitingIndicatorView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
}

#Preview {
    MainView()
}
