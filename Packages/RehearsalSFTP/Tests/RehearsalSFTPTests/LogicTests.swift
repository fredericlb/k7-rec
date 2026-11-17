import XCTest
@testable import RehearsalSFTP

final class LogicTests: XCTestCase {
  func testAFingerprintIsTheUnpaddedSHA256OfTheKeyBlob() {
    // The blob "abc" (YWJj) hashes to ungWv48B... in base64, 44 characters with one pad that is dropped.
    XCTAssertEqual(SFTPLogic.fingerprint(openSSHKey: "ssh-ed25519 YWJj me@host"), "SHA256:ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0")
    XCTAssertNil(SFTPLogic.fingerprint(openSSHKey: "nonsense"))
  }

  func testModeBitsTellFoldersLinksAndFiles() {
    XCTAssertEqual(SFTPLogic.kind(permissions: 0o040755), .folder)
    XCTAssertEqual(SFTPLogic.kind(permissions: 0o120777), .link)
    XCTAssertEqual(SFTPLogic.kind(permissions: 0o100644), .file)
    XCTAssertEqual(SFTPLogic.kind(permissions: nil), .file)
  }

  func testEntriesSortFoldersFirstWithoutCaseAndWithoutDots() {
    let all = [SFTPEntry(name: "b.mp3", isDirectory: false), SFTPEntry(name: "..", isDirectory: true), SFTPEntry(name: "Zed", isDirectory: true),
               SFTPEntry(name: "A.mp3", isDirectory: false), SFTPEntry(name: ".", isDirectory: true), SFTPEntry(name: "alpha", isDirectory: true)]
    XCTAssertEqual(SFTPLogic.sorted(all).map(\.name), ["alpha", "Zed", "A.mp3", "b.mp3"])
  }

  func testPathsJoinWithOneSlash() {
    XCTAssertEqual(SFTPLogic.join("/a", "b"), "/a/b")
    XCTAssertEqual(SFTPLogic.join("/", "b"), "/b")
  }

  func testErrorsSaySomethingUseful() {
    XCTAssertTrue(SFTPError.hostKeyChanged(expected: "x", got: "y").localizedDescription.contains("identity changed"))
    XCTAssertTrue(SFTPError.loginFailed.localizedDescription.contains("refused"))
  }
}
