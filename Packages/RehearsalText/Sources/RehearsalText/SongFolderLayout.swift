// SongFolderLayout.swift: the names of the files in a song folder; names only, no I/O.
// The layout is the songbook's (packages/mediatek/docs/songbook.md), kept so a folder imports as is.

import Foundation

public enum SongFolderLayout {
    public static let lyrics = "lyrics.txt"
    public static let tabs = "tabs.txt"
    public static let chords = "chords.txt"
    public static let sheetsFolder = "sheets"
    public static let sidecar = "song.yaml"
    /// The master's base name; its extension is the audio format's (`original.flac`).
    public static let masterBaseName = "original"

    /// The texts a song may carry, in the order a reader lists them.
    public static let textFiles = [lyrics, tabs, chords]

    /// A sheet's path inside the song folder.
    public static func sheetPath(_ name: String) -> String { sheetsFolder + "/" + name }

    /// Whether a file name (`original.flac`, `original.m4a`) is the song's master.
    public static func isMaster(_ name: String) -> Bool {
        name.hasPrefix(masterBaseName + ".") && name.count > masterBaseName.count + 1
    }

    /// A song is in the songbook when it has a text or a sheet; `entries` are paths relative to the folder.
    public static func carriesSongbook(entries: [String]) -> Bool {
        entries.contains { textFiles.contains($0) || $0.hasPrefix(sheetsFolder + "/") }
    }
}
