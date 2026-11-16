import SwiftUI
import SwiftData

@main
struct PocketLedgerApp: App {
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
            ContentView(initialTab: LaunchArguments.tab ?? 0)
                .modelContainer(container)
        }
    }
}

enum LedgerTab: Int, Hashable, Identifiable, CaseIterable {
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
    var accessibilityId: String { "tab.\(title.lowercased())" }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: LedgerTab
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(initialTab: Int) {
        _selection = State(initialValue: LedgerTab(rawValue: initialTab) ?? .accounts)
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad (all orientations, regular width): sidebar + detail split view.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List {
                    ForEach(LedgerTab.allCases) { tab in
                        Button { selection = tab } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .listRowBackground(selection == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .accessibilityIdentifier(tab.accessibilityId)
                    }
                }
                .navigationTitle("Pocket Ledger")
                .accessibilityIdentifier("sidebar")
            } detail: {
                NavigationStack {
                    tabView(selection)
                        .navigationTitle(selection.title)
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            // iPhone and compact-width iPad multitasking: tab bar + stack.
            TabView(selection: $selection) {
                ForEach(LedgerTab.allCases) { tab in
                    NavigationStack {
                        tabView(tab)
                            .navigationTitle(tab.title)
                    }
                    .tag(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .accessibilityIdentifier(tab.accessibilityId)
                }
            }
        }
    }

    @ViewBuilder
    private func tabView(_ tab: LedgerTab) -> some View {
        switch tab {
        case .accounts: AccountsView()
        case .transactions: TransactionsView()
        case .budgets: BudgetsView()
        case .charts: ChartsView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Accounts

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var transactions: [LedgerTransaction]
    @State private var showingAdd = LaunchArguments.screen == "addAccount"

    private var txs: [Tx] { transactions.map(\.tx) }
    private var netWorth: Decimal {
        LedgerEngine.netWorth(openingBalances: accounts.map(\.openingBalance), transactions: txs)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    Text("Net worth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(amountLabel(netWorth))
                        .font(.system(size: 34, weight: .bold))
                        .accessibilityIdentifier("accounts.netWorth")
                }
            }
            Section("Accounts") {
                ForEach(accounts) { account in
                    HStack {
                        Circle().fill(Color(hex: account.colorHex)).frame(width: 12, height: 12)
                        VStack(alignment: .leading) {
                            Text(account.name)
                            Text(account.kind).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(amountLabel(LedgerEngine.accountBalance(opening: account.openingBalance, transactions: txs.filter { $0.accountName == account.name })))
                            .accessibilityIdentifier("account.row.\(account.name)")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("account.add")
            }
        }
        .sheet(isPresented: $showingAdd) { AddAccountView() }
    }
}

// MARK: - Charts

struct ChartsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var transactions: [LedgerTransaction]

    private var txs: [Tx] { transactions.map(\.tx) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Net worth, 6 months").font(.headline)
                    NetWorthChartView(points: LedgerEngine.netWorthSeries(
                        openingBalances: accounts.map(\.openingBalance), transactions: txs, endMonth: .now))
                        .frame(height: 200)
                }
                .accessibilityIdentifier("charts.netWorth")
                VStack(alignment: .leading) {
                    Text("Spending by category").font(.headline)
                    CategorySpendChartView(points: categories.map { ($0.name, LedgerEngine.spend(category: $0.name, in: .now, of: txs)) })
                        .frame(height: 220)
                }
                .accessibilityIdentifier("charts.categories")
                VStack(alignment: .leading) {
                    Text("Daily cashflow").font(.headline)
                    DailyCashflowChartView(points: LedgerEngine.dailyCashflow(for: .now, transactions: txs))
                        .frame(height: 200)
                }
                .accessibilityIdentifier("charts.cashflow")
            }
            .padding()
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var csv: String? = nil

    init() {
        if LaunchArguments.screen == "export" {
            // preloaded below via task to have a context; simplified: load on appear
        }
    }

    var body: some View {
        Form {
            Section("Data") {
                Button("Seed demo data") {
                    DemoData.seed(context: context)
                }
                .accessibilityIdentifier("settings.demo")
                Button("Reset all data", role: .destructive) {
                    try? Store.resetAll(context: context)
                }
                .accessibilityIdentifier("settings.reset")
                Button("Export CSV") {
                    csv = try? Store.exportCSV(context: context)
                }
                .accessibilityIdentifier("settings.exportButton")
                if let csv {
                    CSVShareLink(csv: csv)
                }
            }
            Section("About") {
                Text("Pocket Ledger — private offline budget ledger. Data stays on this device only. No network, no accounts.")
                    .accessibilityIdentifier("settings.about")
            }
        }
        .task {
            if LaunchArguments.screen == "export" { csv = try? Store.exportCSV(context: context) }
        }
    }
}
