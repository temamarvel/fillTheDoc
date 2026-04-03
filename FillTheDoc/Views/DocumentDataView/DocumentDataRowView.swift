//
//  DocumentDataRowView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 24.03.2026.
//

import SwiftUI


struct DocumentDataRowView<Key: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let errorColor: Color
    let errorText: String?
    @FocusState.Binding var focusedKey: Key?
    let key: Key
    
    var body: some View {
        HStack(alignment: .center) {
            Text(title)
            
            VStack(alignment: .trailing) {
                TextField("", text: $text, prompt: Text(placeholder), axis: .horizontal)
                    .focused($focusedKey, equals: key)
                
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(errorColor)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background {
                if errorText != nil {
                    LinearGradient(
                        colors: [
                            .clear,
                            errorColor.opacity(0.10),
                            errorColor.opacity(0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
    }
}
