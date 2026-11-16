import Foundation
import SwiftUI
import SwiftData

#if !os(watchOS)
import Charts

/// Net worth over the last months (line chart).
struct NetWorthChartView: View {
    var points: [(Date, Decimal)]

    var body: some View {
        Chart(points, id: \.0) { point in
            LineMark(
                x: .value("Month", point.0, unit: .month),
                y: .value("Net worth", NSDecimalNumber(decimal: point.1).doubleValue)
            )
            .accessibilityIdentifier("chart.netWorth.line")
            AreaMark(
                x: .value("Month", point.0, unit: .month),
                y: .value("Net worth", NSDecimalNumber(decimal: point.1).doubleValue)
            )
            .foregroundStyle(.blue.opacity(0.15))
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { value in
            AxisValueLabel(format: .dateTime.month(.abbreviated))
        }}
    }
}

/// Spending per category for one month (bar chart).
struct CategorySpendChartView: View {
    var points: [(String, Decimal)]

    var body: some View {
        Chart(points, id: \.0) { point in
            BarMark(
                x: .value("Category", point.0),
                y: .value("Spent", NSDecimalNumber(decimal: point.1).doubleValue)
            )
            .foregroundStyle(.orange)
            .accessibilityIdentifier("chart.categories.bar")
        }
    }
}

/// Daily net cashflow for one month (bar chart, green income / red expense).
struct DailyCashflowChartView: View {
    var points: [(Date, Decimal)]

    var body: some View {
        Chart(points, id: \.0) { point in
            BarMark(
                x: .value("Day", point.0, unit: .day),
                y: .value("Net", NSDecimalNumber(decimal: point.1).doubleValue)
            )
            .foregroundStyle(NSDecimalNumber(decimal: point.1).doubleValue >= 0 ? .green : .red)
            .accessibilityIdentifier("chart.cashflow.bar")
        }
    }
}
#endif

struct AddAccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = "checking"
    @State private var opening = "0"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name).accessibilityIdentifier("account.nameField")
                Picker("Kind", selection: $kind) {
                    ForEach(["checking", "savings", "cash", "card"], id: \.self) { Text($0) }
                }
                TextField("Opening balance", text: $opening)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityIdentifier("account.openingField")
            }
            .navigationTitle("New account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Account(name: name, kind: kind, openingBalance: Decimal(string: opening) ?? 0))
                        try? context.save()
                        dismiss()
                    }
                    .accessibilityIdentifier("account.save")
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Transactions

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\LedgerTransaction.date, order: .reverse)]) private var transactions: [LedgerTransaction]
    @State private var showingAdd = LaunchArguments.screen == "addTransaction"

    var body: some View {
        List {
            ForEach(transactions) { tx in
                HStack {
                    VStack(alignment: .leading) {
                        Text(tx.note.isEmpty ? (tx.category?.name ?? "—") : tx.note)
                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(amountLabel(tx.amount))
                        .foregroundStyle(tx.amount < 0 ? .red : .green)
                        .accessibilityIdentifier("tx.row.\(tx.date.timeIntervalSince1970)")
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(transactions[i]) }
                try? context.save()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("tx.add")
            }
        }
        .sheet(isPresented: $showingAdd) { AddTransactionView() }
    }
}

struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @State private var amount = ""
    @State private var note = ""
    @State private var isExpense = true
    @State private var date = Date.now
    @State private var account: Account?
    @State private var category: Category?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $isExpense) {
                    Text("Expense").tag(true)
                    Text("Income").tag(false)
                }
                #if !os(watchOS)
                .pickerStyle(.segmented)
                #endif
                .accessibilityIdentifier("tx.typePicker")
                TextField("Amount", text: $amount)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityIdentifier("tx.amountField")
                TextField("Note", text: $note).accessibilityIdentifier("tx.noteField")
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .accessibilityIdentifier("tx.datePicker")
                Picker("Account", selection: $account) {
                    ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                }
                .accessibilityIdentifier("tx.accountPicker")
                Picker("Category", selection: $category) {
                    ForEach(categories) { Text($0.name).tag(Optional($0)) }
                }
                .accessibilityIdentifier("tx.categoryPicker")
            }
            .navigationTitle("New transaction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var value = Decimal(string: amount) ?? 0
                        if isExpense { value = -abs(value) } else { value = abs(value) }
                        context.insert(LedgerTransaction(amount: value, date: date, note: note, account: account, category: category))
                        try? context.save()
                        dismiss()
                    }
                    .accessibilityIdentifier("tx.save")
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Budgets

struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @Query private var transactions: [LedgerTransaction]
    @State private var month = Calendar.current.date(byAdding: .month, value: -LaunchArguments.monthOffset, to: Date.now)!

    private var txs: [Tx] { transactions.map(\.tx) }

    var body: some View {
        List {
            Section {
                ForEach(categories.filter { $0.monthlyBudget > 0 }) { category in
                    let spent = LedgerEngine.spend(category: category.name, in: month, of: txs)
                    let remaining = LedgerEngine.monthRemaining(budget: category.monthlyBudget, spent: spent)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(category.name, systemImage: category.symbol)
                            Spacer()
                            Text("\(amountLabel(spent)) / \(amountLabel(category.monthlyBudget))")
                        }
                        ProgressView(value: NSDecimalNumber(decimal: min(spent / max(category.monthlyBudget, 1), 1)).doubleValue)
                            .accessibilityIdentifier("budget.bar.\(category.name)")
                        Text("Remaining: \(amountLabel(remaining))")
                            .font(.caption)
                            .foregroundStyle(remaining < 0 ? .red : .secondary)
                            .accessibilityIdentifier("budget.remaining.\(category.name)")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! }
                        label: { Image(systemName: "chevron.left") }
                        .accessibilityIdentifier("budget.prevMonth")
                    Spacer()
                    Text(month.formatted(.dateTime.year().month(.wide)))
                        .accessibilityIdentifier("budget.monthLabel")
                    Spacer()
                    Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! }
                        label: { Image(systemName: "chevron.right") }
                        .accessibilityIdentifier("budget.nextMonth")
                }
            }
        }
    }
}


extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        self.init(red: Double((int >> 16) & 0xFF) / 255, green: Double((int >> 8) & 0xFF) / 255, blue: Double(int & 0xFF) / 255)
    }
}

/// Formats a Decimal as a plain currency-ish string for labels.
func amountLabel(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    return formatter.string(from: value as NSDecimalNumber) ?? String(describing: value)
}

#if !os(watchOS)
/// Share sheet for the CSV export (works on iOS and macOS).
struct CSVShareLink: View {
    let csv: String

    var body: some View {
        let url = Self.makeFile(csv)
        ShareLink(item: url) {
            Label("Export CSV", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("settings.export")
    }

    static func makeFile(_ csv: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocket-ledger-\(Int(Date.now.timeIntervalSince1970)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
#endif
