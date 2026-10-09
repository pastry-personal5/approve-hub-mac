import Foundation

/// The stable credential registration key is intentionally absent from snapshots.
public struct RequesterIdentity: Hashable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct RequestInput: Hashable, Sendable {
  public let actionType: String
  public let text: String
  public let sensitive: Bool
  public let sessionID: String?
  public let expirySeconds: Int64?

  public init(
    actionType: String,
    text: String,
    sensitive: Bool,
    sessionID: String? = nil,
    expirySeconds: Int64? = nil
  ) {
    self.actionType = actionType
    self.text = text
    self.sensitive = sensitive
    self.sessionID = sessionID
    self.expirySeconds = expirySeconds
  }
}

public enum RequestDecision: Sendable {
  case approve
  case deny
}

public enum RequestState: String, Sendable {
  case pending
  case approved
  case denied
  case expired
  case cancelled

  public var isTerminal: Bool { self != .pending }
}

public struct RequestSnapshot: Equatable, Sendable {
  public let id: UUID
  public let requesterName: String
  public let actionType: String
  public let text: String
  public let sensitive: Bool
  public let sessionID: String?
  public let requestedExpirySeconds: Int64
  public let createdAt: String
  public let expiresAt: String
  public let resolvedAt: String?
  public let state: RequestState
  public let digest: String
}

public enum RequestLifecycleError: Error, Equatable, Sendable {
  case malformedInput
  case sensitiveRequestNotSupported
  case unsafeRequestText
  case idempotencyKeyReused
  case pendingRequestLimitReached(retryAfterSeconds: Int)
  case requestNotFound
  case digestMismatch
}

public enum RequestTransitionKind: Sendable {
  case created
  case terminal
}

public struct RequestTransition: Sendable {
  public let revision: UInt64
  public let kind: RequestTransitionKind
  public let snapshot: RequestSnapshot
}

public struct PendingRequests: Sendable {
  public let requests: [RequestSnapshot]
  public let revision: UInt64
}

public struct RequestMoment: Sendable {
  public let wallTime: Date
  public let monotonicNanoseconds: Int64

  public init(wallTime: Date, monotonicNanoseconds: Int64) {
    self.wallTime = wallTime
    self.monotonicNanoseconds = monotonicNanoseconds
  }
}

public struct RequestClock: Sendable {
  public let now: @Sendable () -> RequestMoment
  public let sleepUntil: @Sendable (Int64) async throws -> Void

  public init(
    now: @escaping @Sendable () -> RequestMoment,
    sleepUntil: @escaping @Sendable (Int64) async throws -> Void
  ) {
    self.now = now
    self.sleepUntil = sleepUntil
  }

  public static let system = RequestClock(
    now: {
      RequestMoment(
        wallTime: Date(),
        monotonicNanoseconds: Int64(clamping: DispatchTime.now().uptimeNanoseconds)
      )
    },
    sleepUntil: { deadline in
      while true {
        let current = Int64(clamping: DispatchTime.now().uptimeNanoseconds)
        let remaining = deadline - current
        if remaining <= 0 { return }
        try await Task.sleep(for: .nanoseconds(remaining))
      }
    }
  )
}
