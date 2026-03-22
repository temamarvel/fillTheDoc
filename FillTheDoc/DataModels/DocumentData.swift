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
    
    func getDate() -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "«dd» MMMM yyyy 'г.'"
        
        return formatter.string(for: Date.now)
    }
    
    func asDictionary() -> [String: String] {
        
        var dict = companyDetails?.asDictionary() as? [String: String] ?? [:]
        
        if let fee = fee {
            dict["fee"] = fee
        }
        
        if let minFee = minFee {
            dict["min_fee"] = minFee
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "«dd» MMMM yyyy 'г.'"
        
        dict["date"] = getDate()
        
        dict["rules"] = companyDetails?.legalForm == .ip ? "Листа  записи в Едином государственном реестре индивидуальных предпринимателей (ЕГРИП)" : "Устава"
        
        return dict
    }
}
