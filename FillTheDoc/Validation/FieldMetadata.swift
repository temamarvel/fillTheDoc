//
//  FieldMetadata.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 21.02.2026.
//


import Foundation

struct FieldMetadata {
    let title: String
    let placeholder: String
    let normalizer: (String) -> String
    let validator: (String) -> FieldIssue?
}

extension CompanyDetails {
    static let fieldMetadata: [CodingKeys: FieldMetadata] = [
        .companyName: .init(
            title: "Название",
            placeholder: "ООО «Ромашка»",
            normalizer: { $0.trimmed },
            validator: Validators.nonEmpty
        ),
        .inn: .init(
            title: "ИНН",
            placeholder: "10/12 цифр",
            normalizer: Normalizers.trimmedDigitsOnly,
            validator: Validators.inn
        ),
        .kpp: .init(
            title: "КПП",
            placeholder: "9 цифр",
            normalizer: Normalizers.trimmedDigitsOnly,
            validator: Validators.kpp
        ),
        .ogrn: .init(
            title: "ОГРН/ОГРНИП",
            placeholder: "13/15 цифр",
            normalizer: Normalizers.trimmedDigitsOnly,
            validator: Validators.ogrn
        ),
        .ceoFullName: .init(
            title: "Руководитель",
            placeholder: "Иванов Иван Иванович",
            normalizer: { $0.trimmed },
            validator: Validators.fullName
        ),
        .ceoFullGenitiveName: .init(
            title: "Руководитель (в родительном падеже)",
            placeholder: "Иванова Ивана Ивановича",
            normalizer: { $0.trimmed },
            validator: Validators.fullName
        ),
        .ceoShortenName: .init(
            title: "Руководитель (кратко)",
            placeholder: "Иванов И.И.",
            normalizer: { $0.trimmed },
            validator: Validators.shortenName
        ),
        .legalForm: .init(
            title: "Правовая форма",
            placeholder: "ООО / АО / ИП",
            normalizer: { $0.trimmed.uppercased() },
            validator: Validators.legalFormField
        ),
        .email: .init(
            title: "Email",
            placeholder: "example@domain.com",
            normalizer: { $0.trimmed },
            validator: Validators.email
        ),
        .address: .init(
            title: "Адрес",
            placeholder: "город, улица, дом",
            normalizer: { $0.trimmed },
            validator: Validators.address
        ),
        .phone: .init(
            title: "Телефон",
            placeholder: "+79991234567",
            normalizer: Normalizers.phone,
            validator: Validators.phone
        )
    ]
}
