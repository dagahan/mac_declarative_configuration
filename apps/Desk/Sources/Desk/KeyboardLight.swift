import Foundation

struct KeyboardLightSetting: Codable, Equatable {
    let id: UInt64
    let brightness: Float
    let auto: Bool
}

final class KeyboardLight {
    private let client: NSObject?

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        client = (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }

    private func implementation(_ selectorName: String) -> (NSObject, Selector, IMP)? {
        let selector = NSSelectorFromString(selectorName)
        guard let client, client.responds(to: selector), let imp = class_getMethodImplementation(type(of: client), selector) else { return nil }
        return (client, selector, imp)
    }

    private var keyboardIds: [UInt64] {
        typealias Call = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
        guard let (client, selector, imp) = implementation("copyKeyboardBacklightIDs") else { return [] }
        let ids = unsafeBitCast(imp, to: Call.self)(client, selector)?.takeRetainedValue() ?? []
        return ids.compactMap { ($0 as? NSNumber)?.uint64Value }
    }

    private func brightness(_ id: UInt64) -> Float? {
        typealias Call = @convention(c) (AnyObject, Selector, UInt64) -> Float
        guard let (client, selector, imp) = implementation("brightnessForKeyboard:") else { return nil }
        return unsafeBitCast(imp, to: Call.self)(client, selector, id)
    }

    private func isAuto(_ id: UInt64) -> Bool? {
        typealias Call = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        guard let (client, selector, imp) = implementation("isAutoBrightnessEnabledForKeyboard:") else { return nil }
        return unsafeBitCast(imp, to: Call.self)(client, selector, id)
    }

    private func setBrightness(_ value: Float, _ id: UInt64) {
        typealias Call = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        guard let (client, selector, imp) = implementation("setBrightness:forKeyboard:") else { return }
        _ = unsafeBitCast(imp, to: Call.self)(client, selector, value, id)
    }

    private func setAuto(_ on: Bool, _ id: UInt64) {
        typealias Call = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
        guard let (client, selector, imp) = implementation("enableAutoBrightness:forKeyboard:") else { return }
        _ = unsafeBitCast(imp, to: Call.self)(client, selector, on, id)
    }

    func current() -> [KeyboardLightSetting] {
        keyboardIds.compactMap { id in
            guard let brightness = brightness(id), let auto = isAuto(id) else { return nil }
            return KeyboardLightSetting(id: id, brightness: brightness, auto: auto)
        }
    }

    func turnOff() {
        for id in keyboardIds {
            setAuto(false, id)
            setBrightness(0, id)
        }
    }

    func apply(_ settings: [KeyboardLightSetting]) {
        for setting in settings {
            setBrightness(setting.brightness, setting.id)
            setAuto(setting.auto, setting.id)
        }
    }
}
