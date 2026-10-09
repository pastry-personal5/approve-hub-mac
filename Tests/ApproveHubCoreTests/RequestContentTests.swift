import Foundation
import Testing

@testable import ApproveHubCore

@Test func digestMatchesCanonicalExamplesAndEscapes() throws {
  let id = try #require(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000"))
  let ordinary = RequestDigestInput(
    id: id,
    requesterName: "Build Agent",
    actionType: "run-command",
    text: "Run the test suite",
    sensitive: false,
    sessionID: nil,
    createdAt: "2026-10-08T00:00:00Z",
    expiresAt: "2026-10-08T00:02:00Z"
  )
  #expect(
    RequestDigest.value(for: ordinary) == "sha256:elaCJEQKavqDo4s2JkECjeMpE1GK_cAm13-k_OmNn0A")
  #expect(RequestDigest.canonicalJSON(for: ordinary).contains("\"sessionID\":null"))

  let escaped = RequestDigestInput(
    id: id,
    requesterName: "Build Agent",
    actionType: "say\"hi",
    text: "line\ncafé\\x",
    sensitive: false,
    sessionID: "α",
    createdAt: "2026-10-08T00:00:00.000Z",
    expiresAt: "2026-10-08T00:02:00.000Z"
  )
  #expect(RequestDigest.value(for: escaped) == "sha256:1pz2szvZc5Y475SldV7OMxgHINfNU0AL27VP--VkrYw")
  #expect(RequestDigest.canonicalJSON(for: escaped).contains(#""text":"line\ncafé\\x""#))
}

@Test func idempotencyPreservesExactUnicodeSequences() async throws {
  let lifecycle = RequestLifecycle()
  let requester = RequesterIdentity(id: "requester-a", name: "Build Agent")
  let composed = RequestInput(actionType: "run-command", text: "caf\u{00E9}", sensitive: false)
  let decomposed = RequestInput(actionType: "run-command", text: "cafe\u{0301}", sensitive: false)
  _ = try await lifecycle.create(requester: requester, key: "unicode-text", input: composed)
  do {
    _ = try await lifecycle.create(requester: requester, key: "unicode-text", input: decomposed)
    Issue.record("Expected changed Unicode sequence to conflict")
  } catch let error as RequestLifecycleError {
    #expect(error == .idempotencyKeyReused)
  }

  let distinctKey = try await lifecycle.create(
    requester: requester, key: "caf\u{00E9}", input: composed)
  let otherKey = try await lifecycle.create(
    requester: requester, key: "cafe\u{0301}", input: composed)
  #expect(distinctKey.id != otherKey.id)
}
