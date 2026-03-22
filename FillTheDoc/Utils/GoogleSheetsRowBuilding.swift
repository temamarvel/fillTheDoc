//
//  GoogleSheetsRowBuilding.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 19.03.2026.
//


import Foundation
import AppKit

protocol GoogleSheetsRowBuilding {
    func makeRow(from data: DocumentData) -> String
    func copyToPasteboard(_ row: String)
}

final class GoogleSheetsRowBuilder: GoogleSheetsRowBuilding {
    
    func makeRow(from data: DocumentData) -> String {
        let values: [String] = [
            sanitize(data.companyDetails?.fullCompanyName),   // Наименование
            sanitize(data.companyDetails?.ceoFullName),   // ФИО
            sanitize(data.companyDetails?.inn),           // ИНН
            sanitize(data.companyDetails?.phone),         // Телефон компании
            sanitize(data.companyDetails?.email),         // E-mail Компании
            "",                                           // Номер договора
            sanitize(data.getDate()),                     // Дата договора
            "",                                           // Расч.счет
            sanitize(data.fee),                      // %
            sanitize(data.minFee),                   // Min
            "",                                           // Прямые выплаты
            "",                                           // МП. Карты
            ""                                            // МП. СБП
        ]
        
        return values.joined(separator: "\t")
    }
    
    func copyToPasteboard(_ row: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(row, forType: .string)
    }
    
    private func sanitize(_ value: String?) -> String {
        guard let value else { return "" }
        
        return value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
