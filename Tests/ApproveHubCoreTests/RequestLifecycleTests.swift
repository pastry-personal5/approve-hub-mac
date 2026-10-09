import Foundation
import Testing

@testable import ApproveHubCore

private let requester = RequesterIdentity(id: "requester-a", name: "Build Agent")
private let otherRequester = RequesterIdentity(id: "requester-b", name: "Build Agent")

private func request(
  text: String = "Run the test suite",
  sensitive: Bool = false,
  expirySeconds: Int64? = nil
) -> RequestInput {
  RequestInput(
    actionType: "run-command",
    text: text,
    sensitive: sensitive,
    expirySeconds: expirySeconds
  )
}

private func expectError<T>(
  _ expected: RequestLifecycleError,
  operation: () async throws -> T
) async {
  do {
    _ = try await operation()
    Issue.record("Expected \(expected)")
  } catch let error as RequestLifecycleError {
    #expect(error == expected)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private final class ManualRequestClock: @unchecked Sendable {
  private struct Sleeper {
    let deadline: Int64
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var wallTime: Date
  private var tick: Int64 = 0
  private var sleepers: [UUID: Sleeper] = [:]

  init(wallTime: Date = Date(timeIntervalSince1970: 0)) {
    self.wallTime = wallTime
  }

  var lifecycleClock: RequestClock {
    RequestClock(
      now: { self.now() },
      sleepUntil: { try await self.sleep(until: $0) }
    )
  }

  func now() -> RequestMoment {
    lock.withLock {
      RequestMoment(wallTime: wallTime, monotonicNanoseconds: tick)
    }
  }

  func advance(seconds: Int) {
    let ready: [Sleeper] = lock.withLock {
      tick += Int64(seconds) * 1_000_000_000
      wallTime.addTimeInterval(TimeInterval(seconds))
      let due = sleepers.filter { $0.value.deadline <= tick }
      for id in due.keys { sleepers.removeValue(forKey: id) }
      return due.map(\.value)
    }
    for sleeper in ready { sleeper.continuation.resume() }
  }

  func waitForSleepers(_ count: Int) async {
    for _ in 0..<2_000 {
      if lock.withLock({ sleepers.count >= count }) { return }
      await Task.yield()
    }
    Issue.record("Expected at least \(count) registered clock sleepers")
  }

  private func sleep(until deadline: Int64) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let shouldResume: Bool = lock.withLock {
          if Task.isCancelled || tick >= deadline { return true }
          sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
          return false
        }
        if shouldResume {
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
          } else {
            continuation.resume()
          }
        }
      }
    } onCancel: {
      let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func next() -> Int {
    lock.withLock {
      count += 1
      return count
    }
  }
}

@Test func defaultAndCappedExpiryAreImmutableAndMonotonic() async throws {
  let clock = ManualRequestClock()
  let lifecycle = RequestLifecycle(clock: clock.lifecycleClock)
  let ordinary = try await lifecycle.create(requester: requester, key: "default", input: request())
  #expect(ordinary.requestedExpirySeconds == 120)
  #expect(ordinary.createdAt == "1970-01-01T00:00:00.000Z")
  #expect(ordinary.expiresAt == "1970-01-01T00:02:00.000Z")
  let capped = try await lifecycle.create(
    requester: requester,
    key: "capped",
    input: request(expirySeconds: 3_600)
  )
  #expect(capped.requestedExpirySeconds == 3_600)
  #expect(capped.expiresAt == "1970-01-01T00:10:00.000Z")

  clock.advance(seconds: 119)
  #expect(await lifecycle.pending().requests.count == 2)
  clock.advance(seconds: 1)
  let expired = try await lifecycle.cancel(id: ordinary.id, requester: requester)
  #expect(expired.state == .expired)
  #expect(expired.resolvedAt == expired.expiresAt)
  #expect(await lifecycle.pending().requests.count == 1)
  clock.advance(seconds: 480)
  #expect(await lifecycle.pending().requests.isEmpty)
  let cappedRetry = try await lifecycle.create(
    requester: requester,
    key: "capped",
    input: request(expirySeconds: 3_600)
  )
  #expect(cappedRetry.state == .expired)
  #expect(cappedRetry.id == capped.id)
}

