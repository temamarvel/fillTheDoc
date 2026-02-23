//
//  FormatValidators.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 23.02.2026.
//


enum FormatValidators {

    static func digitsOnly(_ s: String) -> String {
        s.filter { $0.isNumber }
    }

    static func isValidINN(_ innRaw: String) -> Bool {
        let inn = digitsOnly(innRaw)
        if inn.count == 10 {
            return innChecksum10(inn)
        }
        if inn.count == 12 {
            return innChecksum12(inn)
        }
        return false
    }

    private static func innChecksum10(_ inn: String) -> Bool {
        guard inn.count == 10, let digits = innDigits(inn) else { return false }
        let weights = [2,4,10,3,5,9,4,6,8]
        let sum = zip(weights, digits.prefix(9)).map(*).reduce(0,+)
        let check = (sum % 11) % 10
        return check == digits[9]
    }

    private static func innChecksum12(_ inn: String) -> Bool {
        guard inn.count == 12, let digits = innDigits(inn) else { return false }
        let w1 = [7,2,4,10,3,5,9,4,6,8,0]
        let w2 = [3,7,2,4,10,3,5,9,4,6,8,0]

        let sum1 = zip(w1, digits.prefix(11)).map(*).reduce(0,+)
        let c1 = (sum1 % 11) % 10

        let sum2 = zip(w2, digits.prefix(11)).map(*).reduce(0,+)
        let c2 = (sum2 % 11) % 10

        return c1 == digits[10] && c2 == digits[11]
    }

    private static func innDigits(_ s: String) -> [Int]? {
        let arr = s.compactMap { Int(String($0)) }
        return arr.count == s.count ? arr : nil
    }

    static func isValidKPP(_ kppRaw: String) -> Bool {
        let kpp = digitsOnly(kppRaw)
        return kpp.count == 9
    }

    static func isValidOGRN(_ ogrnRaw: String) -> Bool {
        let ogrn = digitsOnly(ogrnRaw)
        if ogrn.count == 13 { return ogrnChecksum(ogrn, modBase: 11, checkDigits: 1) }
        if ogrn.count == 15 { return ogrnChecksum(ogrn, modBase: 13, checkDigits: 1) }
        return false
    }

    private static func ogrnChecksum(_ ogrn: String, modBase: Int, checkDigits: Int) -> Bool {
        // Для ОГРН: контрольная цифра = (число без последней цифры % 11) % 10 (для 13)
        // Для ОГРНИП (15): (число без последней % 13) % 10
        guard ogrn.count >= 2 else { return false }
        let body = String(ogrn.dropLast())
        guard let bodyNumber = Int(body),
              let last = Int(String(ogrn.last!))
        else { return false }

        let check = (bodyNumber % modBase) % 10
        return check == last
    }

    /// Очень простая эвристика: в адресе должны быть буквы, числа и один из "маркеров адреса"
    static func looksLikeAddress(_ s: String) -> Bool {
        let normalized = TextNormalization.normalize(s)
        guard normalized.count >= 8 else { return false }

        let hasDigit = normalized.contains(where: { $0.isNumber })
        let hasLetter = normalized.contains(where: { $0.isLetter })

        let markers = ["г", "город", "ул", "улица", "пр", "проспект", "д", "дом", "корп", "кв", "обл", "респ", "край", "р-н", "район", "пер", "проезд", "ш", "шоссе"]
        let hasMarker = markers.contains { normalized.contains($0) }

        return hasDigit && hasLetter && hasMarker
    }
}
