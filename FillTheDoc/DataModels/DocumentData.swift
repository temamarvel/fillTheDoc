//
//  DocumentData.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 18.03.2026.
//

public struct DocumentData: Codable {
    let discount: String?
    let minDiscount: String?
    let companyDetails: CompanyDetails?
    
    func asDictionary() -> [String: String] {
        
        var dict = companyDetails?.asDictionary() as? [String: String] ?? [:]
        
        if let discount = discount {
            dict["discount"] = discount
        }
        
        if let minDiscount = minDiscount {
            dict["min_discount"] = minDiscount
        }
        
        return dict
    }
}
