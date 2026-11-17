// SecureSocket.swift: a blocking TCP socket that can be upgraded to TLS in place, with a read/write timeout.
// What a reader gets wrong: SecureTransport is deprecated, but it alone upgrades an open socket (AUTH TLS) and
// lets a data connection resume the control connection's session, which FTPS servers ask for (docs/ftp.md).

import Foundation
import Security

@available(iOS, deprecated: 13.0, message: "SecureTransport is the only API that can upgrade an open socket and reuse a session")
final class SecureSocket: @unchecked Sendable {
  /// Seconds without a byte after which a read or a write gives up.
  static let idle: TimeInterval = 20
  let fd: Int32
  var context: SSLContext?
  /// `errSSLServerAuthCompleted`, which the SDK no longer exports: the handshake paused for us to judge the certificate.
  private static let serverAuthCompleted: OSStatus = -9841
  private let lock = NSLock()
  private var shut = false
  fileprivate var timedOut = false

  init(fd: Int32) {
    self.fd = fd
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var t = timeval(tv_sec: Int(Self.idle), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &t, socklen_t(MemoryLayout<timeval>.size))
  }

  deinit { Darwin.close(fd) }

  var isClosed: Bool { lock.withLock { shut } }

  /// Resolves `host` and connects to the first address that answers within `timeout`.
  static func connect(host: String, port: UInt16, timeout: TimeInterval = 10) throws -> SecureSocket {
    var hints = addrinfo()
    hints.ai_socktype = SOCK_STREAM
    var found: UnsafeMutablePointer<addrinfo>?
    let rc = getaddrinfo(host, String(port), &hints, &found)
    guard rc == 0, let first = found else { throw FTPError.unreachable(String(cString: gai_strerror(rc))) }
    defer { freeaddrinfo(found) }
    var addresses: [UnsafeMutablePointer<addrinfo>] = []
    var cursor: UnsafeMutablePointer<addrinfo>? = first
    while let a = cursor { addresses.append(a); cursor = a.pointee.ai_next }
    var last = "no address"
    for a in addresses {
      do { return try attempt(a.pointee, timeout: timeout) } catch let FTPError.unreachable(why) { last = why }
    }
    throw FTPError.unreachable(last)
  }

