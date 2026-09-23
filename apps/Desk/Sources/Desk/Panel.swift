import CoreGraphics
import Foundation

enum Panel {
    private typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let configureDisplayEnabled: ConfigureDisplayEnabled? = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        for name in ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"] {
            if let symbol = dlsym(skyLight, name) { return unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self) }
        }
        return nil
    }()

    static var canSwitch: Bool { configureDisplayEnabled != nil }

    static func setEnabled(_ enabled: Bool, display id: CGDirectDisplayID) -> String {
        guard let configureDisplayEnabled else { return "no-display-control" }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { return "begin-failed-\(begin.rawValue)" }
        let set = configureDisplayEnabled(config, id, enabled)
        guard set == .success else {
            CGCancelDisplayConfiguration(config)
            return "set-failed-\(set.rawValue)"
        }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        return complete == .success ? "ok" : "complete-failed-\(complete.rawValue)"
    }
}
