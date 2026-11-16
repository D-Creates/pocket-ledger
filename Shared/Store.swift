import Foundation
import SwiftData

public enum Store {
    public static let sharedSchema = Schema([Account.self, Category.self, LedgerTransaction.self])

    public static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: sharedSchema, isStoredInMemoryOnly: false)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: sharedSchema, configurations: [config])
    }

    /// Delete every stored object. Used by the `-resetData` launch argument.
    public static func resetAll(context: ModelContext) throws {
        for tx in try context.fetch(FetchDescriptor<LedgerTransaction>()) { context.delete(tx) }
        for account in try context.fetch(FetchDescriptor<Account>()) { context.delete(account) }
        for category in try context.fetch(FetchDescriptor<Category>()) { context.delete(category) }
        try context.save()
    }

    /// All transactions as engine snapshots, sorted by date ascending.
    public static func allTransactions(_ context: ModelContext) throws -> [Tx] {
        let descriptor = FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date)])
        return try context.fetch(descriptor).map(\.tx)
    }

    /// Export every stored transaction as a CSV string.
    public static func exportCSV(context: ModelContext) throws -> String {
        let txs = try context.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date)]))
        let rows = txs.map { CsvRow(date: $0.date, account: $0.account?.name ?? "", category: $0.category?.name ?? "", note: $0.note, amount: $0.amount) }
        return CSVExport.csv(rows: rows)
    }
}
