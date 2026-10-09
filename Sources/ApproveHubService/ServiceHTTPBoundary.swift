import ApproveHubContract
import ApproveHubCore
import Darwin
import Foundation
import HTTPTypes
import OpenAPIRuntime

enum ServiceProblem: Error, Sendable {
  case malformedChallenge
  case malformedInput
  case missingIdempotencyKey
  case originRejected
  case unauthenticated
  case wrongRole
  case requestNotFound
  case digestMismatch
  case sensitiveRequestNotSupported
  case unsafeRequestText
  case idempotencyKeyReused
  case eventCursorUnavailable
  case pendingRequestLimitReached(Int)
  case internalFailure

  init(_ error: RequestLifecycleError) {
    switch error {
    case .malformedInput: self = .malformedInput
    case .sensitiveRequestNotSupported: self = .sensitiveRequestNotSupported
    case .unsafeRequestText: self = .unsafeRequestText
    case .idempotencyKeyReused: self = .idempotencyKeyReused
    case .pendingRequestLimitReached(let seconds): self = .pendingRequestLimitReached(seconds)
    case .requestNotFound: self = .requestNotFound
    case .digestMismatch: self = .digestMismatch
    }
  }

  var code: String {
    switch self {
    case .malformedChallenge: "malformed_challenge"
    case .malformedInput: "malformed_input"
    case .missingIdempotencyKey: "missing_idempotency_key"
    case .originRejected: "origin_rejected"
    case .unauthenticated: "unauthenticated"
    case .wrongRole: "wrong_role"
    case .requestNotFound: "request_not_found"
    case .digestMismatch: "digest_mismatch"
    case .sensitiveRequestNotSupported: "sensitive_request_not_supported"
    case .unsafeRequestText: "unsafe_request_text"
    case .idempotencyKeyReused: "idempotency_key_reused"
    case .eventCursorUnavailable: "event_cursor_unavailable"
    case .pendingRequestLimitReached: "pending_request_limit_reached"
    case .internalFailure: "internal_failure"
    }
  }

  var status: Int {
    switch self {
    case .malformedChallenge, .malformedInput, .missingIdempotencyKey: 400
    case .unauthenticated: 401
    case .originRejected, .wrongRole: 403
    case .requestNotFound: 404
    case .digestMismatch, .idempotencyKeyReused, .eventCursorUnavailable: 409
    case .sensitiveRequestNotSupported, .unsafeRequestText: 422
    case .pendingRequestLimitReached: 429
    case .internalFailure: 500
    }
  }

  func response() -> (HTTPResponse, HTTPBody?) {
    if case .internalFailure = self {
      return (HTTPResponse(status: .internalServerError), nil)
    }
    let title = code.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    let payload: [String: Any] = [
      "type": "urn:approvehub:problem:\(code)", "title": title, "status": status, "code": code,
    ]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    var headers: HTTPFields = [.contentType: "application/problem+json"]
    if case .pendingRequestLimitReached(let seconds) = self {
      headers[.retryAfter] = String(seconds)
    }
    return (HTTPResponse(status: .init(code: status), headerFields: headers), HTTPBody(data))
  }
}

enum ServiceRequestContext {
  @TaskLocal static var token: String?
}

struct ServiceHTTPBoundary: ServerMiddleware {
  let runtime: CredentialRuntime

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    metadata: ServerRequestMetadata,
    operationID: String,
    next:
      @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (
        HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPResponse, HTTPBody?) {
    if request.headerFields.contains(where: { $0.name.rawName.lowercased() == "origin" }) {
      return ServiceProblem.originRejected.response()
    }
    do {
      if operationID == "createIdentityProof" {
        return try await next(request, body, metadata)
      }
      let token = try bearerToken(request.headerFields)
      try validateHeaders(request.headerFields, operationID: operationID)
      try await authorize(token, operationID: operationID)
      return try await ServiceRequestContext.$token.withValue(token) {
        try await next(request, body, metadata)
      }
    } catch let error as ServerError where error.underlyingError is CancellationError {
      throw CancellationError()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let mapped = problem(for: error, operationID: operationID)
      if case .internalFailure = mapped {
        fputs("ApproveHub Service: unexpected request failure.\n", stderr)
      }
      return mapped.response()
    }
  }

  private func bearerToken(_ headers: HTTPFields) throws -> String {
    let authorization = headers.filter { $0.name.rawName.lowercased() == "authorization" }
    guard authorization.count == 1 else { throw ServiceProblem.unauthenticated }
    let parts = authorization[0].value.split(separator: " ", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].lowercased() == "bearer", !parts[1].isEmpty else {
      throw ServiceProblem.unauthenticated
    }
    return String(parts[1])
  }

  private func validateHeaders(_ headers: HTTPFields, operationID: String) throws {
    if operationID == "createRequest" || operationID == "submitAndWaitForRequest" {
      let keys = headers.filter { $0.name.rawName.lowercased() == "idempotency-key" }
      guard keys.count == 1, !keys[0].value.isEmpty,
        keys[0].value.unicodeScalars.count <= 128
      else { throw ServiceProblem.missingIdempotencyKey }
    }
    if operationID == "streamDeciderEvents" {
      let cursors = headers.filter { $0.name.rawName.lowercased() == "last-event-id" }
      guard cursors.count <= 1 else { throw ServiceProblem.eventCursorUnavailable }
      if let value = cursors.first?.value {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, UUID(uuidString: String(parts[0])) != nil,
          UInt64(parts[1]) != nil
        else { throw ServiceProblem.eventCursorUnavailable }
      }
    }
  }

  private func authorize(_ token: String, operationID: String) async throws {
    let deciderOperations = ["streamDeciderEvents", "listPendingRequests", "decideRequest"]
    if deciderOperations.contains(operationID) {
      try await runtime.authorizeDecider(token)
    } else {
      _ = try await runtime.authorizeRequester(token)
    }
  }

  private func problem(for error: Error, operationID: String) -> ServiceProblem {
    if let problem = error as? ServiceProblem { return problem }
    if let lifecycleError = error as? RequestLifecycleError {
      return ServiceProblem(lifecycleError)
    }
    if let serverError = error as? ServerError {
      if let problem = serverError.underlyingError as? ServiceProblem { return problem }
      if let lifecycleError = serverError.underlyingError as? RequestLifecycleError {
        return ServiceProblem(lifecycleError)
      }
      if serverError.operationInput == nil {
        return operationID == "createIdentityProof" ? .malformedChallenge : .malformedInput
      }
    }
    return .internalFailure
  }
}
