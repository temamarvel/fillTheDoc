//
//  FillTheDocApp.swift
//  FillTheDoc
//
//  Created by Artem Denisov on 09.02.2026.
//

import SwiftUI

@main
struct FillTheDocApp: App {
    @StateObject private var apiKeyStore = APIKeyStore()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(apiKeyStore)
                .onAppear {
                    apiKeyStore.load()
                }
        }
    }
}
