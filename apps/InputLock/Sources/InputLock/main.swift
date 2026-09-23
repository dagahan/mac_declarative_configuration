import AppKit

let argument = CommandLine.arguments.dropFirst().first

if argument == nil || argument!.hasPrefix("-") {
    Agent.run()
} else if let command = Command(rawValue: argument!) {
    exit(command.send())
} else {
    FileHandle.standardError.write(Data("usage: InputLock [lock | unlock]\n".utf8))
    exit(2)
}
