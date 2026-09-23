import DeskRule
import Foundation
import XCTest

private struct RecordedDisplays {
    let secondsSinceStart: TimeInterval
    let realMonitors: Set<UInt32>
}

private func recordedSession() throws -> [RecordedDisplays] {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "undock-session", withExtension: "jsonl"))
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    let events = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    let start = try XCTUnwrap(events.first?["ts"] as? Double)
    return events.filter { $0["ev"] as? String == "state" }.map { event in
        let displays = (event["displays"] as? [[String: Any]] ?? []).map { display in
            DisplayFacts(
                id: UInt32(display["id"] as? Int ?? 0),
                serial: UInt32(display["serial"] as? Int ?? 0),
                vendor: UInt32(display["vendor"] as? Int ?? 0),
                model: UInt32(display["model"] as? Int ?? 0),
                isBuiltin: display["builtin"] as? Bool ?? false,
                isOnline: display["online"] as? Bool ?? false,
                mirrorsAnotherDisplay: (display["mirrors"] as? Int ?? 0) != 0,
            )
        }
        return RecordedDisplays(secondsSinceStart: (event["ts"] as! Double) - start, realMonitors: realMonitorSerials(displays))
    }
}

private struct PanelChange: Equatable, CustomStringConvertible {
    let at: TimeInterval
    let panelOn: Bool
    var description: String { "\(panelOn ? "on" : "off") at \(String(format: "%.1f", at))" }
}

private func replay(
    _ session: [RecordedDisplays],
    manualChoices: [TimeInterval: Bool] = [:],
    refusedChoices: inout [TimeInterval],
) -> [PanelChange] {
    var rule = DeskRule()
    var panelOn = true
    var changes: [PanelChange] = []
    let end = (session.last?.secondsSinceStart ?? 0) + 5
    for tick in stride(from: 0, through: Int(end * 10), by: 1) {
        let now = TimeInterval(tick) / 10
        let monitors = session.last { $0.secondsSinceStart <= now }?.realMonitors ?? []
        if let choice = manualChoices.first(where: { abs($0.key - now) < 0.05 }) {
            if !rule.choose(panelOn: choice.value, realMonitorSerials: monitors) { refusedChoices.append(now) }
        }
        switch rule.decide(realMonitorSerials: monitors, at: now) {
            case .turnOn where !panelOn:
                panelOn = true
                changes.append(PanelChange(at: now, panelOn: true))
            case .turnOff where panelOn:
                panelOn = false
                changes.append(PanelChange(at: now, panelOn: false))
            default:
                break
        }
    }
    return changes
}

final class RecordedSessionReplayTest: XCTestCase {
    func testTheRuleOnTheRecordedDeskSession() throws {
        var refused: [TimeInterval] = []
        let changes = replay(try recordedSession(), refusedChoices: &refused)
        XCTAssertEqual(changes, [
            PanelChange(at: 1.7, panelOn: false),
            PanelChange(at: 226.7, panelOn: true),
            PanelChange(at: 249.2, panelOn: false),
            PanelChange(at: 259.0, panelOn: true),
            PanelChange(at: 267.6, panelOn: false),
        ])
    }

    func testAManualOnHoldsUntilTheMonitorsChangeAndAManualOffWithNoMonitorsIsRefused() throws {
        var refused: [TimeInterval] = []
        let changes = replay(try recordedSession(), manualChoices: [60: true, 230: false], refusedChoices: &refused)
        XCTAssertEqual(changes, [
            PanelChange(at: 1.7, panelOn: false),
            PanelChange(at: 60, panelOn: true),
            PanelChange(at: 224.0, panelOn: false),
            PanelChange(at: 226.7, panelOn: true),
            PanelChange(at: 249.2, panelOn: false),
            PanelChange(at: 259.0, panelOn: true),
            PanelChange(at: 267.6, panelOn: false),
        ])
        XCTAssertEqual(refused, [230])
    }

    func testSleepingMonitorsStillCount() throws {
        let asleep = try recordedSession().filter { $0.secondsSinceStart > 201 && $0.secondsSinceStart < 205 }
        XCTAssertFalse(asleep.isEmpty)
        XCTAssertTrue(asleep.allSatisfy { $0.realMonitors == [3996, 39260] })
    }

    func testTheStandInIsNoMonitor() {
        let standIn = DisplayFacts(id: 18, serial: 0, vendor: DisplayFacts.standInVendor, model: DisplayFacts.standInModel, isBuiltin: false, isOnline: true, mirrorsAnotherDisplay: false)
        XCTAssertEqual(realMonitorSerials([standIn]), [])
    }
}
