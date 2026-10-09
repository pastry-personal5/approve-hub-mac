import ApproveHubContract
import CryptoKit
import Foundation

struct IssuedRequester {
  let id: UUID
  let name: String
  let token: String
}

struct ServiceCredentialStore: Sendable {
  static let pinAccount = "gui-service-pin"
  static let deciderAccount = "gui-decider-token"

  let files: CredentialFiles
  let keychain: any CredentialKeychain

  init(
    root: URL = CredentialFiles.ownerRoot,
    keychain: any CredentialKeychain = SystemCredentialKeychain()
  ) {
    files = CredentialFiles(root: root)
    self.keychain = keychain
  }

  func setup() throws -> ServicePin {
    try files.withStateLock {
      if let pending = try files.readPending() {
        guard pending.kind == .setup else { throw CredentialError.pendingOperation }
        let current = try files.readState()
        try pending.validateRecovery(current: current)
        if try matchesStoredDecider(pending.candidate.decider) {
          let pin = try pin(for: pending.candidate)
          try keychain.set(try pinData(pin), for: Self.pinAccount)
          try files.writeState(pending.candidate)
          try files.removePending()
          return pin
        }
        guard current == nil else { throw CredentialError.keychainFailure }
        try files.removePending()
      }
      if let state = try files.readState() {
        let pin = try pin(for: state)
        if let stored = try keychain.get(Self.pinAccount) {
          guard stored == (try pinData(pin)) else { throw CredentialError.keychainFailure }
        } else {
          try keychain.set(try pinData(pin), for: Self.pinAccount)
        }
        return pin
      }
      let signingKey = Curve25519.Signing.PrivateKey()
      let decider = try BearerToken.make(role: .decider)
      let setupEvent = CredentialAuditEvent(
        kind: .setup, subjectID: decider.id.uuidString.lowercased(), occurredAt: Date())
      let state = CredentialState(
        version: CredentialState.currentVersion,
        revision: 1,
        signingKey: signingKey.rawRepresentation,
        decider: DeciderRecord(
          id: decider.id, verifier: try CredentialHash.make(secret: decider.secret)),
        requesters: [],
        audit: [setupEvent]
      )
      let pin = try pin(for: state)
      try files.writePending(
        PendingCredentialChange(kind: .setup, baseState: nil, candidate: state))
      try keychain.set(Data(decider.text.utf8), for: Self.deciderAccount)
      try keychain.set(try pinData(pin), for: Self.pinAccount)
      try files.writeState(state)
      try files.removePending()
      return pin
    }
  }

