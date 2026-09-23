import AppKit

final class Agent: NSObject {
    private enum Release: String {
        case requested
        case screenLocked = "screen-locked"
        case terminated
    }

    private let blocker = EventBlocker()
    private let pointers = PointerHold()
    private let hud = HUD()
    private let status = StatusFile()
    private var lastEvent = "started"
    private var pointerTimer: Timer?
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    private var isLocked: Bool { blocker.isActive }

    static func run() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Command.bundleIdentifier)
            .filter { $0.processIdentifier != getpid() }
        if let other = others.first {
            FileHandle.standardError.write(Data("InputLock is already running (pid \(other.processIdentifier))\n".utf8))
            exit(1)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let agent = Agent()
        agent.start()
        withExtendedLifetime(agent) { application.run() }
    }

    private func start() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(lockRequested), name: Command.lock.notificationName,
                                object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(unlockRequested), name: Command.unlock.notificationName,
                                object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"),
                                object: nil, suspensionBehavior: .deliverImmediately)

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(screenLocked), name: name, object: nil)
        }

        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in self?.terminate() }
            source.resume()
            signalSources.append(source)
        }

        Karabiner.setKeyboardLocked(false, report: status.record)
        status.record("started")
        publishStatus()
        watchPermissions()
    }

    @objc private func lockRequested() {
        lock()
    }

    @objc private func unlockRequested() {
        unlock(.requested)
    }

    @objc private func screenLocked() {
        unlock(.screenLocked)
    }

    private func lock() {
        guard !isLocked else {
            Karabiner.setKeyboardLocked(true, report: status.record)
            return
        }
        guard AXIsProcessTrusted() else {
            refuse("no-accessibility", "InputLock needs Accessibility in System Settings")
            return
        }
        guard CGPreflightListenEventAccess() else {
            CGRequestListenEventAccess()
            refuse("no-input-monitoring", "InputLock needs Input Monitoring in System Settings")
            return
        }
        guard blocker.start() else {
            refuse("tap-refused", "macOS refused the event tap")
            return
        }
        Karabiner.setKeyboardLocked(true, report: status.record)
        pointers.holdAll()
        pointerTimer = schedule(after: 1, repeats: true) { [weak self] in
            guard let self, self.pointers.holdAll() else { return }
            self.status.record("held \(self.pointers.names.joined(separator: ","))")
            self.publishStatus()
        }
        lastEvent = "locked"
        status.record("locked held=\(pointers.names.joined(separator: ","))")
        publishStatus()
        hud.show("Input locked", detail: "Right Shift + Delete to unlock")
    }

    private func unlock(_ release: Release, waitForKarabiner: Bool = false) {
        guard isLocked else { return }
        pointers.releaseAll()
        blocker.stop()
        pointerTimer?.invalidate()
        pointerTimer = nil
        Karabiner.setKeyboardLocked(false, wait: waitForKarabiner, report: status.record)
        lastEvent = "unlocked:\(release.rawValue)"
        status.record("unlocked reason=\(release.rawValue)")
        publishStatus()

        switch release {
        case .requested:
            hud.show("Input unlocked")
        case .screenLocked, .terminated:
            break
        }
    }

    private func refuse(_ reason: String, _ detail: String) {
        Karabiner.setKeyboardLocked(false, report: status.record)
        lastEvent = "refused:\(reason)"
        status.record("refused reason=\(reason)")
        publishStatus()
        hud.show("Can't lock input", detail: detail, for: 2.6)
    }

    private func terminate() {
        if isLocked {
            unlock(.terminated, waitForKarabiner: true)
        } else {
            Karabiner.setKeyboardLocked(false, wait: true)
        }
        status.record("stopped")
        exit(0)
    }

    private func publishStatus() {
        status.write([
            "pid": String(getpid()),
            "accessibility": String(AXIsProcessTrusted()),
            "input_monitoring": String(CGPreflightListenEventAccess()),
            "locked": String(isLocked),
            "held": pointers.names.joined(separator: ","),
            "last": lastEvent,
        ])
    }

    private func watchPermissions() {
        guard !(AXIsProcessTrusted() && CGPreflightListenEventAccess()) else { return }
        var reported = (AXIsProcessTrusted(), CGPreflightListenEventAccess())
        permissionTimer = schedule(after: 2, repeats: true) { [weak self] in
            guard let self else { return }
            let now = (AXIsProcessTrusted(), CGPreflightListenEventAccess())
            guard now != reported else { return }
            reported = now
            self.publishStatus()
            if now.0 && now.1 {
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    private func schedule(after interval: TimeInterval, repeats: Bool, _ body: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in body() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
