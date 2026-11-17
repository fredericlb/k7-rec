import XCTest
@testable import RehearsalFTP

final class FTPTests: XCTestCase {
  private var server: FakeFTPServer!

  override func setUp() async throws {
    server = FakeFTPServer()
    server.tree = [
      "/Music": .init(data: nil), "/Music/a song.mp3": .init(data: Data(repeating: 7, count: 200_000)),
      "/Music/Live": .init(data: nil), "/notes.txt": .init(data: Data("hi".utf8)),
    ]
    try server.start()
  }

  override func tearDown() { server.stop() }

  private func open(
    password: String = "secret", security: FTPSecurity = .explicit, trustAnyCertificate: Bool = true
  ) async throws -> FTPSession {
    try await FTPSession.open(
      FTPConfig(host: "127.0.0.1", port: server.port, user: "me", password: password, security: security, trustAnyCertificate: trustAnyCertificate))
  }

  func testListsAFolderFoldersFirst() async throws {
    let s = try await open()
    let entries = try await s.list("/Music")
    XCTAssertEqual(entries.map(\.name), ["Live", "a song.mp3"])
    XCTAssertEqual(entries.map(\.isDirectory), [true, false])
    XCTAssertEqual(entries.last?.size, 200_000)
    s.close()
  }

  func testFallsBackToLISTWhenThereIsNoMLSD() async throws {
    server.supportsMLSD = false
    let s = try await open()
    let entries = try await s.list("/Music")
    XCTAssertEqual(entries.map(\.name), ["Live", "a song.mp3"])
    s.close()
  }

  func testDownloadsAFileWhole() async throws {
    let s = try await open()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).mp3")
    defer { try? FileManager.default.removeItem(at: url) }
    try await s.download("/Music/a song.mp3", to: url)
    XCTAssertEqual(try Data(contentsOf: url), Data(repeating: 7, count: 200_000))
    s.close()
  }

  func testAMissingFileFailsAndLeavesNoPartialFile() async throws {
    let s = try await open()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).mp3")
    do { try await s.download("/nope.mp3", to: url); XCTFail("expected a failure") } catch {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    s.close()
  }

  func testAWrongPasswordIsALoginFailure() async {
    do { _ = try await open(password: "wrong"); XCTFail("expected a failure") } catch {
      XCTAssertEqual(error as? FTPError, .loginFailed)
    }
  }

  func testNothingListeningIsUnreachable() async {
    server.stop()
    do { _ = try await open(); XCTFail("expected a failure") } catch {
      guard case .unreachable = error as? FTPError else { return XCTFail("got \(error)") }
    }
  }

  func testListingStylesParse() {
    let unix = "drwxr-xr-x  2 ftp ftp 4096 Jan  1 12:00 My Folder\n-rw-r--r--  1 ftp ftp 1234 Mar 03  2021 song one.flac\nlrwxrwxrwx 1 a b 5 Jan 1 12:00 link -> x\n"
    XCTAssertEqual(FTPListing.parseList(unix).map(\.name), ["My Folder", "song one.flac", "link"])
    XCTAssertEqual(FTPListing.parseList("01-02-21  10:00AM       <DIR>          Docs\n01-02-21  10:00AM  42 a.wav\n").map(\.isDirectory), [true, false])
    XCTAssertEqual(FTPListing.parseMLSD("type=cdir; .\ntype=dir; Sub\ntype=file;size=9; x y.mp3\n").map(\.name), ["Sub", "x y.mp3"])
  }

  func testThePassivePortComesFromThe227Reply() {
    XCTAssertEqual(FTPSession.passivePort("Entering Passive Mode (10,0,0,5,195,80)"), 195 * 256 + 80)
    XCTAssertNil(FTPSession.passivePort("nonsense"))
  }

  func testAppendAddsToTheEndAndCreatesWhenMissing() async throws {
    let s = try await open()
    try await s.append(Data("one\n".utf8), to: "/LOG.md")
    try await s.append(Data("two\n".utf8), to: "/LOG.md")
    XCTAssertEqual(server.tree["/LOG.md"]?.data, Data("one\ntwo\n".utf8))
    try await s.upload(Data("fresh".utf8), to: "/LOG.md")
    XCTAssertEqual(server.tree["/LOG.md"]?.data, Data("fresh".utf8))
    s.close()
  }

  func testAServerThatRefusesWritesIsARefusalNotAHang() async throws {
    server.refusesWrites = true
    let s = try await open()
    do { try await s.append(Data("x".utf8), to: "/LOG.md"); XCTFail("expected a refusal") } catch {
      guard case .refused = error as? FTPError else { return XCTFail("got \(error)") }
    }
    s.close()
  }

  func testExplicitTLSEncryptsTheControlAndTheDataConnections() async throws {
    let s = try await open()
    _ = try await s.list("/Music")
    XCTAssertTrue(server.sawAuthTLS)
    XCTAssertTrue(server.sawEncryptedData)
    s.close()
  }

  func testImplicitTLSStartsEncryptedWithNoAuthCommand() async throws {
    server.implicit = true
    let s = try await open(security: .implicit)
    let entries = try await s.list("/Music")
    XCTAssertEqual(entries.count, 2)
    XCTAssertFalse(server.sawAuthTLS)
    XCTAssertTrue(server.sawEncryptedData)
    s.close()
  }

  func testAServerWithoutTLSIsRefusedNotUsedInTheClear() async {
    server.offersTLS = false
    do { _ = try await open(); XCTFail("expected a failure") } catch {
      XCTAssertEqual(error as? FTPError, .noTLS)
    }
  }

  func testACertificateTheSystemDoesNotTrustIsRefusedUnlessAccepted() async throws {
    do { _ = try await open(trustAnyCertificate: false); XCTFail("expected a failure") } catch {
      guard case .untrustedCertificate = error as? FTPError else { return XCTFail("got \(error)") }
    }
    let s = try await open(trustAnyCertificate: true)
    s.close()
  }

  func testDefaultPortsFollowTheSecurity() {
    XCTAssertEqual(FTPConfig(host: "h").port, 21)
    XCTAssertEqual(FTPConfig(host: "h", security: .implicit).port, 990)
  }
}
