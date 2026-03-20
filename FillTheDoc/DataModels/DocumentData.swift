//
//  DocumentData.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 18.03.2026.
//

import Foundation

public struct DocumentData: Codable {
    let discount: String?
    let minDiscount: String?
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
        
        if let discount = discount {
            dict["discount"] = discount
        }
        
        if let minDiscount = minDiscount {
            dict["min_discount"] = minDiscount
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "«dd» MMMM yyyy 'г.'"
        
        dict["date"] = getDate()
        
        return dict
    }
}
