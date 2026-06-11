import Foundation

enum ProcessError: LocalizedError {
    case failed(command: String, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, stderr):
            return stderr.isEmpty ? "\(command) failed" : stderr
        }
    }
}

enum ProcessRunner {
    /// Runs a system binary and returns stdout, throwing stderr on a non-zero exit.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], stdin: Data? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProcessError.failed(command: executable, stderr: stderr)
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
