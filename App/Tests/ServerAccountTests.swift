import XCTest
@testable import Rehearsal

@MainActor
final class ServerAccountTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "ftp-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func account(fails: Bool = false, secrets: SecretStore = MemorySecrets()) -> ServerAccount {
        ServerAccount(files: FakeRemoteFiles(fails: fails), defaults: defaults, secrets: secrets)
    }

    func testALoginThatWorksIsKeptAndItsPasswordGoesToTheSecretStore() async {
        let secrets = MemorySecrets()
        let a = account(secrets: secrets)
        (a.host, a.user, a.password) = (" nas.local ", "me", "pw")
        await a.connect()
        XCTAssertTrue(a.connected)
        XCTAssertEqual(a.account, RemoteAccount(host: "nas.local", port: 21, user: "me", password: "pw", folder: "/"))
        XCTAssertEqual(secrets.secret(for: "server.password"), "pw")
        XCTAssertNil(defaults.string(forKey: "server.password"), "the password is never in UserDefaults")
        let again = account(secrets: secrets)
        XCTAssertTrue(again.connected)
        XCTAssertEqual(again.password, "pw")
    }

    func testALoginThatFailsKeepsNothing() async {
        let a = account(fails: true)
        a.host = "nas.local"
        await a.connect()
        XCTAssertFalse(a.connected)
        XCTAssertNotNil(a.failure)
        XCTAssertFalse(defaults.bool(forKey: "server.connected"))
    }

    func testABadAddressOrPortIsRefusedBeforeAnyConnection() async {
        let a = account()
        await a.connect()
        XCTAssertEqual(a.failure, "Enter the server's address.")
        a.host = "x"; a.port = "99999"
        await a.connect()
        XCTAssertEqual(a.failure, "The port is a number from 1 to 65535.")
    }

    func testDisconnectForgetsTheServerAndThePassword() async {
        let secrets = MemorySecrets()
        let a = account(secrets: secrets)
        (a.host, a.password) = ("nas.local", "pw")
        await a.connect()
        a.disconnect()
        XCTAssertFalse(a.connected)
        XCTAssertNil(secrets.secret(for: "server.password"))
        XCTAssertFalse(account(secrets: secrets).connected)
    }

    func testOnlyFoldersAndAudioFilesAreOffered() {
        XCTAssertTrue(RemoteEntry(name: "a.FLAC", isFolder: false).isAudio)
        XCTAssertFalse(RemoteEntry(name: "notes.txt", isFolder: false).isAudio)
        XCTAssertFalse(RemoteEntry(name: "song.mp3", isFolder: true).isAudio)
    }

    func testPickedFilesAreDownloadedImportedAndTheTempFolderGoes() async {
        let library = FakeSongLibrary()
        let a = account()
        a.host = "nas.local"
        await a.connect()
        let model = AppModel(library: library, server: a)
        model.looksUpLyrics = false
        let ok = await model.importFromServer(["/intro.mp3", "/Live/jam.flac"])
        XCTAssertTrue(ok)
        XCTAssertEqual(library.imported.map(\.lastPathComponent), ["intro.mp3", "jam.flac"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.imported[0].path), "the temp copy is removed")
    }

    func testAFailedDownloadImportsNothingAndSaysWhy() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library, server: account(fails: true))
        let ok = await model.importFromServer(["/intro.mp3"])
        XCTAssertFalse(ok)
        XCTAssertTrue(library.imported.isEmpty)
    }

    func testAMissingSongIsAppendedAsOneLineAtTheRootOfTheServer() async {
        let files = FakeRemoteFiles()
        let a = ServerAccount(files: files, defaults: defaults, secrets: MemorySecrets())
        a.host = "nas.local"
        await a.connect()
        let model = AppModel(server: a)
        await model.reportMissingSong(artist: "  Zaho de\nSagazan ", title: "Je   rêve")
        XCTAssertEqual(files.appended.entries.map(\.path), ["/MISSING-SONGS.md"])
        XCTAssertEqual(files.appended.entries.map(\.text), ["- Zaho de Sagazan - Je rêve\n"])
        XCTAssertEqual(model.notice, "Zaho de Sagazan - Je rêve was added to MISSING-SONGS.md.")
    }

    func testAMissingSongNeedsBothAnArtistAndATitleAndSaysWhenTheServerFails() async {
        let files = FakeRemoteFiles()
        let a = ServerAccount(files: files, defaults: defaults, secrets: MemorySecrets())
        a.host = "nas.local"
        await a.connect()
        let model = AppModel(server: a)
        await model.reportMissingSong(artist: "Someone", title: "  ")
        XCTAssertEqual(model.notice, "Enter an artist and a title.")
        XCTAssertTrue(files.appended.entries.isEmpty)
        let down = ServerAccount(files: FakeRemoteFiles(fails: true), defaults: defaults, secrets: MemorySecrets())
        let offline = AppModel(server: down)
        await offline.reportMissingSong(artist: "A", title: "B")
        XCTAssertNotNil(offline.notice)
        XCTAssertNotEqual(offline.notice, "Enter an artist and a title.")
    }

    func testSFTPPinsTheHostKeyAtTheFirstLoginAndKeepsIt() async {
        let a = account()
        (a.kind, a.host, a.user, a.password) = (.sftp, "nas.local", "me", "pw")
        XCTAssertEqual(a.port, "22", "the port follows the protocol")
        await a.connect()
        XCTAssertTrue(a.connected)
        XCTAssertEqual(a.hostKey, "SHA256:fake")
        XCTAssertEqual(a.account?.hostKey, "SHA256:fake")
        let again = account()
        XCTAssertEqual(again.kind, .sftp)
        XCTAssertEqual(again.hostKey, "SHA256:fake")
        again.disconnect()
        XCTAssertNil(again.hostKey)
    }

    func testAChosenPortSurvivesAChangeOfProtocolAndAnSFTPLoginNeedsAUser() async {
        let a = account()
        a.port = "2222"
        a.kind = .sftp
        XCTAssertEqual(a.port, "2222")
        a.host = "nas.local"
        await a.connect()
        XCTAssertFalse(a.connected)
        XCTAssertEqual(a.failure, "Enter the user name.")
    }

    func testAnEarlierPlainFTPLoginIsForgotten() {
        let secrets = MemorySecrets()
        defaults.set(true, forKey: "ftp.connected")
        defaults.set("old.local", forKey: "ftp.host")
        secrets.set("pw", for: "ftp.password")
        let a = account(secrets: secrets)
        XCTAssertFalse(a.connected)
        XCTAssertNil(defaults.string(forKey: "ftp.host"))
        XCTAssertNil(secrets.secret(for: "ftp.password"))
    }
}
