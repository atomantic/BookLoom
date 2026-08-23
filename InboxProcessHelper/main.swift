import Darwin
import Foundation

enum HelperError: Error {
    case invalidArguments
    case lockOpenFailed
    case lockFailed
}

func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 4 else { throw HelperError.invalidArguments }

    switch arguments[1] {
    case "hold-lock":
        let queueURL = URL(fileURLWithPath: arguments[2])
        let readyURL = URL(fileURLWithPath: arguments[3])
        let lockURL = queueURL.appendingPathExtension("lock")
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw HelperError.lockOpenFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw HelperError.lockFailed }
        defer { flock(descriptor, LOCK_UN) }

        try Data().write(to: readyURL, options: .atomic)
        var releaseByte: UInt8 = 0
        _ = read(STDIN_FILENO, &releaseByte, 1)

    case "enqueue":
        guard arguments.count == 5,
              let url = URL(string: arguments[3]) else {
            throw HelperError.invalidArguments
        }
        let queueURL = URL(fileURLWithPath: arguments[2])
        let startedURL = URL(fileURLWithPath: arguments[4])
        try Data().write(to: startedURL, options: .atomic)
        SharedImportInbox.enqueue(url, defaults: nil, fileURL: queueURL)

    default:
        throw HelperError.invalidArguments
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
