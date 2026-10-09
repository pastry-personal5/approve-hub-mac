import CryptoKit
import Foundation

enum RequestTimestamp {
  static func quantized(_ date: Date) -> Date {
    let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
    return Date(timeIntervalSince1970: milliseconds / 1_000)
  }

  static func render(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter.string(from: date)
  }
}

struct RequestDigestInput: Sendable {
  let id: UUID
  let requesterName: String
  let actionType: String
  let text: String
  let sensitive: Bool
  let sessionID: String?
  let createdAt: String
  let expiresAt: String
}

enum RequestDigest {
  static func value(for input: RequestDigestInput) -> String {
    let bytes = Data(canonicalJSON(for: input).utf8)
    let hash = Data(SHA256.hash(data: bytes))
    let encoded = hash.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "sha256:" + encoded
  }

  static func canonicalJSON(for input: RequestDigestInput) -> String {
    // The contract has fixed ASCII keys and only strings, booleans, and null.
    // This is the RFC 8785 form for that restricted value set.
    let sessionID = input.sessionID.map(quote) ?? "null"
    return "{"
      + [
        "\"actionType\":" + quote(input.actionType),
        "\"createdAt\":" + quote(input.createdAt),
        "\"expiresAt\":" + quote(input.expiresAt),
        "\"id\":" + quote(input.id.uuidString.lowercased()),
        "\"requesterName\":" + quote(input.requesterName),
        "\"sensitive\":" + (input.sensitive ? "true" : "false"),
        "\"sessionID\":" + sessionID,
        "\"text\":" + quote(input.text),
      ].joined(separator: ",") + "}"
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

enum RequestContentSafety {
  // Recognizable formats only. The validator cannot prove that text is secret-free.
  private static let secretPatterns = [
    #"-----BEGIN[ A-Z0-9-]*PRIVATE KEY-----"#,
    #"authorization[ \t]*:[ \t]*bearer[ \t]+\S+"#,
    #"\b(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}"#
      + #"|(?:AKIA|ASIA)[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b"#,
    #"(?:^|[\s,{])["']?(?:password|passwd|secret|client_secret|api_key"#
      + #"|access_token|refresh_token|private_key)["']?[ \t]*[:=][ \t]*["']?[^\s"',}\]]+"#,
  ]

  static func hasDeceptiveCharacters(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
      let codepoint = scalar.value
      if codepoint == 0x09 || codepoint == 0x0A { return false }
      if (0xFDD0...0xFDEF).contains(codepoint) { return true }
      let low = codepoint & 0xFFFF
      if low == 0xFFFE || low == 0xFFFF { return true }
      switch scalar.properties.generalCategory {
      case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate:
        return true
      default:
        return false
      }
    }
  }

  static func hasRecognizableSecret(_ text: String) -> Bool {
    secretPatterns.contains {
      text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
    }
  }
}
