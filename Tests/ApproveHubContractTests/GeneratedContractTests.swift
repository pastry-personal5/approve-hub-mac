import ApproveHub
import ApproveHubContract
import ApproveHubService
import Foundation
import OpenAPIRuntime
import Testing

@Test func generatedModelsDecodeOrdinaryAndSensitiveExamples() throws {
  let create = Components.Schemas.CreateRequest(
    actionType: "run-command",
    text: "Run the test suite",
    sensitive: false
  )
  #expect(create.expirySeconds == nil)
  #expect(create.sessionID == nil)

  let snapshotJSON = """
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "requesterName": "Build Agent",
      "actionType": "run-command",
      "text": "Run the test suite",
      "sensitive": false,
      "requestedExpirySeconds": 120,
      "createdAt": "2026-10-08T00:00:00Z",
      "expiresAt": "2026-10-08T00:02:00Z",
      "state": "pending",
      "digest": "sha256:elaCJEQKavqDo4s2JkECjeMpE1GK_cAm13-k_OmNn0A"
    }
    """
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let snapshot = try decoder.decode(
    Components.Schemas.RequestSnapshot.self,
    from: Data(snapshotJSON.utf8)
  )
  #expect(snapshot.state == .pending)
  #expect(snapshot.requestedExpirySeconds == 120)
  #expect(snapshot.sessionID == nil)

  let sensitiveProblemJSON = """
    {
      "type": "urn:approvehub:problem:sensitive_request_not_supported",
      "title": "Sensitive request not supported",
      "status": 422,
      "code": "sensitive_request_not_supported"
    }
    """
  let problem = try decoder.decode(
    Components.Schemas.Problem.self,
    from: Data(sensitiveProblemJSON.utf8)
  )
  #expect(problem.status == 422)
  #expect(problem.code.rawValue == "sensitive_request_not_supported")
}

@Test func generatedWaitInputsHaveDistinctFlows() {
  let create = Components.Schemas.CreateRequest(
    actionType: "run-command",
    text: "Run the test suite",
    sensitive: false
  )
  let submit = Operations.SubmitAndWaitForRequest.Input(
    headers: .init(idempotencyKey: "example-run-1"),
    body: .json(create)
  )
  let step = Operations.WaitForRequest.Input(
    path: .init(requestID: "550e8400-e29b-41d4-a716-446655440000"),
    body: .json(.init(waitSeconds: 30))
  )
  #expect(submit.headers.idempotencyKey == "example-run-1")
  if case .json(let wait) = step.body {
    #expect(wait.waitSeconds == 30)
  }
}

// Compiled but never called: future clients and handlers must retain both wait
// signatures and the generated server transport registration interface.
private func checkGeneratedBindings(
  client: Client,
  handler: any APIProtocol,
  transport: any ServerTransport,
  submit: Operations.SubmitAndWaitForRequest.Input,
  step: Operations.WaitForRequest.Input
) async throws {
  let _: Operations.SubmitAndWaitForRequest.Output = try await client.submitAndWaitForRequest(
    submit
  )
  let _: Operations.WaitForRequest.Output = try await client.waitForRequest(step)
  let _: Operations.SubmitAndWaitForRequest.Output = try await handler.submitAndWaitForRequest(
    submit
  )
  let _: Operations.WaitForRequest.Output = try await handler.waitForRequest(step)
  try handler.registerHandlers(on: transport)
}
