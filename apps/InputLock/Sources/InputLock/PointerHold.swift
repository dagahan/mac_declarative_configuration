import Foundation
import IOKit.hid

// Device matching and exclusive opening are adapted from CleanMyScreen's
// SystemHIDDeviceBlocker (MIT, see LICENSE-CleanMyScreen). WindowServer moves
// the cursor before any event tap runs, so only holding the device stops it.
final class PointerHold {
    private var held: [UInt64: (device: IOHIDDevice, name: String)] = [:]

    var names: [String] { held.values.map(\.name).sorted() }

    @discardableResult
    func holdAll() -> Bool {
        var changed = false
        for device in Self.pointingDevices() {
            let id = Self.registryID(of: device)
            let name = Self.name(of: device)
            guard held[id] == nil, !name.localizedCaseInsensitiveContains("karabiner") else { continue }
            if IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess {
                held[id] = (device, name)
                changed = true
            }
        }
        return changed
    }

    func releaseAll() {
        for entry in held.values {
            IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        held.removeAll()
    }

    private static func pointingDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }
        return (devices as Set).map { $0 as! IOHIDDevice }
    }

    private static func registryID(of device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    private static func name(of device: IOHIDDevice) -> String {
        IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "pointing device"
    }
}
