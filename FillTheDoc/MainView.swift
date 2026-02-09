//
//  ContentView.swift
//  FillTheDoc
//
//  Created by Artem Denisov on 09.02.2026.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main screen

struct MainView: View {
    @State private var templatePath: String = ""
    @State private var detailsPath: String = ""
    
    @State private var isDroppingTemplate = false
    @State private var isDroppingDetails = false
    
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
                    isDropping: isDroppingTemplate,
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
                    isDropping: isDroppingDetails,
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
        .frame(minWidth: 860, minHeight: 360)
    }
    
    // MARK: - Actions
    
    private func runFill() {
        guard let templateURL, let detailsURL else { return }
        // Тут будет твой pipeline:
        // 1) извлечь реквизиты из detailsURL (LLM)
        // 2) скопировать templateURL
        // 3) заполнить плейсхолдеры и сохранить результат
        print("Run with template:", templateURL.path, "details:", detailsURL.path)
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

// MARK: - Drop zone

private struct DropZoneCard: View {
    let title: String
    let subtitle: String
    
    let isValid: Bool
    let isDropping: Bool
    
    @Binding var path: String
    let onDropURLs: ([URL]) -> Void
    
    private var borderColor: Color {
        if isValid { return .green }
        return .red
    }
    
    private var fillColor: Color {
        // лёгкий фон, чтобы зона читалась
        if isDropping { return Color.primary.opacity(0.06) }
        return Color.primary.opacity(0.03)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                StatusBadge(isValid: isValid)
            }
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fillColor)
                
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor.opacity(isDropping ? 1.0 : 0.85),
                                  style: StrokeStyle(lineWidth: isDropping ? 3 : 2, dash: [8, 6]))
                
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 34, weight: .semibold))
                    
                    Text(isValid ? "Файл добавлен" : "Перетащи файл сюда")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(borderColor)
            }
            .frame(height: 160)
            .onDrop(of: [UTType.fileURL], isTargeted: dropTargetBinding) { providers in
                handleDrop(providers: providers)
            }
            
            TextField("Путь к файлу", text: $path)
                .textFieldStyle(.roundedBorder)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor.opacity(0.75), lineWidth: 1)
                )
                .help("Можно вставить/отредактировать путь вручную")
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { isDropping },
            set: { _ in }
        )
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Берём первый provider с fileURL
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
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

private struct StatusBadge: View {
    let isValid: Bool
    
    var body: some View {
        Text(isValid ? "OK" : "Нужно")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isValid ? Color.green.opacity(0.18) : Color.red.opacity(0.18),
                        in: Capsule())
            .foregroundStyle(isValid ? Color.green : Color.red)
    }
}

#Preview {
    MainView()
}
