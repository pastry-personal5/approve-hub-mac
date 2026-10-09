import Foundation

public actor RequestLifecycle {
  private struct NormalizedInput: Equatable {
    let actionType: String
    let text: String
    let sensitive: Bool
    let sessionID: String?
    let requestedExpirySeconds: Int64

    init(_ input: RequestInput) throws {
      let requested = input.expirySeconds ?? 120
      guard !input.actionType.isEmpty, input.actionType.unicodeScalars.count <= 128,
        input.text.utf8.count <= 16_384,
        input.sessionID.map({ !$0.isEmpty && $0.unicodeScalars.count <= 256 }) ?? true,
        requested > 0
      else { throw RequestLifecycleError.malformedInput }
      actionType = input.actionType
      text = input.text
      sensitive = input.sensitive
      sessionID = input.sessionID
      requestedExpirySeconds = requested
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.actionType.utf8.elementsEqual(rhs.actionType.utf8)
        && lhs.text.utf8.elementsEqual(rhs.text.utf8)
        && lhs.sensitive == rhs.sensitive
        && optionalBytesEqual(lhs.sessionID, rhs.sessionID)
        && lhs.requestedExpirySeconds == rhs.requestedExpirySeconds
    }

    private static func optionalBytesEqual(_ lhs: String?, _ rhs: String?) -> Bool {
      switch (lhs, rhs) {
      case (nil, nil): true
      case (let lhs?, let rhs?): lhs.utf8.elementsEqual(rhs.utf8)
      default: false
      }
    }
  }

  private struct IdempotencyScope: Hashable {
    let requesterID: Data
    let key: Data
  }

  private struct IdempotencyRecord {
    let input: NormalizedInput
    let requestID: UUID
  }

  private struct StoredRequest {
    let id: UUID
    let requesterID: Data
    let requesterName: String
    let input: NormalizedInput
    let createdAt: String
    let expiresAt: String
    let deadlineTick: Int64
    let createdRevision: UInt64
    let digest: String
    var state: RequestState = .pending
    var resolvedAt: String?

    func snapshot() -> RequestSnapshot {
      RequestSnapshot(
        id: id,
        requesterName: requesterName,
        actionType: input.actionType,
        text: input.text,
        sensitive: input.sensitive,
        sessionID: input.sessionID,
        requestedExpirySeconds: input.requestedExpirySeconds,
        createdAt: createdAt,
        expiresAt: expiresAt,
        resolvedAt: resolvedAt,
        state: state,
        digest: digest
      )
    }
  }

  private struct Waiter {
    let continuation: AsyncStream<RequestSnapshot>.Continuation
    var timer: Task<Void, Never>?
  }

  private let clock: RequestClock
  private var records: [UUID: StoredRequest] = [:]
  private var idempotency: [IdempotencyScope: IdempotencyRecord] = [:]
  private var expiryTasks: [UUID: Task<Void, Never>] = [:]
  private var waiters: [UUID: [UUID: Waiter]] = [:]
  private var subscribers: [UUID: AsyncStream<RequestTransition>.Continuation] = [:]
  private var pendingCount = 0
  private var revision: UInt64 = 0

  public init(clock: RequestClock = .system) {
    self.clock = clock
  }
}

extension RequestLifecycle {
  public func create(
    requester: RequesterIdentity,
    key: String,
    input: RequestInput
  ) throws -> RequestSnapshot {
    let normalized = try NormalizedInput(input)
    guard !requester.id.isEmpty, !requester.name.isEmpty,
      !key.isEmpty, key.unicodeScalars.count <= 128
    else { throw RequestLifecycleError.malformedInput }

    expireDue()
    let scope = IdempotencyScope(requesterID: Data(requester.id.utf8), key: Data(key.utf8))
    if let prior = idempotency[scope] {
      guard prior.input == normalized else { throw RequestLifecycleError.idempotencyKeyReused }
      guard let current = records[prior.requestID] else {
        throw RequestLifecycleError.requestNotFound
      }
      return current.snapshot()
    }

    try validateNewRequest(normalized)
    let record = makeRecord(requester: requester, input: normalized)
    records[record.id] = record
    idempotency[scope] = IdempotencyRecord(input: normalized, requestID: record.id)
    pendingCount += 1
    emit(.created, snapshot: record.snapshot())
    scheduleExpiry(for: record.id, at: record.deadlineTick)
    return record.snapshot()
  }

