//
//  ExtractedDTOFormView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//


import SwiftUI

struct ExtractedDTOFormView<T: LLMExtractable>: View {

    @StateObject private var model: EditableDTO<T>

    let onApply: (T) -> Void

    @State private var showErrorAlert = false
    @State private var errorText = ""

    init(dto: T, metadata: [String: FieldMetadata], onApply: @escaping (T) -> Void) {
        _model = StateObject(wrappedValue: EditableDTO(dto: dto, metadata: metadata))
        self.onApply = onApply
    }

    var body: some View {
        Form {
            ForEach(model.keysInOrder(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title(for: key))
                        .font(.subheadline.weight(.medium))

                    TextField(model.placeholder(for: key), text: binding(for: key))
                        .textFieldStyle(.roundedBorder)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(model.error(for: key) == nil ? .clear : .red.opacity(0.8), lineWidth: 1)
                        )

                    if let err = model.error(for: key), !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()

                Button("Применить") {
                    do {
                        let dto = try model.buildDTO()
                        onApply(dto)
                    } catch {
                        errorText = error.localizedDescription
                        showErrorAlert = true
                    }
                }
                .disabled(model.hasErrors)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { model.value(for: key) },
            set: { model.setValue($0, for: key) }
        )
    }
}

#Preview("Interactive") {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var requisites = Requisites(
        companyName: "ООО «Ромашка»",
        legalForm: "ООО",
        ceoFullName: "Иванов Иван Иванович",
        ceoShortenName: "Иванов И.И.",
        ogrn: "1234567890123",
        inn: "7701234567",
        kpp: "770101001",
        email: "info@romashka.ru"
    )
    
    var body: some View {
        ExtractedDTOFormView(
            dto: requisites,
            metadata: Requisites.fieldMetadata
        ) { updated in
            requisites = updated
        }
        .frame(width: 600, height: 700)
        .padding()
    }
}
