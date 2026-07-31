// Which processes can see, delay or swallow your keystrokes.
//
// A CGEventTap in `.defaultTap` mode sits in front of every hotkey in the
// system: it can consume an event before Carbon or any app ever sees it. When a
// hotkey "stops working" with no error anywhere, this is the first thing to look
// at — the answer is a process name, not a theory.
import CoreGraphics
import Darwin
import Foundation

var count: UInt32 = 0
CGGetEventTapList(0, nil, &count)
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
CGGetEventTapList(count, &taps, &count)

let keyMask = (UInt64(1) << CGEventType.keyDown.rawValue)
    | (UInt64(1) << CGEventType.keyUp.rawValue)
    | (UInt64(1) << CGEventType.flagsChanged.rawValue)

func name(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    proc_pidpath(pid, &buf, 4096)
    let p = String(cString: buf)
    return p.isEmpty ? "pid \(pid)" : (p as NSString).lastPathComponent
}

var found = false
print("  process              pid      enabled  mode         watches")
for t in taps.prefix(Int(count)) where (t.eventsOfInterest & keyMask) != 0 {
    found = true
    var w: [String] = []
    if t.eventsOfInterest & (1 << CGEventType.keyDown.rawValue) != 0 { w.append("keyDown") }
    if t.eventsOfInterest & (1 << CGEventType.keyUp.rawValue) != 0 { w.append("keyUp") }
    if t.eventsOfInterest & (1 << CGEventType.flagsChanged.rawValue) != 0 { w.append("modifiers") }
    print("  " + name(t.tappingProcess).padding(toLength: 20, withPad: " ", startingAt: 0)
        + " \(t.tappingProcess)".padding(toLength: 8, withPad: " ", startingAt: 0)
        + " \(t.enabled ? "yes" : "NO ")".padding(toLength: 8, withPad: " ", startingAt: 0)
        + " \(t.options == .defaultTap ? "CONSUMES" : "listen  ")".padding(toLength: 12, withPad: " ", startingAt: 0)
        + " " + w.joined(separator: ","))
}
if !found { print("  (no process is tapping the keyboard)") }
