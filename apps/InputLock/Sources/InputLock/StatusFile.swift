import Foundation

// mac_setup's manual permission step and its tests read this; the agent is the
// only process whose Accessibility grant is the one that matters.
struct StatusFile {
    let directory: URL = {
        let stateHome = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return stateHome.appendingPathComponent("mac_setup/inputlock")
    }()

    func write(_ fields: KeyValuePairs<String, String>) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let body = fields.map { "\($0.key)=\($0.value)\n" }.joined()
        try? body.write(to: directory.appendingPathComponent("status"), atomically: true, encoding: .utf8)
    }

    func record(_ event: String) {
        let line = "\(Int(Date().timeIntervalSince1970)) \(event)\n"
        let url = directory.appendingPathComponent("events.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
