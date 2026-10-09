import Darwin
import Foundation

struct RevocationSync {
  let files: CredentialFiles

  func confirm(revision: UInt64) throws {
    guard try files.serviceIsRunning() else { return }
    let deadline = Date().addingTimeInterval(3)
    var lease: ServiceLeaseRecord?
    while Date() < deadline {
      if try !files.serviceIsRunning() { return }
      if lease == nil { lease = try files.readServiceLease() }
      if let lease, try isAcknowledged(revision, by: lease) { return }
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard let lease else { throw CredentialError.serviceShutdownUnconfirmed }
    try stopVerifiedService(lease)
  }

  private func isAcknowledged(_ revision: UInt64, by lease: ServiceLeaseRecord) throws -> Bool {
    guard let acknowledgement = try files.readAcknowledgement() else { return false }
    return acknowledgement.leaseID == lease.id && acknowledgement.revision >= revision
  }

  private func stopVerifiedService(_ lease: ServiceLeaseRecord) throws {
    guard lease.pid != getpid(), try matchesRunningLease(lease) else {
      throw CredentialError.serviceShutdownUnconfirmed
    }
    if kill(lease.pid, SIGTERM) != 0 {
      if try !files.serviceIsRunning() { return }
      throw CredentialError.serviceShutdownUnconfirmed
    }
    if try waitForShutdown(lease, seconds: 2) { return }
    guard try matchesRunningLease(lease) else {
      throw CredentialError.serviceShutdownUnconfirmed
    }
    if kill(lease.pid, SIGKILL) != 0 {
      if try !files.serviceIsRunning() { return }
      throw CredentialError.serviceShutdownUnconfirmed
    }
    guard try waitForShutdown(lease, seconds: 2) else {
      throw CredentialError.serviceShutdownUnconfirmed
    }
  }

  private func waitForShutdown(_ lease: ServiceLeaseRecord, seconds: TimeInterval) throws -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if try !files.serviceIsRunning() { return true }
      guard try matchesRunningLease(lease) else {
        throw CredentialError.serviceShutdownUnconfirmed
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return try !files.serviceIsRunning()
  }

  private func matchesRunningLease(_ lease: ServiceLeaseRecord) throws -> Bool {
    guard try files.serviceIsRunning(), try files.readServiceLease() == lease else { return false }
    guard ProcessIdentity.read(pid: lease.pid) == lease.identity else { return false }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let count = proc_pidpath(lease.pid, &path, UInt32(path.count))
    guard count > 0 else { return false }
    guard
      let currentPath = String(
        bytes: path.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), encoding: .utf8)
    else { return false }
    return ProcessIdentity.read(pid: lease.pid) == lease.identity
      && URL(fileURLWithPath: currentPath).resolvingSymlinksInPath().standardizedFileURL.path
        == URL(fileURLWithPath: lease.executablePath).resolvingSymlinksInPath().standardizedFileURL
        .path
  }
}
