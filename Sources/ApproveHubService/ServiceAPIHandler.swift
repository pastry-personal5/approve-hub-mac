import ApproveHubContract
import ApproveHubCore
import Foundation
import OpenAPIRuntime

typealias ProofOperation = Operations.CreateIdentityProof
typealias CreateOperation = Operations.CreateRequest
typealias Submit = Operations.SubmitAndWaitForRequest
typealias WaitOperation = Operations.WaitForRequest
typealias CancelOperation = Operations.CancelRequest
typealias ListOperation = Operations.ListPendingRequests
typealias DecideOperation = Operations.DecideRequest
typealias EventsOperation = Operations.StreamDeciderEvents

struct ServiceAPIHandler: APIProtocol {
  let signer: ServiceProofSigner
  let runtime: CredentialRuntime
  let lifecycle: RequestLifecycle
  let events: ServiceEventBroker

  func createIdentityProof(_ input: ProofOperation.Input) async throws -> ProofOperation.Output {
    guard case .json(let body) = input.body,
      let challenge = try? Base64URL.decode(body.challenge, count: 32)
    else { throw ServiceProblem.malformedChallenge }
    let proof = try signer.sign(challenge: challenge)
    let payload = proof.payload
    let wire = Components.Schemas.IdentityProof(
      payload: .init(
        _protocol: .approvehubServiceProofV1,
        listener: .http_colon_127_0_0_1_colon_46931,
        keyID: payload.keyID,
        challenge: payload.challenge,
        issuedAt: try parseDate(payload.issuedAt),
        expiresAt: try parseDate(payload.expiresAt)
      ),
      signature: proof.signature
    )
    return .ok(.init(body: .json(wire)))
  }

  func createRequest(_ input: CreateOperation.Input) async throws -> CreateOperation.Output {
    let requester = try await requester()
    let body = createBody(input.body)
    let snapshot = try await lifecycle.create(
      requester: requester, key: input.headers.idempotencyKey, input: body)
    try await verifyRequester()
    return .created(.init(body: .json(try convert(snapshot))))
  }

  func submitAndWaitForRequest(_ input: Submit.Input) async throws -> Submit.Output {
    let requester = try await requester()
    let snapshot = try await lifecycle.submitAndWait(
      requester: requester,
      key: input.headers.idempotencyKey,
      input: createBody(input.body)
    )
    try await verifyRequester()
    return .ok(.init(body: .json(try convert(snapshot))))
  }

  func waitForRequest(_ input: WaitOperation.Input) async throws -> WaitOperation.Output {
    let requester = try await requester()
    guard let id = UUID(uuidString: input.path.requestID),
      case .json(let body) = input.body
    else { throw ServiceProblem.malformedInput }
    let snapshot = try await lifecycle.wait(id: id, requester: requester, seconds: body.waitSeconds)
    try await verifyRequester()
    return .ok(.init(body: .json(try convert(snapshot))))
  }

  func cancelRequest(_ input: CancelOperation.Input) async throws -> CancelOperation.Output {
    let requester = try await requester()
    guard let id = UUID(uuidString: input.path.requestID) else {
      throw ServiceProblem.malformedInput
    }
    let snapshot = try await lifecycle.cancel(id: id, requester: requester)
    try await verifyRequester()
    return .ok(.init(body: .json(try convert(snapshot))))
  }

  func listPendingRequests(_ input: ListOperation.Input) async throws -> ListOperation.Output {
    try await verifyDecider()
    while true {
      let pending = await lifecycle.pending()
      if let cursor = try await events.cursor(after: pending.revision) {
        try await verifyDecider()
        let wire = try pending.requests.map(convert)
        return .ok(.init(body: .json(.init(requests: wire, eventCursor: cursor))))
      }
    }
  }

  func decideRequest(_ input: DecideOperation.Input) async throws -> DecideOperation.Output {
    try await verifyDecider()
    guard let id = UUID(uuidString: input.path.requestID), case .json(let body) = input.body
    else { throw ServiceProblem.malformedInput }
    let decision: RequestDecision = body.decision == .approved ? .approve : .deny
    let snapshot = try await lifecycle.decide(id: id, digest: body.digest, decision: decision)
    try await verifyDecider()
    return .ok(.init(body: .json(try convert(snapshot))))
  }

  func streamDeciderEvents(_ input: EventsOperation.Input) async throws -> EventsOperation.Output {
    try await verifyDecider()
    guard let token = ServiceRequestContext.token else { throw ServiceProblem.unauthenticated }
    let frames = try await events.stream(after: input.headers.lastEventID)
    let runtime = self.runtime
    let byteFrames = AsyncStream<ArraySlice<UInt8>> { continuation in
      let task = Task {
        for await frame in frames {
          if Task.isCancelled { break }
          guard (try? await runtime.authorizeDecider(token)) != nil else { break }
          continuation.yield(ArraySlice(frame.utf8))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
    return .ok(.init(body: .textEventStream(HTTPBody(byteFrames, length: .unknown))))
  }

  private func requester() async throws -> RequesterIdentity {
    guard let token = ServiceRequestContext.token else { throw ServiceProblem.unauthenticated }
    return try await runtime.authorizeRequester(token)
  }

  private func verifyRequester() async throws {
    _ = try await requester()
  }

  private func verifyDecider() async throws {
    guard let token = ServiceRequestContext.token else { throw ServiceProblem.unauthenticated }
    try await runtime.authorizeDecider(token)
  }

  private func createBody(_ body: Components.RequestBodies.CreateRequest) -> RequestInput {
    let value: Components.Schemas.CreateRequest
    switch body {
    case .json(let json): value = json
    }
    return RequestInput(
      actionType: value.actionType, text: value.text, sensitive: value.sensitive,
      sessionID: value.sessionID, expirySeconds: value.expirySeconds
    )
  }

  private func convert(_ value: RequestSnapshot) throws -> Components.Schemas.RequestSnapshot {
    guard
      let state = Components.Schemas.RequestSnapshot.StatePayload(rawValue: value.state.rawValue)
    else { throw ServiceProblem.internalFailure }
    return .init(
      id: value.id.uuidString.lowercased(), requesterName: value.requesterName,
      actionType: value.actionType, text: value.text, sensitive: value.sensitive,
      sessionID: value.sessionID, requestedExpirySeconds: value.requestedExpirySeconds,
      createdAt: try parseDate(value.createdAt), expiresAt: try parseDate(value.expiresAt),
      resolvedAt: try value.resolvedAt.map(parseDate), state: state, digest: value.digest
    )
  }

  private func parseDate(_ text: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: text) else { throw ServiceProblem.internalFailure }
    return date
  }
}