@Test func timestampsKeepMillisecondsAndDeadlineWinsDuringDecision() async throws {
  let fractionalClock = ManualRequestClock(wallTime: Date(timeIntervalSince1970: 0.456))
  let fractional = RequestLifecycle(clock: fractionalClock.lifecycleClock)
  let snapshot = try await fractional.create(
    requester: requester,
    key: "fractional",
    input: request()
  )
  #expect(snapshot.createdAt == "1970-01-01T00:00:00.456Z")
  #expect(snapshot.expiresAt == "1970-01-01T00:02:00.456Z")

  let clock = ManualRequestClock()
  let reads = LockedCounter()
  let advancingClock = RequestClock(
    now: {
      if reads.next() == 4 { clock.advance(seconds: 1) }
      return clock.now()
    },
    sleepUntil: { try await clock.lifecycleClock.sleepUntil($0) }
  )
  let lifecycle = RequestLifecycle(clock: advancingClock)
  let created = try await lifecycle.create(
    requester: requester,
    key: "boundary",
    input: request(expirySeconds: 1)
  )
  let result = try await lifecycle.decide(
    id: created.id,
    digest: created.digest,
    decision: .approve
  )
  #expect(result.state == .expired)
}

@Test func malformedSensitiveAndUnsafeInputsLeaveNoPendingRequest() async throws {
  let lifecycle = RequestLifecycle(clock: ManualRequestClock().lifecycleClock)
  await expectError(.malformedInput) {
    try await lifecycle.create(
      requester: requester, key: "empty", input: request(text: "x", expirySeconds: 0))
  }
  await expectError(.malformedInput) {
    try await lifecycle.create(
      requester: requester,
      key: "length",
      input: request(text: String(repeating: "é", count: 8_193))
    )
  }
  await expectError(.sensitiveRequestNotSupported) {
    try await lifecycle.create(
      requester: requester, key: "sensitive", input: request(sensitive: true))
  }
  for (index, text) in [
    "show \u{202E}spoofed text",
    "password=hunter2",
    #"{"api_key":"sample"}"#,
    "Authorization: Bearer sample-token",
    "-----BEGIN OPENSSH PRIVATE KEY-----",
    "ghp_" + String(repeating: "a", count: 25),
  ].enumerated() {
    await expectError(.unsafeRequestText) {
      try await lifecycle.create(
        requester: requester, key: "unsafe-\(index)", input: request(text: text))
    }
  }
  #expect(await lifecycle.pending().requests.isEmpty)
  await expectError(.unsafeRequestText) {
    try await lifecycle.create(
      requester: requester,
      key: "unsafe-action",
      input: RequestInput(actionType: "run\u{200B}-command", text: "safe", sensitive: false)
    )
  }
  let accepted = try await lifecycle.create(
    requester: requester,
    key: "safe",
    input: request(text: "café ☕\nUse sk-short as a label")
  )
  #expect(accepted.text == "café ☕\nUse sk-short as a label")
}

@Test func normalizedRetryOwnershipAndRestartAreEnforced() async throws {
  let clock = ManualRequestClock()
  let lifecycle = RequestLifecycle(clock: clock.lifecycleClock)
  let first = try await lifecycle.create(requester: requester, key: "same", input: request())
  let retry = try await lifecycle.create(
    requester: requester,
    key: "same",
    input: request(expirySeconds: 120)
  )
  #expect(retry.id == first.id)
  await expectError(.idempotencyKeyReused) {
    try await lifecycle.create(requester: requester, key: "same", input: request(text: "changed"))
  }
  let other = try await lifecycle.create(requester: otherRequester, key: "same", input: request())
  #expect(other.id != first.id)
  await expectError(.requestNotFound) {
    try await lifecycle.cancel(id: first.id, requester: otherRequester)
  }
  await expectError(.requestNotFound) {
    try await lifecycle.wait(id: first.id, requester: otherRequester, seconds: 1)
  }
  let cancelled = try await lifecycle.cancel(id: first.id, requester: requester)
  #expect(cancelled.state == .cancelled)
  #expect(try await lifecycle.cancel(id: first.id, requester: requester) == cancelled)

  let restarted = RequestLifecycle(clock: clock.lifecycleClock)
  await expectError(.requestNotFound) {
    try await restarted.cancel(id: first.id, requester: requester)
  }
  let afterRestart = try await restarted.create(requester: requester, key: "same", input: request())
  #expect(afterRestart.id != first.id)
}

@Test func pendingCapacityIsAtomicAndRejectedKeysCanBeRetried() async throws {
  let clock = ManualRequestClock()
  let lifecycle = RequestLifecycle(clock: clock.lifecycleClock)
  for index in 0..<100 {
    _ = try await lifecycle.create(
      requester: requester,
      key: "request-\(index)",
      input: request(text: "safe request \(index)")
    )
  }
  #expect(await lifecycle.pending().requests.count == 100)
  await expectError(.pendingRequestLimitReached(retryAfterSeconds: 120)) {
    try await lifecycle.create(requester: requester, key: "overflow", input: request())
  }
  clock.advance(seconds: 120)
  let accepted = try await lifecycle.create(requester: requester, key: "overflow", input: request())
  #expect(accepted.state == .pending)
  #expect(await lifecycle.pending().requests.count == 1)
}

