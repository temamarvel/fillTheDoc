//
//  PartyValidator.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 23.02.2026.
//


import Foundation
import DaDataAPIClient

public struct CompanyDetailsValidator: Sendable {

    public struct Policy: Sendable {
        public var nameSimilarityThreshold: Double   // для Jaccard
        public var addressSimilarityThreshold: Double
        public var failScoreThreshold: Double
        public var warnScoreThreshold: Double

        public init(
            nameSimilarityThreshold: Double = 0.72,
            addressSimilarityThreshold: Double = 0.55,
            warnScoreThreshold: Double = 0.75,
            failScoreThreshold: Double = 0.55
        ) {
            self.nameSimilarityThreshold = nameSimilarityThreshold
            self.addressSimilarityThreshold = addressSimilarityThreshold
            self.warnScoreThreshold = warnScoreThreshold
            self.failScoreThreshold = failScoreThreshold
        }
    }

    private let policy: Policy

    public init(policy: Policy = .init()) {
        self.policy = policy
    }

    public func validate(llm: CompanyDetails, api: DaDataParty) -> CompanyDetailsValidationReport {
        var issues: [PartyValidationIssue] = []
        var score: Double = 1.0

        func present(_ s: String?) -> String? {
            guard let s else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        // MARK: - INN
        if let llmINN = present(llm.inn) {
            if !FormatValidators.isValidINN(llmINN) {
                issues.append(.init(
                    severity: .error,
                    code: .innInvalidFormat,
                    message: "ИНН имеет неверный формат или контрольную сумму.",
                    llmValue: llmINN,
                    apiValue: api.inn
                ))
                score -= 0.25
            } else {
                let apiINN = api.inn.map(FormatValidators.digitsOnly)
                if let apiINN, apiINN != FormatValidators.digitsOnly(llmINN) {
                    issues.append(.init(
                        severity: .error,
                        code: .innMismatch,
                        message: "ИНН не совпадает с DaData.",
                        llmValue: llmINN,
                        apiValue: apiINN
                    ))
                    score -= 0.35
                }
            }
        }

        // MARK: - KPP
        if let llmKPP = present(llm.kpp) {
            if !FormatValidators.isValidKPP(llmKPP) {
                issues.append(.init(
                    severity: .warning,
                    code: .kppInvalidFormat,
                    message: "КПП выглядит некорректно (ожидается 9 цифр).",
                    llmValue: llmKPP,
                    apiValue: api.kpp
                ))
                score -= 0.10
            } else if let apiKPP = api.kpp.map(FormatValidators.digitsOnly),
                      apiKPP != FormatValidators.digitsOnly(llmKPP) {
                issues.append(.init(
                    severity: .warning,
                    code: .kppMismatch,
                    message: "КПП не совпадает с DaData.",
                    llmValue: llmKPP,
                    apiValue: apiKPP
                ))
                score -= 0.15
            }
        }

        // MARK: - OGRN
        if let llmOGRN = present(llm.ogrn) {
            if !FormatValidators.isValidOGRN(llmOGRN) {
                issues.append(.init(
                    severity: .warning,
                    code: .ogrnInvalidFormat,
                    message: "ОГРН/ОГРНИП выглядит некорректно (контрольная сумма/длина).",
                    llmValue: llmOGRN,
                    apiValue: api.ogrn
                ))
                score -= 0.10
            } else if let apiOGRN = api.ogrn.map(FormatValidators.digitsOnly),
                      apiOGRN != FormatValidators.digitsOnly(llmOGRN) {
                issues.append(.init(
                    severity: .warning,
                    code: .ogrnMismatch,
                    message: "ОГРН/ОГРНИП не совпадает с DaData.",
                    llmValue: llmOGRN,
                    apiValue: apiOGRN
                ))
                score -= 0.15
            }
        }

        // MARK: - Company name
        if let llmName = present(llm.companyName) {
            let apiName =
                api.name?.fullWithOpf
                ?? api.name?.shortWithOpf
                ?? api.name?.full
                ?? api.name?.short

            if let apiName {
                let sim = TextNormalization.jaccard(llmName, apiName)
                let contains = TextNormalization.containsNormalized(llmName, apiName)

                if !(contains || sim >= policy.nameSimilarityThreshold) {
                    issues.append(.init(
                        severity: .warning,
                        code: .orgNameMismatch,
                        message: "Название организации слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).",
                        llmValue: llmName,
                        apiValue: apiName
                    ))
                    score -= 0.15
                }
            }
        }

        // MARK: - CEO / management name
        if let llmCEO = present(llm.ceoFullName) {
            if let apiCEO = api.management?.name, !apiCEO.isEmpty {
                let sim = TextNormalization.jaccard(llmCEO, apiCEO)
                let contains = TextNormalization.containsNormalized(llmCEO, apiCEO)
                if !(contains || sim >= 0.70) {
                    issues.append(.init(
                        severity: .warning,
                        code: .ceoNameMismatch,
                        message: "ФИО руководителя слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).",
                        llmValue: llmCEO,
                        apiValue: apiCEO
                    ))
                    score -= 0.10
                }
            }
        }

        // MARK: - Status
        if let status = api.state?.status, !status.isEmpty {
            if status.uppercased() != "ACTIVE" {
                issues.append(.init(
                    severity: .warning,
                    code: .statusNotActive,
                    message: "Статус организации не ACTIVE (DaData: \(status)).",
                    llmValue: nil,
                    apiValue: status
                ))
                score -= 0.10
            }
        }

//        // MARK: - Address
//        if let llmAddress = present(llm.) {
//            if !FormatValidators.looksLikeAddress(llmAddress) {
//                issues.append(.init(
//                    severity: .warning,
//                    code: .addressSuspicious,
//                    message: "Адрес выглядит подозрительно (не похож на адрес).",
//                    llmValue: llmAddress,
//                    apiValue: api.address?.value
//                ))
//                score -= 0.10
//            }
//
//            if let apiAddress = api.address?.value, !apiAddress.isEmpty {
//                let sim = TextNormalization.jaccard(llmAddress, apiAddress)
//                let contains = TextNormalization.containsNormalized(llmAddress, apiAddress)
//
//                if !(contains || sim >= policy.addressSimilarityThreshold) {
//                    issues.append(.init(
//                        severity: .warning,
//                        code: .addressMismatch,
//                        message: "Адрес слабо похож на DaData (sim=\(String(format: "%.2f", sim))).",
//                        llmValue: llmAddress,
//                        apiValue: apiAddress
//                    ))
//                    score -= 0.10
//                }
//            }
//        }

        score = max(0, min(1, score))

        let verdict: CompanyDetailsValidationReport.Verdict
        if score < policy.failScoreThreshold || issues.contains(where: { $0.severity == .error }) {
            verdict = .fail
        } else if score < policy.warnScoreThreshold || issues.contains(where: { $0.severity == .warning }) {
            verdict = .warn
        } else {
            verdict = .pass
        }

        return CompanyDetailsValidationReport(verdict: verdict, score: score, issues: issues)
    }
}
