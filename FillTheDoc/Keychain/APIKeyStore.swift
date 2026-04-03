//
//  APIKeyStore.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 13.02.2026.
//


import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
final class APIKeyStore: ObservableObject {
    private(set) var apiKey: String?
    var isPromptPresented: Bool = false
    var errorText: String?
    
    private let keychain: KeychainService
    private let account: String
    
    init(
        keychain: KeychainService = KeychainService(),
        account: String = "openai_api_key"
    ) {
        self.keychain = keychain
        self.account = account
    }
    
    func load() {
        Task {
            do {
                let loaded = try await keychain.loadString(account: account)?
                    .trimmed
                
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
    
    func save(_ enteredKey: String) {
        let trimmed = enteredKey.trimmed
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
    
    func clear() {
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
    var hasKey: Bool {
        let k = apiKey?.trimmed ?? ""
        return !k.isEmpty
    }
}
