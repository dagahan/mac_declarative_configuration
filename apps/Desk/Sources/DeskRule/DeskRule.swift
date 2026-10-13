import Foundation

public enum PanelDecision: Equatable {
    case turnOn
    case turnOff
    case leaveAsIs
}

public struct DeskRule {
    public static let monitorsSettleSeconds: TimeInterval = 1.5

    private struct ManualChoice {
        let panelOn: Bool
        let madeWithMonitors: Set<UInt32>
    }

    private var monitors: Set<UInt32> = []
    private var monitorsUnchangedSince: TimeInterval = 0
    private var manualChoice: ManualChoice?
    private var panelStaysOnUntil: TimeInterval = 0

    public init() {}

    public var manualPanelChoice: Bool? { manualChoice?.panelOn }

    public mutating func decide(realMonitorSerials: Set<UInt32>, at now: TimeInterval) -> PanelDecision {
        if realMonitorSerials != monitors {
            monitors = realMonitorSerials
            monitorsUnchangedSince = now
            if manualChoice?.madeWithMonitors != realMonitorSerials { manualChoice = nil }
        }
        if realMonitorSerials.isEmpty { return .turnOn }
        if let manualChoice, manualChoice.panelOn { return .turnOn }
        if now < panelStaysOnUntil { return .leaveAsIs }
        if manualChoice != nil { return .turnOff }
        return now - monitorsUnchangedSince >= Self.monitorsSettleSeconds ? .turnOff : .leaveAsIs
    }

    public mutating func woke(at now: TimeInterval) {
        panelStaysOnUntil = now + Self.monitorsSettleSeconds
    }

    public mutating func choose(panelOn: Bool, realMonitorSerials: Set<UInt32>) -> Bool {
        if !panelOn && realMonitorSerials.isEmpty { return false }
        manualChoice = ManualChoice(panelOn: panelOn, madeWithMonitors: realMonitorSerials)
        return true
    }

    public mutating func forgetManualChoice() {
        manualChoice = nil
    }
}
