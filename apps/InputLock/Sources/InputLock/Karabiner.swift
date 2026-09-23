import Foundation

// Karabiner holds the keyboard: its rules read this variable, and nothing
// downstream of Karabiner — hotkeys included — ever sees a key while it is 1.
enum Karabiner {
    static let cli = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
    static let variable = "inputlock_locked"

    static func setKeyboardLocked(_ locked: Bool, wait: Bool = false, report: ((String) -> Void)? = nil) {
        let value = locked ? 1 : 0
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["--set-variables", "{\"\(variable)\":\(value)}"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            report?("karabiner \(variable)=\(value) exit=\(finished.terminationStatus)")
        }
        do {
            try process.run()
        } catch {
            report?("karabiner \(variable)=\(value) unavailable")
            return
        }
        if wait { process.waitUntilExit() }
    }
}
