import XCTest
@testable import RehearsalSFTP

final class SFTPTests: XCTestCase {
  private var server: LocalSSHD!

  override func setUpWithError() throws { server = try LocalSSHD() }
  override func tearDown() { server?.stop() }

  private func open(key: String? = nil, pinned: String? = nil, port: Int? = nil) async throws -> SFTPSession {
    try await SFTPSession.open(SFTPConfig(host: "127.0.0.1", port: port ?? server.port, user: NSUserName(), privateKey: key ?? server.userKey, pinnedKey: pinned))
  }

  private func path(_ name: String) -> String { server.root.path + "/" + name }

  func testListsAFolderFoldersFirstAndResolvesALink() async throws {
    let s = try await open()
    let entries = try await s.list(server.root.path)
    XCTAssertEqual(entries.map(\.name), ["link", "Music", "notes.txt"])
    XCTAssertEqual(entries.map(\.isDirectory), [true, true, false])
    let inside = try await s.list(path("Music"))
    XCTAssertEqual(inside.map(\.name), ["Live", "a song.mp3"])
    XCTAssertEqual(inside.last?.size, 300_000)
    s.close()
  }

  func testDownloadsAFileWholeAndReportsProgress() async throws {
    let s = try await open()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).mp3")
    defer { try? FileManager.default.removeItem(at: url) }
    let last = Counter()
    try await s.download(path("Music/a song.mp3"), to: url, progress: { last.set($0) })
    XCTAssertEqual(try Data(contentsOf: url), Data(repeating: 7, count: 300_000))
    XCTAssertEqual(last.value, 300_000)
    s.close()
  }

  func testAMissingFileFailsAndLeavesNoPartialFile() async throws {
    let s = try await open()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).mp3")
    do { try await s.download(path("nope.mp3"), to: url); XCTFail("expected a failure") } catch {
      guard case .refused = error as? SFTPError else { return XCTFail("got \(error)") }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    s.close()
  }

  func testAppendAddsToTheEndCreatesWhenMissingAndUploadReplaces() async throws {
    let s = try await open()
    try await s.append(Data("one\n".utf8), to: path("LOG.md"))
    try await s.append(Data("two\n".utf8), to: path("LOG.md"))
    XCTAssertEqual(try Data(contentsOf: server.root.appendingPathComponent("LOG.md")), Data("one\ntwo\n".utf8))
    try await s.upload(Data("fresh".utf8), to: path("LOG.md"))
    XCTAssertEqual(try Data(contentsOf: server.root.appendingPathComponent("LOG.md")), Data("fresh".utf8))
    s.close()
  }

  func testTheHostKeyIsReportedAndAMatchingPinIsAccepted() async throws {
    let first = try await open()
    XCTAssertEqual(first.hostKey, server.hostFingerprint)
    first.close()
    let again = try await open(pinned: first.hostKey)
    again.close()
  }

  func testAChangedHostKeyIsRefused() async throws {
    do { _ = try await open(pinned: "SHA256:AAAA"); XCTFail("expected a failure") } catch {
      XCTAssertEqual(error as? SFTPError, .hostKeyChanged(expected: "SHA256:AAAA", got: server.hostFingerprint))
    }
  }

  func testAKeyTheServerDoesNotKnowIsALoginFailure() async {
    do { _ = try await open(key: server.otherKey); XCTFail("expected a failure") } catch {
      XCTAssertEqual(error as? SFTPError, .loginFailed)
    }
  }

  func testNothingListeningIsUnreachable() async {
    do { _ = try await open(port: 1); XCTFail("expected a failure") } catch {
      guard case .unreachable = error as? SFTPError else { return XCTFail("got \(error)") }
    }
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var n: Int64 = 0
  func set(_ v: Int64) { lock.lock(); n = v; lock.unlock() }
  var value: Int64 { lock.lock(); defer { lock.unlock() }; return n }
}
