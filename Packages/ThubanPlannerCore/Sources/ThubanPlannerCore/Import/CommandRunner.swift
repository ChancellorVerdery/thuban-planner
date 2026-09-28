import Foundation

/// Output of one external command.
public struct CommandResult: Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stderrText: String { String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Runs an executable with arguments and stdin. The Atlas importer talks to the world only through this, so tests
/// substitute a fixture runner and never touch ssh.
public protocol CommandRunner: Sendable {
    func run(executable: String, arguments: [String], stdin: Data, timeout: TimeInterval) async throws -> CommandResult
}

#if os(macOS)
/// `Foundation.Process` implementation. Reads stdout/stderr concurrently (no pipe-buffer deadlock), feeds stdin,
/// and terminates the process at `timeout` or when the calling task is cancelled.
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(executable: String, arguments: [String], stdin: Data, timeout: TimeInterval) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    box.stdout = output.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    box.stderr = errors.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                process.terminationHandler = { finished in
                    group.notify(queue: .global()) {
                        if box.timedOut {
                            continuation.resume(throwing: ThubanError.importFailed("Timed out after \(Int(timeout)) s."))
                        } else if box.cancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: CommandResult(status: finished.terminationStatus, stdout: box.stdout, stderr: box.stderr))
                        }
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    try? output.fileHandleForWriting.close()
                    try? errors.fileHandleForWriting.close()
                    continuation.resume(throwing: ThubanError.importFailed("Could not start \(executable): \(error.localizedDescription)"))
                    return
                }
                DispatchQueue.global().async {
                    try? input.fileHandleForWriting.write(contentsOf: stdin)
                    try? input.fileHandleForWriting.close()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        box.timedOut = true
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    var timedOut = false
    var stdout = Data()
    var stderr = Data()
    var cancelled = false
    init(_ process: Process) { self.process = process }
    func cancel() {
        cancelled = true
        if process.isRunning { process.terminate() }
    }
}
#endif

/// The runner an `AtlasImporter` uses when none is given: `ProcessRunner` on the Mac. iOS has no `Process` (and the
/// Atlas ssh import is Mac-only), so there it is a runner that always fails.
public enum DefaultCommandRunner {
    public static func make() -> CommandRunner {
        #if os(macOS)
        return ProcessRunner()
        #else
        return UnavailableRunner()
        #endif
    }
}

/// Fails every command: external programs cannot be run on this platform.
public struct UnavailableRunner: CommandRunner {
    public init() {}
    public func run(executable: String, arguments: [String], stdin: Data, timeout: TimeInterval) async throws -> CommandResult {
        throw ThubanError.importFailed("Importing from Atlas over ssh is only available on the Mac.")
    }
}
