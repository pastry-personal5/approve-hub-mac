import ApproveHubContract
import Foundation

enum OwnerCommandError: Error {
  case usage
  case invalidRequesterID
}

struct OwnerCommands {
  let store: ServiceCredentialStore

  func run(_ arguments: [String]) throws -> String {
    switch arguments {
    case ["setup"]:
      return try formatPin(store.setup())
    case let values where values.count == 3 && values[0] == "requester" && values[1] == "add":
      let issued = try store.addRequester(name: values[2])
      return
        "Requester ID: \(issued.id.uuidString.lowercased())\nToken (shown once): \(issued.token)\n"
    case ["requester", "list"]:
      let records = try store.listRequesters()
      if records.isEmpty { return "No requesters registered.\n" }
      return records.map {
        "\($0.id.uuidString.lowercased())\t\($0.active ? "active" : "revoked")\t\($0.name)"
      }.joined(separator: "\n") + "\n"
    case let values where values.count == 3 && values[0] == "requester" && values[1] == "revoke":
      guard let id = UUID(uuidString: values[2]) else { throw OwnerCommandError.invalidRequesterID }
      let revision = try store.revokeRequester(id: id)
      try RevocationSync(files: store.files).confirm(revision: revision)
      return "Revoked requester \(id.uuidString.lowercased()).\n"
    case ["pin", "export"]:
      return try formatPin(store.pinExport())
    case ["identity", "rotate"]:
      return try formatPin(store.rotateIdentity())
        + "Restart ApproveHub Service and distribute the new pin.\n"
    case ["decider", "reset"]:
      try store.resetDecider()
      return "Decider credential replaced in Keychain.\n"
    default:
      throw OwnerCommandError.usage
    }
  }

  private func formatPin(_ pin: ServicePin) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(pin)
    guard let json = String(data: data, encoding: .utf8) else {
      throw CredentialError.storageFailure
    }
    return "Service pin: \(json)\nFingerprint: \(pin.fingerprint)\n"
  }

  static func diagnostic(for error: Error) -> String {
    if let ownerError = error as? OwnerCommandError {
      switch ownerError {
      case .usage:
        return "Usage: approve-hub setup | requester add <name> | requester list | "
          + "requester revoke <id> | pin export | identity rotate | decider reset"
      case .invalidRequesterID:
        return "Invalid requester ID."
      }
    }
    if let credentialError = error as? CredentialError {
      return credentialMessages[credentialError] ?? "Credential operation failed."
    }
    return "Credential operation failed."
  }

  private static let credentialMessages: [CredentialError: String] = [
    .uninitialized: "Setup required. Run approve-hub setup.",
    .duplicateName: "An active requester already uses that name.",
    .invalidName: "Invalid requester name. Use 1–128 visible characters without outer spaces.",
    .requesterNotFound: "Requester ID not found.",
    .serviceRunning: "Stop ApproveHub Service before rotating its identity.",
    .portOccupied: "The fixed listener port is occupied; identity rotation is blocked.",
    .serviceShutdownUnconfirmed:
      "Requester revoked; service shutdown could not be confirmed. Stop it now.",
    .pendingOperation: "A credential change is incomplete. Retry its original local command.",
    .keychainFailure: "Keychain access failed; no credential was printed.",
    .insecureStorage: "Credential storage ownership or permissions are unsafe.",
    .corruptState: "Credential storage is unreadable; it was not reset.",
    .unsupportedState: "Credential storage is incompatible; it was not reset.",
  ]
}
