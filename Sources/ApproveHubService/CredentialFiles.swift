import CryptoKit
import Darwin
import Foundation

struct CredentialFiles: Sendable {
  let root: URL

  static var ownerRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ApproveHub", isDirectory: true)
  }

  private var stateURL: URL { root.appendingPathComponent("identity.json") }
  private var pendingURL: URL { root.appendingPathComponent("pending-identity.json") }
  private var stateLockURL: URL { root.appendingPathComponent("identity.lock") }
  private var serviceLockURL: URL { root.appendingPathComponent("service.lock") }
  private var acknowledgementURL: URL { root.appendingPathComponent("applied-revision.json") }

  func ensureDirectory() throws {
    do {
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch { throw CredentialError.storageFailure }
    var info = stat()
    guard lstat(root.path, &info) == 0,
      (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
      info.st_uid == getuid(),
      (info.st_mode & 0o077) == 0
    else { throw CredentialError.insecureStorage }
  }

  func withStateLock<T>(_ body: () throws -> T) throws -> T {
    try ensureDirectory()
    let descriptor = try openLock(stateLockURL)
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw CredentialError.storageFailure }
    defer { flock(descriptor, LOCK_UN) }
    return try body()
  }

  func withServiceStopped<T>(_ body: () throws -> T) throws -> T {
    try ensureDirectory()
    let descriptor = try openLock(serviceLockURL)
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CredentialError.serviceRunning }
    defer { flock(descriptor, LOCK_UN) }
    guard try fixedPortIsAvailable() else { throw CredentialError.portOccupied }
    return try body()
  }

  private func fixedPortIsAvailable() throws -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw CredentialError.storageFailure }
    defer { close(descriptor) }
    var reuseAddress: Int32 = 1
    guard
      setsockopt(
        descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress,
        socklen_t(MemoryLayout<Int32>.size)) == 0
    else { throw CredentialError.storageFailure }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(46_931).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    if result == 0 {
      if listen(descriptor, 1) == 0 { return true }
      if errno == EADDRINUSE { return false }
      throw CredentialError.storageFailure
    }
    if errno == EADDRINUSE { return false }
    throw CredentialError.storageFailure
  }

  func serviceIsRunning() throws -> Bool {
    try ensureDirectory()
    let descriptor = try openLock(serviceLockURL)
    defer { close(descriptor) }
    if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
      flock(descriptor, LOCK_UN)
      return false
    }
    guard errno == EWOULDBLOCK else { throw CredentialError.storageFailure }
    return true
  }

  func acquireServiceLease() throws -> ServiceLease {
    try ensureDirectory()
    let descriptor = try openLock(serviceLockURL)
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      throw CredentialError.serviceRunning
    }
    guard let identity = ProcessIdentity.read(pid: getpid()) else {
      flock(descriptor, LOCK_UN)
      close(descriptor)
      throw CredentialError.storageFailure
    }
    let record = ServiceLeaseRecord(
      id: UUID(), pid: getpid(),
      identity: identity,
      executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0]
    )
    do {
      try writeDescriptor(descriptor, data: JSONEncoder().encode(record))
      return ServiceLease(descriptor: descriptor, record: record)
    } catch {
      flock(descriptor, LOCK_UN)
      close(descriptor)
      throw error
    }
  }

  func readServiceLease() throws -> ServiceLeaseRecord? {
    guard let data = try read(serviceLockURL), !data.isEmpty else { return nil }
    // The holder writes this file just after taking the lock; a concurrent
    // reader may observe the short, incomplete write before its fsync.
    return try? JSONDecoder().decode(ServiceLeaseRecord.self, from: data)
  }

  func acknowledge(revision: UInt64, lease: ServiceLease) throws {
    try write(
      JSONEncoder().encode(ServiceAcknowledgement(leaseID: lease.record.id, revision: revision)),
      to: acknowledgementURL
    )
  }

  func readAcknowledgement() throws -> ServiceAcknowledgement? {
    guard let data = try read(acknowledgementURL) else { return nil }
    do { return try JSONDecoder().decode(ServiceAcknowledgement.self, from: data) } catch {
      throw CredentialError.corruptState
    }
  }

  func readState() throws -> CredentialState? {
    guard let data = try read(stateURL) else { return nil }
    do {
      let decoded = try JSONDecoder().decode(CredentialState.self, from: data)
      return try decoded.validated()
    } catch let error as CredentialError {
      throw error
    } catch {
      throw CredentialError.corruptState
    }
  }

  func readPending() throws -> PendingCredentialChange? {
    guard let data = try read(pendingURL) else { return nil }
    do {
      return try JSONDecoder().decode(PendingCredentialChange.self, from: data).validated()
    } catch {
      if let error = error as? CredentialError { throw error }
      throw CredentialError.corruptState
    }
  }

  func writeState(_ state: CredentialState) throws {
    try write(JSONEncoder().encode(state.validated()), to: stateURL)
  }

  func writePending(_ pending: PendingCredentialChange) throws {
    try write(JSONEncoder().encode(pending.validated()), to: pendingURL)
  }

  func removePending() throws {
    if unlink(pendingURL.path) != 0 && errno != ENOENT { throw CredentialError.storageFailure }
    try syncDirectory()
  }

  private func openLock(_ url: URL) throws -> Int32 {
    let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CredentialError.storageFailure }
    var info = stat()
    guard fstat(descriptor, &info) == 0,
      (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
      info.st_uid == getuid(),
      (info.st_mode & 0o077) == 0
    else {
      close(descriptor)
      throw CredentialError.insecureStorage
    }
    return descriptor
  }

  private func read(_ url: URL) throws -> Data? {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      throw CredentialError.storageFailure
    }
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0,
      (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
      info.st_uid == getuid(),
      (info.st_mode & 0o077) == 0,
      info.st_size <= 8_000_000
    else { throw CredentialError.insecureStorage }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count < 0 { throw CredentialError.storageFailure }
      if count == 0 { break }
      data.append(contentsOf: buffer.prefix(count))
      if data.count > 8_000_000 { throw CredentialError.corruptState }
    }
    return data
  }

  private func write(_ data: Data, to url: URL) throws {
    try ensureDirectory()
    let temporary = root.appendingPathComponent(".\(UUID().uuidString).tmp")
    let descriptor = open(
      temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CredentialError.storageFailure }
    defer { close(descriptor) }
    do {
      try data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { throw CredentialError.storageFailure }
        var position = 0
        while position < data.count {
          let written = Darwin.write(descriptor, base.advanced(by: position), data.count - position)
          guard written > 0 else { throw CredentialError.storageFailure }
          position += written
        }
      }
      guard fsync(descriptor) == 0, rename(temporary.path, url.path) == 0 else {
        throw CredentialError.storageFailure
      }
      try syncDirectory()
    } catch {
      _ = unlink(temporary.path)
      throw error
    }
  }

  private func writeDescriptor(_ descriptor: Int32, data: Data) throws {
    guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) == 0 else {
      throw CredentialError.storageFailure
    }
    try data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { throw CredentialError.storageFailure }
      var position = 0
      while position < data.count {
        let written = Darwin.write(descriptor, base.advanced(by: position), data.count - position)
        guard written > 0 else { throw CredentialError.storageFailure }
        position += written
      }
    }
    guard fsync(descriptor) == 0 else { throw CredentialError.storageFailure }
  }

  private func syncDirectory() throws {
    let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw CredentialError.storageFailure }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else { throw CredentialError.storageFailure }
  }
}

