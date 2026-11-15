// Where the app keeps its files; Songs and Takes sit in Documents so the Files app shows them.
import Foundation

struct AppPaths {
    let songs: URL
    let takes: URL
    let database: URL

    /// All three under one root, which is how the tests run in a temp folder.
    init(root: URL) {
        songs = root.appendingPathComponent("Songs", isDirectory: true)
        takes = root.appendingPathComponent("Takes", isDirectory: true)
        database = root.appendingPathComponent("rehearsal.sqlite")
    }

    init(documents: URL, support: URL) {
        songs = documents.appendingPathComponent("Songs", isDirectory: true)
        takes = documents.appendingPathComponent("Takes", isDirectory: true)
        database = support.appendingPathComponent("rehearsal.sqlite")
    }

    static func live() -> AppPaths {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(documents: docs, support: support)
    }

    func create() throws {
        let fm = FileManager.default
        for dir in [songs, takes, database.deletingLastPathComponent()] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
