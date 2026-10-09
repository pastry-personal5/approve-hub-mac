import ApproveHubContract
import ApproveHubCore
import CryptoKit
import Foundation
import Testing

@testable import ApproveHubService

final class TestKeychain: CredentialKeychain, @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String: Data] = [:]
  private var rejectedAccount: String?

  func rejectWrites(to account: String?) {
    lock.withLock { rejectedAccount = account }
  }

  func get(_ account: String) throws -> Data? { lock.withLock { items[account] } }
  func set(_ value: Data, for account: String) throws {
    if lock.withLock({ rejectedAccount == account }) { throw CredentialError.keychainFailure }
    lock.withLock { items[account] = value }
  }
  func delete(_ account: String) throws {
    _ = lock.withLock { items.removeValue(forKey: account) }
  }
}

final class TestRoot {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "approvehub-credential-test-\(UUID().uuidString)", isDirectory: true)

  deinit { try? FileManager.default.removeItem(at: url) }
}

private struct CLIResult {
  let status: Int32
  let output: String
  let error: String
}

private struct TestCLI {
  let root: URL
  let service: String

  func execute(_ arguments: [String]) throws -> CLIResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".build/debug/approve-hub")
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging([
      "APPROVE_HUB_TEST_ROOT": root.path,
      "APPROVE_HUB_TEST_KEYCHAIN": service,
    ]) { _, new in new }
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    return CLIResult(
      status: process.terminationStatus,
      output: try #require(String(data: outputData, encoding: .utf8)),
      error: try #require(String(data: errorData, encoding: .utf8))
    )
  }
}

@Test func setupRestartOneTimeOutputAndNameUniqueness() throws {
  let root = TestRoot()
  let keychain = TestKeychain()
  let store = ServiceCredentialStore(root: root.url, keychain: keychain)
  let pin = try store.setup()
  #expect(try store.pinExport() == pin)
  #expect(try store.listRequesters().isEmpty)
  let originalDecider = try #require(try keychain.get(ServiceCredentialStore.deciderAccount))
  let originalText = try #require(String(data: originalDecider, encoding: .utf8))
  try store.authenticateDecider(originalText)

  let issued = try store.addRequester(name: "Build Agent")
  #expect(try store.authenticateRequester(issued.token).name == "Build Agent")
  #expect(throws: CredentialError.wrongRole) { try store.authenticateRequester(originalText) }
  #expect(throws: CredentialError.wrongRole) { try store.authenticateDecider(issued.token) }
  let raw = try Data(contentsOf: root.url.appendingPathComponent("identity.json"))
  #expect(!raw.contains(Data(issued.token.utf8)))
  #expect(!raw.contains(originalDecider))
  #expect(throws: CredentialError.duplicateName) {
    try store.addRequester(name: "build agent")
  }
  let restarted = ServiceCredentialStore(root: root.url, keychain: keychain)
  #expect(try restarted.pinExport() == pin)
  #expect(try restarted.authenticateRequester(issued.token).id == issued.id.uuidString.lowercased())
  #expect(try restarted.setup() == pin)
  #expect(try keychain.get(ServiceCredentialStore.deciderAccount) == originalDecider)

  try keychain.delete(ServiceCredentialStore.pinAccount)
  #expect(try restarted.setup() == pin)
  #expect(try keychain.get(ServiceCredentialStore.pinAccount) != nil)
  try restarted.revokeRequester(id: issued.id)
  #expect(throws: CredentialError.unauthenticated) {
    try restarted.authenticateRequester(issued.token)
  }
  let replacement = try restarted.addRequester(name: "Build Agent")
  #expect(replacement.id != issued.id)
  #expect(try restarted.listRequesters().filter(\.active).count == 1)
  let state = try restarted.currentState()
  #expect(state.audit.map(\.kind) == [.setup, .requesterAdded, .requesterRevoked, .requesterAdded])
}

@Test func canonicalNameCollisionIsRejected() throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  _ = try store.setup()
  _ = try store.addRequester(name: "Café")
  #expect(throws: CredentialError.duplicateName) {
    try store.addRequester(name: "Cafe\u{301}")
  }
}

