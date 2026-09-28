import Foundation
@testable import ThubanPlannerCore

enum TestSupport {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `new Date('2025-10-01')` (UTC midnight), as in Atlas's tests.
    static func date(_ ymd: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: ymd)!
    }

    static func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
            ?? Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtureURL(name)) }
}

/// Returns canned output; records what it was asked to run.
final class FixtureRunner: CommandRunner, @unchecked Sendable {
    var result: CommandResult
    private(set) var executable: String?
    private(set) var arguments: [String] = []
    private(set) var stdin = Data()
    private(set) var runs = 0

    init(result: CommandResult) { self.result = result }

    func run(executable: String, arguments: [String], stdin: Data, timeout: TimeInterval) async throws -> CommandResult {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        runs += 1
        return result
    }
}
