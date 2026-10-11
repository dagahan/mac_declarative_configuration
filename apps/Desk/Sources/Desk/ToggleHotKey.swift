import Carbon.HIToolbox

enum ToggleHotKey {
    private static var whenPressed: (() -> Void)?

    static func register(whenPressed: @escaping () -> Void) -> Bool {
        self.whenPressed = whenPressed
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            ToggleHotKey.whenPressed?()
            return noErr
        }, 1, &pressed, nil, nil)
        var registration: EventHotKeyRef?
        let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)
        let identity = EventHotKeyID(signature: OSType(0x6465_736B), id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_L), controlOptionCommand, identity, GetEventDispatcherTarget(), 0, &registration) == noErr
    }
}
