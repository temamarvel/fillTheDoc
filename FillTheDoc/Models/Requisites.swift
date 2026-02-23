//
//  Requisites.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 20.02.2026.
//


public struct Requisites: Decodable, LLMExtractable {
    let companyName: String?
    let legalForm: String?
    let ceoFullName: String?
    let ceoShortenName: String?
    let ogrn: String?
    let inn: String?
    let kpp: String?
    let email: String?
    
    enum CodingKeys: String, CodingKey, CaseIterable {
        case companyName = "company_name"
        case legalForm = "legal_form"
        case ceoFullName = "ceo_full_name"
        case ceoShortenName = "ceo_shorten_name"
        case ogrn
        case inn
        case kpp
        case email
    }
}