  public func submitAndWait(
    requester: RequesterIdentity,
    key: String,
    input: RequestInput
  ) async throws -> RequestSnapshot {
    try Task.checkCancellation()
    let snapshot = try create(requester: requester, key: key, input: input)
    return try await waitForCurrent(id: snapshot.id, requester: requester, seconds: nil)
  }

  public func wait(
    id: UUID,
    requester: RequesterIdentity,
    seconds: Int
  ) async throws -> RequestSnapshot {
    guard (1...30).contains(seconds) else { throw RequestLifecycleError.malformedInput }
    return try await waitForCurrent(id: id, requester: requester, seconds: seconds)
  }

  public func cancel(id: UUID, requester: RequesterIdentity) throws -> RequestSnapshot {
    expireDue()
    let current = try owned(id: id, requester: requester)
    if current.state == .pending {
      complete(id: id, as: .cancelled)
    }
    guard let result = records[id] else { throw RequestLifecycleError.requestNotFound }
    return result.snapshot()
  }

  /// Revocation ends every pending request owned by this credential identity.
  /// Terminal requests keep their first outcome.
  @discardableResult
  public func cancelPending(requesterID: String) -> [RequestSnapshot] {
    expireDue()
    let ids = records.values
      .filter { $0.state == .pending && $0.requesterID == Data(requesterID.utf8) }
      .sorted { $0.createdRevision < $1.createdRevision }
      .map(\.id)
    for id in ids { complete(id: id, as: .cancelled) }
    return ids.compactMap { records[$0]?.snapshot() }
  }

  public func decide(
    id: UUID,
    digest: String,
    decision: RequestDecision
  ) throws -> RequestSnapshot {
    expireDue()
    guard let current = records[id] else { throw RequestLifecycleError.requestNotFound }
    guard current.digest == digest else { throw RequestLifecycleError.digestMismatch }
    if current.state == .pending {
      let state: RequestState = decision == .approve ? .approved : .denied
      complete(id: id, as: state)
    }
    guard let result = records[id] else { throw RequestLifecycleError.requestNotFound }
    return result.snapshot()
  }

  public func pending() -> PendingRequests {
    expireDue()
    let snapshots = records.values
      .filter { $0.state == .pending }
      .sorted { $0.createdRevision > $1.createdRevision }
      .map { $0.snapshot() }
    return PendingRequests(requests: snapshots, revision: revision)
  }

  public func transitions() -> AsyncStream<RequestTransition> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<RequestTransition>.makeStream(
      bufferingPolicy: .bufferingNewest(1_024)
    )
    subscribers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(id) }
    }
    return stream
  }
}

extension RequestLifecycle {
  private func validateNewRequest(_ input: NormalizedInput) throws {
    guard !input.sensitive else {
      throw RequestLifecycleError.sensitiveRequestNotSupported
    }
    guard !RequestContentSafety.hasDeceptiveCharacters(input.actionType),
      !RequestContentSafety.hasDeceptiveCharacters(input.text),
      !RequestContentSafety.hasRecognizableSecret(input.text)
    else { throw RequestLifecycleError.unsafeRequestText }
    if pendingCount >= 100 { expireDue() }
    guard pendingCount < 100 else {
      throw RequestLifecycleError.pendingRequestLimitReached(
        retryAfterSeconds: retryAfterSeconds()
      )
    }
  }

  private func makeRecord(
    requester: RequesterIdentity,
    input: NormalizedInput
  ) -> StoredRequest {
    let moment = clock.now()
    let effectiveSeconds = min(input.requestedExpirySeconds, 600)
    let createdDate = RequestTimestamp.quantized(moment.wallTime)
    let createdAt = RequestTimestamp.render(createdDate)
    let expiresAt = RequestTimestamp.render(
      createdDate.addingTimeInterval(TimeInterval(effectiveSeconds))
    )
    let deadline = moment.monotonicNanoseconds + effectiveSeconds * 1_000_000_000
    let id = UUID()
    let digest = RequestDigest.value(
      for: RequestDigestInput(
        id: id,
        requesterName: requester.name,
        actionType: input.actionType,
        text: input.text,
        sensitive: input.sensitive,
        sessionID: input.sessionID,
        createdAt: createdAt,
        expiresAt: expiresAt
      )
    )
    return StoredRequest(
      id: id,
      requesterID: Data(requester.id.utf8),
      requesterName: requester.name,
      input: input,
      createdAt: createdAt,
      expiresAt: expiresAt,
      deadlineTick: deadline,
      createdRevision: revision + 1,
      digest: digest
    )
  }
  private func owned(id: UUID, requester: RequesterIdentity) throws -> StoredRequest {
    guard let record = records[id], record.requesterID == Data(requester.id.utf8) else {
      throw RequestLifecycleError.requestNotFound
    }
    return record
  }

