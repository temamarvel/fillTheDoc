//
//  ProcessRunning.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 10.02.2026.
//

import Foundation


public protocol ProcessRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput
}

public struct ProcessOutput {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
}

public enum ProcessRunnerError: Error {
    case nonZeroExit(code: Int32, stderr: String)
    case timeout
}

public final class DefaultProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw ProcessRunnerError.timeout
        }

        let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
        let code = process.terminationStatus

        if code != 0 {
            let errText = String(data: stderr, encoding: .utf8) ?? ""
            throw ProcessRunnerError.nonZeroExit(code: code, stderr: errText)
        }

        return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: code)
    }
}
