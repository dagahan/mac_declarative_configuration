import AppKit
import Carbon
import CoreAudio
import IOKit
import LocalAuthentication

typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
let coreBrightnessPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

func emit(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

func displayList(_ getter: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError) -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    _ = getter(32, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

var onlineDisplays: [CGDirectDisplayID] { displayList(CGGetOnlineDisplayList) }
var activeDisplays: [CGDirectDisplayID] { displayList(CGGetActiveDisplayList) }

func isBuiltin(_ id: CGDirectDisplayID) -> Bool { CGDisplayIsBuiltin(id) != 0 }

let fallbackVendor: UInt32 = 0x756E_6B6E
let fallbackModel: UInt32 = 0x7669_7274

func isRealExternal(_ id: CGDirectDisplayID) -> Bool {
    CGDisplayIsOnline(id) != 0 && !isBuiltin(id) && CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
        && CGDisplaySerialNumber(id) != 0 && CGDisplayVendorNumber(id) != fallbackVendor && CGDisplayModelNumber(id) != fallbackModel
}

func screenNames() -> [CGDirectDisplayID: String] {
    var names: [CGDirectDisplayID: String] = [:]
    for screen in NSScreen.screens {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            names[number.uint32Value] = screen.localizedName
        }
    }
    return names
}

func describe(_ id: CGDirectDisplayID, names: [CGDirectDisplayID: String] = [:]) -> [String: Any] {
    let bounds = CGDisplayBounds(id)
    var info: [String: Any] = [
        "id": Int(id),
        "builtin": isBuiltin(id),
        "serial": Int(CGDisplaySerialNumber(id)),
        "vendor": Int(CGDisplayVendorNumber(id)),
        "model": Int(CGDisplayModelNumber(id)),
        "online": CGDisplayIsOnline(id) != 0,
        "active": CGDisplayIsActive(id) != 0,
        "asleep": CGDisplayIsAsleep(id) != 0,
        "main": CGDisplayIsMain(id) != 0,
        "mirrors": Int(CGDisplayMirrorsDisplay(id)),
        "real": isBuiltin(id) || isRealExternal(id),
        "x": Int(bounds.minX), "y": Int(bounds.minY), "w": Int(bounds.width), "h": Int(bounds.height),
    ]
    if let mode = CGDisplayCopyDisplayMode(id) { info["hz"] = mode.refreshRate }
    if let name = names[id] { info["name"] = name }
    return info
}

func snapshot(names: [CGDirectDisplayID: String] = [:]) -> [[String: Any]] {
    var ids = onlineDisplays
    for id in activeDisplays where !ids.contains(id) { ids.append(id) }
    return ids.map { describe($0, names: names) }
}

func letters(_ displays: [[String: Any]]) -> [String: String] {
    let usable = displays.filter { ($0["active"] as! Bool) && ($0["mirrors"] as! Int) == 0 }
    let sorted = usable.sorted { (($0["y"] as! Int), ($0["x"] as! Int)) < (($1["y"] as! Int), ($1["x"] as! Int)) }
    var rows: [[[String: Any]]] = []
    for display in sorted {
        let top = display["y"] as! Int
        let bottom = top + (display["h"] as! Int)
        let overlaps = { (other: [String: Any]) -> Bool in
            let otherTop = other["y"] as! Int
            return top < otherTop + (other["h"] as! Int) && otherTop < bottom
        }
        if let row = rows.firstIndex(where: { $0.contains(where: overlaps) }) {
            rows[row].append(display)
        } else {
            rows.append([display])
        }
    }
    let keys: [[Int: [String]]] = [
        [1: ["d"], 2: ["d", "f"], 3: ["s", "d", "f"], 4: ["s", "d", "f", "g"]],
        [1: ["c"], 2: ["c", "v"], 3: ["x", "c", "v"], 4: ["x", "c", "v", "b"]],
    ]
    var result: [String: String] = [:]
    for (index, row) in rows.enumerated() where index < keys.count {
        let ordered = row.sorted { ($0["x"] as! Int) < ($1["x"] as! Int) }
        guard let set = keys[index][ordered.count] else { continue }
        for (position, display) in ordered.enumerated() { result[String(display["serial"] as! Int)] = set[position] }
    }
    return result
}

func lidClosed() -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
}

