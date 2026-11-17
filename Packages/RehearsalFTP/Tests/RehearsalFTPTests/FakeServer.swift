// A small in-process FTPS server on the loopback: explicit or implicit TLS, passive transfers, MLSD (or not) and LIST.
import Foundation
@testable import RehearsalFTP

final class FakeFTPServer: @unchecked Sendable {
  struct Node { var data: Data? }  // nil data is a folder
  var tree: [String: Node] = [:]
  var supportsMLSD = true
  var refusesWrites = false
  /// TLS from the first byte, as on port 990.
  var implicit = false
  /// Whether the server answers AUTH TLS; false makes it a plain server.
  var offersTLS = true
  var user = "me", password = "secret"
  /// What the last data connections looked like, for the tests to read.
  private let lock = NSLock()
  private var seen = (dataEncrypted: false, auth: false)
  private var live: [SecureSocket] = []
  private var listenFD: Int32 = -1
  private(set) var port = 0

  var sawEncryptedData: Bool { lock.withLock { seen.dataEncrypted } }
  var sawAuthTLS: Bool { lock.withLock { seen.auth } }

  func start() throws {
    listenFD = try Self.listen()
    port = Self.port(of: listenFD)
    let fd = listenFD
    Thread.detachNewThread { [self] in
      while true {
        let c = accept(fd, nil, nil)
        if c < 0 { return }
        let socket = SecureSocket(fd: c)
        lock.withLock { live.append(socket) }
        Thread.detachNewThread { Session(server: self, control: socket).run() }
      }
    }
  }

  func stop() {
    if listenFD >= 0 { shutdown(listenFD, SHUT_RDWR); Darwin.close(listenFD); listenFD = -1 }
    lock.withLock { live }.forEach { $0.close() }
  }

  fileprivate func track(_ s: SecureSocket) { lock.withLock { live.append(s) } }
  fileprivate func note(auth: Bool = false, encrypted: Bool = false) {
    lock.withLock { if auth { seen.auth = true }; if encrypted { seen.dataEncrypted = true } }
  }

  static func listen() throws -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard ok == 0, Darwin.listen(fd, 8) == 0 else { throw FTPError.unreachable("cannot listen") }
    return fd
  }

  static func port(of fd: Int32) -> Int {
    var addr = sockaddr_in()
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) } }
    return Int(UInt16(bigEndian: addr.sin_port))
  }

  fileprivate func payload(_ verb: String, _ arg: String) -> Data? {
    if verb == "RETR" { return tree[arg]?.data }
    let base = arg.hasSuffix("/") ? arg : arg + "/"
    guard arg == "/" || tree[arg] != nil else { return nil }
    let children = tree.filter { $0.key.hasPrefix(base) && !$0.key.dropFirst(base.count).contains("/") && $0.key != base }
    var out = ""
    for (path, node) in children.sorted(by: { $0.key < $1.key }) {
      let name = String(path.dropFirst(base.count))
      if verb == "MLSD" { out += "type=\(node.data == nil ? "dir" : "file");size=\(node.data?.count ?? 0); \(name)\r\n" }
      else if let d = node.data { out += "-rw-r--r-- 1 u g \(d.count) Jan  1 12:00 \(name)\r\n" }
      else { out += "drwxr-xr-x 2 u g 4096 Jan  1 12:00 \(name)\r\n" }
    }
    return Data(out.utf8)
  }

  fileprivate final class Session {
    let server: FakeFTPServer
    let control: SecureSocket
    var buffer = Data()
    var data: Int32 = -1
    var loggedIn = false, secured = false, protected = false
    var named = ""

    init(server: FakeFTPServer, control: SecureSocket) { (self.server, self.control) = (server, control) }

    func run() {
      defer { control.close() }
      do {
        if server.implicit { try control.startServerTLS(identity: TestIdentity.identity); secured = true }
        try say("220 fake")
        while let line = try readLine() { try handle(line) }
      } catch {}
    }

    func say(_ text: String) throws { try control.write(Data((text + "\r\n").utf8)) }

    func readLine() throws -> String? {
      while true {
        if let end = buffer.firstIndex(of: 0x0A) {
          let line = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
          buffer.removeSubrange(buffer.startIndex...end)
          return line
        }
        guard let more = try control.read(max: 4096) else { return nil }
        buffer.append(more)
      }
    }

    func handle(_ line: String) throws {
      let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
      let verb = parts.first?.uppercased() ?? "", arg = parts.count > 1 ? parts[1] : ""
      switch verb {
      case "AUTH":
        guard server.offersTLS else { return try say("502 no tls") }
        server.note(auth: true)
        try say("234 go")
        try control.startServerTLS(identity: TestIdentity.identity)
        secured = true
      case "PBSZ": try say(secured ? "200 ok" : "503 no tls")
      case "PROT": protected = arg == "P"; try say(secured ? "200 ok" : "503 no tls")
      case "USER": named = arg; try say("331 password")
      case "PASS":
        loggedIn = named == server.user && arg == server.password
        try say(loggedIn ? "230 in" : "530 no")
      case "TYPE", "OPTS": try say("200 ok")
      case "QUIT": try say("221 bye")
      case "EPSV":
        if data >= 0 { Darwin.close(data) }
        data = try FakeFTPServer.listen()
        try say("229 Entering Extended Passive Mode (|||\(FakeFTPServer.port(of: data))|)")
      case "MLSD", "LIST", "RETR": try send(verb, arg)
      case "STOR", "APPE": try receive(verb, arg)
      default: try say("502 no")
      }
    }

    /// Accepts the data connection and, once 150 is out, does the TLS handshake a protected channel asks for.
    func open() throws -> SecureSocket {
      let fd = accept(data, nil, nil)
      Darwin.close(data)
      data = -1
      let s = SecureSocket(fd: fd)
      server.track(s)
      try say("150 go")
      if protected { try s.startServerTLS(identity: TestIdentity.identity); server.note(encrypted: true) }
      return s
    }

    func send(_ verb: String, _ arg: String) throws {
      guard loggedIn else { return try say("530 login") }
      if verb == "MLSD", !server.supportsMLSD { return try say("500 no") }
      guard let payload = server.payload(verb, arg) else { return try say("550 not found") }
      let s = try open()
      try s.write(payload)
      s.finish()
      s.close()
      try say("226 done")
    }

    func receive(_ verb: String, _ arg: String) throws {
      guard loggedIn else { return try say("530 login") }
      if server.refusesWrites { return try say("550 read only") }
      let s = try open()
      var got = Data()
      while let chunk = try s.read(max: 65_536) { got.append(chunk) }
      s.close()
      let old = server.tree[arg]?.data ?? Data()
      server.tree[arg] = .init(data: verb == "APPE" ? old + got : got)
      try say("226 stored")
    }
  }
}
