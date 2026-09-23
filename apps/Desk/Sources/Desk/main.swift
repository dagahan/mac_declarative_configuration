import AppKit

let argument = CommandLine.arguments.dropFirst().first

if argument == nil || argument!.hasPrefix("-") {
    Agent.run()
} else if let command = Command(rawValue: argument!) {
    exit(command.run())
} else {
    FileHandle.standardError.write(Data("usage: Desk [on | off | toggle | auto | status | rescue]\n".utf8))
    exit(2)
}
