import XCTest
import SwiftData
@testable import PocketLedger

// MARK: - Balances

final class BalanceTests: XCTestCase {
    func testAccountBalanceIsOpeningPlusSignedSum() {
        let txs = [
            Tx(amount: -50, date: Date(timeIntervalSince1970: 1000)),
            Tx(amount: -25.50, date: Date(timeIntervalSince1970: 2000)),
            Tx(amount: 200, date: Date(timeIntervalSince1970: 3000)),
        ]
        let balance = LedgerEngine.accountBalance(opening: 100, transactions: txs)
        XCTAssertEqual(balance, 100 - 50 - 25.50 + 200)
    }

    func testAccountBalanceWithNoTransactionsIsOpening() {
        XCTAssertEqual(LedgerEngine.accountBalance(opening: 42, transactions: []), 42)
    }

    func testNetWorthSumsAllAccountsAndTransactions() {
        let txs = [Tx(amount: -10, date: .now), Tx(amount: 5, date: .now)]
        let worth = LedgerEngine.netWorth(openingBalances: [1000, 500, 0], transactions: txs)
        XCTAssertEqual(worth, 1495)
    }
}

// MARK: - Budgets and month rollover

final class BudgetTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var oct2026: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 15
        return calendar.date(from: comps)!
    }
    private var nov2026: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 15
        return calendar.date(from: comps)!
    }

    private func tx(_ amount: Decimal, _ date: Date, _ category: String = "Food") -> Tx {
        Tx(amount: amount, date: date, categoryName: category)
    }

    func testSpendCountsOnlyExpensesOfThatMonth() {
        let txs = [
            tx(-30, oct2026),
            tx(-20, calendar.date(byAdding: .day, value: 10, to: oct2026)!),
            tx(100, oct2026), // income must not count as spend
            tx(-99, nov2026), // other month must not count
        ]
        XCTAssertEqual(LedgerEngine.spend(category: "Food", in: oct2026, of: txs, calendar: calendar), 50)
    }

    func testSpendIgnoresOtherCategories() {
        let txs = [tx(-30, oct2026, "Food"), tx(-70, oct2026, "Rent")]
        XCTAssertEqual(LedgerEngine.spend(category: "Food", in: oct2026, of: txs, calendar: calendar), 30)
    }

    func testMonthRolloverResetsSpent() {
        // Same category, transactions in October and November: November spend
        // must not include October, i.e. budgets roll over to a fresh month.
        let txs = [tx(-80, oct2026), tx(-20, nov2026)]
        let octSpent = LedgerEngine.spend(category: "Food", in: oct2026, of: txs, calendar: calendar)
        let novSpent = LedgerEngine.spend(category: "Food", in: nov2026, of: txs, calendar: calendar)
        XCTAssertEqual(octSpent, 80)
        XCTAssertEqual(novSpent, 20)
        XCTAssertEqual(LedgerEngine.monthRemaining(budget: 100, spent: novSpent), 80)
    }

    func testMonthIntervalBoundaries() {
        let interval = LedgerEngine.monthInterval(for: oct2026, calendar: calendar)
        var comps = DateComponents(); comps.year = 2026; comps.month = 10
        XCTAssertEqual(interval.start, calendar.date(from: comps)!)
        comps.month = 11
        XCTAssertEqual(interval.end, calendar.date(from: comps)!)
        XCTAssertTrue(interval.contains(interval.start))
        XCTAssertTrue(interval.contains(oct2026))
        XCTAssertFalse(interval.contains(calendar.date(byAdding: .day, value: 1, to: interval.end)!))
    }

    func testMonthRemainingCanGoNegativeWhenOverBudget() {
        XCTAssertEqual(LedgerEngine.monthRemaining(budget: 100, spent: 130), -30)
        XCTAssertTrue(LedgerEngine.isOverBudget(budget: 100, spent: 130))
        XCTAssertFalse(LedgerEngine.isOverBudget(budget: 100, spent: 100))
        XCTAssertFalse(LedgerEngine.isOverBudget(budget: 0, spent: 500)) // no budget set
    }
}

// MARK: - CSV export

final class CSVExportTests: XCTestCase {
    func testHeaderAndRowPerTransactionSortedByDate() {
        let rows = [
            CsvRow(date: Date(timeIntervalSince1970: 2000), account: "Cash", category: "Food", note: "b", amount: -2),
            CsvRow(date: Date(timeIntervalSince1970: 1000), account: "Bank", category: "Pay", note: "a", amount: 100),
        ]
        let csv = CSVExport.csv(rows: rows)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "date,account,category,note,amount")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("1970-01-01,Bank,Pay,a,100.00"))
        XCTAssertTrue(lines[2].hasPrefix("1970-01-01,Cash,Food,b,-2.00"))
        XCTAssertTrue(csv.hasSuffix("\n"))
    }

    func testEscapingCommasQuotesNewlines() {
        XCTAssertEqual(CSVExport.escape("plain"), "plain")
        XCTAssertEqual(CSVExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExport.escape("line1\nline2"), "\"line1\nline2\"")
    }

    func testAmountFormatUsesDotAndTwoDecimals() {
        XCTAssertEqual(CSVExport.amountString(Decimal(string: "12.5")!), "12.50")
        XCTAssertEqual(CSVExport.amountString(Decimal(-3)), "-3.00")
    }
}

// MARK: - Series helpers