@Test func firstTerminalTransitionWinsAndDigestIsAlwaysChecked() async throws {
  let clock = ManualRequestClock()
  let lifecycle = RequestLifecycle(clock: clock.lifecycleClock)
  let created = try await lifecycle.create(requester: requester, key: "race", input: request())
  async let approve = lifecycle.decide(id: created.id, digest: created.digest, decision: .approve)
  async let deny = lifecycle.decide(id: created.id, digest: created.digest, decision: .deny)
  async let cancel = lifecycle.cancel(id: created.id, requester: requester)
  let results = try await [approve, deny, cancel]
  let finalState = results[0].state
  #expect(finalState.isTerminal)
  #expect(results.allSatisfy { $0.state == finalState })
  #expect(
    try await lifecycle.decide(id: created.id, digest: created.digest, decision: .deny).state
      == finalState)
  await expectError(.digestMismatch) {
    try await lifecycle.decide(id: created.id, digest: "sha256:wrong", decision: .approve)
  }
  #expect(await lifecycle.pending().requests.isEmpty)

  let late = try await lifecycle.create(
    requester: requester, key: "deadline", input: request(expirySeconds: 1))
  clock.advance(seconds: 1)
  let expired = try await lifecycle.decide(id: late.id, digest: late.digest, decision: .approve)
  #expect(expired.state == .expired)
}

@Test func bothWaitFlowsWakeAndClientCancellationDoesNotCancelRequest() async throws {
  let clock = ManualRequestClock()
  let lifecycle = RequestLifecycle(clock: clock.lifecycleClock)
  let created = try await lifecycle.create(requester: requester, key: "wait", input: request())
  let shortWait = Task {
    try await lifecycle.wait(id: created.id, requester: requester, seconds: 30)
  }
  await clock.waitForSleepers(2)
  clock.advance(seconds: 30)
  let stillPending = try await shortWait.value
  #expect(stillPending.state == .pending)

  let cancelledWait = Task {
    try await lifecycle.wait(id: created.id, requester: requester, seconds: 30)
  }
  await clock.waitForSleepers(2)
  cancelledWait.cancel()
  do {
    _ = try await cancelledWait.value
    Issue.record("Expected cancellation")
  } catch is CancellationError {
    // The approval request itself stays pending.
  }
  #expect(await lifecycle.pending().requests.count == 1)

  let held = Task {
    try await lifecycle.submitAndWait(requester: requester, key: "wait", input: request())
  }
  let secondWait = Task {
    try await lifecycle.wait(id: created.id, requester: requester, seconds: 30)
  }
  let decided = try await lifecycle.decide(
    id: created.id, digest: created.digest, decision: .approve)
  #expect(decided.state == .approved)
  #expect(try await held.value == decided)
  #expect(try await secondWait.value == decided)
  await expectError(.malformedInput) {
    try await lifecycle.wait(id: created.id, requester: requester, seconds: 31)
  }
}

@Test func pendingListAndTransitionsShareARevision() async throws {
  let lifecycle = RequestLifecycle(clock: ManualRequestClock().lifecycleClock)
  let stream = await lifecycle.transitions()
  var iterator = stream.makeAsyncIterator()
  let first = try await lifecycle.create(
    requester: requester, key: "one", input: request(text: "first"))
  let second = try await lifecycle.create(
    requester: requester, key: "two", input: request(text: "second"))
  let list = await lifecycle.pending()
  #expect(list.requests.map(\.id) == [second.id, first.id])
  #expect(list.revision == 2)
  let decided = try await lifecycle.decide(id: first.id, digest: first.digest, decision: .deny)
  let events = await [iterator.next(), iterator.next(), iterator.next()]
  #expect(events.compactMap { $0?.revision } == [1, 2, 3])
  #expect(events[0]?.kind == .created)
  #expect(events[2]?.kind == .terminal)
  #expect(events[2]?.snapshot == decided)
  #expect(await lifecycle.pending().revision == 3)
}

@Test func revocationCancelsOnlyPendingRequestsForItsRequester() async throws {
  let lifecycle = RequestLifecycle(clock: ManualRequestClock().lifecycleClock)
  let first = try await lifecycle.create(requester: requester, key: "revoke-one", input: request())
  let second = try await lifecycle.create(requester: requester, key: "revoke-two", input: request())
  let other = try await lifecycle.create(
    requester: otherRequester, key: "other", input: request())
  let decided = try await lifecycle.decide(
    id: first.id, digest: first.digest, decision: .deny)
  let cancelled = await lifecycle.cancelPending(requesterID: requester.id)
  #expect(cancelled.map(\.id) == [second.id])
  #expect(cancelled.map(\.state) == [.cancelled])
  #expect(await lifecycle.cancelPending(requesterID: requester.id).isEmpty)
  #expect(try await lifecycle.wait(id: first.id, requester: requester, seconds: 1) == decided)
  #expect(await lifecycle.pending().requests.map(\.id) == [other.id])
}
