import Foundation

/// Conservative OCR suggestions. A receipt total can cover several garments;
/// the user must review it before treating it as the item's price.
struct ReceiptSuggestions: Sendable, Equatable {
    let text: String
    let retailer: String?
    let total: Decimal?
    let currency: String?
    let date: Date?

    static func parse(_ lines: [String]) -> ReceiptSuggestions {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let totals = lines.filter {
            $0.range(of: #"^(?:grand\s+total|total|amount\s+paid)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        var total: Decimal?
        var currency: String?
        if totals.count == 1, let line = totals.first,
           let range = line.range(of: #"(?:USD|EUR|GBP|\$|€|£)?\s*[0-9]+\.[0-9]{2}\s*$"#, options: .regularExpression) {
            let value = String(line[range]).trimmingCharacters(in: .whitespaces)
            let number = value.replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
            let prefix = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let isPartialOrRefund = prefix.last.map { $0.isNumber || [",", ".", "-"].contains(String($0)) } ?? false
            if !isPartialOrRefund { total = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) }
            if value.contains("USD") { currency = "USD" }
            if value.contains("EUR") || value.contains("€") { currency = "EUR" }
            if value.contains("GBP") || value.contains("£") { currency = "GBP" }
            // A dollar sign alone is shared by several currencies.
        }
        let dates = lines.compactMap { line -> String? in
            guard let range = line.range(of: #"\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b"#, options: .regularExpression) else { return nil }
            return String(line[range])
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let date = dates.count == 1 ? dates.first.flatMap(formatter.date(from:)) : nil
        let first = lines.first
        let retailer = first.flatMap { line in
            line.rangeOfCharacter(from: .letters) != nil && line.rangeOfCharacter(from: .decimalDigits) == nil
                && !totals.contains(line) ? line : nil
        }
        return ReceiptSuggestions(text: lines.joined(separator: "\n"), retailer: retailer, total: total, currency: currency, date: date)
    }
}
