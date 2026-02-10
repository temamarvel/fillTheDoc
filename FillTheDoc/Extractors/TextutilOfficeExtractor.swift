//
//  TextutilOfficeExtractor.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation


public struct TextutilOfficeExtractor: TextExtracting {
    private let runner: ProcessRunning
    private let timeout: TimeInterval

    public init(runner: ProcessRunning, timeout: TimeInterval) {
        self.runner = runner
        self.timeout = timeout
    }

    public func extract(from url: URL) throws -> (String, ExtractionResult.Method, Bool, [String]) {
        let tool = URL(fileURLWithPath: "/usr/bin/textutil")
        let out = try runner.run(
            executable: tool,
            arguments: ["-convert", "txt", "-stdout", url.path],
            timeout: timeout
        )
        let text = TextDecoding.decodeBestEffort(out.stdout)
        return (text, .textutil, false, ["Converted via textutil (-stdout)."])
    }
}
