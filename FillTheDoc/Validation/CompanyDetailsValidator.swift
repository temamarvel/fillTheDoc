import Foundation
import DaDataAPIClient

//public struct FieldMessage{
//    
//}

public struct FieldState: Sendable, Equatable {
    var value : String?
    var message: CompanyDetailsValidator.FieldMessage?
    var isValid: Bool {
        message == nil
    }
}

//struct CompanyInfoCache: Sendable {
//    public typealias Key = CompanyDetails.CodingKeys
//    
//    private var storage: [Key: DaDataCompanyInfo] = [:]
//    
//    func value(for key: LookupKey) -> CompanyInfo? {
//        storage[key]
//    }
//    
//    mutating func insert(_ companyInfo: CompanyInfo) {
//        if let inn = normalizedDigits(companyInfo.inn) {
//            storage[.inn(inn)] = companyInfo
//        }
//        
//        if let ogrn = normalizedDigits(companyInfo.ogrn) {
//            storage[.ogrn(ogrn)] = companyInfo
//        }
//    }
//}

public final class CompanyDetailsValidator: Sendable {
    
    public typealias Key = CompanyDetails.CodingKeys
    
    // MARK: - Policy
    
    public struct Policy: Sendable {
        public var nameSimilarityThreshold: Double   // Jaccard
        public var addressSimilarityThreshold: Double
        
        /// Merge policy
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
    
    public enum Severity: Int, Sendable, Comparable {
        case warning = 0
        case error = 1
        
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    public struct FieldMessage: Sendable, Equatable {
        public var severity: Severity? {
            if error != nil {
                return .error
            }
            if warning != nil {
                return .warning
            }
            return nil
        }
        public var text: String? { error ?? warning }
        public var error: String?
        public var warning: String?
        
//        public init(_ severity: Severity, _ text: String) {
//            self.severity = severity
//            self.text = text
//        }
    }
    
    public struct RemoteState: Sendable {
        public var companyInfo: DaDataCompanyInfo?
        public init(companyInfo: DaDataCompanyInfo? = nil) { self.companyInfo = companyInfo }
    }
    
    private let policy: Policy
    private let dadataClient: DaDataClient
    private var cache: [String: DaDataCompanyInfo] //TODO maybe not good to use String as key
    
    public init(dadataClient: DaDataClient, policy: Policy = .init()) {
        self.policy = policy
        self.dadataClient = dadataClient
        self.cache = [:]
    }
    
    // MARK: - Local validation (no network)
    
    public func validateField(for fieldKey: Key, value: String) -> FieldMessage? {
        guard let validator = CompanyDetails.fieldMetadata[fieldKey]?.validator else {
            return nil
        }
        
        let validationResult = validator(value)
        
        //TODO FieldMessage same logic as ValidationResult
        return validationResult.state == .pass ? nil : FieldMessage(error: validationResult.text, warning: nil)
    }

    public func validateOnFocusLost(fields: [Key: FieldState]) async -> [Key: FieldState] {
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
            let msg = crossValidateField(fieldKey: key, state: state, companyInfo: dadataCompanyInfo)
            resultFields[key]?.message = msg
        }
        
        return resultFields
    }
    
    
    
    
    