  private func waitForCurrent(
    id: UUID,
    requester: RequesterIdentity,
    seconds: Int?
  ) async throws -> RequestSnapshot {
    try Task.checkCancellation()
    expireDue()
    let current = try owned(id: id, requester: requester)
    if current.state.isTerminal { return current.snapshot() }

    let waiterID = UUID()
    let (stream, continuation) = AsyncStream<RequestSnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    var waiter = Waiter(continuation: continuation)
    if let seconds {
      let deadline = clock.now().monotonicNanoseconds + Int64(seconds) * 1_000_000_000
      let clock = self.clock
      waiter.timer = Task { [weak self] in
        do { try await clock.sleepUntil(deadline) } catch { return }
        await self?.finishWaiter(id: id, waiterID: waiterID)
      }
    }
    waiters[id, default: [:]][waiterID] = waiter
    return try await withTaskCancellationHandler {
      var iterator = stream.makeAsyncIterator()
      guard let snapshot = await iterator.next() else { throw CancellationError() }
      try Task.checkCancellation()
      return snapshot
    } onCancel: {
      Task { await self.removeWaiter(id: id, waiterID: waiterID) }
    }
  }

  private func scheduleExpiry(for id: UUID, at deadline: Int64) {
    let clock = self.clock
    expiryTasks[id] = Task { [weak self] in
      do { try await clock.sleepUntil(deadline) } catch { return }
      await self?.expire(id: id)
    }
  }

  private func expire(id: UUID) {
    expireDue()
  }

  private func expireDue() {
    let now = clock.now().monotonicNanoseconds
    let due = records.values
      .filter { $0.state == .pending && $0.deadlineTick <= now }
      .sorted {
        if $0.deadlineTick == $1.deadlineTick {
          return $0.createdRevision < $1.createdRevision
        }
        return $0.deadlineTick < $1.deadlineTick
      }
    for record in due {
      complete(id: record.id, as: .expired)
    }
  }

  private func complete(id: UUID, as requestedState: RequestState) {
    guard var record = records[id], record.state == .pending else { return }
    let moment = clock.now()
    let state: RequestState =
      requestedState == .expired || moment.monotonicNanoseconds >= record.deadlineTick
      ? .expired : requestedState
    record.state = state
    record.resolvedAt =
      state == .expired ? record.expiresAt : RequestTimestamp.render(moment.wallTime)
    records[id] = record
    pendingCount -= 1
    expiryTasks.removeValue(forKey: id)?.cancel()
    let snapshot = record.snapshot()
    emit(.terminal, snapshot: snapshot)
    let pendingWaiters = waiters.removeValue(forKey: id) ?? [:]
    for waiter in pendingWaiters.values {
      waiter.timer?.cancel()
      waiter.continuation.yield(snapshot)
      waiter.continuation.finish()
    }
  }

  private func finishWaiter(id: UUID, waiterID: UUID) {
    expireDue()
    guard let waiter = waiters[id]?.removeValue(forKey: waiterID) else { return }
    if waiters[id]?.isEmpty == true { waiters.removeValue(forKey: id) }
    waiter.timer?.cancel()
    if let snapshot = records[id]?.snapshot() { waiter.continuation.yield(snapshot) }
    waiter.continuation.finish()
  }

  private func removeWaiter(id: UUID, waiterID: UUID) {
    guard let waiter = waiters[id]?.removeValue(forKey: waiterID) else { return }
    if waiters[id]?.isEmpty == true { waiters.removeValue(forKey: id) }
    waiter.timer?.cancel()
    waiter.continuation.finish()
  }

  private func retryAfterSeconds() -> Int {
    let now = clock.now().monotonicNanoseconds
    let earliest =
      records.values
      .filter { $0.state == .pending }
      .map(\.deadlineTick)
      .min() ?? now + 1_000_000_000
    let remaining = max(earliest - now, 1)
    return max(Int((remaining + 999_999_999) / 1_000_000_000), 1)
  }

  private func emit(_ kind: RequestTransitionKind, snapshot: RequestSnapshot) {
    revision += 1
    let transition = RequestTransition(revision: revision, kind: kind, snapshot: snapshot)
    for continuation in subscribers.values { continuation.yield(transition) }
  }

  private func removeSubscriber(_ id: UUID) {
    subscribers.removeValue(forKey: id)
  }
}
