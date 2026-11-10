import Darwin
import Foundation

public struct ShellResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum Shell {
    /// Output goes to files, not pipes. A full pipe deadlocks `ps`, whose
    /// listing is larger than the kernel buffer, because we would wait for
    /// exit before reading.
    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            process.environment = env
        }

        let token = UUID().uuidString
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("manter-out-\(token)")
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("manter-err-\(token)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        do {
            let outHandle = try FileHandle(forWritingTo: outURL)
            let errHandle = try FileHandle(forWritingTo: errURL)
            process.standardOutput = outHandle
            process.standardError = errHandle
            try process.run()
            let timedOut = wait(process, timeout: timeout)
            process.waitUntilExit()
            try outHandle.close()
            try errHandle.close()
            if timedOut {
                return ShellResult(status: 124, stdout: "", stderr: "tempo esgotado")
            }
            let stdout = String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self)
            let stderr = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
            return ShellResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        } catch {
            return ShellResult(status: 127, stdout: "", stderr: error.localizedDescription)
        }
    }

    private static func wait(_ process: Process, timeout: TimeInterval?) -> Bool {
        guard let timeout else {
            return false
        }
        let limit = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < limit {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.isRunning else { return false }
        process.terminate()
        let killAfter = Date().addingTimeInterval(0.4)
        while process.isRunning, Date() < killAfter {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        return true
    }
}
