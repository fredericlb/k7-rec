// The real exporter: AVAssetExportSession reads an owned item's file and writes AAC in an m4a.
// What a reader gets wrong: cancellation calls `cancelExport`, and a cancelled session throws CancellationError.
import AVFoundation

struct AssetExporter: AudioExporting {
    func export(from source: URL, to destination: URL, progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw ExportError.unsupported }
        session.outputURL = destination
        session.outputFileType = .m4a
        let box = SessionBox(session)
        try await withTaskCancellationHandler {
            async let done: Void = box.run()
            while !box.finished {
                progress(Double(box.session.progress))
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            try await done
            progress(1)
        } onCancel: { box.session.cancelExport() }
    }
}

enum ExportError: LocalizedError {
    case unsupported, failed(String)
    var errorDescription: String? {
        switch self {
        case .unsupported: "this file cannot be exported"
        case .failed(let m): m
        }
    }
}

private final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    private(set) var finished = false
    init(_ s: AVAssetExportSession) { session = s }

    func run() async throws {
        await withCheckedContinuation { c in session.exportAsynchronously { c.resume() } }
        finished = true
        switch session.status {
        case .completed: return
        case .cancelled: throw CancellationError()
        default: throw ExportError.failed(session.error?.localizedDescription ?? "the export failed")
        }
    }
}
