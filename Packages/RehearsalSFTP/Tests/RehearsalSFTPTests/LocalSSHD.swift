// LocalSSHD.swift: a throwaway sshd on the loopback, run as the current user, with a key login and the sftp subsystem.
// What a reader gets wrong: a user process cannot check passwords, so the tests log in with a key.
import Foundation
import XCTest

final class LocalSSHD {
  let dir: URL
  let root: URL
  let port: Int
  private let process = Process()
  private(set) var userKey = ""
  private(set) var otherKey = ""
  private(set) var hostFingerprint = ""

  init() throws {
    guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd"), FileManager.default.isExecutableFile(atPath: "/usr/libexec/sftp-server") else {
      throw XCTSkip("no sshd on this machine")
    }
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("sshd-\(UUID().uuidString)")
    root = dir.appendingPathComponent("root")
    port = Int.random(in: 20_000..<40_000)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Music/Live"), withIntermediateDirectories: true)
    try Data(repeating: 7, count: 300_000).write(to: root.appendingPathComponent("Music/a song.mp3"))
    try Data("hi".utf8).write(to: root.appendingPathComponent("notes.txt"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("Music"))
    for name in ["host_key", "user_key", "other_key"] {
      try Self.run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", dir.appendingPathComponent(name).path])
    }
    try FileManager.default.copyItem(at: dir.appendingPathComponent("user_key.pub"), to: dir.appendingPathComponent("authorized_keys"))
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("authorized_keys").path)
    userKey = try String(contentsOf: dir.appendingPathComponent("user_key"), encoding: .utf8)
    otherKey = try String(contentsOf: dir.appendingPathComponent("other_key"), encoding: .utf8)
    hostFingerprint = try Self.run("/usr/bin/ssh-keygen", ["-lf", dir.appendingPathComponent("host_key.pub").path]).split(separator: " ")[1].description
    try """
      Port \(port)
      ListenAddress 127.0.0.1
      HostKey \(dir.path)/host_key
      AuthorizedKeysFile \(dir.path)/authorized_keys
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      UsePAM no
      StrictModes no
      Subsystem sftp /usr/libexec/sftp-server
      LogLevel QUIET
      """.write(to: dir.appendingPathComponent("sshd_config"), atomically: true, encoding: .utf8)
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
    process.arguments = ["-D", "-e", "-f", dir.appendingPathComponent("sshd_config").path]
    process.standardError = FileHandle.nullDevice
    try process.run()
    guard Self.waitForPort(port) else { stop(); throw XCTSkip("the throwaway sshd did not start") }
  }

  func stop() {
    if process.isRunning { process.terminate(); process.waitUntilExit() }
    try? FileManager.default.removeItem(at: dir)
  }

  @discardableResult
  private static func run(_ tool: String, _ args: [String]) throws -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = out
    try p.run()
    p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  }

  private static func waitForPort(_ port: Int) -> Bool {
    for _ in 0..<50 {
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      var addr = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: UInt16(port).bigEndian,
                             sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
      let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
      close(fd)
      if ok { return true }
      Thread.sleep(forTimeInterval: 0.1)
    }
    return false
  }
}
