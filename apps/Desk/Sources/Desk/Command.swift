import AppKit
import DeskRule

enum Command: String, CaseIterable {
    case on
    case off
    case toggle
    case auto
    case status
    case rescue

    static let notificationPrefix = "com.mac-setup.desk"
    static let sentToAgent: [Command] = [.on, .off, .toggle, .auto]

    var notificationName: Notification.Name {
        Notification.Name("\(Command.notificationPrefix).\(rawValue)")
    }

    private static let agentLabel = "com.mac-setup.desk"
    private static let agentStartSeconds: TimeInterval = 3

    private var agentIsRunning: Bool { DeskState().agentIsRunning }

    func run() -> Int32 {
        switch self {
            case .status:
                printStatus()
                return 0
            case .rescue:
                return rescuePanelThroughTheAgent()
            case .on, .off, .toggle, .auto:
                guard agentIsRunning || startAgent(replacingARunningOne: false) else {
                    FileHandle.standardError.write(Data("the desk agent did not start — mac workspace up loads it\n".utf8))
                    return 1
                }
                DistributedNotificationCenter.default().postNotificationName(
                    notificationName, object: nil, userInfo: nil, deliverImmediately: true
                )
                return 0
        }
    }

    private func rescuePanelThroughTheAgent() -> Int32 {
        let displays = Displays.online()
        guard !displays.contains(where: \.isBuiltin), realMonitorSerials(displays).isEmpty else { return 0 }
        DeskState().record("rescue agent=\(agentIsRunning ? "restarted" : "started")")
        return startAgent(replacingARunningOne: true) ? 0 : 1
    }

    private func startAgent(replacingARunningOne: Bool) -> Bool {
        let job = "gui/\(getuid())/\(Command.agentLabel)"
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mac_setup/launchd/\(Command.agentLabel).plist").path
        if !launchctl(["kickstart"] + (replacingARunningOne ? ["-k"] : []) + [job]) {
            _ = launchctl(["bootstrap", "gui/\(getuid())", plist])
        }
        let deadline = Date().addingTimeInterval(Command.agentStartSeconds)
        while !agentIsListening, Date() < deadline { usleep(50000) }
        return agentIsListening
    }

    private func launchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private var agentIsListening: Bool {
        guard agentIsRunning, let status = DeskState().readStatus() else { return false }
        let pid = status.split(separator: "\n").first { $0.hasPrefix("pid=") }.flatMap { pid_t($0.dropFirst(4)) }
        return pid.map { kill($0, 0) == 0 } ?? false
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
