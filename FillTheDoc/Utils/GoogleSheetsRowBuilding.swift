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
            data.companyDetails?.fullCompanyName.sanitizedForTSV ?? "",   // Наименование
            data.companyDetails?.ceoFullName?.sanitizedForTSV ?? "",      // ФИО
            data.companyDetails?.inn?.sanitizedForTSV ?? "",              // ИНН
            data.companyDetails?.phone?.sanitizedForTSV ?? "",            // Телефон компании
            data.companyDetails?.email?.sanitizedForTSV ?? "",            // E-mail Компании
            data.docNumber?.sanitizedForTSV ?? "",                        // Номер договора
            data.date.sanitizedForTSV,                                    // Дата договора
            "",                                                           // Расч.счет
            data.fee?.sanitizedForTSV ?? "",                              // %
            data.minFee?.sanitizedForTSV ?? "",                           // Min
            "",                                                           // Прямые выплаты
            "",                                                           // МП. Карты
            ""                                                            // МП. СБП
        ]
        
        return values.joined(separator: "\t")
    }
    
    func copyToPasteboard(_ row: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(row, forType: .string)
    }
}
