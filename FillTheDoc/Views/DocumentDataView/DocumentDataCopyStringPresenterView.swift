//
//  CodeBlockView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 26.03.2026.
//


import SwiftUI

struct DocumentDataCopyStringPresenterView: View {
    let content: String
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView([.horizontal, .vertical]) {
                
                Text(content.replacingOccurrences(of: "\t", with: " | "))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.trailing, 36) // место под кнопку
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Кнопка копирования
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content.replacingOccurrences(of: " | ", with: "\t"), forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copied ? .green : .secondary)
                    .frame(width: 28, height: 28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}
