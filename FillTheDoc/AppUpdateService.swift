//
//  GitHubReleaseDTO.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 01.04.2026.
//


import Foundation

import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]
    let prerelease: Prerelease?
    
    var description: String {
        let base = components.map(String.init).joined(separator: ".")
        if let prerelease {
            return "\(base)-\(prerelease.rawValue)"
        }
        return base
    }
    
    init?(_ raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.anchored, .caseInsensitive])
        
        guard !normalized.isEmpty else { return nil }
        
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        
        let numericPart = String(parts[0])
        let numericComponents = numericPart
            .split(separator: ".")
            .compactMap { Int($0) }
        
        guard !numericComponents.isEmpty else { return nil }
        
        self.components = numericComponents
        
        if parts.count > 1 {
            self.prerelease = Prerelease(String(parts[1]))
        } else {
            self.prerelease = nil
        }
    }
    
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        
        for index in 0..<maxCount {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            
            if l != r {
                return l < r
            }
        }
        
        switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil):
                return false
                
            case (nil, .some):
                // release > prerelease
                return false
                
            case (.some, nil):
                // prerelease < release
                return true
                
            case let (.some(lp), .some(rp)):
                return lp < rp
        }
    }
    
    enum Prerelease: Comparable {
        case alpha
        case beta
        case rc
        case other(String)
        
        init(_ raw: String) {
            let value = raw.lowercased()
            
            if value.hasPrefix("alpha") {
                self = .alpha
            } else if value.hasPrefix("beta") {
                self = .beta
            } else if value.hasPrefix("rc") {
                self = .rc
            } else {
                self = .other(value)
            }
        }
        
        var rawValue: String {
            switch self {
                case .alpha: return "alpha"
                case .beta: return "beta"
                case .rc: return "rc"
                case .other(let value): return value
            }
        }
        
        private var rank: Int {
            switch self {
                case .alpha: return 0
                case .beta: return 1
                case .rc: return 2
                case .other: return 3
            }
        }
        
        static func < (lhs: Prerelease, rhs: Prerelease) -> Bool {
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            
            switch (lhs, rhs) {
                case let (.other(l), .other(r)):
                    return l < r
                default:
                    return false
            }
        }
    }
}

struct GitHubReleaseDTO: Decodable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case assets
    }
}

struct AppUpdateInfo: Sendable {
    let currentVersion: String
    let latestVersion: String
    let releasePageURL: URL
    let downloadURL: URL?
    let releaseTitle: String?
    let releaseNotes: String?
}

enum AppUpdateError: LocalizedError {
    case missingCurrentVersion
    case invalidResponseStatus(Int)
    case invalidHTTPResponse

    var errorDescription: String? {
        switch self {
        case .missingCurrentVersion:
            return "Не удалось получить текущую версию приложения."
        case .invalidResponseStatus(let code):
            return "GitHub вернул ошибку со статусом \(code)."
        case .invalidHTTPResponse:
            return "Некорректный ответ сервера."
        }
    }
}

actor AppUpdateService {
    private let owner: String
    private let repo: String
    private let session: URLSession

    init(owner: String, repo: String, session: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.session = session
    }

    func checkForUpdate() async throws -> AppUpdateInfo? {
        let currentVersion = try currentAppVersion()

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("FillTheDoc", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidHTTPResponse
        }

        guard 200..<300 ~= http.statusCode else {
            throw AppUpdateError.invalidResponseStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubReleaseDTO.self, from: data)

        let latestVersion = normalizeVersion(release.tagName)
        let normalizedCurrentVersion = normalizeVersion(currentVersion)

        guard isVersion(latestVersion, greaterThan: normalizedCurrentVersion) else {
            return nil
        }

        let preferredAsset = preferredDownloadAsset(from: release.assets)

        return AppUpdateInfo(
            currentVersion: normalizedCurrentVersion,
            latestVersion: latestVersion,
            releasePageURL: release.htmlURL,
            downloadURL: preferredAsset?.browserDownloadURL,
            releaseTitle: release.name,
            releaseNotes: release.body
        )
    }

    private func currentAppVersion() throws -> String {
        guard
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AppUpdateError.missingCurrentVersion
        }

        return version
    }

    private func normalizeVersion(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.anchored, .caseInsensitive])
    }

    private func preferredDownloadAsset(from assets: [GitHubReleaseDTO.Asset]) -> GitHubReleaseDTO.Asset? {
        if let dmg = assets.first(where: { $0.name.localizedCaseInsensitiveContains(".dmg") }) {
            return dmg
        }

        if let zip = assets.first(where: { $0.name.localizedCaseInsensitiveContains(".zip") }) {
            return zip
        }

        return assets.first
    }

    private func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        compareVersions(lhs, rhs) == .orderedDescending
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = AppVersion(lhs), let right = AppVersion(rhs) else {
            return .orderedSame
        }
        
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}
