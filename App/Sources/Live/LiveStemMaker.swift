// The real stem maker: a Core ML model from the bundle or the Models folder, the stems in the song's folder.
// What a reader gets wrong: a .mlpackage dropped in Models is compiled once and kept as a .mlmodelc beside it.
import Foundation
import RehearsalStems

@MainActor
final class LiveStemMaker: StemMaking {
    static let modelName = "StemSeparator"
    private let songs: URL
    private let models: URL
    private let bundle: Bundle

    init(songs: URL, models: URL, bundle: Bundle = .main) {
        (self.songs, self.models, self.bundle) = (songs, models, bundle)
    }

    var hasModel: Bool { compiledURL != nil || packageURL != nil }

    func existing(for song: Song) -> [Stem: URL]? { folder(of: song).flatMap(Stem.existing(in:)) }

    func separate(_ song: Song, progress: @escaping @Sendable (Double) -> Void) async -> String? {
        guard let source = song.audioURL, let folder = folder(of: song) else { return "This song has no audio file to separate." }
        do {
            let model = try await loadModel()
            try await StemSeparator(model: model).separate(source: source, into: Stem.folder(in: folder), progress: progress)
            return nil
        } catch is CancellationError {
            return nil
        } catch StemError.modelMissing {
            return "No separation model is installed. Put \(Self.modelName).mlpackage in the Models folder of Rehearsal, in the Files app."
        } catch {
            return "The song could not be separated: \(error.localizedDescription)"
        }
    }

    func remove(for song: Song) {
        if let folder = folder(of: song) { try? FileManager.default.removeItem(at: Stem.folder(in: folder)) }
    }

    func instrumentalURL(for song: Song) -> URL? {
        guard let folder = folder(of: song) else { return nil }
        let url = InstrumentalMix.url(in: folder)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func makeInstrumental(for song: Song) async -> String? {
        guard let folder = folder(of: song), let stems = Stem.existing(in: folder) else { return "This song has no stems yet." }
        let out = InstrumentalMix.url(in: folder)
        do {
            try await Task.detached { try InstrumentalMix.write(from: stems, to: out) }.value
            return nil
        } catch { return "The instrumental could not be made: \(error.localizedDescription)" }
    }

    private func folder(of song: Song) -> URL? {
        song.folder.isEmpty ? song.audioURL?.deletingLastPathComponent() : songs.appendingPathComponent(song.folder, isDirectory: true)
    }

    private var compiledURL: URL? {
        let kept = models.appendingPathComponent(Self.modelName + ".mlmodelc")
        if let inBundle = bundle.url(forResource: Self.modelName, withExtension: "mlmodelc") { return inBundle }
        return FileManager.default.fileExists(atPath: kept.path) ? kept : nil
    }

    private var packageURL: URL? {
        let url = models.appendingPathComponent(Self.modelName + ".mlpackage")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadModel() async throws -> CoreMLSegmentModel {
        if let url = compiledURL { return try CoreMLSegmentModel(url: url) }
        guard let package = packageURL else { throw StemError.modelMissing }
        let compiled = try await CoreMLSegmentModel.compile(package)
        let kept = models.appendingPathComponent(Self.modelName + ".mlmodelc")
        try? FileManager.default.removeItem(at: kept)
        try FileManager.default.moveItem(at: compiled, to: kept)
        return try CoreMLSegmentModel(url: kept)
    }
}
