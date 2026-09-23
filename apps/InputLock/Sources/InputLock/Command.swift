import AppKit

enum Command: String {
    case lock
    case unlock

    static let bundleIdentifier = "com.mac-setup.inputlock"

    var notificationName: Notification.Name {
        Notification.Name("\(Command.bundleIdentifier).\(rawValue)")
    }

    func send() -> Int32 {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Command.bundleIdentifier).isEmpty else {
            Karabiner.setKeyboardLocked(false, wait: true)
            FileHandle.standardError.write(Data("InputLock is not running — keyboard released; mac workspace up starts it\n".utf8))
            return 1
        }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil, userInfo: nil, deliverImmediately: true
        )
        return 0
    }
}
