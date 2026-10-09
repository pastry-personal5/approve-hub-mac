import ApproveHubContract
import Foundation
import Testing

@testable import ApproveHubService

private struct HTTPResult: Sendable {
  let status: Int
  let contentType: String?
  let body: Data

  func object() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  }

  func code() throws -> String { try #require(object()["code"] as? String) }
}

private func http(
  _ path: String,
  method: String = "GET",
  token: String? = nil,
  key: String? = nil,
  origin: String? = nil,
  lastEventID: String? = nil,
  json: [String: Any]? = nil
) async throws -> HTTPResult {
  var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:46931\(path)")))
  request.httpMethod = method
  request.timeoutInterval = 35
  if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
  if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
  if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
  if let lastEventID { request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
  if let json {
    request.httpBody = try JSONSerialization.data(withJSONObject: json)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  }
  let (data, response) = try await URLSession.shared.data(for: request)
  let result = try #require(response as? HTTPURLResponse)
  return HTTPResult(
    status: result.statusCode,
    contentType: result.value(forHTTPHeaderField: "Content-Type"), body: data)
}

// One subprocess owns the fixed port for the complete wire flow.
// swiftlint:disable:next function_body_length
@Test func fixedListenerServesProofRolesAndRequesterLifecycle() async throws {
  let portLock = try FixedPortTestLock()
  defer { _ = portLock }
  let uninitialized = TestRoot()
  let binary =
    ProcessInfo.processInfo.environment["APPROVE_HUB_TEST_SERVICE_BIN"]
    ?? FileManager.default.currentDirectoryPath + "/.build/debug/approve-hub-service"
  let noState = Process()
  noState.executableURL = URL(fileURLWithPath: binary)
  noState.environment = ProcessInfo.processInfo.environment.merging([
    "APPROVE_HUB_TEST_ROOT": uninitialized.url.path,
    "APPROVE_HUB_TEST_KEYCHAIN": "com.approvehub.uninitialized-test.\(UUID().uuidString)",
  ]) { _, new in new }
  noState.standardOutput = Pipe()
  noState.standardError = Pipe()
  try noState.run()
  noState.waitUntilExit()
  #expect(noState.terminationStatus != 0)

  let corrupt = TestRoot()
  try FileManager.default.createDirectory(
    at: corrupt.url, withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
  try Data("not-json".utf8).write(to: corrupt.url.appendingPathComponent("identity.json"))
  let invalidState = Process()
  invalidState.executableURL = URL(fileURLWithPath: binary)
  invalidState.environment = noState.environment?.merging([
    "APPROVE_HUB_TEST_ROOT": corrupt.url.path
  ]) { _, new in new }
  invalidState.standardOutput = Pipe()
  invalidState.standardError = Pipe()
  try invalidState.run()
  invalidState.waitUntilExit()
  #expect(invalidState.terminationStatus != 0)

  let root = TestRoot()
  let keychain = TestKeychain()
  let store = ServiceCredentialStore(root: root.url, keychain: keychain)
  let pin = try store.setup()
  let issued = try store.addRequester(name: "Build Agent")
  let other = try store.addRequester(name: "Other Agent")
  let recovery = try store.addRequester(name: "Recovery Agent")
  let racingCreate = try store.addRequester(name: "Create Race")
  let racingDecision = try store.addRequester(name: "Decision Race")
  let decider = try #require(try keychain.get(ServiceCredentialStore.deciderAccount))
  let deciderToken = try #require(String(data: decider, encoding: .utf8))

  let process = Process()
  process.executableURL = URL(fileURLWithPath: binary)
  process.environment = ProcessInfo.processInfo.environment.merging([
    "APPROVE_HUB_TEST_ROOT": root.url.path,
    "APPROVE_HUB_TEST_KEYCHAIN": "com.approvehub.http-test.\(UUID().uuidString)",
  ]) { _, new in new }
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  defer {
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
  }

  var ready = false
  let readinessChallenge = Base64URL.encode(Data(repeating: 3, count: 32))
  for _ in 0..<300 {
    let readiness = try? await http(
      "/v1/identity/proofs", method: "POST", json: ["challenge": readinessChallenge])
    if readiness?.status == 200 {
      ready = true
      break
    }
    try await Task.sleep(for: .milliseconds(20))
  }
  if !ready, !process.isRunning, let error = process.standardError as? Pipe {
    let diagnostic = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    Issue.record("Service did not bind: \(diagnostic ?? "unknown")")
  }
  try #require(ready)

  let challenge = Data(repeating: 7, count: 32)
  let proofResponse = try await http(
    "/v1/identity/proofs", method: "POST", json: ["challenge": Base64URL.encode(challenge)])
  #expect(proofResponse.status == 200)
  let proof = try JSONDecoder().decode(ServiceProof.self, from: proofResponse.body)
  let verified = try ServiceProofAttempt(pin: pin, challenge: challenge).verify(proof, now: Date())
  try verified.authorizeBearerOperation()

  let rejectedOrigin = try await http(
    "/v1/identity/proofs", method: "POST", origin: "http://evil.invalid", json: [:])
  #expect(rejectedOrigin.status == 403)
  #expect(try rejectedOrigin.code() == "origin_rejected")
  #expect(rejectedOrigin.contentType?.hasPrefix("application/problem+json") == true)
  let badChallenge = try await http(
    "/v1/identity/proofs", method: "POST", json: ["challenge": "bad"])
  #expect(try badChallenge.code() == "malformed_challenge")
  let missingKey = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token,
    json: ["actionType": "run-command", "text": "Run tests", "sensitive": false])
  #expect(try missingKey.code() == "missing_idempotency_key")
  let wrongRole = try await http(
    "/v1/decider/requests", token: issued.token)
  #expect(try wrongRole.code() == "wrong_role")
  let unknownCursor = try await http(
    "/v1/decider/events", token: deciderToken, lastEventID: "unknown:0")
  #expect(try unknownCursor.code() == "event_cursor_unavailable")

  let input: [String: Any] = [
    "actionType": "run-command", "text": "Run tests", "sensitive": false,
  ]
  let created = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "test-1", json: input)
  #expect(created.status == 201)
  let snapshot = try created.object()
  #expect(snapshot["requesterName"] as? String == "Build Agent")
  let id = try #require(snapshot["id"] as? String)
  let digest = try #require(snapshot["digest"] as? String)
  let repeated = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "test-1", json: input)
  #expect(try repeated.object()["id"] as? String == id)
  let listed = try await http("/v1/decider/requests", token: deciderToken)
  #expect(listed.status == 200)
  #expect((try listed.object()["requests"] as? [[String: Any]])?.count == 1)
  let cursor = try #require(try listed.object()["eventCursor"] as? String)

  let wrongDigest = try await http(
    "/v1/decider/requests/\(id):decide", method: "POST", token: deciderToken,
    json: ["decision": "approved", "digest": "sha256:\(String(repeating: "A", count: 43))"])
  #expect(try wrongDigest.code() == "digest_mismatch")
  let decided = try await http(
    "/v1/decider/requests/\(id):decide", method: "POST", token: deciderToken,
    json: ["decision": "approved", "digest": digest])
  #expect(decided.status == 200)
  #expect(try decided.object()["state"] as? String == "approved")
  let stream = Process()
  stream.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
  stream.arguments = [
    "-sS", "-N", "--max-time", "2", "-H", "Authorization: Bearer \(deciderToken)",
    "-H", "Last-Event-ID: \(cursor)", "http://127.0.0.1:46931/v1/decider/events",
  ]
  let streamOutput = Pipe()
  stream.standardOutput = streamOutput
  stream.standardError = Pipe()
  try stream.run()
  stream.waitUntilExit()
  let streamText = try #require(
    String(data: streamOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
  #expect(streamText.contains("id: "))
  #expect(streamText.contains("event: request.terminal"))
  #expect(streamText.contains("\"state\":\"approved\""))
  let waited = try await http(
    "/v1/requester/requests/\(id):wait", method: "POST", token: issued.token,
    json: ["waitSeconds": 1])
  #expect(try waited.object()["state"] as? String == "approved")

  let concealed = try await http(
    "/v1/requester/requests/\(id):wait", method: "POST", token: other.token,
    json: ["waitSeconds": 1])
  #expect(try concealed.code() == "request_not_found")
  let changed = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "test-1",
    json: ["actionType": "run-command", "text": "Changed", "sensitive": false])
  #expect(try changed.code() == "idempotency_key_reused")
  let sensitive = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "sensitive",
    json: ["actionType": "read", "text": "Read data", "sensitive": true])
  #expect(try sensitive.code() == "sensitive_request_not_supported")
  let unsafe = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "unsafe",
    json: ["actionType": "run", "text": "abc\u{202E}def", "sensitive": false])
  #expect(try unsafe.code() == "unsafe_request_text")
  let malformedWait = try await http(
    "/v1/requester/requests/\(id):wait", method: "POST", token: issued.token,
    json: ["waitSeconds": 0])
  #expect(try malformedWait.code() == "malformed_input")

  let pending = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "pending",
    json: input)
  let pendingID = try #require(try pending.object()["id"] as? String)
  let cancelled = try await http(
    "/v1/requester/requests/\(pendingID)", method: "DELETE", token: issued.token)
  #expect(try cancelled.object()["state"] as? String == "cancelled")

  let held = Task {
    try await http(
      "/v1/requester/requests:submit-and-wait", method: "POST", token: other.token,
      key: "held",
      json: ["actionType": "run-command", "text": "Run tests", "sensitive": false])
  }
  var heldSnapshot: [String: Any]?
  for _ in 0..<100 {
    let current = try await http("/v1/decider/requests", token: deciderToken)
    heldSnapshot = (try current.object()["requests"] as? [[String: Any]])?.first {
      $0["requesterName"] as? String == "Other Agent"
    }
    if heldSnapshot != nil { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let heldID = try #require(heldSnapshot?["id"] as? String)
  let heldDigest = try #require(heldSnapshot?["digest"] as? String)
  _ = try await http(
    "/v1/decider/requests/\(heldID):decide", method: "POST", token: deciderToken,
    json: ["decision": "denied", "digest": heldDigest])
  #expect(try await held.value.object()["state"] as? String == "denied")

  let expires = try await http(
    "/v1/requester/requests", method: "POST", token: other.token, key: "short",
    json: [
      "actionType": "run", "text": "Soon expires", "sensitive": false,
      "expirySeconds": 1,
    ])
  let expiresID = try #require(try expires.object()["id"] as? String)
  let expired = try await http(
    "/v1/requester/requests/\(expiresID):wait", method: "POST", token: other.token,
    json: ["waitSeconds": 2])
  #expect(try expired.object()["state"] as? String == "expired")

  let next = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "revoked",
    json: input)
  #expect(next.status == 201)
  let nextID = try #require(try next.object()["id"] as? String)
  let nextDigest = try #require(try next.object()["digest"] as? String)
  let revokedWait = Task {
    try await http(
      "/v1/requester/requests/\(nextID):wait", method: "POST", token: issued.token,
      json: ["waitSeconds": 30])
  }
  try await Task.sleep(for: .milliseconds(100))
  let revision = try store.revokeRequester(id: issued.id)
  try RevocationSync(files: store.files).confirm(revision: revision)
  #expect(try await revokedWait.value.code() == "unauthenticated")
  let afterRevocation = try await http(
    "/v1/requester/requests", method: "POST", token: issued.token, key: "again", json: input)
  #expect(try afterRevocation.code() == "unauthenticated")
  let afterList = try await http("/v1/decider/requests", token: deciderToken)
  #expect((try afterList.object()["requests"] as? [[String: Any]])?.isEmpty == true)
  let lateDecision = try await http(
    "/v1/decider/requests/\(nextID):decide", method: "POST", token: deciderToken,
    json: ["decision": "approved", "digest": nextDigest])
  #expect(try lateDecision.object()["state"] as? String == "cancelled")

  let createRace = Task {
    try await http(
      "/v1/requester/requests", method: "POST", token: racingCreate.token,
      key: "create-race",
      json: ["actionType": "run", "text": "Race", "sensitive": false])
  }
  let createRevision = try store.revokeRequester(id: racingCreate.id)
  try RevocationSync(files: store.files).confirm(revision: createRevision)
  let createResult = try await createRace.value
  let createCode = try? createResult.code()
  #expect(createResult.status == 201 || createCode == "unauthenticated")
  let afterCreateRace = try await http("/v1/decider/requests", token: deciderToken)
  #expect((try afterCreateRace.object()["requests"] as? [[String: Any]])?.isEmpty == true)

  let decisionRaceRequest = try await http(
    "/v1/requester/requests", method: "POST", token: racingDecision.token,
    key: "decision-race", json: input)
  let decisionRaceID = try #require(try decisionRaceRequest.object()["id"] as? String)
  let decisionRaceDigest = try #require(try decisionRaceRequest.object()["digest"] as? String)
  let decisionRace = Task {
    try await http(
      "/v1/decider/requests/\(decisionRaceID):decide", method: "POST", token: deciderToken,
      json: ["decision": "approved", "digest": decisionRaceDigest])
  }
  let decisionRevision = try store.revokeRequester(id: racingDecision.id)
  try RevocationSync(files: store.files).confirm(revision: decisionRevision)
  let racedDecision = try await decisionRace.value
  let racedState = try racedDecision.object()["state"] as? String
  #expect(racedState == "approved" || racedState == "cancelled")
  let revokedDecisionWait = try await http(
    "/v1/requester/requests/\(decisionRaceID):wait", method: "POST",
    token: racingDecision.token, json: ["waitSeconds": 1])
  #expect(try revokedDecisionWait.code() == "unauthenticated")

  let collisionRoot = TestRoot()
  let collisionStore = ServiceCredentialStore(root: collisionRoot.url, keychain: TestKeychain())
  _ = try collisionStore.setup()
  let collision = Process()
  collision.executableURL = URL(fileURLWithPath: binary)
  collision.environment = process.environment?.merging([
    "APPROVE_HUB_TEST_ROOT": collisionRoot.url.path
  ]) { _, new in new }
  collision.standardOutput = Pipe()
  collision.standardError = Pipe()
  try collision.run()
  collision.waitUntilExit()
  #expect(collision.terminationStatus != 0)
  #expect((try await http("/v1/decider/requests", token: deciderToken)).status == 200)

  let lost = try await http(
    "/v1/requester/requests", method: "POST", token: recovery.token, key: "lost-on-restart",
    json: input)
  let lostID = try #require(try lost.object()["id"] as? String)
  let beforeRestart = try await http("/v1/decider/requests", token: deciderToken)
  let oldCursor = try #require(try beforeRestart.object()["eventCursor"] as? String)
  let fallbackPending = try await http(
    "/v1/requester/requests", method: "POST", token: other.token, key: "fallback-pending",
    json: input)
  #expect(fallbackPending.status == 201)

  let ack = root.url.appendingPathComponent("applied-revision.json")
  try FileManager.default.removeItem(at: ack)
  try FileManager.default.createDirectory(at: ack, withIntermediateDirectories: false)
  _ = try store.revokeRequester(id: other.id)
  for _ in 0..<200 where process.isRunning {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(!process.isRunning)
  process.waitUntilExit()
  try FileManager.default.removeItem(at: ack)

  let restarted = Process()
  restarted.executableURL = URL(fileURLWithPath: binary)
  restarted.environment = process.environment
  restarted.standardOutput = Pipe()
  restarted.standardError = Pipe()
  try restarted.run()
  defer {
    if restarted.isRunning { restarted.terminate() }
    restarted.waitUntilExit()
  }
  var restartedReady = false
  for _ in 0..<300 {
    if (try? await http("/v1/decider/requests", token: deciderToken))?.status == 200 {
      restartedReady = true
      break
    }
    try await Task.sleep(for: .milliseconds(20))
  }
  try #require(restartedReady)
  let oldStream = try await http(
    "/v1/decider/events", token: deciderToken, lastEventID: oldCursor)
  #expect(try oldStream.code() == "event_cursor_unavailable")
  let lostWait = try await http(
    "/v1/requester/requests/\(lostID):wait", method: "POST", token: recovery.token,
    json: ["waitSeconds": 1])
  #expect(try lostWait.code() == "request_not_found")
}

@Test func pendingLimitProblemIncludesRetryDelay() {
  let (response, _) = ServiceProblem.pendingRequestLimitReached(4).response()
  #expect(response.status.code == 429)
  let delay = response.headerFields.first { $0.name.rawName.lowercased() == "retry-after" }
  #expect(delay?.value == "4")
}
