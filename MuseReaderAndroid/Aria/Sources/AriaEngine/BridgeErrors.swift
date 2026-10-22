// Errors and enums of the iOS bridge (MuseReaderiOS/MuseReaderiOS/Bridge/MuseScorePackageBridge.h),
// with the same names and values, so shared Swift code can match on them.

import Foundation

public let MSRBridgeErrorDomain = "MuseReaderiOS.Bridge"

public struct MSRBridgeError: CustomNSError, Hashable, Error {
    public enum Code: Int, @unchecked Sendable, Equatable {
        case unsupportedFormat = 1
        case unreadableFile = 2
        case invalidArchive = 3
        case missingScoreFile = 4
        case invalidScoreEncoding = 5
        case renderCoreUnavailable = 6
        case renderCoreFailure = 7
        case chordSymbolRemovalNeedsApproval = 8
    }

    public let code: Code
    public let errorUserInfo: [String: Any]

    public init(_ code: Code, message: String) {
        self.code = code
        self.errorUserInfo = [NSLocalizedDescriptionKey: message]
    }

    public static var errorDomain: String { MSRBridgeErrorDomain }
    public var errorCode: Int { code.rawValue }

    public static var unsupportedFormat: Code { .unsupportedFormat }
    public static var unreadableFile: Code { .unreadableFile }
    public static var invalidArchive: Code { .invalidArchive }
    public static var missingScoreFile: Code { .missingScoreFile }
    public static var invalidScoreEncoding: Code { .invalidScoreEncoding }
    public static var renderCoreUnavailable: Code { .renderCoreUnavailable }
    public static var renderCoreFailure: Code { .renderCoreFailure }
    public static var chordSymbolRemovalNeedsApproval: Code { .chordSymbolRemovalNeedsApproval }

    public static func == (lhs: MSRBridgeError, rhs: MSRBridgeError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

public enum MSRDocumentFormat: Int, @unchecked Sendable {
    case MSCZ = 0
    case MSCX = 1
    case MXL = 2
    case musicXML = 3
}

/// The NSError the iOS bridge reports (domain MSRBridgeErrorDomain).
func bridgeError(_ code: MSRBridgeError.Code, _ message: String) -> NSError {
    NSError(domain: MSRBridgeErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
}
