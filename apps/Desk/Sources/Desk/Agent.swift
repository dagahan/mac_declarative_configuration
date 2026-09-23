import AppKit
import DeskRule

final class Agent: NSObject {
    private static let evaluationInterval: DispatchTimeInterval = .milliseconds(100)
    private static let retryAfterSeconds: TimeInterval = 2

    private let queue = DispatchQueue(label: "com.mac-setup.desk.rule")
    private let panelSwitch = PanelSwitch()
    private var rule = DeskRule()
    private var evaluationTimer: DispatchSourceTimer?
    private var lastAttempt: [Bool: Date] = [:]
    private var lastEvent = "started"
    private var publishedStatus = ""
    private var signalSources: [DispatchSourceSignal] = []
    private var rememberedPanelId: UInt32?

    static func run() {
        guard let agentLock = DeskState().takeAgentLock() else {
            FileHandle.standardError.write(Data("Desk is already running\n".utf8))
            exit(1)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let agent = Agent()
        agent.start()
        withExtendedLifetime((agent, agentLock)) { application.run() }
    }

    private func start() {
        for command in Command.sentToAgent {
            DistributedNotificationCenter.default().addObserver(
                forName: command.notificationName, object: nil, queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.handle(command) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.panelSwitch.keepKeyboardDarkWhilePanelIsOff() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.evaluate() }
        }
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in self?.stop() }
            source.resume()
            signalSources.append(source)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.evaluationInterval)
        timer.setEventHandler { [weak self] in self?.evaluate() }
        if Displays.online().contains(where: \.isBuiltin) { panelSwitch.giveTheKeyboardItsLightBack() }
        timer.resume()
        evaluationTimer = timer
        panelSwitch.state.record("started display-control=\(Panel.canSwitch ? "available" : "missing")")
    }

    private func evaluate() {
        let displays = Displays.online()
        let panel = displays.first(where: \.isBuiltin)
        if let panel, panel.id != rememberedPanelId {
            panelSwitch.state.rememberPanelId(panel.id)
            rememberedPanelId = panel.id
        }
        let monitors = realMonitorSerials(displays)
        switch rule.decide(realMonitorSerials: monitors, at: Date().timeIntervalSinceReferenceDate) {
            case .turnOn where panel == nil && mayTry(panelOn: true):
                panelSwitch.turnPanelOn(because: monitors.isEmpty ? "no-monitors" : "chosen")
                lastEvent = "panel-on"
            case .turnOff where panel != nil && Panel.canSwitch && mayTry(panelOn: false):
                panelSwitch.turnPanelOff(panel!, because: rule.manualPanelChoice == false ? "chosen" : "monitors-settled")
                lastEvent = "panel-off"
            default:
                break
        }
        publishStatus(panelOn: panel != nil, monitors: monitors)
    }

    private func mayTry(panelOn: Bool) -> Bool {
        let now = Date()
        if let last = lastAttempt[panelOn], now.timeIntervalSince(last) < Self.retryAfterSeconds { return false }
        lastAttempt[panelOn] = now
        return true
    }

    private func handle(_ command: Command) {
        let displays = Displays.online()
        let monitors = realMonitorSerials(displays)
        let panelIsOn = displays.contains(where: \.isBuiltin)
        switch command {
            case .on:
                _ = rule.choose(panelOn: true, realMonitorSerials: monitors)
            case .off:
                if !rule.choose(panelOn: false, realMonitorSerials: monitors) { refuseOff() }
            case .toggle:
                if !rule.choose(panelOn: !panelIsOn, realMonitorSerials: monitors) { refuseOff() }
            case .auto:
                rule.forgetManualChoice()
            case .status, .rescue:
                break
        }
        lastAttempt = [:]
        panelSwitch.state.record("command \(command.rawValue)")
        evaluate()
    }

    private func refuseOff() {
        lastEvent = "refused-off-no-monitors"
        panelSwitch.state.record("refused off: no monitor is connected")
    }

    private func stop() {
        evaluationTimer?.cancel()
        if !Displays.online().contains(where: \.isBuiltin) {
            panelSwitch.turnPanelOn(because: "desk-stopped")
        }
        panelSwitch.state.record("stopped")
        publishStatus(panelOn: true, monitors: realMonitorSerials(Displays.online()), agentRunning: false)
        exit(0)
    }

    private func publishStatus(panelOn: Bool, monitors: Set<UInt32>, agentRunning: Bool = true) {
        let choice = rule.manualPanelChoice.map { $0 ? "on" : "off" } ?? "automatic"
        let fields: KeyValuePairs<String, String> = [
            "pid": agentRunning ? String(getpid()) : "",
            "display_control": Panel.canSwitch ? "available" : "missing",
            "panel": panelOn ? "on" : "off",
            "monitors": monitors.sorted().map(String.init).joined(separator: ","),
            "choice": choice,
            "last": lastEvent,
        ]
        let rendered = fields.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        guard rendered != publishedStatus else { return }
        publishedStatus = rendered
        panelSwitch.state.writeStatus(fields)
    }
}
