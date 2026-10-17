import Foundation
import Observation

/// Owns the full list of playable clips: the two bundled demo clips plus any
/// user-recorded/imported ones. User clips are persisted as plain files under
/// Documents/UserClips/{Recorded,Imported}/ -- directory contents are the source of
/// truth (no separate index file to keep in sync).
@Observable
@MainActor
final class AudioLibrary {
    private(set) var sources: [AudioSource] = []

    private let recordedDirectory: URL
    private let importedDirectory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordedDirectory = documents.appendingPathComponent("UserClips/Recorded", isDirectory: true)
        importedDirectory = documents.appendingPathComponent("UserClips/Imported", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordedDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: importedDirectory, withIntermediateDirectories: true)
        reload()
    }

    private func bundledSources() -> [AudioSource] {
        var result: [AudioSource] = []
        if let url = Bundle.main.url(forResource: "speech", withExtension: "wav") {
            result.append(AudioSource(id: "bundled-speech", name: "Speech", kind: .bundledSpeech, url: url))
        }
        if let url = Bundle.main.url(forResource: "music", withExtension: "wav") {
            result.append(AudioSource(id: "bundled-music", name: "Music", kind: .bundledMusic, url: url))
        }
        return result
    }

    private func scan(_ directory: URL, kind: AudioSourceKind) -> [AudioSource] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let sorted = files.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lDate > rDate // newest first
        }
        return sorted.map { url in
            AudioSource(id: url.path, name: url.deletingPathExtension().lastPathComponent, kind: kind, url: url)
        }
    }

    func reload() {
        sources = bundledSources() + scan(recordedDirectory, kind: .recorded) + scan(importedDirectory, kind: .imported)
    }

    /// Filename-safe timestamp (dot, not colon, so it survives on-disk unmodified).
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h.mm a"
        return formatter.string(from: Date())
    }

    /// A chip only has room to show the first few characters before `.lineLimit(1)`
    /// truncates the rest -- with the distinguishing detail (a timestamp) at the *end*
    /// of the name, every recording's chip truncated to the same "Recording —…", so
    /// none were tellable apart at a glance. A zero-padded number right at the very
    /// front fixes that: it's always the part still visible after truncation, and
    /// sorts correctly as plain text too. Based on a count of what's already on disk,
    /// so it naturally doesn't repeat after a deletion either (whatever's left is
    /// exactly what gets counted next time).
    private func nextNumberPrefix(in directory: URL) -> String {
        let count = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.count ?? 0
        return String(format: "%02d", count + 1)
    }

    /// Move a just-finished recording (already at a temp URL) into permanent storage.
    @discardableResult
    func addRecording(from tempURL: URL) throws -> AudioSource {
        let destination = recordedDirectory
            .appendingPathComponent("\(nextNumberPrefix(in: recordedDirectory)) Recording — \(timestamp())")
            .appendingPathExtension("m4a")
        try FileManager.default.moveItem(at: tempURL, to: destination)
        reload()
        guard let added = sources.first(where: { $0.url == destination }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return added
    }

    /// Copy a user-picked file (from the file importer, security-scoped) into permanent storage.
    @discardableResult
    func addImportedFile(from sourceURL: URL) throws -> AudioSource {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destination = importedDirectory
            .appendingPathComponent("\(nextNumberPrefix(in: importedDirectory)) Import — \(baseName)")
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        reload()
        guard let added = sources.first(where: { $0.url == destination }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return added
    }

    func delete(_ source: AudioSource) {
        guard source.isDeletable else { return }
        try? FileManager.default.removeItem(at: source.url)
        reload()
    }
}