func configureEnabled() -> ConfigureEnabledFn {
    let skyLight = dlopen(skyLightPath, RTLD_LAZY)
    for name in ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"] {
        if let symbol = dlsym(skyLight, name) { return unsafeBitCast(symbol, to: ConfigureEnabledFn.self) }
    }
    fail("no display-enable symbol")
}

func setPanel(_ id: CGDirectDisplayID, enabled: Bool, option: CGConfigureOption) -> [String: Any] {
    var config: CGDisplayConfigRef?
    let begin = CGBeginDisplayConfiguration(&config)
    guard begin == .success else { return ["begin": Int(begin.rawValue)] }
    let set = configureEnabled()(config, id, enabled)
    guard set == .success else {
        CGCancelDisplayConfiguration(config)
        return ["begin": 0, "set": Int(set.rawValue)]
    }
    let complete = CGCompleteDisplayConfiguration(config, option)
    return ["begin": 0, "set": 0, "complete": Int(complete.rawValue)]
}

func scope(_ name: String) -> CGConfigureOption {
    switch name {
        case "appOnly": .forAppOnly
        case "session": .forSession
        default: fail("scope must be appOnly or session")
    }
}

func panelState() -> [String: Any] {
    let displays = snapshot()
    let builtin = (onlineDisplays + activeDisplays).first(where: isBuiltin)
    var state: [String: Any] = [
        "displays": displays,
        "main": Int(CGMainDisplayID()),
        "lidClosed": lidClosed() as Any? ?? NSNull(),
    ]
    if let builtin {
        state["builtin"] = Int(builtin)
        state["active"] = activeDisplays.contains(builtin)
        state["online"] = onlineDisplays.contains(builtin)
    } else {
        state["active"] = false
    }
    return state
}

final class Keyboard {
    let client: NSObject

    init() {
        _ = dlopen(coreBrightnessPath, RTLD_LAZY)
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { fail("no KeyboardBrightnessClient") }
        client = type.init()
    }

    private func imp(_ name: String) -> IMP { class_getMethodImplementation(Swift.type(of: client), NSSelectorFromString(name))! }

    var ids: [UInt64] {
        typealias Fn = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
        let array = unsafeBitCast(imp("copyKeyboardBacklightIDs"), to: Fn.self)(client, NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() ?? []
        return array.compactMap { ($0 as? NSNumber)?.uint64Value }
    }

    func float(_ name: String, _ id: UInt64) -> Float {
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        return unsafeBitCast(imp(name), to: Fn.self)(client, NSSelectorFromString(name), id)
    }

    func double(_ name: String, _ id: UInt64) -> Double {
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Double
        return unsafeBitCast(imp(name), to: Fn.self)(client, NSSelectorFromString(name), id)
    }

    func bool(_ name: String, _ id: UInt64) -> Bool {
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        return unsafeBitCast(imp(name), to: Fn.self)(client, NSSelectorFromString(name), id)
    }

    func setBrightness(_ value: Float, _ id: UInt64) -> Bool {
        typealias Fn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        return unsafeBitCast(imp("setBrightness:forKeyboard:"), to: Fn.self)(client, NSSelectorFromString("setBrightness:forKeyboard:"), value, id)
    }

    func setAuto(_ on: Bool, _ id: UInt64) -> Bool {
        typealias Fn = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
        return unsafeBitCast(imp("enableAutoBrightness:forKeyboard:"), to: Fn.self)(client, NSSelectorFromString("enableAutoBrightness:forKeyboard:"), on, id)
    }

    func report() -> [[String: Any]] {
        ids.map { id in
            [
                "id": Int(id),
                "builtIn": bool("isKeyboardBuiltIn:", id),
                "brightness": float("brightnessForKeyboard:", id),
                "level": float("backlightLevelForKeyboard:", id),
                "auto": bool("isAutoBrightnessEnabledForKeyboard:", id),
                "idleDim": double("idleDimTimeForKeyboard:", id),
                "suppressed": bool("isBacklightSuppressedOnKeyboard:", id),
                "dimmed": bool("isBacklightDimmedOnKeyboard:", id),
            ]
        }
    }
}

func touchID(ask: Bool) -> [String: Any] {
    let context = LAContext()
    var error: NSError?
    let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    var result: [String: Any] = ["available": available, "biometry": context.biometryType.rawValue]
    if let error { result["error"] = error.code; result["message"] = error.localizedDescription }
    guard ask, available else { return result }
    let done = DispatchSemaphore(value: 0)
    var passed = false
    var askError: Int?
    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "test the fingerprint sensor for the monitor setup") { ok, err in
        passed = ok
        askError = (err as NSError?)?.code
        done.signal()
    }
    result["timeout"] = done.wait(timeout: .now() + 60) == .timedOut
    result["passed"] = passed
    if let askError { result["askError"] = askError }
    return result
}

