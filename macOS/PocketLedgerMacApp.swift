import SwiftUI
import SwiftData

@main
struct PocketLedgerMacApp: App {
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
            MacContentView(initialSection: LedgerSection(rawValue: LaunchArguments.tab ?? 0) ?? .accounts)
                .modelContainer(container)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

enum LedgerSection: Int, Hashable, Identifiable, CaseIterable {
    case accounts, transactions, budgets, charts, settings
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .accounts: "Accounts"
        case .transactions: "Transactions"
        case .budgets: "Budgets"
        case .charts: "Charts"
        case .settings: "Settings"
        }
    }
    var systemImage: String {
        switch self {
        case .accounts: "building.columns"
        case .transactions: "list.bullet"
        case .budgets: "target"
        case .charts: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct MacContentView: View {
    @State private var selection: LedgerSection

    init(initialSection: LedgerSection) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(LedgerSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .accessibilityIdentifier("nav.\(section.title.lowercased())")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            switch selection {
            case .accounts: MacAccountsView()
            case .transactions: MacTransactionsView()
            case .budgets: BudgetsView()
            case .charts: MacChartsView()
            case .settings: MacSettingsView()
            }
        }
    }
}

struct MacAccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var transactions: [LedgerTransaction]
    @State private var showingAdd = false

    private var txs: [Tx] { transactions.map(\.tx) }
    private var netWorth: Decimal {
        LedgerEngine.netWorth(openingBalances: accounts.map(\.openingBalance), transactions: txs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Net worth").font(.caption).foregroundStyle(.secondary)
                Text(amountLabel(netWorth)).font(.system(size: 40, weight: .bold))
                    .accessibilityIdentifier("accounts.netWorth")
            }
            Table(accounts) {
                TableColumn("Name") { a in
                    HStack {
                        Circle().fill(Color(hex: a.colorHex)).frame(width: 10, height: 10)
                        Text(a.name)
                    }
                }
                TableColumn("Kind") { a in Text(a.kind) }
                TableColumn("Balance") { a in
                    Text(amountLabel(LedgerEngine.accountBalance(opening: a.openingBalance, transactions: txs.filter { $0.accountName == a.name })))
                        .accessibilityIdentifier("account.row.\(a.name)")
                }
            }
        }
        .padding()
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("account.add")
            }
        }
        .sheet(isPresented: $showingAdd) { AddAccountView().frame(minWidth: 400, minHeight: 260) }
        .navigationTitle("Accounts")
    }
}

struct MacTransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\LedgerTransaction.date, order: .reverse)]) private var transactions: [LedgerTransaction]
    @State private var showingAdd = false

    var body: some View {
        Table(transactions) {
            TableColumn("Date") { t in Text(t.date.formatted(date: .abbreviated, time: .omitted)) }
            TableColumn("Note") { t in Text(t.note) }
            TableColumn("Category") { t in Text(t.category?.name ?? "—") }
            TableColumn("Account") { t in Text(t.account?.name ?? "—") }
            TableColumn("Amount") { t in
                Text(amountLabel(t.amount)).foregroundStyle(t.amount < 0 ? .red : .green)
                    .accessibilityIdentifier("tx.row.\(t.date.timeIntervalSince1970)")
            }
        }
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("tx.add")
            }
        }
        .sheet(isPresented: $showingAdd) { AddTransactionView().frame(minWidth: 420, minHeight: 380) }
        .navigationTitle("Transactions")
    }
}

struct MacChartsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var transactions: [LedgerTransaction]

    private var txs: [Tx] { transactions.map(\.tx) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Net worth, 6 months").font(.headline)
                NetWorthChartView(points: LedgerEngine.netWorthSeries(
                    openingBalances: accounts.map(\.openingBalance), transactions: txs, endMonth: .now))
                    .frame(height: 260)
                    .accessibilityIdentifier("charts.netWorth")
                Text("Spending by category").font(.headline)
                CategorySpendChartView(points: categories.map { ($0.name, LedgerEngine.spend(category: $0.name, in: .now, of: txs)) })
                    .frame(height: 280)
                    .accessibilityIdentifier("charts.categories")
                Text("Daily cashflow").font(.headline)
                DailyCashflowChartView(points: LedgerEngine.dailyCashflow(for: .now, transactions: txs))
                    .frame(height: 240)
                    .accessibilityIdentifier("charts.cashflow")
            }
            .padding()
        }
        .navigationTitle("Charts")
    }
}

struct MacSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var csv: String?

    var body: some View {
        Form {
            Section("Data") {
                Button("Seed demo data") { DemoData.seed(context: context) }
                    .accessibilityIdentifier("settings.demo")
                Button("Reset all data", role: .destructive) { try? Store.resetAll(context: context) }
                    .accessibilityIdentifier("settings.reset")
                Button("Export CSV") { csv = try? Store.exportCSV(context: context) }
                    .accessibilityIdentifier("settings.exportButton")
                if let csv { CSVShareLink(csv: csv) }
            }
            Section("About") {
                Text("Pocket Ledger — private offline budget ledger. Data stays on this device only. No network, no accounts.")
                    .accessibilityIdentifier("settings.about")
            }
        }
        .padding()
        .navigationTitle("Settings")
    }
}
