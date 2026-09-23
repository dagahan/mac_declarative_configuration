import AppKit
import DeskRule

enum Command: String, CaseIterable {
    case on
    case off
    case toggle
    case auto
    case status
    case rescue

    static let bundleIdentifier = "com.mac-setup.desk"
    static let sentToAgent: [Command] = [.on, .off, .toggle, .auto]

    var notificationName: Notification.Name {
        Notification.Name("\(Command.bundleIdentifier).\(rawValue)")
    }

    private var agentIsRunning: Bool { DeskState().agentIsRunning }

    func run() -> Int32 {
        switch self {
            case .status:
                printStatus()
                return 0
            case .rescue:
                rescuePanelIfNothingElseCan()
                return 0
            case .on, .off, .toggle, .auto:
                if agentIsRunning {
                    DistributedNotificationCenter.default().postNotificationName(
                        notificationName, object: nil, userInfo: nil, deliverImmediately: true
                    )
                    return 0
                }
                return runWithoutAgent()
        }
    }

    private func runWithoutAgent() -> Int32 {
        let panelIsOn = Displays.online().contains(where: \.isBuiltin)
        let turnsThePanelOn = self == .on || (self == .toggle && !panelIsOn)
        guard turnsThePanelOn else {
            FileHandle.standardError.write(Data("Desk is not running — only turning the panel on works without it; mac workspace up starts it\n".utf8))
            return 1
        }
        PanelSwitch().turnPanelOn(because: "\(rawValue)-without-agent")
        return 0
    }

    private func rescuePanelIfNothingElseCan() {
        let displays = Displays.online()
        guard !displays.contains(where: \.isBuiltin), realMonitorSerials(displays).isEmpty else { return }
        PanelSwitch().turnPanelOn(because: "rescue")
    }

    private func printStatus() {
        let displays = Displays.online()
        let state = DeskState()
        print("agent=\(agentIsRunning ? "running" : "stopped")")
        print("panel_now=\(displays.contains(where: \.isBuiltin) ? "on" : "off")")
        print("monitors_now=\(realMonitorSerials(displays).sorted().map(String.init).joined(separator: ","))")
        if let status = state.readStatus() {
            print(status.split(separator: "\n").map { "agent_\($0)" }.joined(separator: "\n"))
        }
    }
}
