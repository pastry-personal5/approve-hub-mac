import ApproveHubCore
import Darwin
import Foundation
import Hummingbird
import OpenAPIHummingbird
import OpenAPIRuntime

@main
struct ApproveHubServiceEntryPoint {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    do {
      if arguments.first == "--owner" {
        let result = try OwnerCommands(store: commandStore()).run(
          Array(arguments.dropFirst()))
        print(result, terminator: "")
      } else if arguments.isEmpty {
        try await serve(store: commandStore())
      } else {
        fputs("Usage: approve-hub-service [--owner <command>]\n", stderr)
        exit(1)
      }
    } catch {
      let diagnostic =
        error is CredentialError
        ? OwnerCommands.diagnostic(for: error) : "ApproveHub Service could not start."
      fputs(diagnostic + "\n", stderr)
      exit(1)
    }
  }

  private static func serve(store: ServiceCredentialStore) async throws {
    let state = try store.currentState()
    let signer = try ServiceProofSigner(state: state)
    let lifecycle = RequestLifecycle()
    let runtime = try CredentialRuntime(store: store, lifecycle: lifecycle)
    try await runtime.applyCurrentState()
    let broker = ServiceEventBroker()
    let transitions = await lifecycle.transitions()
    let eventTask = Task {
      for await transition in transitions { await broker.observe(transition) }
    }
    do {
      let handler = ServiceAPIHandler(
        signer: signer, runtime: runtime, lifecycle: lifecycle, events: broker)
      let router = Router()
      try handler.registerHandlers(
        on: router,
        configuration: OpenAPIRuntime.Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
        middlewares: [ServiceHTTPBoundary(runtime: runtime)]
      )
      let application = Application(
        router: router,
        configuration: .init(address: .hostname("127.0.0.1", port: 46931))
      )
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await application.runService() }
        group.addTask { try await runtime.run() }
        _ = try await group.next()
        group.cancelAll()
      }
    } catch {
      eventTask.cancel()
      await broker.close()
      throw error
    }
    eventTask.cancel()
    await broker.close()
  }

  private static func commandStore() -> ServiceCredentialStore {
    #if DEBUG
      let environment = ProcessInfo.processInfo.environment
      let root = environment["APPROVE_HUB_TEST_ROOT"]
      let keychainService = environment["APPROVE_HUB_TEST_KEYCHAIN"]
      if let root, let keychainService {
        return ServiceCredentialStore(
          root: URL(fileURLWithPath: root, isDirectory: true),
          keychain: SystemCredentialKeychain(service: keychainService)
        )
      }
    #endif
    return ServiceCredentialStore()
  }
}
