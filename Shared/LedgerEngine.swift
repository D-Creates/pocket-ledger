import Foundation

/// Plain, Sendable transaction snapshot used by the pure engine (no SwiftData).
public struct Tx: Sendable, Equatable {
    public var amount: Decimal // negative = expense, positive = income
    public var date: Date
    public var note: String
    public var accountName: String
    public var categoryName: String

    public init(amount: Decimal, date: Date, note: String = "", accountName: String = "", categoryName: String = "") {
        self.amount = amount
        self.date = date
        self.note = note
        self.accountName = accountName
        self.categoryName = categoryName
    }
}

/// Pure budget/balance logic. No SwiftData, no UI — fully unit-testable.
public enum LedgerEngine {

    /// Balance of one account: opening balance plus all signed transactions.
    public static func accountBalance(opening: Decimal, transactions: [Tx]) -> Decimal {
        opening + transactions.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Net worth: all opening balances plus all signed transactions.
    public static func netWorth(openingBalances: [Decimal], transactions: [Tx]) -> Decimal {
        openingBalances.reduce(Decimal(0), +) + transactions.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Calendar-month interval containing `date`.
    public static func monthInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    /// Expense magnitude (positive number) of one category in the given month.
    /// Only negative amounts inside the month count. Month rollover: transactions
    /// from any other month are excluded by construction.
    public static func spend(category: String, in month: Date, of transactions: [Tx], calendar: Calendar = .current) -> Decimal {
        let interval = monthInterval(for: month, calendar: calendar)
        return transactions
            .filter { $0.categoryName == category && $0.amount < 0 && interval.contains($0.date) }
            .reduce(Decimal(0)) { $0 - $1.amount }
    }

    /// Remaining budget for a month. Negative means over budget.
    public static func monthRemaining(budget: Decimal, spent: Decimal) -> Decimal {
        budget - spent
    }

    public static func isOverBudget(budget: Decimal, spent: Decimal) -> Bool {
        spent > budget && budget > 0
    }

    /// Monthly net-worth snapshots, one per month, ending at `month`.
    public static func netWorthSeries(openingBalances: [Decimal], transactions: [Tx], endMonth: Date, periods: Int = 6, calendar: Calendar = .current) -> [(Date, Decimal)] {
        let interval = monthInterval(for: endMonth, calendar: calendar)
        var months: [Date] = []
        for i in stride(from: periods - 1, through: 0, by: -1) {
            months.append(calendar.date(byAdding: .month, value: -i, to: interval.start)!)
        }
        let base = openingBalances.reduce(Decimal(0), +)
        return months.map { monthStart in
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            let upToEnd = transactions.filter { $0.date < monthEnd }.reduce(Decimal(0)) { $0 + $1.amount }
            return (monthStart, base + upToEnd)
        }
    }

    /// Per-day net cashflow (income minus expenses) for the month containing `month`.
    public static func dailyCashflow(for month: Date, transactions: [Tx], calendar: Calendar = .current) -> [(Date, Decimal)] {
        let interval = monthInterval(for: month, calendar: calendar)
        var days: [Date: Decimal] = [:]
        for tx in transactions where interval.contains(tx.date) {
            let day = calendar.startOfDay(for: tx.date)
            days[day, default: 0] += tx.amount
        }
        return days.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

extension LedgerTransaction {
    /// Adapter from the SwiftData model to the pure engine type.
    var tx: Tx {
        Tx(amount: amount, date: date, note: note,
           accountName: account?.name ?? "", categoryName: category?.name ?? "")
    }
}
