import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Copies dropped files into app storage.
///
/// Files are copied, never bookmarked. A security-scoped bookmark breaks the
/// moment the user moves or renames the original, and a report whose evidence
/// silently stops resolving is worse than no report at all. Copying also means
/// the attachment survives the source being deleted.
enum AttachmentStore {
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("NilaiKinerja/Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum StoreError: LocalizedError {
        case unreadable(URL)
        case duplicate

        var errorDescription: String? {
            switch self {
            case .unreadable(let url): return "Tidak bisa membaca \(url.lastPathComponent)"
            case .duplicate: return "Dokumen ini sudah dilampirkan."
            }
        }
    }

    struct Stored {
        let filename: String
        let path: String
        let kind: Attachment.Kind
        let bytes: Int
        let sha256: String
    }

    static func kind(for url: URL) -> Attachment.Kind {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .pdf) { return .pdf }
        }
        return .other
    }

    static func store(_ url: URL) throws -> Stored {
        // startAccessingSecurityScopedResource is a no-op for non-sandboxed
        // apps but harmless, and keeps the code correct if it is ever sandboxed.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw StoreError.unreadable(url)
        }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let filename = sanitized(url.lastPathComponent)
        let kind = kind(for: url)

        // Content-addressed name: re-dropping the same file is a no-op rather
        // than a duplicate row, and the name is filesystem-safe by
        // construction.
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension.lowercased())"
        let storedName = "\(digest.prefix(16))\(ext)"
        let destination = directory.appendingPathComponent(storedName)

        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }

        return Stored(
            filename: filename,
            path: destination.path,
            kind: kind,
            bytes: data.count,
            sha256: digest
        )
    }

    /// Strips path separators and control characters from a user-supplied name
    /// so it can never escape the attachments directory.
    private static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:\0")
            .union(.controlCharacters)
        let cleaned = name.components(separatedBy: illegal).joined(separator: "_")
        return cleaned.isEmpty ? "dokumen" : String(cleaned.prefix(120))
    }
}