@Test func concurrentAdministrativeWritesPreserveAllRequesters() async throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  _ = try store.setup()
  try await withThrowingTaskGroup(of: Void.self) { group in
    for index in 0..<4 {
      group.addTask { _ = try store.addRequester(name: "Agent \(index)") }
    }
    try await group.waitForAll()
  }
  #expect(try store.listRequesters().count == 4)
  #expect(try store.currentState().revision == 5)
}

@Test func proofIsBoundToPinNonceTimeAndOneUse() throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  let pin = try store.setup()
  let signer = try ServiceProofSigner(state: store.currentState())
  let challenge = Data(repeating: 7, count: 32)
  let now = Date(timeIntervalSince1970: 1_000)
  let proof = try signer.sign(challenge: challenge, now: now)
  let fractionalNow = now.addingTimeInterval(0.0009)
  let fractionalProof = try signer.sign(challenge: challenge, now: fractionalNow)
  #expect(try #require(ProofTimestamp.parse(fractionalProof.payload.issuedAt)) <= fractionalNow)
  let canonical = try #require(String(data: proof.payload.canonicalBytes(), encoding: .utf8))
  let expectedCanonical =
    "{\"challenge\":\"\(Base64URL.encode(challenge))\","
    + "\"expiresAt\":\"1970-01-01T00:17:40.000Z\","
    + "\"issuedAt\":\"1970-01-01T00:16:40.000Z\","
    + "\"keyID\":\"\(pin.keyID)\","
    + "\"listener\":\"http://127.0.0.1:46931\","
    + "\"protocol\":\"approvehub-service-proof-v1\"}"
  #expect(canonical == expectedCanonical)
  let valid = try ServiceProofAttempt(pin: pin, challenge: challenge)
  let authorization = try valid.verify(proof, now: now)
  #expect(authorization.keyID == pin.keyID)
  try authorization.authorizeBearerOperation(now: now)
  #expect(throws: IdentityProofError.authorizationConsumed) {
    try authorization.authorizeBearerOperation(now: now)
  }
  let delayed = try ServiceProofAttempt(pin: pin, challenge: challenge).verify(proof, now: now)
  #expect(throws: IdentityProofError.staleProof) {
    try delayed.authorizeBearerOperation(now: now.addingTimeInterval(61))
  }
  #expect(throws: IdentityProofError.authorizationConsumed) {
    try delayed.authorizeBearerOperation(now: now)
  }
  #expect(throws: IdentityProofError.challengeConsumed) {
    try valid.verify(proof, now: now)
  }
  let wrongChallenge = try ServiceProofAttempt(pin: pin, challenge: Data(repeating: 8, count: 32))
  #expect(throws: IdentityProofError.wrongChallenge) {
    try wrongChallenge.verify(proof, now: now)
  }
  let stale = try ServiceProofAttempt(pin: pin, challenge: challenge)
  #expect(throws: IdentityProofError.staleProof) {
    try stale.verify(proof, now: now.addingTimeInterval(61))
  }
  let wrongPin = try ServicePin(
    rawPublicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
  let wrong = try ServiceProofAttempt(pin: wrongPin, challenge: challenge)
  #expect(throws: IdentityProofError.wrongKey) { try wrong.verify(proof, now: now) }
}

