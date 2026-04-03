//
//  SecurityScopedAccessing.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation


protocol SecurityScopedAccessing {
    func withAccess<T>(_ url: URL, _ body: () throws -> T) throws -> T
}

struct DefaultSecurityScopedAccessor: SecurityScopedAccessing {
    init() {}

    func withAccess<T>(_ url: URL, _ body: () throws -> T) throws -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
