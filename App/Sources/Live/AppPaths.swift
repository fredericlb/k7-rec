// Where the app keeps its files; Songs and Takes live in the iCloud container when there is one (docs/sync.md).
import Foundation

struct AppPaths {
    let songs: URL
    let takes: URL
    /// One small JSON per song and per take, what another device rebuilds its database from.
    let records: URL
    /// Where a separation model is dropped, in Documents so the Files app reaches it; never synced.
    let models: URL
    let database: URL
    /// The iCloud container's Documents folder, nil when the files are local only.
    let cloud: URL?

    static let containerID = "iCloud.se.frediver.rehearsal"

    /// All of them under one root, which is how the tests run in a temp folder.
    init(root: URL) {
        songs = root.appendingPathComponent("Songs", isDirectory: true)
        takes = root.appendingPathComponent("Takes", isDirectory: true)
        records = root.appendingPathComponent("Records", isDirectory: true)
        models = root.appendingPathComponent("Models", isDirectory: true)
        database = root.appendingPathComponent("rehearsal.sqlite")
        cloud = nil
    }

    /// Files under `cloud` when given, else under `documents`; the model and the database never leave the device.
    init(documents: URL, support: URL, cloud: URL? = nil) {
        let files = cloud ?? documents
        songs = files.appendingPathComponent("Songs", isDirectory: true)
        takes = files.appendingPathComponent("Takes", isDirectory: true)
        records = files.appendingPathComponent("Records", isDirectory: true)
        models = documents.appendingPathComponent("Models", isDirectory: true)
        database = support.appendingPathComponent("rehearsal.sqlite")
        self.cloud = cloud
    }

    static func live() -> AppPaths {
        if DebugLaunch.freshLibrary {
            return AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("fresh-\(UUID().uuidString)", isDirectory: true))
        }
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cloud = fm.url(forUbiquityContainerIdentifier: containerID)?.appendingPathComponent("Documents", isDirectory: true)
        return AppPaths(documents: docs, support: support, cloud: cloud)
    }

    func create() throws {
        let fm = FileManager.default
        for dir in [songs, takes, records, models, database.deletingLastPathComponent()] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Moves the Songs and Takes a local-only install made into the container; a name already there is left alone.
    func adoptLocalFiles(from documents: URL) {
        guard cloud != nil else { return }
        let fm = FileManager.default
        for (name, dest) in [("Songs", songs), ("Takes", takes)] {
            let old = documents.appendingPathComponent(name, isDirectory: true)
            guard old.standardizedFileURL != dest.standardizedFileURL,
                  let items = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { continue }
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for item in items {
                let target = dest.appendingPathComponent(item.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else { continue }
                try? fm.setUbiquitous(true, itemAt: item, destinationURL: target)
            }
        }
    }
}
