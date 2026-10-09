import Darwin
import Foundation
import SwiftUI

@main
struct ApproveHubApplication {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard !arguments.isEmpty else { return }
    let helper = URL(fileURLWithPath: CommandLine.arguments[0])
      .deletingLastPathComponent().appendingPathComponent("approve-hub-service")
    guard FileManager.default.isExecutableFile(atPath: helper.path) else {
      fputs("ApproveHub Service helper is missing; run swift build first.\n", stderr)
      exit(1)
    }
    let process = Process()
    process.executableURL = helper
    process.arguments = ["--owner"] + arguments
    do {
      try process.run()
      process.waitUntilExit()
      exit(process.terminationStatus)
    } catch {
      fputs("Could not start ApproveHub Service helper.\n", stderr)
      exit(1)
    }
  }
}
