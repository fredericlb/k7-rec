import Foundation
import GRDB
import Testing
@testable import RehearsalStore

@Suite struct StoreTests {
    @Test func missingFieldReadsAsZero() async throws {
        let s = try Store()
        try await s.write { tx in
            try tx.db.execute(sql: "INSERT INTO docs VALUES ('Takes', 'a', '{\"id\":\"a\"}')")
        }
        let t = try #require(try await s.get(Take.self, "a"))
        #expect(t == Take(id: "a", createdAt: 0))
        #expect(t.duration == 0 && t.envelope.isEmpty && t.title == "")
    }

    @Test func modelsEncodeExactlyTheSchemaFields() throws {
        func keys<D: Document>(_ d: D) throws -> Set<String> {
            let o = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
            return Set(o.keys)
        }
        #expect(try keys(Song()) == Set(Collection.songs.fields))
        #expect(try keys(SongFile()) == Set(Collection.songFiles.fields))
        #expect(try keys(Take()) == Set(Collection.takes.fields))
        #expect(try keys(Moment()) == Set(Collection.moments.fields))
        #expect(try keys(Marker()) == Set(Collection.markers.fields))
    }

    @Test func listingThatNamesFieldsReadsOnlyThose() async throws {
        let s = try Store()
        try await s.put(Take(id: "a", title: "T", duration: 9, envelope: [0.5, 1], audioPath: "r/a.m4a"))
        let l = try await s.list(Query<Take>(fields: ["title", "duration"]))
        #expect(l.count == 1 && l[0].id == "a" && l[0].title == "T" && l[0].duration == 9)
        #expect(l[0].envelope.isEmpty && l[0].audioPath == "")
        let whole = try await s.list(Query<Take>())
        #expect(whole[0].envelope == [0.5, 1])
    }

    @Test func filtersOrderAndUnknownFields() async throws {
        let s = try Store()
        try await s.put([Moment(id: "m2", recordingPath: "r", startSec: 5), Moment(id: "m1", recordingPath: "r", startSec: 1),
                         Moment(id: "m3", recordingPath: "other", validated: true)])
        #expect(try await s.moments(of: "r").map(\.id) == ["m1", "m2"])
        #expect(try await s.list(Query<Moment>(where: [Filter("validated", equals: true)])).map(\.id) == ["m3"])
        #expect(try await s.list(Query<Moment>(where: [Filter("recordingPath", in: [])])).isEmpty)
        await #expect(throws: StoreError.unknownField(collection: "Moments", field: "x'--")) {
            _ = try await s.list(Query<Moment>(where: [Filter("x'--", equals: "a")]))
        }
    }

    @Test func multiRowWriteRollsBackWhole() async throws {
        let s = try Store()
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await s.write { tx in try tx.put(Song(id: "s1")); throw Boom() }
        }
        #expect(try await s.get(Song.self, "s1") == nil)
    }

    @Test func expressionIndexesAreUsed() async throws {
        let s = try Store()
        let plan = try await s.write { tx -> String in
            let sql = "EXPLAIN QUERY PLAN SELECT id FROM docs WHERE coll = 'Moments' AND json_extract(fields, '$.recordingPath') IN ('x')"
            return try Row.fetchAll(tx.db, sql: sql).map { $0["detail"] as String }.joined()
        }
        #expect(plan.contains("docs_recordingPath"))
    }

    @Test func deletingSongKeepsTakesDetached() async throws {
        let s = try Store()
        try await s.saveSong(Song(id: "s"), files: [SongFile(id: "f", kind: .sheet)])
        try await s.put(Take(id: "t", songId: "s"))
        #expect(try await s.list(Query<SongFile>()).first?.songId == "s")
        try await s.deleteSong("s")
        #expect(try await s.list(Query<SongFile>()).isEmpty)
        #expect(try await s.get(Take.self, "t")?.songId == "")
    }

    @Test func saveSongReplacesItsFiles() async throws {
        let s = try Store()
        try await s.saveSong(Song(id: "s"), files: [SongFile(id: "a"), SongFile(id: "b")])
        try await s.saveSong(Song(id: "s"), files: [SongFile(id: "c")])
        #expect(try await s.list(Query<SongFile>()).map(\.id) == ["c"])
    }

    @Test func recordingRules() async throws {
        let s = try Store()
        try await s.put(Take(id: "t", audioPath: "day/a.m4a"))
        try await s.put(Moment(id: "m", recordingPath: "day/a.m4a"))
        try await s.put([Marker(id: "k1", recordingPath: "day/a.m4a"),
                         Marker(id: "k2", recordingPath: "day/a.m4a", momentId: "m")])
        try await s.moveRecording(from: "day/a.m4a", to: "day/b.m4a")
        #expect(try await s.get(Take.self, "t")?.audioPath == "day/b.m4a")
        #expect(try await s.moments(of: "day/b.m4a").count == 1)
        #expect(try await s.get(Marker.self, "k2")?.recordingPath == "day/b.m4a")
        try await s.deleteTake("t")
        #expect(try await s.get(Marker.self, "k1") == nil)
        #expect(try await s.get(Marker.self, "k2") != nil)
        #expect(try await s.moments(of: "day/b.m4a").count == 1)
        try await s.deleteMoment("m")
        #expect(try await s.list(Query<Marker>()).isEmpty)
    }

    @Test func observeEmitsOnChange() async throws {
        let s = try Store()
        var it = s.observe(Query<Song>()).makeAsyncIterator()
        #expect(try await it.next()?.count == 0)
        try await s.put(Song(id: "a", title: "A"))
        #expect(try await it.next()?.map(\.title) == ["A"])
    }

    @Test func fileStoreSurvivesReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rs-\(newID()).db")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        do {
            let s = try Store(url: url)
            try await s.put(Song(id: "a", title: "A"))
            let mode = try await s.write { try String.fetchOne($0.db, sql: "PRAGMA journal_mode") }
            #expect(mode == "wal")
        }
        #expect(try await Store(url: url).get(Song.self, "a")?.title == "A")
    }
}
