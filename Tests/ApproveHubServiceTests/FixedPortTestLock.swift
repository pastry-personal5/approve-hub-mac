import Darwin
import Foundation

@testable import ApproveHubService

/// Cross-process exclusion for tests that bind or inspect the fixed listener.
final class FixedPortTestLock {
  private let descriptor: Int32

  init() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("approvehub-fixed-port-test.lock").path
    let opened = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard opened >= 0 else { throw CredentialError.storageFailure }
    guard flock(opened, LOCK_EX) == 0 else {
      close(opened)
      throw CredentialError.storageFailure
    }
    descriptor = opened
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
