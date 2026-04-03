//
//  AppUpdateStore.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 01.04.2026.
//


import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateStore {
    private let service: AppUpdateService

    var updateInfo: AppUpdateInfo?
    var isChecking = false
    var errorText: String?

    init() {
        self.service = AppUpdateService(owner: "temamarvel", repo: "FillTheDoc")
    }

    var currentVersionText: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        return "—"
    }

    var hasUpdate: Bool {
        updateInfo != nil
    }

    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        do {
            updateInfo = try await service.checkForUpdate()
            errorText = nil
        } catch {
            updateInfo = nil
            errorText = error.localizedDescription
        }
    }
}
