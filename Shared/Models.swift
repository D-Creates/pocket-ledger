import Foundation
import SwiftData

/// A financial account (checking, savings, cash, card).
@Model
final class Account {
    var name: String
    /// checking / savings / cash / card
    var kind: String
    var openingBalance: Decimal
    var colorHex: String
    var createdAt: Date
    @Relationship(inverse: \LedgerTransaction.account)
    var transactions: [LedgerTransaction]?

    init(name: String, kind: String, openingBalance: Decimal = 0, colorHex: String = "#0A84FF", createdAt: Date = .now) {
        self.name = name
        self.kind = kind
        self.openingBalance = openingBalance
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

/// A spending/income category, optionally with a monthly budget limit.
@Model
final class Category {
    var name: String
    var symbol: String
    var colorHex: String
    /// Monthly budget limit. 0 means "no budget".
    var monthlyBudget: Decimal
    @Relationship(inverse: \LedgerTransaction.category)
    var transactions: [LedgerTransaction]?

    init(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal = 0) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget
    }
}

/// A single ledger entry. Negative amount = expense, positive = income.
@Model
final class LedgerTransaction {
    var amount: Decimal
    var date: Date
    var note: String
    var account: Account?
    var category: Category?

    init(amount: Decimal, date: Date, note: String = "", account: Account? = nil, category: Category? = nil) {
        self.amount = amount
        self.date = date
        self.note = note
        self.account = account
        self.category = category
    }
}
