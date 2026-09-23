public struct DisplayFacts: Equatable {
    public let id: UInt32
    public let serial: UInt32
    public let vendor: UInt32
    public let model: UInt32
    public let isBuiltin: Bool
    public let isOnline: Bool
    public let mirrorsAnotherDisplay: Bool

    public init(id: UInt32, serial: UInt32, vendor: UInt32, model: UInt32, isBuiltin: Bool, isOnline: Bool, mirrorsAnotherDisplay: Bool) {
        self.id = id
        self.serial = serial
        self.vendor = vendor
        self.model = model
        self.isBuiltin = isBuiltin
        self.isOnline = isOnline
        self.mirrorsAnotherDisplay = mirrorsAnotherDisplay
    }

    public static let standInVendor: UInt32 = 0x756E_6B6E
    public static let standInModel: UInt32 = 0x7669_7274

    public var isStandIn: Bool { vendor == Self.standInVendor || model == Self.standInModel }

    public var isRealMonitor: Bool {
        isOnline && !isBuiltin && !mirrorsAnotherDisplay && serial != 0 && !isStandIn
    }
}

public func realMonitorSerials(_ displays: [DisplayFacts]) -> Set<UInt32> {
    Set(displays.filter(\.isRealMonitor).map(\.serial))
}