    private func crossValidateField(fieldKey: Key, state: FieldState, companyInfo: DaDataCompanyInfo) -> FieldMessage? {
        switch fieldKey {
            case .inn:
                guard let llmINN = state.value else { return nil }
                let apiINN = companyInfo.inn.map{FormatValidators.digitsOnly($0)}
                if let apiINN, apiINN != FormatValidators.digitsOnly(llmINN) {
                    return FieldMessage(error: nil, warning: "ИНН не совпадает с DaData.")
                }
                return nil
                
            case .kpp:
                guard let llmKPP = state.value else { return nil }
                if let apiKPP = companyInfo.kpp.map({FormatValidators.digitsOnly($0)}),
                   apiKPP != FormatValidators.digitsOnly(llmKPP) {
                    return FieldMessage(error: nil, warning: "КПП не совпадает с DaData.")
                }
                return nil
                
            case .ogrn:
                guard let llmOGRN = state.value else { return nil }
                if let apiOGRN = companyInfo.ogrn.map({FormatValidators.digitsOnly($0)}),
                   apiOGRN != FormatValidators.digitsOnly(llmOGRN) {
                    return FieldMessage(error: nil, warning: "ОГРН/ОГРНИП не совпадает с DaData.")
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
                
                let sim = TextNormalization.jaccard(llmName, apiName)
                let contains = TextNormalization.containsNormalized(llmName, apiName)
                
                if !(contains || sim >= policy.nameSimilarityThreshold) {
                    return FieldMessage(error: nil, warning: "Название слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                }
                return nil
                
            case .ceoFullName:
                guard let llmCEO = state.value else { return nil }
                if let apiCEO = companyInfo.management?.name, !apiCEO.isEmpty {
                    let sim = TextNormalization.jaccard(llmCEO, apiCEO)
                    let contains = TextNormalization.containsNormalized(llmCEO, apiCEO)
                    if !(contains || sim >= 0.70) {
                        return FieldMessage(error: nil, warning: "ФИО руководителя слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                    }
                }
                return nil
                
                // сейчас не кросс-валидируем
            case .legalForm, .ceoShortenName, .email:
                return nil
        }
    }
    
    
    
    
    
    
    // MARK: - Remote validation on focus lost (may call DaData)
    
    /// Главный метод под твою UX-логику: blur конкретного поля.
    ///
    /// Возвращает:
    /// - updated RemoteState (кэш DaDataParty)
    /// - merged messages (local + remote) по понятной политике
//    public func validateOnFocusLost(
//        changed field: Key,
//        all rawAll: [Key: String],
//        remote: RemoteState,
//        dadata: DaDataClient
//    ) async -> (RemoteState, [Key: FieldMessage]) {
//        
//        //TODO refactoring remote validation
//        
//        
//        // 0) Нормализация входа (trim)
//        let all = normalizedAll(rawAll)
//        
//        // 1) Local messages (только для changed поля — обычно этого достаточно на blur)
//        //    Если хочешь — можешь заменить на validateLocalAll(all:) для “всей формы”.
//        let localChanged: [Key: FieldMessage] = {
//            if let msg = validateField(for: field, value: all[field] ?? "") {
//                return [field: msg]
//            }
//            return [:]
//        }()
//        
//        // 2) Решаем: нужен ли запрос в DaData?
//        //    - Если blur был на INN/OGRN: и значение валидное → делаем fetch
//        //    - Иначе: если party уже есть в remote → не дергаем сеть, просто cross-validate по кешу
//        //    - Иначе: ничего не делаем (remote пуст)
//        let query: Query?
//        switch field {
//            case .ogrn:
//                if let ogrn = present(all[.ogrn]), FormatValidators.isValidOGRN(ogrn).state == .pass {
//                    query = .ogrn(FormatValidators.digitsOnly(ogrn))
//                } else {
//                    query = nil
//                }
//            case .inn:
//                if let inn = present(all[.inn]), FormatValidators.isValidINN(inn).state == .pass {
//                    query = .inn(FormatValidators.digitsOnly(inn))
//                } else {
//                    query = nil
//                }
//            default:
//                query = nil
//        }
//        
//        var newRemote = remote
//        var remoteMessages: [Key: FieldMessage] = [:]
//        
//        if let query {
//            // 3) fetch по идентификатору, который пользователь “подтвердил” уходом с поля
//            do {
//                let companyInfo = try await fetchCompanyInfo(dadata: dadata, query: query)
//                newRemote.companyInfo = companyInfo
//            } catch {
//                remoteMessages[query.field] = .init(.warning, "Не удалось проверить по DaData: \(error.localizedDescription)")
//                return (newRemote, merge(local: localChanged, remote: remoteMessages))
//            }
//            
//            guard let companyInfo = newRemote.companyInfo else {
//                remoteMessages[query.field] = .init(.warning, "DaData не вернула организацию по указанному идентификатору.")
//                return (newRemote, merge(local: localChanged, remote: remoteMessages))
//            }
//            
//            // 4) cross-validate ВСЕ релевантные поля по свежему party
//            remoteMessages = crossValidateAll(all: all, companyInfo: companyInfo)
//            return (newRemote, merge(local: localChanged, remote: remoteMessages))
//        } else if let companyInfo = newRemote.companyInfo {
//            // 3b) сеть не дергаем, но можем подсветить расхождения относительно закешированного party
//            remoteMessages = crossValidateAll(all: all, companyInfo: companyInfo)
//            return (newRemote, merge(local: localChanged, remote: remoteMessages))
//        } else {
//            // 3c) нет валидного запроса и нет кеша — только local
//            //      ВАЖНО: тут специально не добавляю “root error” на INN/OGRN,
//            //      потому что это blur ЛЮБОГО поля, и твой UX не должен “ругаться”
//            //      если пользователь еще не дошел до INN/OGRN.
//            return (newRemote, localChanged)
//        }
//    }
    
    /// Backward-compatible overload (если пока не хочешь прокидывать changed-key из UI)
    /// Логика как у тебя была: OGRN > INN, иначе возвращаем ошибку на оба.
//    public func validateOnFocusLost(
//        all rawAll: [Key: String],
//        remote: RemoteState,
//        dadata: DaDataClient
//    ) async -> (RemoteState, [Key: FieldMessage]) {
//        
//        let all = normalizedAll(rawAll)
//        
//        let ogrnRaw = present(all[.ogrn])
//        let innRaw  = present(all[.inn])
//        
//        let query: Query?
//        if let ogrnRaw, FormatValidators.isValidOGRN(ogrnRaw).state == .pass {
//            query = .ogrn(FormatValidators.digitsOnly(ogrnRaw))
//        } else if let innRaw, FormatValidators.isValidINN(innRaw).state == .pass {
//            query = .inn(FormatValidators.digitsOnly(innRaw))
//        } else {
//            // Твой старый “root error” режим:
//            var msgs: [Key: FieldMessage] = [:]
//            
//            if ogrnRaw?.isEmpty == false, !(FormatValidators.isValidOGRN(ogrnRaw!).state == .pass) {
//                msgs[.ogrn] = .init(.warning, "ОГРН указан, но формат/контрольная сумма некорректны.")
//            }
//            if innRaw?.isEmpty == false, !(FormatValidators.isValidINN(innRaw!).state == .pass) {
//                msgs[.inn] = .init(.warning, "ИНН указан, но формат/контрольная сумма некорректны.")
//            }
//            
//            let root = FieldMessage(.error, "Для проверки по DaData укажите корректный ОГРН или ИНН.")
//            msgs[.ogrn] = msgs[.ogrn] ?? root
//            msgs[.inn]  = msgs[.inn]  ?? root
//            
//            return (remote, merge(local: [:], remote: msgs))
//        }
//        
//        guard let query else { return (remote, [:]) }
//        
//        var newRemote = remote
//        do {
//            let companyInfo = try await fetchCompanyInfo(dadata: dadata, query: query)
//            newRemote.companyInfo = companyInfo
//        } catch {
//            return (newRemote, [
//                query.field: .init(.warning, "Не удалось проверить по DaData: \(error.localizedDescription)")
//            ])
//        }
//        
//        guard let companyInfo = newRemote.companyInfo else {
//            return (newRemote, [
//                query.field: .init(.warning, "DaData не вернула организацию по указанному идентификатору.")
//            ])
//        }
//        
//        let remoteMessages = crossValidateAll(all: all, companyInfo: companyInfo)
//        return (newRemote, remoteMessages)
//    }
    
    // MARK: - Merge policy: local + remote
    
    /// Merge правило:
    /// - если сообщение только одно → берем его
    /// - если оба есть:
    ///   - берем более “сильное” по severity (error > warning)
    ///   - если severity одинаковая:
    ///       - combineTextsOnTie=true → склеиваем тексты (local + remote)
    ///       - иначе: preferRemoteOnTie ? remote : local
//    private func merge(local: [Key: FieldMessage], remote: [Key: FieldMessage]) -> [Key: FieldMessage] {
//        var result: [Key: FieldMessage] = local
//        
//        for (k, r) in remote {
//            guard let l = result[k] else {
//                result[k] = r
//                continue
//            }
//            
//            if r.severity > l.severity {
//                result[k] = r
//            } else if r.severity < l.severity {
//                result[k] = l
//            } else {
//                // tie by severity
//                if policy.combineTextsOnTie {
//                    let combined = combineTexts(local: l.text, remote: r.text)
//                    // severity одинаковая — оставляем ее
//                    result[k] = .init(l.severity, combined)
//                } else {
//                    result[k] = policy.preferRemoteOnTie ? r : l
//                }
//            }
//        }
//        
//        return result
//    }
    
//    private func combineTexts(local: String, remote: String) -> String {
//        let l = local.trimmingCharacters(in: .whitespacesAndNewlines)
//        let r = remote.trimmingCharacters(in: .whitespacesAndNewlines)
//        if l.isEmpty { return r }
//        if r.isEmpty { return l }
//        if l == r { return l }
//        // аккуратно, без “простыни”
//        return "\(l)\n\(r)"
//    }
    
    // MARK: - Cross validation with DaData
    
    private func crossValidateAll(all: [Key: String], companyInfo: DaDataCompanyInfo) -> [Key: FieldMessage] {
        // Какие поля реально сверяем с DaData
        let keysToCheck: [Key] = [
            .ogrn, .inn, .kpp, .companyName, .ceoFullName
            // TODO: address — когда добавишь в CompanyDetails
        ]
        
        var result: [Key: FieldMessage] = [:]
        
        for key in keysToCheck {
            if let msg = crossValidateField(field: key, all: all, companyInfo: companyInfo) {
                result[key] = msg
            }
        }
        
        // Дополнительно: ACTIVE статус — привяжем к companyName (или сделай отдельный “form-level key”)
        if let status = companyInfo.state?.status, !status.isEmpty, status.uppercased() != "ACTIVE" {
            result[.companyName] = result[.companyName]
            ?? FieldMessage(error: nil, warning: "Статус организации не ACTIVE (DaData: \(status)).")
        }
        
        return result
    }
    
    private func crossValidateField(field: Key, all: [Key: String], companyInfo: DaDataCompanyInfo) -> FieldMessage? {
        switch field {
            case .inn:
                guard let llmINN = present(all[.inn]) else { return nil }
                let apiINN = companyInfo.inn.map{FormatValidators.digitsOnly($0)}
                if let apiINN, apiINN != FormatValidators.digitsOnly(llmINN) {
                    return FieldMessage(error: nil, warning: "ИНН не совпадает с DaData.")
                }
                return nil
                
            case .kpp:
                guard let llmKPP = present(all[.kpp]) else { return nil }
                if let apiKPP = companyInfo.kpp.map({FormatValidators.digitsOnly($0)}),
                   apiKPP != FormatValidators.digitsOnly(llmKPP) {
                    return FieldMessage(error: nil, warning: "КПП не совпадает с DaData.")
                }
                return nil
                
            case .ogrn:
                guard let llmOGRN = present(all[.ogrn]) else { return nil }
                if let apiOGRN = companyInfo.ogrn.map({FormatValidators.digitsOnly($0)}),
                   apiOGRN != FormatValidators.digitsOnly(llmOGRN) {
                    return FieldMessage(error: nil, warning: "ОГРН/ОГРНИП не совпадает с DaData.")
                }
                return nil
                
            case .companyName:
                guard let llmName = present(all[.companyName]) else { return nil }
                
                let apiName =
                companyInfo.name?.fullWithOpf
                ?? companyInfo.name?.shortWithOpf
                ?? companyInfo.name?.full
                ?? companyInfo.name?.short
                
                guard let apiName else { return nil }
                
                let sim = TextNormalization.jaccard(llmName, apiName)
                let contains = TextNormalization.containsNormalized(llmName, apiName)
                
                if !(contains || sim >= policy.nameSimilarityThreshold) {
                    return FieldMessage(error: nil, warning: "Название слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                }
                return nil
                
            case .ceoFullName:
                guard let llmCEO = present(all[.ceoFullName]) else { return nil }
                if let apiCEO = companyInfo.management?.name, !apiCEO.isEmpty {
                    let sim = TextNormalization.jaccard(llmCEO, apiCEO)
                    let contains = TextNormalization.containsNormalized(llmCEO, apiCEO)
                    if !(contains || sim >= 0.70) {
                        return FieldMessage(error: nil, warning: "ФИО руководителя слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                    }
                }
                return nil
                
                // сейчас не кросс-валидируем
            case .legalForm, .ceoShortenName, .email:
                return nil
        }
    }
    
    // MARK: - DaData query logic
    
    private enum Query {
        case ogrn(String)
        case inn(String)
        
        var field: Key {
            switch self {
                case .ogrn: return .ogrn
                case .inn:  return .inn
            }
        }
    }
    
    private func fetchCompanyInfo(dadata: DaDataClient, query: Query) async throws -> DaDataCompanyInfo? {
        switch query {
            case .ogrn(let ogrn):
                return try await dadata.fetchCompanyInfoFirts(innOrOgrn: ogrn)?.data
            case .inn(let inn):
                return try await dadata.fetchCompanyInfoFirts(innOrOgrn: inn)?.data
        }
    }
    
    // MARK: - Helpers
    
    private func normalizedAll(_ all: [Key: String]) -> [Key: String] {
        var res: [Key: String] = [:]
        res.reserveCapacity(all.count)
        for (k, v) in all {
            res[k] = v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return res
    }
    
    private func present(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
