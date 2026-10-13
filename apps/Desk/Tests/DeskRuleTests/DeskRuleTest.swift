import DeskRule
import XCTest

final class DeskRuleTest: XCTestCase {
    private let bothMonitors: Set<UInt32> = [3996, 39260]

    func testThePanelGoesOffOnlyAfterTheMonitorsSettle() {
        var rule = DeskRule()
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 10), .leaveAsIs)
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 11.4), .leaveAsIs)
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 11.5), .turnOff)
    }

    func testNoMonitorsMeansPanelOnAtOnceWhateverWasChosen() {
        var rule = DeskRule()
        XCTAssertTrue(rule.choose(panelOn: false, realMonitorSerials: bothMonitors))
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 1), .turnOff)
        XCTAssertEqual(rule.decide(realMonitorSerials: [], at: 2), .turnOn)
        XCTAssertNil(rule.manualPanelChoice)
    }

    func testAChoiceHoldsUntilTheSetOfMonitorsChanges() {
        var rule = DeskRule()
        _ = rule.decide(realMonitorSerials: bothMonitors, at: 0)
        XCTAssertTrue(rule.choose(panelOn: true, realMonitorSerials: bothMonitors))
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 100), .turnOn)
        XCTAssertEqual(rule.decide(realMonitorSerials: [3996], at: 101), .leaveAsIs)
        XCTAssertEqual(rule.decide(realMonitorSerials: [3996], at: 102.5), .turnOff)
    }

    func testAfterWakingThePanelStaysOnUntilTheMonitorsSettleEvenWhenOffWasChosen() {
        var rule = DeskRule()
        _ = rule.decide(realMonitorSerials: bothMonitors, at: 0)
        XCTAssertTrue(rule.choose(panelOn: false, realMonitorSerials: bothMonitors))
        rule.woke(at: 100)
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 100), .leaveAsIs)
        XCTAssertEqual(rule.decide(realMonitorSerials: [], at: 100.4), .turnOn)
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 101.4), .leaveAsIs)
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 102.9), .turnOff)
    }

    func testTurningThePanelOffWithNoMonitorIsRefused() {
        var rule = DeskRule()
        XCTAssertFalse(rule.choose(panelOn: false, realMonitorSerials: []))
        XCTAssertEqual(rule.decide(realMonitorSerials: [], at: 0), .turnOn)
    }

    func testAutomaticForgetsTheChoice() {
        var rule = DeskRule()
        _ = rule.decide(realMonitorSerials: bothMonitors, at: 0)
        XCTAssertTrue(rule.choose(panelOn: true, realMonitorSerials: bothMonitors))
        rule.forgetManualChoice()
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 5), .turnOff)
    }

    func testNoMonitorsAtLaunchMeansPanelOn() {
        var rule = DeskRule()
        XCTAssertEqual(rule.decide(realMonitorSerials: [], at: 0), .turnOn)
    }

    func testTheStandInDisplayIsNotAMonitor() {
        let standIn = DisplayFacts(
            id: 9, serial: 0, vendor: DisplayFacts.standInVendor, model: DisplayFacts.standInModel,
            isBuiltin: false, isOnline: true, mirrorsAnotherDisplay: false
        )
        let standInWithASerial = DisplayFacts(
            id: 9, serial: 77, vendor: DisplayFacts.standInVendor, model: DisplayFacts.standInModel,
            isBuiltin: false, isOnline: true, mirrorsAnotherDisplay: false
        )
        XCTAssertEqual(realMonitorSerials([standIn, standInWithASerial]), [])
        var rule = DeskRule()
        XCTAssertEqual(rule.decide(realMonitorSerials: realMonitorSerials([standIn]), at: 0), .turnOn)
    }

    func testMonitorsThatLeftDuringSleepLightThePanelOnTheFirstLookAfterWaking() {
        var rule = DeskRule()
        _ = rule.decide(realMonitorSerials: bothMonitors, at: 0)
        XCTAssertEqual(rule.decide(realMonitorSerials: bothMonitors, at: 2), .turnOff)
        XCTAssertEqual(rule.decide(realMonitorSerials: [], at: 30_000), .turnOn)
    }
}
