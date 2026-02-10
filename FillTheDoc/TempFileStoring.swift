//
//  TempFileStoring.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation


public protocol TempFileStoring {
    func copyToTemp(_ url: URL) throws -> URL
    func cleanup(forTempCopy tempURL: URL)
}

public struct DefaultTempFileStore: TempFileStoring {
    public init() {}

    public func copyToTemp(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("FillTheDoc-Extract-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let dst = dir.appendingPathComponent(url.lastPathComponent, isDirectory: false)
        try fm.copyItem(at: url, to: dst)
        return dst
    }

    public func cleanup(forTempCopy tempURL: URL) {
        let parent = tempURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }
}
