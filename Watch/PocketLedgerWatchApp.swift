import SwiftUI
import SwiftData

@main
struct PocketLedgerWatchApp: App {
    let container: ModelContainer

    init() {
        let c = Store.makeContainer()
        container = c
        let context = ModelContext(c)
        if LaunchArguments.resetData { try? Store.resetAll(context: context) }
        if LaunchArguments.demo { DemoData.seedIfEmpty(context: context) }
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .modelContainer(container)
        }
    }
}

struct WatchContentView: View {
    @State private var selection: Int = LaunchArguments.tab ?? 0

    var body: some View {
        TabView(selection: $selection) {
            WatchMonthView()
                .tag(0)
                .tabItem { Image(systemName: "target") }
                .accessibilityIdentifier("tab.month")
            WatchAddView()
                .tag(1)
                .tabItem { Image(systemName: "plus") }
                .accessibilityIdentifier("tab.add")
        }
    }
}

/// Month remaining per budgeted category plus total spent this month.
struct WatchMonthView: View {
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @Query private var transactions: [LedgerTransaction]

    private var txs: [Tx] { transactions.map(\.tx) }
    private var totalSpent: Decimal {
        txs.filter { LedgerEngine.monthInterval(for: .now).contains($0.date) && $0.amount < 0 }
            .reduce(Decimal(0)) { $0 - $1.amount }
    }

    var body: some View {
        List {
            Section {
                Text("Spent this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(amountLabel(totalSpent))
                    .font(.title2.bold())
                    .accessibilityIdentifier("watch.month.totalSpent")
            }
            Section("Remaining") {
                ForEach(categories.filter { $0.monthlyBudget > 0 }) { category in
                    let spent = LedgerEngine.spend(category: category.name, in: .now, of: txs)
                    let remaining = LedgerEngine.monthRemaining(budget: category.monthlyBudget, spent: spent)
                    VStack(alignment: .leading) {
                        Text(category.name)
                        Text(amountLabel(remaining))
                            .foregroundStyle(remaining < 0 ? .red : .green)
                            .accessibilityIdentifier("watch.month.remaining.\(category.name)")
                    }
                }
            }
        }
    }
}

/// Quick-add an expense: amount + category, saved as a negative transaction.
struct WatchAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var amount = ""
    @State private var note = ""
    @State private var category: Category?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Amount", text: $amount)
                    .accessibilityIdentifier("watch.add.amount")
                TextField("Note", text: $note)
                    .accessibilityIdentifier("watch.add.note")
                Picker("Category", selection: $category) {
                    ForEach(categories) { Text($0.name).tag(Optional($0)) }
                }
                .accessibilityIdentifier("watch.add.category")
            }
            Section {
                Button(saved ? "Saved" : "Add expense") {
                    let value = -(Decimal(string: amount) ?? 0)
                    let account = accounts.first
                    context.insert(LedgerTransaction(amount: value, date: .now, note: note, account: account, category: category))
                    try? context.save()
                    saved = true
                    amount = ""
                    note = ""
                }
                .disabled(amount.isEmpty)
                .accessibilityIdentifier("watch.add.save")
            }
        }
        .navigationTitle("Quick add")
    }
}
