//
//  DocumentData.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 18.03.2026.
//

import Foundation

public struct DocumentData: Codable {
    let fee: String?
    let minFee: String?
    let companyDetails: CompanyDetails?
    
    var date: String {
        Self.dateFormatter.string(from: .now)
    }
    
    var ceoRole: String {
        companyDetails?.legalForm == .ip ? "Индивидуальный предприниматель" : "Генеральный директор"
    }
    
    func asDictionary() -> [String: String] {
        var dict = companyDetails?.asDictionary() ?? [:]
        
        if let fee = fee {
            dict["fee"] = fee
        }
        
        if let minFee = minFee {
            dict["min_fee"] = minFee
        }
        
        dict["date"] = date
        dict["ceo_role"] = ceoRole
        dict["rules"] = companyDetails?.legalForm == .ip ? "Листа  записи в Едином государственном реестре индивидуальных предпринимателей (ЕГРИП)" : "Устава"
        
        return dict
    }
}

private extension DocumentData {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "«dd» MMMM yyyy 'г.'"
        return formatter
    }()
}
