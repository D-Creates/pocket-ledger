import Foundation

public struct CsvRow: Sendable {
    public var date: Date
    public var account: String
    public var category: String
    public var note: String
    public var amount: Decimal

    public init(date: Date, account: String, category: String, note: String, amount: Decimal) {
        self.date = date
        self.account = account
        self.category = category
        self.note = note
        self.amount = amount
    }
}

/// RFC-4180-style CSV export of transactions. Deterministic, sorted by date.
public enum CSVExport {

    public static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private nonisolated(unsafe) static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    public static func dateString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    public static func amountString(_ amount: Decimal) -> String {
        amountFormatter.string(from: amount as NSDecimalNumber) ?? String(describing: amount)
    }

    public static func csv(rows: [CsvRow]) -> String {
        var lines = ["date,account,category,note,amount"]
        for row in rows.sorted(by: { $0.date < $1.date }) {
            lines.append([
                dateString(row.date),
                escape(row.account),
                escape(row.category),
                escape(row.note),
                amountString(row.amount),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
