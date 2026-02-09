//
//  DropZoneCard.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 09.02.2026.
//

import SwiftUI
import UniformTypeIdentifiers


// MARK: - Drop zone

struct DropZoneCard: View {
    let title: String
    let subtitle: String
    
    let isValid: Bool
    @State private var isDropping: Bool = false
    
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
    
    private var iconName: String {
        isValid ? "checkmark.circle.fill" : "doc.badge.plus"
    }
    
    private var statusText: String {
        isValid ? "Файл добавлен" : "Перетащи файл сюда"
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
                    Image(systemName: iconName)
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isValid)
                    
                    Text(statusText)
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(borderColor)
            }
            .frame(height: 160)
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropping) { providers in
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
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }
        
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let u = item as? URL {
                    url = u
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                
                guard let url else { return }
                
                DispatchQueue.main.async {
                    onDropURLs([url])
                }
            }
        }
        return true
    }
}

#Preview("DropZoneCard – states") {
    struct PreviewWrapper: View {
        @State private var validPath: String = "/Users/artem/Documents/template.docx"
        @State private var invalidPath: String = ""
        
        var body: some View {
            VStack(spacing: 20) {
                
                DropZoneCard(
                    title: "Шаблон (DOCX)",
                    subtitle: "Перетащи сюда файл шаблона",
                    isValid: false,
                    path: $invalidPath,
                    onDropURLs: { _ in }
                )
                
                DropZoneCard(
                    title: "Реквизиты",
                    subtitle: "Файл с реквизитами клиента",
                    isValid: true,
                    path: $validPath,
                    onDropURLs: { _ in }
                )
                
                DropZoneCard(
                    title: "Dragging state",
                    subtitle: "Имитируем drag-over",
                    isValid: false,
                    path: $invalidPath,
                    onDropURLs: { _ in }
                )
            }
            .padding(24)
            .frame(width: 600)
        }
    }
    
    return PreviewWrapper()
}