  func pinExport() throws -> ServicePin {
    try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard let state = try files.readState() else { throw CredentialError.uninitialized }
      return try pin(for: state)
    }
  }

  func addRequester(name: String) throws -> IssuedRequester {
    let name = try RequesterName.validate(name)
    return try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard var state = try files.readState() else { throw CredentialError.uninitialized }
      let comparison = RequesterName.comparisonKey(name)
      guard
        !state.requesters.contains(where: {
          $0.isActive && RequesterName.comparisonKey($0.name) == comparison
        })
      else { throw CredentialError.duplicateName }
      let token = try BearerToken.make(role: .requester)
      state.requesters.append(
        RequesterRecord(
          id: token.id,
          name: name,
          createdAt: Date(),
          revokedAt: nil,
          verifier: try CredentialHash.make(secret: token.secret)
        )
      )
      state.audit.append(
        CredentialAuditEvent(
          kind: .requesterAdded, subjectID: token.id.uuidString.lowercased(), occurredAt: Date())
      )
      state.revision += 1
      try files.writeState(state)
      return IssuedRequester(id: token.id, name: name, token: token.text)
    }
  }

  func listRequesters() throws -> [RequesterListing] {
    try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard let state = try files.readState() else { throw CredentialError.uninitialized }
      return state.requesters.map {
        RequesterListing(id: $0.id, name: $0.name, active: $0.isActive)
      }
    }
  }

  @discardableResult
  func revokeRequester(id: UUID) throws -> UInt64 {
    try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard var state = try files.readState() else { throw CredentialError.uninitialized }
      guard let index = state.requesters.firstIndex(where: { $0.id == id }) else {
        throw CredentialError.requesterNotFound
      }
      if state.requesters[index].isActive {
        state.requesters[index].revokedAt = Date()
        state.requesters[index].verifier = nil
        state.audit.append(
          CredentialAuditEvent(
            kind: .requesterRevoked, subjectID: id.uuidString.lowercased(), occurredAt: Date())
        )
        state.revision += 1
        try files.writeState(state)
      }
      return state.revision
    }
  }

  func authenticateRequester(_ text: String) throws -> AuthenticatedRequester {
    let token = try BearerToken.parse(text)
    guard token.role == .requester else { throw CredentialError.wrongRole }
    return try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard let state = try files.readState() else { throw CredentialError.uninitialized }
      guard let record = state.requesters.first(where: { $0.id == token.id }),
        record.isActive,
        let verifier = record.verifier,
        try verifier.matches(token.secret)
      else { throw CredentialError.unauthenticated }
      return AuthenticatedRequester(id: record.id.uuidString.lowercased(), name: record.name)
    }
  }

  func authenticateDecider(_ text: String) throws {
    let token = try BearerToken.parse(text)
    guard token.role == .decider else { throw CredentialError.wrongRole }
    try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard let state = try files.readState() else { throw CredentialError.uninitialized }
      guard token.id == state.decider.id,
        try state.decider.verifier.matches(token.secret)
      else { throw CredentialError.unauthenticated }
    }
  }

  func rotateIdentity() throws -> ServicePin {
    try files.withServiceStopped {
      try files.withStateLock {
        if let pending = try files.readPending() {
          guard pending.kind == .rotate else { throw CredentialError.pendingOperation }
          try pending.validateRecovery(current: files.readState())
          return try completeRotation(pending.candidate)
        }
        guard var state = try files.readState() else { throw CredentialError.uninitialized }
        let baseState = state
        state.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation
        state.audit.append(
          CredentialAuditEvent(
            kind: .identityRotated, subjectID: try pin(for: state).keyID, occurredAt: Date())
        )
        state.revision += 1
        try files.writePending(
          PendingCredentialChange(kind: .rotate, baseState: baseState, candidate: state))
        return try completeRotation(state)
      }
    }
  }

  func resetDecider() throws {
    try files.withStateLock {
      if let pending = try files.readPending() {
        guard pending.kind == .resetDecider else { throw CredentialError.pendingOperation }
        try pending.validateRecovery(current: files.readState())
        if try matchesStoredDecider(pending.candidate.decider) {
          try files.writeState(pending.candidate)
          try files.removePending()
          return
        }
        try files.removePending()
      }
      guard var state = try files.readState() else { throw CredentialError.uninitialized }
      let baseState = state
      let token = try BearerToken.make(role: .decider)
      let formerID = state.decider.id
      state.decider = DeciderRecord(
        id: token.id, verifier: try CredentialHash.make(secret: token.secret))
      state.audit.append(
        CredentialAuditEvent(
          kind: .deciderReset, subjectID: formerID.uuidString.lowercased(), occurredAt: Date())
      )
      state.revision += 1
      try files.writePending(
        PendingCredentialChange(kind: .resetDecider, baseState: baseState, candidate: state))
      try keychain.set(Data(token.text.utf8), for: Self.deciderAccount)
      try files.writeState(state)
      try files.removePending()
    }
  }

  func currentState() throws -> CredentialState {
    try files.withStateLock {
      guard try files.readPending() == nil else { throw CredentialError.pendingOperation }
      guard let state = try files.readState() else { throw CredentialError.uninitialized }
      return state
    }
  }

  private func completeRotation(_ candidate: CredentialState) throws -> ServicePin {
    let pin = try pin(for: candidate)
    try keychain.set(try pinData(pin), for: Self.pinAccount)
    try files.writeState(candidate)
    try files.removePending()
    return pin
  }

  private func pin(for state: CredentialState) throws -> ServicePin {
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: state.signingKey) else {
      throw CredentialError.corruptState
    }
    return try ServicePin(rawPublicKey: key.publicKey.rawRepresentation)
  }

  private func pinData(_ pin: ServicePin) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(pin)
  }

  private func matchesStoredDecider(_ decider: DeciderRecord) throws -> Bool {
    guard let data = try keychain.get(Self.deciderAccount),
      let text = String(data: data, encoding: .utf8),
      let token = try? BearerToken.parse(text),
      token.role == .decider,
      token.id == decider.id
    else { return false }
    return try decider.verifier.matches(token.secret)
  }
}
