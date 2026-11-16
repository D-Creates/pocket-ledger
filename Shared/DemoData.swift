import Foundation
import SwiftData

/// Deterministic-ish sample data spanning the current and previous months.
public enum DemoData {

    public static func isEmpty(context: ModelContext) -> Bool {
        (try? context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty) ?? true
    }

    public static func seedIfEmpty(context: ModelContext) {
        if isEmpty(context: context) { seed(context: context) }
    }

    @discardableResult
    public static func seed(context: ModelContext) -> Bool {
        let calendar = Calendar.current
        let now = Date.now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: monthStart)!

        func day(_ base: Date, _ d: Int) -> Date {
            calendar.date(byAdding: .day, value: d - 1, to: base)!
        }

        let groceries = Category(name: "Groceries", symbol: "cart", colorHex: "#30D158", monthlyBudget: 450)
        let dining = Category(name: "Dining", symbol: "fork.knife", colorHex: "#FF9F0A", monthlyBudget: 200)
        let transport = Category(name: "Transport", symbol: "car", colorHex: "#64D2FF", monthlyBudget: 120)
        let housing = Category(name: "Housing", symbol: "house", colorHex: "#5E5CE6", monthlyBudget: 900)
        let fun = Category(name: "Fun", symbol: "gamecontroller", colorHex: "#FF375F", monthlyBudget: 100)
        let health = Category(name: "Health", symbol: "cross.case", colorHex: "#FF453A", monthlyBudget: 0)
        let salary = Category(name: "Salary", symbol: "banknote", colorHex: "#32D74B", monthlyBudget: 0)
        let categories = [groceries, dining, transport, housing, fun, health, salary]

        let checking = Account(name: "Checking", kind: "checking", openingBalance: 1200, colorHex: "#0A84FF")
        let savings = Account(name: "Savings", kind: "savings", openingBalance: 4000, colorHex: "#30D158")
        let cash = Account(name: "Cash", kind: "cash", openingBalance: 150, colorHex: "#FF9F0A")
        let card = Account(name: "Card", kind: "card", openingBalance: 0, colorHex: "#FF375F")
        let accounts = [checking, savings, cash, card]

        for c in categories { context.insert(c) }
        for a in accounts { context.insert(a) }

        var txs: [(Decimal, Date, String, Account, Category)] = [
            (2600, day(monthStart, 1), "Salary", checking, salary),
            (-850, day(monthStart, 2), "Rent", card, housing),
            (-62.40, day(monthStart, 3), "Supermarket", checking, groceries),
            (-24.90, day(monthStart, 5), "Pizza night", card, dining),
            (-12.00, day(monthStart, 7), "Metro", cash, transport),
            (-95.20, day(monthStart, 9), "Groceries", checking, groceries),
            (-38.50, day(monthStart, 12), "Restaurant", card, dining),
            (-15.99, day(monthStart, 15), "Pharmacy", cash, health),
            (-49.00, day(monthStart, 18), "Cinema", card, fun),
            (-11.50, day(monthStart, 21), "Bakery", cash, groceries),
            (2600, day(prevMonth, 1), "Salary", checking, salary),
            (-850, day(prevMonth, 2), "Rent", card, housing),
            (-120.75, day(prevMonth, 10), "Groceries", checking, groceries),
            (-31.20, day(prevMonth, 14), "Brunch", card, dining),
            (-9.80, day(prevMonth, 20), "Bus", cash, transport),
            (-2600, day(twoMonthsAgo, 1), "Salary", checking, salary),
            (-780, day(twoMonthsAgo, 3), "Rent", card, housing),
            (-140.10, day(twoMonthsAgo, 11), "Groceries", checking, groceries),
        ]
        // A few entries dated "today" so the current month always has activity.
        txs.append((-18.30, now, "Coffee", cash, dining))
        txs.append((-42.60, now, "Weekly shop", checking, groceries))

        for (amount, date, note, account, category) in txs {
            context.insert(LedgerTransaction(amount: amount, date: date, note: note, account: account, category: category))
        }
        try? context.save()
        return true
    }
}
