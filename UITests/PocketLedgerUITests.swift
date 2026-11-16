import XCTest

// UI smoke tests per platform. Written but NOT run in this pass (reported as
// pending in the release README); they compile for all three platforms.

#if os(iOS)
final class PocketLedgerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Top-level navigation is a tab bar on compact width (iPhone) and a
    /// split-view sidebar on regular width (iPad). Query by accessibilityIdentifier
    /// or visible label with waitForExistence.
    private func navButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let id = "tab.\(title.lowercased())"
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", id, title)
        return app.buttons.matching(predicate).firstMatch
    }

    private func revealSidebarIfNeeded(_ app: XCUIApplication, for target: XCUIElement) {
        if target.waitForExistence(timeout: 3), target.isHittable { return }
        let toggle = app.buttons.matching(
            NSPredicate(format: "identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar'")
        ).firstMatch
        if toggle.waitForExistence(timeout: 2), toggle.isHittable {
            toggle.tap()
        }
    }

    private func navExists(_ app: XCUIApplication, _ title: String) -> Bool {
        let button = navButton(app, title)
        revealSidebarIfNeeded(app, for: button)
        return button.waitForExistence(timeout: 10)
    }

    private func tapNav(_ app: XCUIApplication, _ title: String) {
        let button = navButton(app, title)
        revealSidebarIfNeeded(app, for: button)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing nav item \(title)")
        button.tap()
    }

    func testTabsExistAfterDemoLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-tab=0"]
        app.launch()
        for title in ["Accounts", "Transactions", "Budgets", "Charts", "Settings"] {
            XCTAssertTrue(navExists(app, title), "missing nav \(title)")
        }
        XCTAssertTrue(app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(navExists(app, "Accounts"), "missing Accounts nav in landscape")
        XCTAssertTrue(app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(navExists(app, "Accounts"), "missing Accounts nav in portrait")
    }

    func testWalksEveryScreenAndButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-tab=0"]
        app.launch()

        // Accounts (initial tab): net worth, a seeded account row, add button + sheet.
        XCTAssertTrue(navExists(app, "Accounts"))
        XCTAssertTrue(app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["account.row.Checking"].waitForExistence(timeout: 5))
        let addAccount = app.buttons["account.add"]
        XCTAssertTrue(addAccount.waitForExistence(timeout: 5))
        addAccount.tap()
        XCTAssertTrue(app.textFields["account.nameField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["account.openingField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account.save"].waitForExistence(timeout: 5))
        let cancelAccount = app.buttons["Cancel"]
        XCTAssertTrue(cancelAccount.waitForExistence(timeout: 5))
        cancelAccount.tap()

        // Transactions: add button + sheet fields.
        tapNav(app, "Transactions")
        let addTx = app.buttons["tx.add"]
        XCTAssertTrue(addTx.waitForExistence(timeout: 10))
        addTx.tap()
        XCTAssertTrue(app.textFields["tx.amountField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["tx.noteField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tx.save"].waitForExistence(timeout: 5))
        let cancelTx = app.buttons["Cancel"]
        XCTAssertTrue(cancelTx.waitForExistence(timeout: 5))
        cancelTx.tap()

        // Budgets: month navigation actually changes the label, budget bars exist.
        tapNav(app, "Budgets")
        let monthLabel = app.staticTexts["budget.monthLabel"]
        XCTAssertTrue(monthLabel.waitForExistence(timeout: 10))
        let initialMonth = monthLabel.label
        let prevMonth = app.buttons["budget.prevMonth"]
        let nextMonth = app.buttons["budget.nextMonth"]
        XCTAssertTrue(prevMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(app.progressIndicators["budget.bar.Groceries"].waitForExistence(timeout: 5))
        prevMonth.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "identifier == 'budget.monthLabel' AND label != %@", initialMonth)
            ).firstMatch.waitForExistence(timeout: 5),
            "month label did not change after tapping prevMonth")
        nextMonth.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "identifier == 'budget.monthLabel' AND label == %@", initialMonth)
            ).firstMatch.waitForExistence(timeout: 5),
            "month label did not revert after tapping nextMonth")

        // Charts: all three chart containers.
        tapNav(app, "Charts")
        for id in ["charts.netWorth", "charts.categories", "charts.cashflow"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 10), "missing \(id)")
        }

        // Settings: data buttons and about text.
        tapNav(app, "Settings")
        for id in ["settings.demo", "settings.reset", "settings.exportButton"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), "missing \(id)")
        }
        XCTAssertTrue(app.staticTexts["settings.about"].waitForExistence(timeout: 5))

        // Round-trip back to Accounts.
        tapNav(app, "Accounts")
        XCTAssertTrue(app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 10))
    }
}

/// Attaches to an already-launched PocketLedger demo instance (`simctl launch ... -cfg=reset=1|demo=1|tab=0`)
/// and navigates to each of the 5 feature screens without terminating the app on teardown,
/// so synchronous foreground `xcrun simctl io <id> screenshot` captures each screen cleanly.
final class PocketLedgerScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(bundleIdentifier: "fr.dcreations.pocketledger")
        app.activate()
    }

    private func selectSection(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.waitForExistence(timeout: 1.5), tab.isHittable {
            tab.tap()
            return
        }
        let id = "tab.\(title.lowercased())"
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", id, title)
        let button = app.buttons.matching(predicate).firstMatch
        if !button.exists || !button.isHittable {
            let toggle = app.buttons.matching(
                NSPredicate(format: "identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar'")
            ).firstMatch
            if toggle.waitForExistence(timeout: 2), toggle.isHittable {
                toggle.tap()
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing nav item \(title)", file: file, line: line)
        button.tap()
    }

    func test1Accounts() throws {
        if !app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 4) {
            selectSection("Accounts")
        }
        XCTAssertTrue(app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["account.row.Checking"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test2Transactions() throws {
        selectSection("Transactions")
        XCTAssertTrue(app.buttons["tx.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'tx.row.'"))
                .firstMatch
                .waitForExistence(timeout: 10)
        )
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test3Budgets() throws {
        selectSection("Budgets")
        XCTAssertTrue(app.staticTexts["budget.monthLabel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.progressIndicators["budget.bar.Groceries"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test4Charts() throws {
        selectSection("Charts")
        for id in ["charts.netWorth", "charts.categories", "charts.cashflow"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 10), "missing \(id)")
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test5Export() throws {
        selectSection("Settings")
        let exportButton = app.buttons["settings.exportButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["settings.about"].waitForExistence(timeout: 10))
        if !app.descendants(matching: .any)["settings.export"].exists {
            exportButton.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["settings.export"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
    }
}
#elseif os(macOS)
final class PocketLedgerMacUITests: XCTestCase {
    func testSidebarAndNetWorthExist() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Saved window state left by an earlier killed run can hold zero windows;
        // AppKit then restores that instead of opening the WindowGroup window.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-demo", "-tab=0"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "no window opened at launch")
        // On macOS, sidebar List rows are static texts inside the outline, not buttons.
        for section in ["accounts", "transactions", "budgets", "charts", "settings"] {
            XCTAssertTrue(app.outlines.staticTexts["nav.\(section)"].waitForExistence(timeout: 10), "missing sidebar item \(section)")
        }
        XCTAssertTrue(app.staticTexts["accounts.netWorth"].waitForExistence(timeout: 10))
    }
}
#elseif os(watchOS)
final class PocketLedgerWatchUITests: XCTestCase {
    func testMonthTotalExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["watch.month.totalSpent"].waitForExistence(timeout: 10))
    }
}
#endif
