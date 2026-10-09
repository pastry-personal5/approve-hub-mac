import Testing

@testable import ApproveHubCore
@testable import ApproveHubService

@Test func brokerReplaysAfterListCursorAndRejectsLostPositions() async throws {
  let broker = ServiceEventBroker()
  let lifecycle = RequestLifecycle()
  let source = await lifecycle.transitions()
  let observer = Task {
    for await transition in source { await broker.observe(transition) }
  }
  defer { observer.cancel() }
  let empty = try #require(try await broker.cursor(after: 0))
  let requester = RequesterIdentity(id: "one", name: "Agent")
  let created = try await lifecycle.create(
    requester: requester, key: "one",
    input: RequestInput(actionType: "run", text: "Run tests", sensitive: false))
  _ = try await lifecycle.decide(id: created.id, digest: created.digest, decision: .deny)
  _ = try await broker.cursor(after: 2)
  var iterator = try await broker.stream(after: empty).makeAsyncIterator()
  #expect((await iterator.next())?.contains("event: request.created") == true)
  #expect((await iterator.next())?.contains("event: request.terminal") == true)
  await broker.close()
  await #expect(throws: ServiceProblem.self) {
    _ = try await broker.stream(after: "unknown:1")
  }
}

@Test func brokerEvictionGapAndRestartInvalidateOldCursors() async throws {
  let lifecycle = RequestLifecycle()
  let requester = RequesterIdentity(id: "one", name: "Agent")
  let snapshot = try await lifecycle.create(
    requester: requester, key: "one",
    input: RequestInput(actionType: "run", text: "Run tests", sensitive: false))
  let broker = ServiceEventBroker()
  let first = try #require(try await broker.cursor(after: 0))
  for revision in 1...1_025 {
    await broker.observe(
      RequestTransition(revision: UInt64(revision), kind: .created, snapshot: snapshot))
  }
  await #expect(throws: ServiceProblem.self) {
    _ = try await broker.stream(after: first)
  }
  let current = try #require(try await broker.cursor(after: 1_025))
  let active = try await broker.stream(after: current)
  var activeIterator = active.makeAsyncIterator()
  await broker.observe(RequestTransition(revision: 1_027, kind: .terminal, snapshot: snapshot))
  #expect(await activeIterator.next() == nil)
  await #expect(throws: ServiceProblem.self) {
    _ = try await broker.stream(after: current)
  }
  let replacement = try #require(try await broker.cursor(after: 1_027))
  _ = try await broker.stream(after: replacement)
  let restarted = ServiceEventBroker()
  await #expect(throws: ServiceProblem.self) {
    _ = try await restarted.stream(after: replacement)
  }
}