func audioNumber(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : 0
}

func audioName(_ device: AudioObjectID) -> String {
    var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<CFString?>.size)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<CFString?>.alignment)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr,
          let name = buffer.load(as: Unmanaged<CFString>?.self) else { return "" }
    return name.takeRetainedValue() as String
}

func audioInputs() -> [[String: Any]] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices)
    return devices.compactMap { device in
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize)
        guard streamSize > 0 else { return nil }
        return [
            "id": Int(device),
            "name": audioName(device),
            "builtIn": audioNumber(device, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn,
            "alive": audioNumber(device, kAudioDevicePropertyDeviceIsAlive) != 0,
        ]
    }
}

func keyTable() {
    let keys: [(String, UInt16)] = [
        ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("5", 0x17), ("6", 0x16), ("7", 0x1A), ("8", 0x1C), ("9", 0x19), ("0", 0x1D),
        ("q", 0x0C), ("w", 0x0D), ("e", 0x0E), ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("g", 0x05),
        ("z", 0x06), ("x", 0x07), ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("p", 0x23), ("h", 0x04), ("j", 0x26), ("k", 0x28), ("l", 0x25),
    ]
    let layouts = ["com.apple.keylayout.ABC", "com.apple.keylayout.Russian"].map { id -> UnsafePointer<UCKeyboardLayout>? in
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        return UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
    }
    func translate(_ layout: UnsafePointer<UCKeyboardLayout>?, _ code: UInt16, _ modifiers: Int) -> String {
        guard let layout else { return "?" }
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let state = UInt32((modifiers >> 8) & 0xFF)
        UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), state, UInt32(LMGetKbdType()), 0, &dead, 4, &length, &chars)
        if dead != 0 {
            dead = 0
            UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), state, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &length, &chars)
            return String(utf16CodeUnits: chars, count: length) + "(dead)"
        }
        return String(utf16CodeUnits: chars, count: length)
    }
    print("key\tABC ⌥\tABC ⌥⇧\tRU\tRU ⌥\tRU ⌥⇧")
    for (name, code) in keys {
        let row = [
            translate(layouts[0], code, optionKey), translate(layouts[0], code, optionKey | shiftKey),
            translate(layouts[1], code, 0), translate(layouts[1], code, optionKey), translate(layouts[1], code, optionKey | shiftKey),
        ]
        print(([name] + row).joined(separator: "\t"))
    }
}

func apiReport() -> [String: Any] {
    let skyLight = dlopen(skyLightPath, RTLD_LAZY)
    _ = dlopen(coreBrightnessPath, RTLD_LAZY)
    var report: [String: Any] = [:]
    for name in ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"] { report[name] = dlsym(skyLight, name) != nil }
    report["KeyboardBrightnessClient"] = NSClassFromString("KeyboardBrightnessClient") != nil
    return report
}