enum CredentialChangeKind: String, Codable {
  case setup
  case rotate
  case resetDecider
}

struct PendingCredentialChange: Codable {
  let kind: CredentialChangeKind
  let baseStateDigest: Data?
  let candidate: CredentialState

  init(kind: CredentialChangeKind, baseState: CredentialState?, candidate: CredentialState) throws {
    self.kind = kind
    baseStateDigest = try baseState.map(Self.digest)
    self.candidate = candidate
    _ = try validated()
  }

  func validated() throws -> Self {
    _ = try candidate.validated()
    switch kind {
    case .setup:
      guard baseStateDigest == nil, candidate.revision == 1 else {
        throw CredentialError.corruptState
      }
    case .rotate, .resetDecider:
      guard baseStateDigest?.count == 32, candidate.revision > 1 else {
        throw CredentialError.corruptState
      }
    }
    return self
  }

  func validateRecovery(current: CredentialState?) throws {
    _ = try validated()
    if current == candidate { return }
    if let current, let baseStateDigest {
      let expectedRevision =
        current.revision < candidate.revision
        && current.revision + 1 == candidate.revision
      if expectedRevision {
        let currentDigest = try Self.digest(current)
        if currentDigest == baseStateDigest { return }
      }
    }
    if current == nil, kind == .setup { return }
    throw CredentialError.corruptState
  }

  private static func digest(_ state: CredentialState) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Data(SHA256.hash(data: try encoder.encode(state.validated())))
  }
}

struct ServiceLeaseRecord: Codable, Equatable {
  let id: UUID
  let pid: Int32
  let identity: ProcessIdentity
  let executablePath: String
}

struct ProcessIdentity: Codable, Equatable {
  let ownerUID: UInt32
  let startSeconds: UInt64
  let startMicroseconds: UInt64

  static func read(pid: Int32) -> Self? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
      info.pbi_pid == UInt32(pid)
    else { return nil }
    return Self(
      ownerUID: info.pbi_uid,
      startSeconds: info.pbi_start_tvsec,
      startMicroseconds: info.pbi_start_tvusec
    )
  }
}

struct ServiceAcknowledgement: Codable {
  let leaseID: UUID
  let revision: UInt64
}

final class ServiceLease {
  let record: ServiceLeaseRecord
  private let descriptor: Int32

  init(descriptor: Int32, record: ServiceLeaseRecord) {
    self.descriptor = descriptor
    self.record = record
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
