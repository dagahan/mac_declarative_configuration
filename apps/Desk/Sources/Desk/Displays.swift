import CoreGraphics
import DeskRule

enum Displays {
    static func online() -> [DisplayFacts] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            DisplayFacts(
                id: id,
                serial: CGDisplaySerialNumber(id),
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isOnline: CGDisplayIsOnline(id) != 0,
                mirrorsAnotherDisplay: CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay,
            )
        }
    }
}
