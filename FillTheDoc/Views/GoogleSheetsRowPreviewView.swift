//
//  GoogleSheetsRowPreview.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 19.03.2026.
//

import SwiftUI


struct GoogleSheetsRowPreviewView: View {
    let row: String
    let status: String?
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Строка для Google Sheets")
                .font(.headline)
            
            ScrollView {
                Text(row)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 100)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.25))
            }
            
            HStack(spacing: 12) {
                Button("Скопировать еще раз") {
                    onCopy()
                }
                
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
