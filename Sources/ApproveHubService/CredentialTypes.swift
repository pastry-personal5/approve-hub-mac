import ApproveHubContract
import CommonCrypto
import CryptoKit
import Foundation
import Security

enum CredentialError: Error, Hashable {
  case uninitialized
  case corruptState
  case unsupportedState
  case insecureStorage
  case invalidName
  case duplicateName
  case requesterNotFound
  case unauthenticated
  case wrongRole
  case serviceRunning
  case portOccupied
  case pendingOperation
  case keychainFailure
  case randomFailure
  case hashingFailure
  case storageFailure
  case serviceShutdownUnconfirmed
}

enum CredentialRole: String, Codable {
  case requester = "req"
  case decider = "dec"
}

struct CredentialHash: Codable, Equatable {
  static let iterations: UInt32 = 600_000
  let version: Int
  let algorithm: String
  let salt: Data
  let value: Data
  let rounds: UInt32

  var isWellFormed: Bool {
    version == 1 && algorithm == "pbkdf2-hmac-sha256"
      && salt.count == 32 && value.count == 32
      && (Self.iterations...5_000_000).contains(rounds)
  }

  static func make(secret: Data) throws -> Self {
    let salt = try SecureRandom.bytes(count: 32)
    return try Self(
      version: 1,
      algorithm: "pbkdf2-hmac-sha256",
      salt: salt,
      value: derive(secret, salt: salt, rounds: iterations),
      rounds: iterations
    )
  }

  func matches(_ secret: Data) throws -> Bool {
    guard isWellFormed else {
      throw CredentialError.corruptState
    }
    let candidate = try Self.derive(secret, salt: salt, rounds: rounds)
    return zip(candidate, value).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }

  private static func derive(_ secret: Data, salt: Data, rounds: UInt32) throws -> Data {
    let outputLength = 32
    var output = Data(count: outputLength)
    let status = output.withUnsafeMutableBytes { outputBytes in
      secret.withUnsafeBytes { secretBytes in
        salt.withUnsafeBytes { saltBytes in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            secretBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
            secret.count,
            saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            rounds,
            outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            outputLength
          )
        }
      }
    }
    guard status == kCCSuccess else { throw CredentialError.hashingFailure }
    return output
  }
}

enum SecureRandom {
  static func bytes(count: Int) throws -> Data {
    guard count > 0 else { throw CredentialError.randomFailure }
    var bytes = Data(count: count)
    let status = bytes.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, count, base)
    }
    guard status == errSecSuccess else { throw CredentialError.randomFailure }
    return bytes
  }
}

struct BearerToken {
  let role: CredentialRole
  let id: UUID
  let secret: Data

  static func make(role: CredentialRole) throws -> Self {
    Self(role: role, id: UUID(), secret: try SecureRandom.bytes(count: 32))
  }

  var text: String {
    "ah.\(role.rawValue).v1.\(id.uuidString.lowercased()).\(Base64URL.encode(secret))"
  }

  static func parse(_ text: String) throws -> Self {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 5, parts[0] == "ah", parts[2] == "v1",
      let role = CredentialRole(rawValue: String(parts[1])),
      let id = UUID(uuidString: String(parts[3])),
      let secret = try? Base64URL.decode(String(parts[4]), count: 32)
    else { throw CredentialError.unauthenticated }
    return Self(role: role, id: id, secret: secret)
  }
}

struct RequesterRecord: Codable, Equatable {
  let id: UUID
  let name: String
  let createdAt: Date
  var revokedAt: Date?
  var verifier: CredentialHash?

  var isActive: Bool { revokedAt == nil && verifier != nil }
}

struct DeciderRecord: Codable, Equatable {
  let id: UUID
  let verifier: CredentialHash
}

enum CredentialAuditKind: String, Codable {
  case setup
  case requesterAdded
  case requesterRevoked
  case deciderReset
  case identityRotated
}

struct CredentialAuditEvent: Codable, Equatable {
  let kind: CredentialAuditKind
  let subjectID: String
  let occurredAt: Date
}

struct CredentialState: Codable, Equatable {
  static let currentVersion = 1
  let version: Int
  var revision: UInt64
  var signingKey: Data
  var decider: DeciderRecord
  var requesters: [RequesterRecord]
  var audit: [CredentialAuditEvent]

  func validated() throws -> Self {
    guard version == Self.currentVersion else { throw CredentialError.unsupportedState }
    guard revision > 0 else { throw CredentialError.corruptState }
    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: signingKey),
      requesters.allSatisfy({ ($0.verifier != nil) == ($0.revokedAt == nil) }),
      Set(requesters.map(\.id)).count == requesters.count,
      Set(requesters.filter(\.isActive).map { RequesterName.comparisonKey($0.name) }).count
        == requesters.filter(\.isActive).count,
      decider.verifier.isWellFormed,
      requesters.allSatisfy({ $0.verifier?.isWellFormed ?? true }),
      requesters.allSatisfy({ (try? RequesterName.validate($0.name)) != nil })
    else { throw CredentialError.corruptState }
    _ = try ServicePin(rawPublicKey: privateKey.publicKey.rawRepresentation)
    return self
  }
}

struct RequesterListing: Equatable {
  let id: UUID
  let name: String
  let active: Bool
}

struct AuthenticatedRequester: Equatable {
  let id: String
  let name: String
}

enum RequesterName {
  static func validate(_ value: String) throws -> String {
    guard !value.isEmpty, value.unicodeScalars.count <= 128,
      value.trimmingCharacters(in: .whitespacesAndNewlines) == value,
      !value.unicodeScalars.contains(where: { scalar in
        let codepoint = scalar.value
        if (0xFDD0...0xFDEF).contains(codepoint) { return true }
        let low = codepoint & 0xFFFF
        if low == 0xFFFE || low == 0xFFFF { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate:
          return true
        default: return false
        }
      })
    else { throw CredentialError.invalidName }
    return value
  }

  static func comparisonKey(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.folding(
      options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
}