  private static func attempt(_ ai: addrinfo, timeout: TimeInterval) throws -> SecureSocket {
    let s = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
    guard s >= 0 else { throw FTPError.unreachable(String(cString: strerror(errno))) }
    let flags = fcntl(s, F_GETFL)
    _ = fcntl(s, F_SETFL, flags | O_NONBLOCK)
    func fail(_ why: String) -> FTPError { Darwin.close(s); return .unreachable(why) }
    if Darwin.connect(s, ai.ai_addr, ai.ai_addrlen) != 0, errno != EINPROGRESS { throw fail(String(cString: strerror(errno))) }
    var p = pollfd(fd: s, events: Int16(POLLOUT), revents: 0)
    let n = poll(&p, 1, Int32(timeout * 1000))
    guard n > 0 else { throw fail(n == 0 ? "timed out" : String(cString: strerror(errno))) }
    var err: Int32 = 0
    var size = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &size)
    guard err == 0 else { throw fail(String(cString: strerror(err))) }
    _ = fcntl(s, F_SETFL, flags)
    return SecureSocket(fd: s)
  }

  // MARK: TLS

  /// Upgrades the open socket to TLS; the peer id lets another socket resume this session.
  func startTLS(host: String, peerID: String, trustAnyCertificate: Bool) throws {
    guard let ctx = SSLCreateContext(nil, .clientSide, .streamType) else { throw FTPError.tls("no TLS context") }
    try setUp(ctx)
    SSLSetProtocolVersionMin(ctx, .tlsProtocol12)
    SSLSetPeerDomainName(ctx, host, host.utf8.count)
    SSLSetPeerID(ctx, peerID, peerID.utf8.count)
    SSLSetSessionOption(ctx, .breakOnServerAuth, true)
    try handshake(ctx) { try Self.verify(ctx, host: host, trustAnyCertificate: trustAnyCertificate) }
  }

  /// The server side of the same upgrade, for the tests' in-process server.
  func startServerTLS(identity: SecIdentity) throws {
    guard let ctx = SSLCreateContext(nil, .serverSide, .streamType) else { throw FTPError.tls("no TLS context") }
    try setUp(ctx)
    SSLSetCertificate(ctx, [identity] as CFArray)
    try handshake(ctx) {}
  }

  private func setUp(_ ctx: SSLContext) throws {
    SSLSetIOFuncs(ctx, Self.readCallback, Self.writeCallback)
    SSLSetConnection(ctx, Unmanaged.passUnretained(self).toOpaque())
    context = ctx
  }

  private func handshake(_ ctx: SSLContext, onServerAuth: () throws -> Void) throws {
    while true {
      let status = SSLHandshake(ctx)
      switch status {
      case errSecSuccess: return
      case errSSLWouldBlock: continue
      case Self.serverAuthCompleted: try onServerAuth()
      default: context = nil; throw failure(status, during: "the TLS handshake")
      }
    }
  }

  private static func verify(_ ctx: SSLContext, host: String, trustAnyCertificate: Bool) throws {
    guard !trustAnyCertificate else { return }
    var trust: SecTrust?
    SSLCopyPeerTrust(ctx, &trust)
    guard let trust else { throw FTPError.untrustedCertificate("the server sent no certificate") }
    SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
    var error: CFError?
    guard SecTrustEvaluateWithError(trust, &error) else {
      throw FTPError.untrustedCertificate((error as Error?)?.localizedDescription ?? "the certificate is not trusted")
    }
  }

  // MARK: I/O

  /// The next bytes, nil once the peer ended the stream.
  func read(max: Int) throws -> Data? {
    guard !isClosed else { throw FTPError.unreachable("the connection is closed") }
    var buffer = [UInt8](repeating: 0, count: max)
    guard let ctx = context else {
      let n = recv(fd, &buffer, max, 0)
      if n > 0 { return Data(buffer[0..<n]) }
      if n == 0 { return nil }
      throw ioError()
    }
    while true {
      var got = 0
      let status = SSLRead(ctx, &buffer, max, &got)
      if got > 0 { return Data(buffer[0..<got]) }
      switch status {
      case errSSLWouldBlock: continue
      case errSSLClosedGraceful, errSSLClosedNoNotify: return nil
      default: throw failure(status, during: "a read")
      }
    }
  }

  func write(_ data: Data) throws {
    guard !isClosed else { throw FTPError.unreachable("the connection is closed") }
    guard let ctx = context else { return try data.withUnsafeBytes { try Self.sendAll(fd, $0) } }
    var offset = 0
    while offset < data.count {
      var done = 0
      let status = data.withUnsafeBytes { SSLWrite(ctx, $0.baseAddress! + offset, data.count - offset, &done) }
      offset += done
      guard status == errSecSuccess || status == errSSLWouldBlock else { throw failure(status, during: "a write") }
    }
  }

  /// Tells the peer nothing more is coming (a TLS close first), without closing the read side.
  func finish() {
    if let ctx = context { SSLClose(ctx) }
    shutdown(fd, SHUT_WR)
  }

  /// Ends the connection; a read blocked on it wakes up.
  func close() {
    let first = lock.withLock { () -> Bool in defer { shut = true }; return !shut }
    if first { shutdown(fd, SHUT_RDWR) }
  }

  private func ioError() -> FTPError {
    if timedOut || errno == EAGAIN || errno == EWOULDBLOCK { return .unreachable("the server stopped answering") }
    return .unreachable(String(cString: strerror(errno)))
  }

  private func failure(_ status: OSStatus, during what: String) -> FTPError {
    if timedOut { return .unreachable("the server stopped answering") }
    if isClosed { return .unreachable("the connection is closed") }
    let text = (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
    return status == errSSLClosedAbort ? .unreachable("the server closed the connection") : .tls("\(what) failed: \(text)")
  }

  private static func sendAll(_ fd: Int32, _ bytes: UnsafeRawBufferPointer) throws {
    var sent = 0
    while sent < bytes.count {
      let n = send(fd, bytes.baseAddress! + sent, bytes.count - sent, 0)
      if n <= 0 { throw FTPError.unreachable(String(cString: strerror(errno))) }
      sent += n
    }
  }

  private static let readCallback: SSLReadFunc = { connection, data, length in
    let socket = Unmanaged<SecureSocket>.fromOpaque(connection).takeUnretainedValue()
    let want = length.pointee
    let n = recv(socket.fd, data, want, 0)
    if n > 0 { length.pointee = n; return n < want ? errSSLWouldBlock : errSecSuccess }
    length.pointee = 0
    if n == 0 { return errSSLClosedGraceful }
    if errno == EINTR { return errSSLWouldBlock }
    if errno == EAGAIN || errno == EWOULDBLOCK { socket.timedOut = true }
    return errSSLClosedAbort
  }

  private static let writeCallback: SSLWriteFunc = { connection, data, length in
    let socket = Unmanaged<SecureSocket>.fromOpaque(connection).takeUnretainedValue()
    let want = length.pointee
    var sent = 0
    while sent < want {
      let n = send(socket.fd, data + sent, want - sent, 0)
      if n <= 0 { length.pointee = sent; return errSSLClosedAbort }
      sent += n
    }
    length.pointee = sent
    return errSecSuccess
  }
}
