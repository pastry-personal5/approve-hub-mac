import CryptoKit
import Foundation
import Testing

@testable import ApproveHubService

@Test func interruptedSetupRecoversAndCorruptStateFailsClosed() throws {
  let root = TestRoot()
  let keychain = TestKeychain()
  let store = ServiceCredentialStore(root: root.url, keychain: keychain)
  keychain.rejectWrites(to: ServiceCredentialStore.pinAccount)
  #expect(throws: CredentialError.keychainFailure) { try store.setup() }
  #expect(throws: CredentialError.pendingOperation) { try store.currentState() }
  keychain.rejectWrites(to: nil)
  let pin = try store.setup()
  #expect(try store.pinExport() == pin)

  let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.url.path)
  #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
  let stateURL = root.url.appendingPathComponent("identity.json")
  let fileAttributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
  #expect(fileAttributes[.posixPermissions] as? Int == 0o600)
  try Data("invalid-json".utf8).write(to: stateURL)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  #expect(throws: CredentialError.corruptState) { try store.pinExport() }
  #expect(throws: CredentialError.corruptState) { try store.setup() }
}

@Test func staleRecoveryMarkerCannotReplaceNewerCredentials() throws {
  let portLock = try FixedPortTestLock()
  defer { _ = portLock }
  let root = TestRoot()
  let keychain = TestKeychain()
  let store = ServiceCredentialStore(root: root.url, keychain: keychain)
  _ = try store.setup()
  let base = try store.currentState()
  var candidate = base
  candidate.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation
  candidate.revision += 1
  let staleRotation = try PendingCredentialChange(
    kind: .rotate, baseState: base, candidate: candidate)

  _ = try store.addRequester(name: "Current")
  let current = try store.currentState()
  try store.files.writePending(staleRotation)
  #expect(throws: CredentialError.corruptState) { try store.rotateIdentity() }
  #expect(try store.files.readState() == current)

  try store.files.removePending()
  let staleSetup = try PendingCredentialChange(kind: .setup, baseState: nil, candidate: base)
  try store.files.writePending(staleSetup)
  #expect(throws: CredentialError.corruptState) { try store.setup() }
  #expect(try store.files.readState() == current)
}

@Test func interruptedRotationCompletesOriginalCandidate() throws {
  let portLock = try FixedPortTestLock()
  defer { _ = portLock }
  let root = TestRoot()
  let keychain = TestKeychain()
  let store = ServiceCredentialStore(root: root.url, keychain: keychain)
  let originalPin = try store.setup()
  let base = try store.currentState()
  var candidate = base
  candidate.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation
  candidate.revision += 1
  try store.files.writePending(
    PendingCredentialChange(kind: .rotate, baseState: base, candidate: candidate))

  let recoveredPin = try store.rotateIdentity()
  #expect(recoveredPin != originalPin)
  #expect(try store.pinExport() == recoveredPin)
  #expect(try store.currentState() == candidate)
}
