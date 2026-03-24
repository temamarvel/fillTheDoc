import Foundation
public enum LegalForm: String, CaseIterable, Sendable {
    case ooo
    case zao
    case ao
    case ip
    case pao
}

public extension LegalForm {
    var shortName: String {
        switch self {
            case .ooo: return "ООО"
            case .zao: return "ЗАО"
            case .ao: return "АО"
            case .ip: return "ИП"
            case .pao: return "ПАО"
        }
    }
    
    var fullName: String {
        switch self {
            case .ooo:
                return "Общество с ограниченной ответственностью"
            case .zao:
                return "Закрытое акционерное общество"
            case .ao:
                return "Акционерное общество"
            case .ip:
                return "Индивидуальный предприниматель"
            case .pao:
                return "Публичное акционерное общество"
        }
    }
    
    static func parse(_ raw: String) -> LegalForm? {
        let normalized = normalize(raw)
        
        for form in Self.allCases {
            let aliases = aliases(for: form)
            if aliases.contains(normalized) {
                return form
            }
        }
        
        return nil
    }
}

private extension LegalForm {
    static func aliases(for form: LegalForm) -> Set<String> {
        switch form {
            case .ooo:
                return [
                    "ооо",
                    "ooo",
                    "общество с ограниченной ответственностью"
                ]
                
            case .zao:
                return [
                    "зао",
                    "zao",
                    "закрытое акционерное общество"
                ]
                
            case .ao:
                return [
                    "ао",
                    "ao",
                    "акционерное общество"
                ]
                
            case .ip:
                return [
                    "ип",
                    "ip",
                    "индивидуальный предприниматель"
                ]
                
            case .pao:
                return [
                    "пао",
                    "pao",
                    "публичное акционерное общество"
                ]
        }
    }
    
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "«", with: "")
            .replacingOccurrences(of: "»", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "  ", with: " ")
    }
}

extension LegalForm: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        
        guard let value = Self.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported legal form: \(raw)"
            )
        }
        
        self = value
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(shortName)
    }
}

public struct CompanyDetails: Decodable, LLMExtractable, Sendable {
    public let companyName: String?
    public let legalForm: LegalForm?
    public let ceoFullName: String?
    public let ceoShortenName: String?
    public let ogrn: String?
    public let inn: String?
    public let kpp: String?
    public let email: String?
    public let address: String?
    public let phone: String?
    
    public init(
        companyName: String?,
        legalForm: LegalForm?,
        ceoFullName: String?,
        ceoShortenName: String?,
        ogrn: String?,
        inn: String?,
        kpp: String?,
        email: String?,
        address: String?,
        phone: String?
    ) {
        self.companyName = companyName
        self.legalForm = legalForm
        self.ceoFullName = ceoFullName
        self.ceoShortenName = ceoShortenName
        self.ogrn = ogrn
        self.inn = inn
        self.kpp = kpp
        self.email = email
        self.address = address
        self.phone = phone
    }
    
    public enum CodingKeys: String, CodingKey, CaseIterable {
        case companyName = "company_name"
        case legalForm = "legal_form"
        case ceoFullName = "ceo_full_name"
        case ceoShortenName = "ceo_shorten_name"
        case ogrn
        case inn
        case kpp
        case email
        case address
        case phone
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        self.ceoFullName = try container.decodeIfPresent(String.self, forKey: .ceoFullName)
        self.ceoShortenName = try container.decodeIfPresent(String.self, forKey: .ceoShortenName)
        self.ogrn = try container.decodeIfPresent(String.self, forKey: .ogrn)
        self.inn = try container.decodeIfPresent(String.self, forKey: .inn)
        self.kpp = try container.decodeIfPresent(String.self, forKey: .kpp)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.address = try container.decodeIfPresent(String.self, forKey: .address)
        self.phone = try container.decodeIfPresent(String.self, forKey: .phone)
        
        if let rawLegalForm = try container.decodeIfPresent(String.self, forKey: .legalForm) {
            self.legalForm = LegalForm.parse(rawLegalForm)
        } else {
            self.legalForm = nil
        }
    }
}

public extension CompanyDetails {
    var fullCompanyName: String {
        [
            legalForm?.shortName,
            companyName?.trimmedNilIfEmpty
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }
    
    var fullCompanyNameExpanded: String {
        [
            legalForm?.fullName,
            companyName?.trimmedNilIfEmpty
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }
    
    subscript(key: CodingKeys) -> String? {
        switch key {
            case .companyName:
                return companyName
            case .legalForm:
                return legalForm?.shortName
            case .ceoFullName:
                return ceoFullName
            case .ceoShortenName:
                return ceoShortenName
            case .ogrn:
                return ogrn
            case .inn:
                return inn
            case .kpp:
                return kpp
            case .email:
                return email
            case .address:
                return address
            case .phone:
                return phone
        }
    }
    
    func value(for key: CodingKeys, expandedLegalForm: Bool) -> String? {
        switch key {
            case .companyName:
                return companyName
            case .legalForm:
                return expandedLegalForm ? legalForm?.fullName : legalForm?.shortName
            case .ceoFullName:
                return ceoFullName
            case .ceoShortenName:
                return ceoShortenName
            case .ogrn:
                return ogrn
            case .inn:
                return inn
            case .kpp:
                return kpp
            case .email:
                return email
            case .address:
                return address
            case .phone:
                return phone
        }
    }
    
    func asDictionary(expandedLegalForm: Bool = false) -> [String: String] {
        var result: [String: String] = [:]
        
        for key in CodingKeys.allCases {
            if let value = value(for: key, expandedLegalForm: expandedLegalForm)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                result[key.rawValue] = value
            }
        }
        
        return result
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
