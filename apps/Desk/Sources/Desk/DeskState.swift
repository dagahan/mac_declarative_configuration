import Foundation

struct DeskState {
    let directory: URL = {
        let stateHome = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return stateHome.appendingPathComponent("mac_setup/desk")
    }()

    private var statusFile: URL { directory.appendingPathComponent("status") }
    private var eventsFile: URL { directory.appendingPathComponent("events.log") }
    private var panelIdFile: URL { directory.appendingPathComponent("panel-id") }
    private var keyboardBeforeDeskFile: URL { directory.appendingPathComponent("keyboard-before-desk.json") }
    private var agentLockFile: URL { directory.appendingPathComponent("agent.lock") }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeStatus(_ fields: KeyValuePairs<String, String>) {
        ensureDirectory()
        let body = fields.map { "\($0.key)=\($0.value)\n" }.joined()
        try? body.write(to: statusFile, atomically: true, encoding: .utf8)
    }

    func readStatus() -> String? {
        try? String(contentsOf: statusFile, encoding: .utf8)
    }

    func record(_ event: String) {
        ensureDirectory()
        let line = "\(String(format: "%.1f", Date().timeIntervalSince1970)) \(event)\n"
        if let handle = try? FileHandle(forWritingTo: eventsFile) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: eventsFile, atomically: true, encoding: .utf8)
        }
    }

    var panelId: UInt32? {
        (try? String(contentsOf: panelIdFile, encoding: .utf8)).flatMap { UInt32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func rememberPanelId(_ id: UInt32) {
        guard panelId != id else { return }
        ensureDirectory()
        try? String(id).write(to: panelIdFile, atomically: true, encoding: .utf8)
    }

    var keyboardBeforeDesk: [KeyboardLightSetting]? {
        (try? Data(contentsOf: keyboardBeforeDeskFile)).flatMap { try? JSONDecoder().decode([KeyboardLightSetting].self, from: $0) }
    }

    func rememberKeyboardBeforeDesk(_ settings: [KeyboardLightSetting]) {
        ensureDirectory()
        try? JSONEncoder().encode(settings).write(to: keyboardBeforeDeskFile, options: .atomic)
    }

    func forgetKeyboardBeforeDesk() {
        try? FileManager.default.removeItem(at: keyboardBeforeDeskFile)
    }

    func takeAgentLock() -> Int32? {
        ensureDirectory()
        let descriptor = open(agentLockFile.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
        close(descriptor)
        return nil
    }

    var agentIsRunning: Bool {
        guard let descriptor = takeAgentLock() else { return true }
        close(descriptor)
        return false
    }
}
