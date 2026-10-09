import ApproveHubCore
import Foundation

/// Runs beside the HTTP adapter in M7 and applies credential revocations to the
/// in-memory request lifecycle before acknowledging their durable revision.
actor CredentialRuntime {
  private let store: ServiceCredentialStore
  private let lifecycle: RequestLifecycle
  private let lease: ServiceLease
  private var appliedRevision: UInt64 = 0

  init(store: ServiceCredentialStore, lifecycle: RequestLifecycle) throws {
    self.store = store
    self.lifecycle = lifecycle
    _ = try store.currentState()
    lease = try store.files.acquireServiceLease()
  }

  func applyCurrentState() async throws {
    let state = try store.currentState()
    guard state.revision > appliedRevision else { return }
    for requester in state.requesters where !requester.isActive {
      await lifecycle.cancelPending(requesterID: requester.id.uuidString.lowercased())
    }
    try store.files.acknowledge(revision: state.revision, lease: lease)
    appliedRevision = state.revision
  }

  func authorizeRequester(_ token: String) async throws -> RequesterIdentity {
    do {
      try await applyCurrentState()
      let requester = try store.authenticateRequester(token)
      return RequesterIdentity(id: requester.id, name: requester.name)
    } catch CredentialError.wrongRole {
      throw ServiceProblem.wrongRole
    } catch CredentialError.unauthenticated {
      throw ServiceProblem.unauthenticated
    }
  }

  func authorizeDecider(_ token: String) async throws {
    do {
      try await applyCurrentState()
      try store.authenticateDecider(token)
    } catch CredentialError.wrongRole {
      throw ServiceProblem.wrongRole
    } catch CredentialError.unauthenticated {
      throw ServiceProblem.unauthenticated
    }
  }

  func run() async throws {
    try await applyCurrentState()
    while !Task.isCancelled {
      try await Task.sleep(for: .milliseconds(50))
      try await applyCurrentState()
    }
  }
}
