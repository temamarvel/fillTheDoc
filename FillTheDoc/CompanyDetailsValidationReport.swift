//
//  PartyValidationReport.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 23.02.2026.
//


import Foundation
import DaDataAPIClient

public struct CompanyDetailsValidationReport: Sendable {
    public enum Verdict: String, Sendable { case pass, warn, fail }

    public let verdict: Verdict
    public let score: Double          // 0...1
    public let issues: [PartyValidationIssue]

    public init(verdict: Verdict, score: Double, issues: [PartyValidationIssue]) {
        self.verdict = verdict
        self.score = max(0, min(1, score))
        self.issues = issues
    }
}

public struct PartyValidationIssue: Sendable, Identifiable {
    public enum Severity: String, Sendable { case info, warning, error }
    public enum Code: String, Sendable {
        case innInvalidFormat
        case innMismatch
        case kppInvalidFormat
        case kppMismatch
        case ogrnInvalidFormat
        case ogrnMismatch
        case orgNameMismatch
        case ceoNameMismatch
        case statusNotActive
        case addressSuspicious
        case addressMismatch
    }

    public let id = UUID()
    public let severity: Severity
    public let code: Code
    public let message: String

    public let llmValue: String?
    public let apiValue: String?

    public init(
        severity: Severity,
        code: Code,
        message: String,
        llmValue: String? = nil,
        apiValue: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.llmValue = llmValue
        self.apiValue = apiValue
    }
}
