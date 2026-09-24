import AppKit

let usage = """
usage: mac desk <verb>
  on      light the laptop panel and keep it lit until a monitor cable changes
  off     switch the laptop panel off until a monitor cable changes
  toggle  on if it is off, off if it is on
  auto    hand the panel back: off while a monitor is attached, on when none is
  status  what the panel, the monitors and the agent are doing now

"""

let verb = CommandLine.arguments.dropFirst().first ?? ""

if verb == "agent" {
    Agent.run()
} else if let command = Command(rawValue: verb) {
    exit(command.run())
} else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
