import SwiftUI
import UniformTypeIdentifiers

/// Generic DropZone карточка с опциональным "нижним" контентом (bottom).
/// - Поддерживает drag&drop файлов (UTType.fileURL)
/// - Показывает path (как текст) и валидность (иконка/цвет)
/// - Может "расти по контенту" (heightToContent) или быть фиксированной по высоте
struct DropZoneCard<Bottom: View>: View {
    let title: String
    var subtitle: String? = nil
    
    let isValid: Bool
    @Binding var path: String
    
    /// Если true — карточка не фиксирует высоту и растёт под контентом (включая bottom).
    var heightToContent: Bool = true
    
    /// Callback: что делать с за-дропанными URL.
    let onDropURLs: ([URL]) -> Void
    
    /// Опциональный нижний контент (например: ProgressView, ошибки, превью текста и т.п.)
    private let bottom: Bottom
    
    // UI state
    @State private var isTargeted: Bool = false
    
    // MARK: - Initializers
    
    init(
        title: String,
        subtitle: String? = nil,
        isValid: Bool,
        path: Binding<String>,
        onDropURLs: @escaping ([URL]) -> Void,
        heightToContent: Bool = true,
        fixedHeight: CGFloat = 120,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isValid = isValid
        self._path = path
        self.onDropURLs = onDropURLs
        self.heightToContent = heightToContent
        self.bottom = bottom()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            
            dropArea
            
            Divider().opacity(hasBottomContent ? 0.6 : 0.0)
                .frame(height: hasBottomContent ? nil : 0)
            
            if hasBottomContent {
                bottom
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
    
    // MARK: - Subviews
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isValid ? .green : .red)
                .imageScale(.large)
                .accessibilityLabel(isValid ? "Valid" : "Not selected")
        }
    }
    
    private var dropArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: isValid ? "doc.badge.checkmark" : "doc")
                    .imageScale(.large)
                    .foregroundStyle(isValid ? .green : .red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isValid ? "Файл выбран" : "Перетащи файл сюда")
                        .font(.subheadline.weight(.semibold))
                    Text(pathPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop(providers:))
    }
    
    // MARK: - Helpers
    
    private var borderColor: Color {
        if isTargeted { return .yellow.opacity(0.7) }
        if isValid { return .green.opacity(0.5) }
        return .red.opacity(0.5)
    }
    
    private var pathPreview: String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Путь не выбран" : trimmed
    }
    
    private var hasBottomContent: Bool {
        // Для EmptyView мы не хотим показывать Divider и лишнее пространство.
        Bottom.self != EmptyView.self
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            DispatchQueue.main.async {
                onDropURLs([url])
            }
        }
        return true
    }
}

// MARK: - Convenience init for “no bottom content”
extension DropZoneCard where Bottom == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        isValid: Bool,
        path: Binding<String>,
        onDropURLs: @escaping ([URL]) -> Void,
        heightToContent: Bool = true,
        fixedHeight: CGFloat = 120
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            isValid: isValid,
            path: path,
            onDropURLs: onDropURLs,
            heightToContent: heightToContent,
            fixedHeight: fixedHeight
        ) {
            EmptyView()
        }
    }
}

private struct DropZoneCardPreviewContainer: View {
    @State private var emptyPath: String = ""
    @State private var validPath: String = "/Users/artem/Documents/template.docx"
    @State private var loadingPath: String = "/Users/artem/Documents/details.pdf"
    
    var body: some View {
        VStack(spacing: 24) {
            
            // 1. Пустое состояние
            DropZoneCard(
                title: "Шаблон (DOCX)",
                subtitle: "Перетащи сюда файл шаблона",
                isValid: false,
                path: $emptyPath,
                onDropURLs: { _ in }
            )
            
            // 2. Валидное состояние
            DropZoneCard(
                title: "Реквизиты",
                subtitle: "Файл с данными клиента",
                isValid: true,
                path: $validPath,
                onDropURLs: { _ in }
            )
            
            // 3. С нижним контентом (например, загрузка)
            DropZoneCard(
                title: "Обработка",
                subtitle: "Извлечение данных из документа",
                isValid: true,
                path: $loadingPath,
                onDropURLs: { _ in }
            ) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        
                        Text("Извлечение текста через textutil...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .background(.yellow)
                        .frame(height: 30)
                }
            }
        }
    }
}

#Preview("DropZoneCard States") {
    DropZoneCardPreviewContainer()
        .frame(width: 520)
        .padding()
}
