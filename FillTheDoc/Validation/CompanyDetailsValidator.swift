import Foundation
import DaDataAPIClient

public struct CompanyDetailsValidator: Sendable {
    
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
        public var severity: Severity
        public var text: String
        
        public init(_ severity: Severity, _ text: String) {
            self.severity = severity
            self.text = text
        }
    }
    
    public struct RemoteState: Sendable {
        public var companyInfo: DaDataCompanyInfo?
        public init(companyInfo: DaDataCompanyInfo? = nil) { self.companyInfo = companyInfo }
    }
    
    private let policy: Policy
    
    public init(policy: Policy = .init()) {
        self.policy = policy
    }
    
    // MARK: - Local validation (no network)
    
    public func validateLocal(fieldKey: Key, value: String, all: [Key: String]) -> FieldMessage? {
        //let value = present(raw)
        
        
        //TODO: think about validators funcs signatures
        if (CompanyDetails.fieldMetadata[fieldKey]?.validator ?? { _ in false })(value){
                    return .init(.error, "metaError") //TODO
                }
//        switch field {
//            case .inn:
//                guard let value else { return nil }
//                if !FormatValidators.isValidINN(value) {
//                    return .init(.error, "ИНН имеет неверный формат или контрольную сумму.")
//                }
//                return nil
//                
//            case .kpp:
//                guard let value else { return nil }
//                if !FormatValidators.isValidKPP(value) {
//                    return .init(.warning, "КПП выглядит некорректно (ожидается 9 цифр).")
//                }
//                return nil
//                
//            case .ogrn:
//                guard let value else { return nil }
//                if !FormatValidators.isValidOGRN(value) {
//                    return .init(.warning, "ОГРН/ОГРНИП выглядит некорректно (контрольная сумма/длина).")
//                }
//                return nil
//                
//            case .companyName:
//                guard let value else { return nil }
//                if value.count < 3 { return .init(.warning, "Название слишком короткое.") }
//                return nil
//                
//            case .ceoFullName:
//                guard let value else { return nil }
//                if value.count < 5 { return .init(.warning, "ФИО руководителя выглядит слишком коротким.") }
//                return nil
//                
//                // Эти поля локально не валидируем (или валидируй тут, если надо)
//            case .legalForm, .ceoShortenName, .email:
//                return nil
//        }
    }
    
    /// Удобный хелпер: прогнать local-валидацию по всем полям и вернуть словарь сообщений.
    public func validateLocalAll(all: [Key: String]) -> [Key: FieldMessage] {
        var result: [Key: FieldMessage] = [:]
        for key in Key.allCases {
            if let msg = validateLocal(fieldKey: key, value: all[key] ?? "", all: all) {
                result[key] = msg
            }
        }
        return result
    }
    
    // MARK: - Remote validation on focus lost (may call DaData)
    
    /// Главный метод под твою UX-логику: blur конкретного поля.
    ///
    /// Возвращает:
    /// - updated RemoteState (кэш DaDataParty)
    /// - merged messages (local + remote) по понятной политике
    public func validateOnFocusLost(
        changed field: Key,
        all rawAll: [Key: String],
        remote: RemoteState,
        dadata: DaDataClient
    ) async -> (RemoteState, [Key: FieldMessage]) {
        
        // 0) Нормализация входа (trim)
        let all = normalizedAll(rawAll)
        
        // 1) Local messages (только для changed поля — обычно этого достаточно на blur)
        //    Если хочешь — можешь заменить на validateLocalAll(all:) для “всей формы”.
        let localChanged: [Key: FieldMessage] = {
            if let msg = validateLocal(fieldKey: field, value: all[field] ?? "", all: all) {
                return [field: msg]
            }
            return [:]
        }()
        
        // 2) Решаем: нужен ли запрос в DaData?
        //    - Если blur был на INN/OGRN: и значение валидное → делаем fetch
        //    - Иначе: если party уже есть в remote → не дергаем сеть, просто cross-validate по кешу
        //    - Иначе: ничего не делаем (remote пуст)
        let query: Query?
        switch field {
            case .ogrn:
                if let ogrn = present(all[.ogrn]), FormatValidators.isValidOGRN(ogrn) {
                    query = .ogrn(FormatValidators.digitsOnly(ogrn))
                } else {
                    query = nil
                }
            case .inn:
                if let inn = present(all[.inn]), FormatValidators.isValidINN(inn) {
                    query = .inn(FormatValidators.digitsOnly(inn))
                } else {
                    query = nil
                }
            default:
                query = nil
        }
        
        var newRemote = remote
        var remoteMessages: [Key: FieldMessage] = [:]
        
        if let query {
            // 3) fetch по идентификатору, который пользователь “подтвердил” уходом с поля
            do {
                let companyInfo = try await fetchCompanyInfo(dadata: dadata, query: query)
                newRemote.companyInfo = companyInfo
            } catch {
                remoteMessages[query.field] = .init(.warning, "Не удалось проверить по DaData: \(error.localizedDescription)")
                return (newRemote, merge(local: localChanged, remote: remoteMessages))
            }
            
            guard let companyInfo = newRemote.companyInfo else {
                remoteMessages[query.field] = .init(.warning, "DaData не вернула организацию по указанному идентификатору.")
                return (newRemote, merge(local: localChanged, remote: remoteMessages))
            }
            
            // 4) cross-validate ВСЕ релевантные поля по свежему party
            remoteMessages = crossValidateAll(all: all, companyInfo: companyInfo)
            return (newRemote, merge(local: localChanged, remote: remoteMessages))
        } else if let companyInfo = newRemote.companyInfo {
            // 3b) сеть не дергаем, но можем подсветить расхождения относительно закешированного party
            remoteMessages = crossValidateAll(all: all, companyInfo: companyInfo)
            return (newRemote, merge(local: localChanged, remote: remoteMessages))
        } else {
            // 3c) нет валидного запроса и нет кеша — только local
            //      ВАЖНО: тут специально не добавляю “root error” на INN/OGRN,
            //      потому что это blur ЛЮБОГО поля, и твой UX не должен “ругаться”
            //      если пользователь еще не дошел до INN/OGRN.
            return (newRemote, localChanged)
        }
    }
    
    /// Backward-compatible overload (если пока не хочешь прокидывать changed-key из UI)
    /// Логика как у тебя была: OGRN > INN, иначе возвращаем ошибку на оба.
    public func validateOnFocusLost(
        all rawAll: [Key: String],
        remote: RemoteState,
        dadata: DaDataClient
    ) async -> (RemoteState, [Key: FieldMessage]) {
        
        let all = normalizedAll(rawAll)
        
        let ogrnRaw = present(all[.ogrn])
        let innRaw  = present(all[.inn])
        
        let query: Query?
        if let ogrnRaw, FormatValidators.isValidOGRN(ogrnRaw) {
            query = .ogrn(FormatValidators.digitsOnly(ogrnRaw))
        } else if let innRaw, FormatValidators.isValidINN(innRaw) {
            query = .inn(FormatValidators.digitsOnly(innRaw))
        } else {
            // Твой старый “root error” режим:
            var msgs: [Key: FieldMessage] = [:]
            
            if ogrnRaw?.isEmpty == false, !FormatValidators.isValidOGRN(ogrnRaw!) {
                msgs[.ogrn] = .init(.warning, "ОГРН указан, но формат/контрольная сумма некорректны.")
            }
            if innRaw?.isEmpty == false, !FormatValidators.isValidINN(innRaw!) {
                msgs[.inn] = .init(.warning, "ИНН указан, но формат/контрольная сумма некорректны.")
            }
            
            let root = FieldMessage(.error, "Для проверки по DaData укажите корректный ОГРН или ИНН.")
            msgs[.ogrn] = msgs[.ogrn] ?? root
            msgs[.inn]  = msgs[.inn]  ?? root
            
            return (remote, merge(local: [:], remote: msgs))
        }
        
        guard let query else { return (remote, [:]) }
        
        var newRemote = remote
        do {
            let companyInfo = try await fetchCompanyInfo(dadata: dadata, query: query)
            newRemote.companyInfo = companyInfo
        } catch {
            return (newRemote, [
                query.field: .init(.warning, "Не удалось проверить по DaData: \(error.localizedDescription)")
            ])
        }
        
        guard let companyInfo = newRemote.companyInfo else {
            return (newRemote, [
                query.field: .init(.warning, "DaData не вернула организацию по указанному идентификатору.")
            ])
        }
        
        let remoteMessages = crossValidateAll(all: all, companyInfo: companyInfo)
        return (newRemote, remoteMessages)
    }
    
    // MARK: - Merge policy: local + remote
    
    /// Merge правило:
    /// - если сообщение только одно → берем его
    /// - если оба есть:
    ///   - берем более “сильное” по severity (error > warning)
    ///   - если severity одинаковая:
    ///       - combineTextsOnTie=true → склеиваем тексты (local + remote)
    ///       - иначе: preferRemoteOnTie ? remote : local
    private func merge(local: [Key: FieldMessage], remote: [Key: FieldMessage]) -> [Key: FieldMessage] {
        var result: [Key: FieldMessage] = local
        
        for (k, r) in remote {
            guard let l = result[k] else {
                result[k] = r
                continue
            }
            
            if r.severity > l.severity {
                result[k] = r
            } else if r.severity < l.severity {
                result[k] = l
            } else {
                // tie by severity
                if policy.combineTextsOnTie {
                    let combined = combineTexts(local: l.text, remote: r.text)
                    // severity одинаковая — оставляем ее
                    result[k] = .init(l.severity, combined)
                } else {
                    result[k] = policy.preferRemoteOnTie ? r : l
                }
            }
        }
        
        return result
    }
    
    private func combineTexts(local: String, remote: String) -> String {
        let l = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.isEmpty { return r }
        if r.isEmpty { return l }
        if l == r { return l }
        // аккуратно, без “простыни”
        return "\(l)\n\(r)"
    }
    
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
            ?? .init(.warning, "Статус организации не ACTIVE (DaData: \(status)).")
        }
        
        return result
    }
    
    private func crossValidateField(field: Key, all: [Key: String], companyInfo: DaDataCompanyInfo) -> FieldMessage? {
        switch field {
                
            case .inn:
                guard let llmINN = present(all[.inn]) else { return nil }
                let apiINN = companyInfo.inn.map{FormatValidators.digitsOnly($0)}
                if let apiINN, apiINN != FormatValidators.digitsOnly(llmINN) {
                    return .init(.error, "ИНН не совпадает с DaData.")
                }
                return nil
                
            case .kpp:
                guard let llmKPP = present(all[.kpp]) else { return nil }
                if let apiKPP = companyInfo.kpp.map({FormatValidators.digitsOnly($0)}),
                   apiKPP != FormatValidators.digitsOnly(llmKPP) {
                    return .init(.warning, "КПП не совпадает с DaData.")
                }
                return nil
                
            case .ogrn:
                guard let llmOGRN = present(all[.ogrn]) else { return nil }
                if let apiOGRN = companyInfo.ogrn.map({FormatValidators.digitsOnly($0)}),
                   apiOGRN != FormatValidators.digitsOnly(llmOGRN) {
                    return .init(.warning, "ОГРН/ОГРНИП не совпадает с DaData.")
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
                    return .init(.warning, "Название слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
                }
                return nil
                
            case .ceoFullName:
                guard let llmCEO = present(all[.ceoFullName]) else { return nil }
                if let apiCEO = companyInfo.management?.name, !apiCEO.isEmpty {
                    let sim = TextNormalization.jaccard(llmCEO, apiCEO)
                    let contains = TextNormalization.containsNormalized(llmCEO, apiCEO)
                    if !(contains || sim >= 0.70) {
                        return .init(.warning, "ФИО руководителя слабо похоже на DaData (sim=\(String(format: "%.2f", sim))).")
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
