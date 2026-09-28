import Foundation

/// Every error the core throws. `parse` is shared with the theme code copied from Thuban Canvas / Study / Gym.
public enum ThubanError: Error, LocalizedError, Equatable, Sendable {
    case parse(String)
    case store(String)
    /// The Atlas import could not reach or read the database (ssh / docker / psql failure).
    case importFailed(String)
    /// The Atlas document was reachable but its content could not be understood.
    case decoding(String)
    /// A request referenced something that does not exist or is malformed.
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .parse(let message), .store(let message), .importFailed(let message), .decoding(let message), .invalid(let message):
            return message
        }
    }
}
