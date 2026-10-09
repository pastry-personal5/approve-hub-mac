import ApproveHubCore
import Foundation

actor ServiceEventBroker {
  private struct Event {
    let position: UInt64
    let frame: String
  }

  private var generation = UUID().uuidString.lowercased()
  private var position: UInt64 = 0
  private var observedRevision: UInt64 = 0
  private var events: [Event] = []
  private var revisionPositions: [UInt64: UInt64] = [0: 0]
  private var subscribers: [UUID: AsyncStream<String>.Continuation] = [:]

  func observe(_ transition: RequestTransition) {
    guard transition.revision == observedRevision + 1 else {
      invalidate(at: transition.revision)
      return
    }
    observedRevision = transition.revision
    position += 1
    let eventName = transition.kind == .created ? "request.created" : "request.terminal"
    guard let data = try? JSONEncoder().encode(WireSnapshot(transition.snapshot)),
      let json = String(data: data, encoding: .utf8)
    else {
      invalidate(at: transition.revision)
      return
    }
    let frame = "id: \(cursor(position))\nevent: \(eventName)\ndata: \(json)\n\n"
    events.append(Event(position: position, frame: frame))
    revisionPositions[observedRevision] = position
    if events.count > 1_024 {
      events.removeFirst()
      let oldest = events[0].position - 1
      revisionPositions = revisionPositions.filter { $0.value >= oldest }
    }
    for (id, continuation) in subscribers {
      if case .dropped = continuation.yield(frame) {
        subscribers.removeValue(forKey: id)?.finish()
      }
    }
  }

  func cursor(after revision: UInt64) async throws -> String? {
    while observedRevision < revision {
      try Task.checkCancellation()
      try await Task.sleep(for: .milliseconds(1))
    }
    guard let position = revisionPositions[revision] else { return nil }
    return cursor(position)
  }

  func stream(after requested: String?) throws -> AsyncStream<String> {
    let start: UInt64
    if let requested {
      let parts = requested.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, parts[0] == generation,
        let parsed = UInt64(parts[1]), parsed <= position,
        parsed >= (events.first?.position ?? position + 1) - 1
      else { throw ServiceProblem.eventCursorUnavailable }
      start = parsed
    } else {
      start = position
    }
    let id = UUID()
    let (stream, continuation) = AsyncStream<String>.makeStream(
      bufferingPolicy: .bufferingNewest(1_024)
    )
    for event in events where event.position > start {
      if case .dropped = continuation.yield(event.frame) {
        continuation.finish()
        throw ServiceProblem.eventCursorUnavailable
      }
    }
    subscribers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(id) }
    }
    return stream
  }

  func close() {
    for continuation in subscribers.values { continuation.finish() }
    subscribers.removeAll()
  }

  private func invalidate(at revision: UInt64) {
    close()
    generation = UUID().uuidString.lowercased()
    position = 0
    observedRevision = revision
    events.removeAll()
    revisionPositions = [revision: 0]
  }

  private func removeSubscriber(_ id: UUID) {
    subscribers.removeValue(forKey: id)
  }

  private func cursor(_ position: UInt64) -> String { "\(generation):\(position)" }
}

private struct WireSnapshot: Encodable {
  let id: String
  let requesterName: String
  let actionType: String
  let text: String
  let sensitive: Bool
  let sessionID: String?
  let requestedExpirySeconds: Int64
  let createdAt: String
  let expiresAt: String
  let resolvedAt: String?
  let state: String
  let digest: String

  init(_ value: RequestSnapshot) {
    id = value.id.uuidString.lowercased()
    requesterName = value.requesterName
    actionType = value.actionType
    text = value.text
    sensitive = value.sensitive
    sessionID = value.sessionID
    requestedExpirySeconds = value.requestedExpirySeconds
    createdAt = value.createdAt
    expiresAt = value.expiresAt
    resolvedAt = value.resolvedAt
    state = value.state.rawValue
    digest = value.digest
  }
}