@Test func proofRejectsAlteredFieldsAndMalformedSignature() throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  let pin = try store.setup()
  let signer = try ServiceProofSigner(state: store.currentState())
  let challenge = Data(repeating: 9, count: 32)
  let now = Date(timeIntervalSince1970: 1_000)
  let proof = try signer.sign(challenge: challenge, now: now)
  let encoded = try JSONEncoder().encode(proof)
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  var payload = try #require(object["payload"] as? [String: Any])
  payload["protocol"] = "wrong-protocol"
  object["payload"] = payload
  let alteredProtocol = try JSONDecoder().decode(
    ServiceProof.self, from: JSONSerialization.data(withJSONObject: object))
  let protocolAttempt = try ServiceProofAttempt(pin: pin, challenge: challenge)
  #expect(throws: IdentityProofError.unexpectedProtocol) {
    try protocolAttempt.verify(alteredProtocol, now: now)
  }

  payload["protocol"] = ServiceProofPayload.protocolLabel
  payload["listener"] = "http://127.0.0.1:9999"
  object["payload"] = payload
  let alteredListener = try JSONDecoder().decode(
    ServiceProof.self, from: JSONSerialization.data(withJSONObject: object))
  let listenerAttempt = try ServiceProofAttempt(pin: pin, challenge: challenge)
  #expect(throws: IdentityProofError.unexpectedListener) {
    try listenerAttempt.verify(alteredListener, now: now)
  }

  let badSignature = ServiceProof(payload: proof.payload, signature: "not-base64!")
  let malformedAttempt = try ServiceProofAttempt(pin: pin, challenge: challenge)
  #expect(throws: IdentityProofError.malformedEncoding) {
    try malformedAttempt.verify(badSignature, now: now)
  }
  let alteredSignature = ServiceProof(
    payload: proof.payload, signature: Base64URL.encode(Data(repeating: 0, count: 64)))
  let signatureAttempt = try ServiceProofAttempt(pin: pin, challenge: challenge)
  #expect(throws: IdentityProofError.invalidSignature) {
    try signatureAttempt.verify(alteredSignature, now: now)
  }
  #expect(throws: IdentityProofError.malformedEncoding) {
    try Base64URL.decode("AA=", count: 1)
  }
}

@Test func deciderResetAndStoppedRotation() throws {
  let portLock = try FixedPortTestLock()
  defer { _ = portLock }
  let root = TestRoot()
  let keychain = TestKeychain()
  let store = ServiceCredentialStore(root: root.url, keychain: keychain)
  let originalPin = try store.setup()
  let original = try #require(try keychain.get(ServiceCredentialStore.deciderAccount))
  try store.resetDecider()
  let replacement = try #require(try keychain.get(ServiceCredentialStore.deciderAccount))
  #expect(original != replacement)
  let originalText = try #require(String(data: original, encoding: .utf8))
  let replacementText = try #require(String(data: replacement, encoding: .utf8))
  #expect(throws: CredentialError.unauthenticated) {
    try store.authenticateDecider(originalText)
  }
  try store.authenticateDecider(replacementText)
  do {
    let lease = try store.files.acquireServiceLease()
    #expect(lease.record.pid > 0)
    #expect(throws: CredentialError.serviceRunning) { try store.rotateIdentity() }
  }
  let rotated = try store.rotateIdentity()
  #expect(rotated.keyID != originalPin.keyID)
  #expect(try store.pinExport() == rotated)
}

@Test func liveRevocationCancelsPendingBeforeAcknowledgement() async throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  _ = try store.setup()
  let issued = try store.addRequester(name: "Build Agent")
  let lifecycle = RequestLifecycle()
  let requester = RequesterIdentity(id: issued.id.uuidString.lowercased(), name: issued.name)
  let created = try await lifecycle.create(
    requester: requester,
    key: "pending",
    input: RequestInput(actionType: "run-command", text: "Run tests", sensitive: false)
  )
  let runtime = try CredentialRuntime(store: store, lifecycle: lifecycle)
  try await runtime.applyCurrentState()
  let revision = try store.revokeRequester(id: issued.id)
  try await runtime.applyCurrentState()
  let acknowledgement = try #require(try store.files.readAcknowledgement())
  #expect(acknowledgement.revision == revision)
  #expect(await lifecycle.pending().requests.isEmpty)
  #expect(
    try await lifecycle.wait(id: created.id, requester: requester, seconds: 1).state == .cancelled)
}

@Test func ownerCommandsRevealRequesterTokenOnlyOnAdd() throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  let command = OwnerCommands(store: store)
  let setupOutput = try command.run(["setup"])
  #expect(setupOutput.contains("Service pin:"))
  #expect(!setupOutput.contains("ah.dec.v1"))
  let addOutput = try command.run(["requester", "add", "Build Agent"])
  let token = try #require(addOutput.split(separator: " ").last.map(String.init))
  #expect(token.hasPrefix("ah.req.v1."))
  let listOutput = try command.run(["requester", "list"])
  #expect(!listOutput.contains(token))
  let id = try #require(store.listRequesters().first?.id)
  let revokeOutput = try command.run(["requester", "revoke", id.uuidString])
  #expect(!revokeOutput.contains(token))
  let exportOutput = try command.run(["pin", "export"])
  #expect(!exportOutput.contains(token))
}