final class EventLog {
    let fd: Int32

    init(_ path: String) {
        fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if fd < 0 { fail("cannot open \(path)") }
    }

    func write(_ event: String, _ extra: [String: Any] = [:]) {
        var object = extra
        object["ts"] = Date().timeIntervalSince1970
        object["ev"] = event
        var data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress, data.count) }
    }
}

var sharedLog: EventLog!

func flagNames(_ flags: CGDisplayChangeSummaryFlags) -> [String] {
    let names: [(CGDisplayChangeSummaryFlags, String)] = [
        (.beginConfigurationFlag, "begin"), (.movedFlag, "moved"), (.setMainFlag, "setMain"), (.setModeFlag, "setMode"),
        (.addFlag, "add"), (.removeFlag, "remove"), (.enabledFlag, "enabled"), (.disabledFlag, "disabled"),
        (.mirrorFlag, "mirror"), (.unMirrorFlag, "unmirror"), (.desktopShapeChangedFlag, "desktopShape"),
    ]
    return names.filter { flags.contains($0.0) }.map(\.1)
}

func runLogger(_ path: String) -> Never {
    sharedLog = EventLog(path)
    NSApplication.shared.setActivationPolicy(.prohibited)
    sharedLog.write("logger-start", ["displays": snapshot(), "lidClosed": lidClosed() as Any? ?? NSNull(), "main": Int(CGMainDisplayID())])
    CGDisplayRegisterReconfigurationCallback({ id, flags, _ in
        sharedLog.write("reconfig", ["display": Int(id), "flags": flagNames(flags), "builtin": CGDisplayIsBuiltin(id) != 0, "serial": Int(CGDisplaySerialNumber(id))])
    }, nil)
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.willSleepNotification,
                 NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification] {
        workspace.addObserver(forName: name, object: nil, queue: nil) { sharedLog.write("workspace", ["name": $0.name.rawValue]) }
    }
    for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: nil) {
            sharedLog.write("lock", ["name": $0.name.rawValue])
        }
    }
    var last = ""
    let stopFile = (path as NSString).deletingLastPathComponent + "/stop"
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        if FileManager.default.fileExists(atPath: stopFile) { sharedLog.write("logger-exit"); exit(0) }
        let state: [String: Any] = ["displays": snapshot(), "lidClosed": lidClosed() as Any? ?? NSNull(), "main": Int(CGMainDisplayID())]
        let signature = String(data: try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]), encoding: .utf8)!
        if signature != last {
            last = signature
            sharedLog.write("state", state)
        }
    }
    RunLoop.main.run()
    exit(0)
}

