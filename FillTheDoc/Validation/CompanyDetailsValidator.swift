import Foundation
import DaDataAPIClient

public struct FieldState: Sendable, Equatable {
    var value : String?
    var issue: FieldIssue?
    var isValid: Bool {
        issue == nil
    }
}

public actor CompanyDetailsValidator {
    
    typealias Key = CompanyDetails.CodingKeys
    
    public struct Policy: Sendable {
        public var nameSimilarityThreshold: Double
        public var addressSimilarityThreshold: Double
        
        public var preferRemoteOnTie: Bool
        public var combineTextsOnTie: Bool
        
        public init(
            nameSimilarityThreshold: Double = 0.72,
            addressSimilarityThreshold: Double = 0.55,
            preferRemoteOnTie: Bool = false,
            combineTextsOnTie: Bool = true
        ) {
            self.nameSimilarityThreshold = nameSimilarityThreshold
            self.addressSimilarityThreshold = addressSimilarityThreshold
            self.preferRemoteOnTie = preferRemoteOnTie
            self.combineTextsOnTie = combineTextsOnTie
        }
    }
    
    private let policy: Policy
    private let dadataClient: DaDataClient
    private var cache: [String: DaDataCompanyInfo]
    
    public init(dadataClient: DaDataClient, policy: Policy = .init()) {
        self.policy = policy
        self.dadataClient = dadataClient
        self.cache = [:]
    }
    
    // MARK: - Local validation (no network)
    
    nonisolated func validateField(for fieldKey: Key, state: FieldState) -> FieldIssue? {
        guard let validator = CompanyDetails.fieldMetadata[fieldKey]?.validator else {
            return nil
        }
        
        guard let value = state.value else {
            return nil
        }
        
        return validator(value)
    }
    
    func validateFieldsWithReference(fields: [Key: FieldState]) async -> [Key: FieldState] {
        //fields have to be normalized and not null before validation
        
        let ogrn = fields[.ogrn]?.value
        let inn = fields[.inn]?.value
        
        // MARK: get dadata company info
        var dadataCompanyInfo: DaDataCompanyInfo? = nil
        do{
            let identifier = ogrn ?? inn
            
            guard let identifier else {
                return fields
            }
            
            if let cached = cache[identifier] {
                dadataCompanyInfo = cached
            } else {
                dadataCompanyInfo = try await dadataClient.fetchCompanyInfoFirts(innOrOgrn: identifier)?.data
                if let dadataCompanyInfo {
                    if let fetchedOgrn = dadataCompanyInfo.ogrn {
                        cache[fetchedOgrn] = dadataCompanyInfo
                    }
                    if let fetchedInn = dadataCompanyInfo.inn {
                        cache[fetchedInn] = dadataCompanyInfo
                    }
                }
            }
        }
        catch{
            
        }
        
        guard let dadataCompanyInfo else {
            return fields //TODO
        }
        
        // MARK: validate all fields using dadata info
        
        var resultFields = fields
        
        for (key, state) in fields {
            let crossIssue = crossValidateField(fieldKey: key, state: state, companyInfo: dadataCompanyInfo)
            
            guard let crossIssue else { continue }
            
            // Не перезаписываем error от локальной валидации warning-ом от DaData
            if resultFields[key]?.issue == nil || resultFields[key]?.issue?.severity == .warning {
                resultFields[key]?.issue = crossIssue
            }
        }
        
        return resultFields
    }
    
    // MARK: - Cross validation with DaData
    
    private func crossValidateField(fieldKey: Key, state: FieldState, companyInfo: DaDataCompanyInfo) -> FieldIssue? {
        switch fieldKey {
            case .inn:
                guard let llmINN = state.value else { return nil }
                let apiINN = companyInfo.inn.map { $0.digitsOnly }
                if let apiINN, apiINN != llmINN.digitsOnly {
                    return .warning("ИНН не совпадает с DaData.")
                }
                return nil
                
            case .kpp:
                guard let llmKPP = state.value else { return nil }
                if let apiKPP = companyInfo.kpp.map({ $0.digitsOnly }),
                   apiKPP != llmKPP.digitsOnly {
                    return .warning("КПП не совпадает с DaData.")
                }
                return nil
                
            case .ogrn:
                guard let llmOGRN = state.value else { return nil }
                if let apiOGRN = companyInfo.ogrn.map({ $0.digitsOnly }),
                   apiOGRN != llmOGRN.digitsOnly {
                    return .warning("ОГРН/ОГРНИП не совпадает с DaData.")
                }
                return nil
                
            case .companyName:
                guard let llmName = state.value else { return nil }
                
                let apiName =
                companyInfo.name?.fullWithOpf
                ?? companyInfo.name?.shortWithOpf
                ?? companyInfo.name?.full
                ?? companyInfo.name?.short
                
                guard let apiName else { return nil }
                
                let sim = Validators.jaccardSimilarity(llmName, apiName)
                let contains = Validators.containsNormalized(llmName, apiName)
                
                if !(contains || sim >= policy.nameSimilarityThreshold) {
                    return .warning("Название слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                }
                return nil
                
            case .ceoFullName:
                guard let llmCEO = state.value else { return nil }
                if let apiCEO = companyInfo.management?.name, !apiCEO.isEmpty {
                    let sim = Validators.jaccardSimilarity(llmCEO, apiCEO)
                    let contains = Validators.containsNormalized(llmCEO, apiCEO)
                    if !(contains || sim >= 0.70) {
                        return .warning("ФИО руководителя слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                    }
                }
                return nil
                
                // сейчас не кросс-валидируем
            case .legalForm, .ceoShortenName, .email, .phone:
                return nil
                // TODO: address
            case .address:
                guard let llmAddress = state.value else { return nil }
                
                if let apiAddress = companyInfo.address?.value, !apiAddress.isEmpty {
                    let sim = Validators.jaccardSimilarity(llmAddress, apiAddress)
                    let contains = Validators.containsNormalized(llmAddress, apiAddress)
                    if !(contains || sim >= 0.70) {
                        return .warning("Адрес слабо похож на DaData \(apiAddress) (sim=\(String(format: "%.2f", sim))).")
                    }
                }
                
                return nil
        }
    }
}