@Test func systemKeychainRoundTripUsesIsolatedTestItem() throws {
  let account = "test-\(UUID().uuidString)"
  let keychain = SystemCredentialKeychain(service: "com.approvehub.tests.\(UUID().uuidString)")
  defer { try? keychain.delete(account) }
  let secret = Data("isolated-keychain-test".utf8)
  try keychain.set(secret, for: account)
  #expect(try keychain.get(account) == secret)
  try keychain.delete(account)
  #expect(try keychain.get(account) == nil)
}

@Test func ownerCLIUsesHelperWithoutRepeatingSecret() throws {
  let root = TestRoot()
  let service = "com.approvehub.cli-test.\(UUID().uuidString)"
  let keychain = SystemCredentialKeychain(service: service)
  defer {
    try? keychain.delete(ServiceCredentialStore.pinAccount)
    try? keychain.delete(ServiceCredentialStore.deciderAccount)
  }
  let cli = TestCLI(root: root.url, service: service)

  let setup = try cli.execute(["setup"])
  #expect(setup.status == 0)
  #expect(setup.output.contains("Service pin:"))
  let added = try cli.execute(["requester", "add", "Build Agent"])
  #expect(added.status == 0)
  let tokenLine = try #require(added.output.split(separator: "\n").first { $0.hasPrefix("Token") })
  let token = String(tokenLine.replacingOccurrences(of: "Token (shown once): ", with: ""))
  #expect(token.hasPrefix("ah.req.v1."))
  let listed = try cli.execute(["requester", "list"])
  #expect(listed.status == 0)
  #expect(!listed.output.contains(token))
  #expect(!listed.error.contains(token))
  let exported = try cli.execute(["pin", "export"])
  #expect(exported.status == 0)
  #expect(!exported.output.contains(token))
  let id = try #require(listed.output.split(separator: "\t").first.map(String.init))
  let revoked = try cli.execute(["requester", "revoke", id])
  #expect(revoked.status == 0)
  #expect(!revoked.output.contains(token))
  let repeated = try cli.execute(["setup"])
  #expect(repeated.status == 0)
  #expect(!repeated.output.contains(token))
}

@Test func liveOwnerRevocationWaitsForCancellationAcknowledgement() async throws {
  let root = TestRoot()
  let store = ServiceCredentialStore(root: root.url, keychain: TestKeychain())
  _ = try store.setup()
  let issued = try store.addRequester(name: "Build Agent")
  let requester = RequesterIdentity(id: issued.id.uuidString.lowercased(), name: issued.name)
  let lifecycle = RequestLifecycle()
  let created = try await lifecycle.create(
    requester: requester,
    key: "cross-process",
    input: RequestInput(actionType: "run-command", text: "Run tests", sensitive: false)
  )
  let runtime = try CredentialRuntime(store: store, lifecycle: lifecycle)
  try await runtime.applyCurrentState()
  let originalRevision = try store.currentState().revision

  let process = Process()
  process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(".build/debug/approve-hub")
  process.arguments = ["requester", "revoke", issued.id.uuidString]
  process.environment = ProcessInfo.processInfo.environment.merging([
    "APPROVE_HUB_TEST_ROOT": root.url.path,
    "APPROVE_HUB_TEST_KEYCHAIN": "com.approvehub.revoke-test.\(UUID().uuidString)",
  ]) { _, new in new }
  let output = Pipe()
  let error = Pipe()
  process.standardOutput = output
  process.standardError = error
  try process.run()
  for _ in 0..<200 where (try store.currentState().revision) == originalRevision {
    try await Task.sleep(for: .milliseconds(10))
  }
  try await runtime.applyCurrentState()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
  #expect(await lifecycle.pending().requests.isEmpty)
  #expect(
    try await lifecycle.wait(id: created.id, requester: requester, seconds: 1).state == .cancelled)
  let errorText = try #require(
    String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
  #expect(errorText.isEmpty)
}