func readText(_ path: String) -> String? {
    (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func runWatchdog(_ dir: String, _ eventsPath: String, dry: Bool) -> Never {
    let log = EventLog(eventsPath)
    guard let builtin = readText(dir + "/builtin").flatMap(UInt32.init) else { fail("no builtin id in \(dir)") }
    var noExternalSince: Date?
    var holderGoneSince: Date?
    var disabledSince: Date?
    var lastAttempt = Date.distantPast
    log.write("watchdog-start", ["builtin": Int(builtin), "dry": dry])
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
        let now = Date()
        let active = activeDisplays
        let stop = FileManager.default.fileExists(atPath: dir + "/stop")
        if active.contains(builtin) {
            noExternalSince = nil
            holderGoneSince = nil
            disabledSince = nil
            if stop { log.write("watchdog-exit"); exit(0) }
            return
        }
        disabledSince = disabledSince ?? now
        let externals = onlineDisplays.filter(isRealExternal).count
        let grace = readText(dir + "/grace").flatMap(Double.init) ?? 0
        let holder = readText(dir + "/holder.pid").flatMap(Int32.init)
        var reason: String?
        if externals == 0 {
            noExternalSince = noExternalSince ?? now
            if now.timeIntervalSince(noExternalSince!) >= grace { reason = "no-externals" }
        } else {
            noExternalSince = nil
        }
        if let holder, kill(holder, 0) != 0 {
            holderGoneSince = holderGoneSince ?? now
            if now.timeIntervalSince(holderGoneSince!) >= 3 { reason = reason ?? "holder-gone" }
        } else {
            holderGoneSince = nil
        }
        if let beat = (try? FileManager.default.attributesOfItem(atPath: dir + "/heartbeat"))?[.modificationDate] as? Date,
           now.timeIntervalSince(beat) > 10 {
            reason = reason ?? "driver-gone"
        }
        if now.timeIntervalSince(disabledSince!) > 600 { reason = reason ?? "cap" }
        if stop { reason = reason ?? "stop" }
        guard let reason, now.timeIntervalSince(lastAttempt) > 2 else { return }
        lastAttempt = now
        if dry {
            log.write("watchdog-would-enable", ["reason": reason])
            return
        }
        if let holder, kill(holder, 0) == 0 { kill(holder, SIGKILL) }
        log.write("watchdog-enable", ["reason": reason, "result": setPanel(builtin, enabled: true, option: .forSession)])
    }
    RunLoop.main.run()
    exit(0)
}

let args = Array(CommandLine.arguments.dropFirst())
func arg(_ index: Int) -> String {
    guard index < args.count else { fail("missing argument \(index)") }
    return args[index]
}

switch args.first ?? "" {
    case "displays":
        let displays = snapshot(names: screenNames())
        emit(["displays": displays, "letters": letters(displays), "main": Int(CGMainDisplayID()), "lidClosed": lidClosed() as Any? ?? NSNull()])
    case "api":
        emit(apiReport())
    case "panel":
        switch arg(1) {
            case "state":
                emit(panelState())
            case "off":
                emit(setPanel(CGDirectDisplayID(arg(3))!, enabled: false, option: scope(arg(2))))
            case "on":
                emit(setPanel(CGDirectDisplayID(arg(2))!, enabled: true, option: .forSession))
            case "hold":
                let result = setPanel(CGDirectDisplayID(arg(3))!, enabled: false, option: scope(arg(2)))
                try! String(getpid()).write(toFile: arg(4), atomically: true, encoding: .utf8)
                emit(result.merging(["held": true, "pid": Int(getpid())]) { $1 })
                RunLoop.main.run()
            default:
                fail("panel state|off <scope> <id>|on <id>|hold <scope> <id> <pidfile>")
        }
    case "kbd":
        let keyboard = Keyboard()
        switch arg(1) {
            case "get":
                emit(keyboard.report())
            case "off":
                let saved = keyboard.report()
                try! JSONSerialization.data(withJSONObject: saved).write(to: URL(fileURLWithPath: arg(2)))
                emit(keyboard.ids.map { ["id": Int($0), "auto": keyboard.setAuto(false, $0), "brightness": keyboard.setBrightness(0, $0)] })
            case "restore":
                let saved = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arg(2)))) as! [[String: Any]]
                emit(saved.map { entry -> [String: Any] in
                    let id = UInt64(entry["id"] as! Int)
                    return ["id": Int(id), "brightness": keyboard.setBrightness(Float(entry["brightness"] as! Double), id), "auto": keyboard.setAuto(entry["auto"] as! Bool, id)]
                })
            default:
                fail("kbd get|off <file>|restore <file>")
        }
    case "touchid":
        emit(touchID(ask: arg(1) == "ask"))
    case "mic":
        emit(audioInputs())
    case "keys":
        keyTable()
    case "logger":
        runLogger(arg(1))
    case "watchdog":
        runWatchdog(arg(1), arg(2), dry: args.count > 3 && args[3] == "1")
    default:
        fail("probe displays|api|panel|kbd|touchid|mic|keys|logger|watchdog")
}
