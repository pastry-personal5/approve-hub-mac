import CryptoKit
import Foundation

public enum IdentityProofError: Error, Equatable, Sendable {
  case malformedEncoding
  case invalidPin
  case unexpectedProtocol
  case unexpectedListener
  case wrongKey
  case wrongChallenge
  case staleProof
  case invalidSignature
  case challengeConsumed
  case authorizationConsumed
}

public enum Base64URL {
  public static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  public static func decode(_ text: String, count: Int) throws -> Data {
    guard !text.isEmpty,
      text.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
          || $0 == 45 || $0 == 95
      })
    else { throw IdentityProofError.malformedEncoding }
    let padded =
      text.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
      + String(repeating: "=", count: (4 - text.count % 4) % 4)
    guard let data = Data(base64Encoded: padded), data.count == count,
      encode(data) == text
    else { throw IdentityProofError.malformedEncoding }
    return data
  }
}

public struct ServicePin: Codable, Equatable, Sendable {
  public let version: Int
  public let algorithm: String
  public let publicKey: String
  public let keyID: String

  public init(rawPublicKey: Data) throws {
    guard rawPublicKey.count == 32,
      (try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey)) != nil
    else { throw IdentityProofError.invalidPin }
    version = 1
    algorithm = "ed25519"
    publicKey = Base64URL.encode(rawPublicKey)
    keyID = Base64URL.encode(Data(SHA256.hash(data: rawPublicKey)))
  }

  public func validatedPublicKey() throws -> Curve25519.Signing.PublicKey {
    guard version == 1, algorithm == "ed25519",
      let raw = try? Base64URL.decode(publicKey, count: 32),
      let rawID = try? Base64URL.decode(keyID, count: 32),
      Data(SHA256.hash(data: raw)) == rawID,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    else { throw IdentityProofError.invalidPin }
    return key
  }

  public var fingerprint: String {
    guard let digest = try? Base64URL.decode(keyID, count: 32) else { return "invalid" }
    let hex = digest.map { String(format: "%02X", $0) }.joined()
    return stride(from: 0, to: hex.count, by: 4).map {
      let start = hex.index(hex.startIndex, offsetBy: $0)
      let end = hex.index(start, offsetBy: min(4, hex.count - $0))
      return String(hex[start..<end])
    }.joined(separator: "-")
  }
}

public struct ServiceProofPayload: Codable, Equatable, Sendable {
  public static let protocolLabel = "approvehub-service-proof-v1"
  public static let fixedListener = "http://127.0.0.1:46931"

  public let `protocol`: String
  public let listener: String
  public let keyID: String
  public let challenge: String
  public let issuedAt: String
  public let expiresAt: String

  public init(
    keyID: String,
    challenge: String,
    issuedAt: String,
    expiresAt: String
  ) {
    self.protocol = Self.protocolLabel
    listener = Self.fixedListener
    self.keyID = keyID
    self.challenge = challenge
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
  }

  public func canonicalBytes() -> Data {
    // Six fixed ASCII keys and string values are the restricted RFC 8785 form.
    let fields = [
      "\"challenge\":" + Self.quote(challenge),
      "\"expiresAt\":" + Self.quote(expiresAt),
      "\"issuedAt\":" + Self.quote(issuedAt),
      "\"keyID\":" + Self.quote(keyID),
      "\"listener\":" + Self.quote(listener),
      "\"protocol\":" + Self.quote(`protocol`),
    ]
    return Data(("{" + fields.joined(separator: ",") + "}").utf8)
  }

  private static func quote(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x08: result += "\\b"
      case 0x09: result += "\\t"
      case 0x0A: result += "\\n"
      case 0x0C: result += "\\f"
      case 0x0D: result += "\\r"
      case 0x22: result += "\\\""
      case 0x5C: result += "\\\\"
      case 0x00...0x1F:
        let hex = String(scalar.value, radix: 16)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }
}

public struct ServiceProof: Codable, Equatable, Sendable {
  public let payload: ServiceProofPayload
  public let signature: String

  public init(payload: ServiceProofPayload, signature: String) {
    self.payload = payload
    self.signature = signature
  }
}

public final class VerifiedServiceIdentity: @unchecked Sendable {
  public let keyID: String
  private let issuedAt: Date
  private let expiresAt: Date
  private let lock = NSLock()
  private var available = true

  fileprivate init(keyID: String, issuedAt: Date, expiresAt: Date) {
    self.keyID = keyID
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
  }

  /// Consume this proof result immediately before one bearer-bearing operation.
  public func authorizeBearerOperation(now: Date = Date()) throws {
    let failure = lock.withLock { () -> IdentityProofError? in
      guard available else { return .authorizationConsumed }
      available = false
      guard issuedAt <= now, now <= expiresAt else { return .staleProof }
      return nil
    }
    if let failure { throw failure }
  }
}

/// One attempt authorizes one subsequent bearer-bearing operation. Reference
/// identity prevents a copy from reusing an already consumed challenge.
public final class ServiceProofAttempt: @unchecked Sendable {
  private let lock = NSLock()
  private let pin: ServicePin
  private var challenge: Data?

  public init(pin: ServicePin, challenge: Data) throws {
    guard challenge.count == 32 else { throw IdentityProofError.malformedEncoding }
    _ = try pin.validatedPublicKey()
    self.pin = pin
    self.challenge = challenge
  }

  public func verify(_ proof: ServiceProof, now: Date) throws -> VerifiedServiceIdentity {
    guard
      let challenge = lock.withLock({
        let value = self.challenge
        self.challenge = nil
        return value
      })
    else { throw IdentityProofError.challengeConsumed }
    let payload = proof.payload
    guard payload.protocol == ServiceProofPayload.protocolLabel else {
      throw IdentityProofError.unexpectedProtocol
    }
    guard payload.listener == ServiceProofPayload.fixedListener else {
      throw IdentityProofError.unexpectedListener
    }
    guard payload.keyID == pin.keyID else { throw IdentityProofError.wrongKey }
    guard try Base64URL.decode(payload.challenge, count: 32) == challenge else {
      throw IdentityProofError.wrongChallenge
    }
    guard let issued = ProofTimestamp.parse(payload.issuedAt),
      let expires = ProofTimestamp.parse(payload.expiresAt),
      issued <= now, now <= expires,
      expires.timeIntervalSince(issued) > 0,
      expires.timeIntervalSince(issued) <= 60
    else { throw IdentityProofError.staleProof }
    let signature = try Base64URL.decode(proof.signature, count: 64)
    let key = try pin.validatedPublicKey()
    guard key.isValidSignature(signature, for: payload.canonicalBytes()) else {
      throw IdentityProofError.invalidSignature
    }
    return VerifiedServiceIdentity(keyID: pin.keyID, issuedAt: issued, expiresAt: expires)
  }
}

public enum ProofTimestamp {
  public static func render(_ date: Date) -> String {
    let formatter = makeFormatter()
    return formatter.string(from: date)
  }

  public static func parse(_ text: String) -> Date? {
    let formatter = makeFormatter()
    guard let date = formatter.date(from: text), render(date) == text else { return nil }
    return date
  }

  private static func makeFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    formatter.isLenient = false
    return formatter
  }
}
