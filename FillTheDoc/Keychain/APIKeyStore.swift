//
//  APIKeyStore.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 13.02.2026.
//


import Foundation
import SwiftUI
public import Combine

@MainActor
public final class APIKeyStore: ObservableObject {
    @Published public private(set) var apiKey: String?
    @Published public var isPromptPresented: Bool = false
    @Published public var errorText: String?

    private let keychain: KeychainService
    private let account: String

    public init(
        keychain: KeychainService = KeychainService(),
        account: String = "openai_api_key"
    ) {
        self.keychain = keychain
        self.account = account
    }

    public func load() {
        Task {
            do {
                let loaded = try await keychain.loadString(account: account)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let loaded, !loaded.isEmpty {
                    apiKey = loaded
                    isPromptPresented = false
                    errorText = nil
                } else {
                    apiKey = nil
                    isPromptPresented = true
                }
            } catch {
                apiKey = nil
                errorText = "Не удалось прочитать ключ из Keychain: \(error.localizedDescription)"
                isPromptPresented = true
            }
        }
    }

    public func save(_ enteredKey: String) {
        let trimmed = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apiKey = nil
            isPromptPresented = true
            errorText = "Ключ не может быть пустым."
            return
        }

        Task {
            do {
                try await keychain.saveString(trimmed, account: account)
                apiKey = trimmed
                errorText = nil
                isPromptPresented = false
            } catch {
                apiKey = nil
                errorText = "Не удалось сохранить ключ в Keychain: \(error.localizedDescription)"
                isPromptPresented = true
            }
        }
    }

    public func clear() {
        Task {
            do {
                try await keychain.delete(account: account)
                apiKey = nil
                errorText = nil
                isPromptPresented = true
            } catch {
                errorText = "Не удалось удалить ключ из Keychain: \(error.localizedDescription)"
            }
        }
    }

    /// Удобно для guard’ов в действиях.
    public var hasKey: Bool {
        let k = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !k.isEmpty
    }
}