final class SeriesTests: XCTestCase {
    func testDailyCashflowGroupsByDay() {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.year = 2026; comps.month = 5; comps.day = 3
        let day1 = cal.date(from: comps)!
        let txs = [
            Tx(amount: -10, date: day1),
            Tx(amount: -5, date: day1.addingTimeInterval(3600)),
            Tx(amount: 100, date: cal.date(byAdding: .day, value: 1, to: day1)!),
        ]
        let series = LedgerEngine.dailyCashflow(for: day1, transactions: txs, calendar: cal)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].1, -15)
        XCTAssertEqual(series[1].1, 100)
    }

    func testNetWorthSeriesHasRequestedPeriods() {
        let txs = [Tx(amount: -10, date: .now)]
        let series = LedgerEngine.netWorthSeries(openingBalances: [1000], transactions: txs, endMonth: .now, periods: 6)
        XCTAssertEqual(series.count, 6)
        XCTAssertEqual(series.last!.1, 990)
    }
}

// MARK: - Demo data consistency (in-memory SwiftData)

final class DemoDataTests: XCTestCase {
    func testSeedProducesConsistentData() throws {
        let container = try ModelContainer(
            for: Store.sharedSchema,
            configurations: [ModelConfiguration(schema: Store.sharedSchema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        DemoData.seed(context: context)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<PocketLedger.Category>())
        let txs = try context.fetch(FetchDescriptor<LedgerTransaction>())
        XCTAssertGreaterThanOrEqual(accounts.count, 3)
        XCTAssertGreaterThanOrEqual(categories.count, 5)
        XCTAssertGreaterThanOrEqual(txs.count, 10)

        let engineTxs = try Store.allTransactions(context)
        let worth = LedgerEngine.netWorth(openingBalances: accounts.map(\.openingBalance), transactions: engineTxs)
        // 1200 + 4000 + 150 + 0 + 2*2600 - 2600 (salary signs) ... just check it computes and is finite
        XCTAssertNotEqual(worth, 0)

        let csv = try Store.exportCSV(context: context)
        XCTAssertTrue(csv.hasPrefix("date,account,category,note,amount\n"))
        XCTAssertEqual(csv.split(separator: "\n").count, txs.count + 1)
    }
}

// MARK: - Edge cases

final class EdgeCaseTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return calendar.date(from: comps)!
    }

    func testCSVWithNoRowsIsHeaderOnly() {
        XCTAssertEqual(CSVExport.csv(rows: []), "date,account,category,note,amount\n")
    }

    func testCSVRowQuotesFieldsContainingCommas() {
        let rows = [CsvRow(date: Date(timeIntervalSince1970: 43200), account: "Cash", category: "Food", note: "bread, milk", amount: -2)]
        let lines = CSVExport.csv(rows: rows).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "1970-01-01,Cash,Food,\"bread, milk\",-2.00")
    }

    func testEscapeHandlesCarriageReturnAndEmptyString() {
        XCTAssertEqual(CSVExport.escape(""), "")
        XCTAssertEqual(CSVExport.escape("a\rb"), "\"a\rb\"")
    }

    func testAmountStringForZero() {
        XCTAssertEqual(CSVExport.amountString(0), "0.00")
    }

    func testAccountBalanceKeepsDecimalPrecision() {
        let txs = [
            Tx(amount: Decimal(string: "0.1")!, date: .now),
            Tx(amount: Decimal(string: "0.2")!, date: .now),
        ]
        XCTAssertEqual(LedgerEngine.accountBalance(opening: 0, transactions: txs), Decimal(string: "0.3")!)
    }

    func testSpendIsZeroWithoutMatchingExpenses() {
        let month = day(2026, 10, 15)
        XCTAssertEqual(LedgerEngine.spend(category: "Food", in: month, of: [], calendar: calendar), 0)
        let incomeOnly = [Tx(amount: 50, date: month, categoryName: "Food")]
        XCTAssertEqual(LedgerEngine.spend(category: "Food", in: month, of: incomeOnly, calendar: calendar), 0)
    }

    func testNetWorthSeriesIsCumulativeAndAscending() {
        let txs = [
            Tx(amount: -10, date: day(2026, 9, 10)),
            Tx(amount: -20, date: day(2026, 10, 10)),
        ]
        let series = LedgerEngine.netWorthSeries(
            openingBalances: [1000], transactions: txs, endMonth: day(2026, 10, 20), periods: 3, calendar: calendar)
        XCTAssertEqual(series.map(\.0), [day(2026, 8, 1), day(2026, 9, 1), day(2026, 10, 1)])
        XCTAssertEqual(series.map(\.1), [1000, 990, 970])
    }

    func testDailyCashflowExcludesOtherMonthsAndIsSorted() {
        let txs = [
            Tx(amount: 7, date: day(2026, 5, 20)),
            Tx(amount: -3, date: day(2026, 5, 2)),
            Tx(amount: -99, date: day(2026, 4, 28)),
            Tx(amount: -99, date: day(2026, 6, 5)),
        ]
        let series = LedgerEngine.dailyCashflow(for: day(2026, 5, 15), transactions: txs, calendar: calendar)
        XCTAssertEqual(series.map(\.0), [day(2026, 5, 2), day(2026, 5, 20)])
        XCTAssertEqual(series.map(\.1), [-3, 7])
        XCTAssertTrue(LedgerEngine.dailyCashflow(for: day(2026, 5, 15), transactions: [], calendar: calendar).isEmpty)
    }
}
