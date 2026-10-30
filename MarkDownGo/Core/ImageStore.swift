import Foundation

/// Turns pasted/dropped image bytes into Markdown, either as a sibling file or as an inline data URL
/// (SPEC Q25 — both modes shipped, the setting picks one).
public struct ImageStore {
    public enum Mode: String, CaseIterable {
        case directory
        case base64
    }

    public enum Failure: Error {
        case writeFailed
    }

    public init() {}

    /// Markdown to insert for the given image. `documentURL` is nil for untitled documents, which
    /// cannot host a sibling folder — those always inline, so nothing is lost on save.
    public func markdown(for data: Data, fileExtension: String, documentURL: URL?, mode: Mode, now: Date = Date()) throws -> String {
        let ext = fileExtension.lowercased()
        let alt = "image"

        guard mode == .directory, let documentURL, documentURL.isFileURL, documentURL.pathExtension.isEmpty == false else {
            return "![\(alt)](data:image/\(Self.mimeType(for: ext));base64,\(data.base64EncodedString()))"
        }

        let folder = documentURL.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = fileName(extension: ext, in: folder, now: now)
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return "![\(alt)](images/\(name))"
        } catch {
            throw Failure.writeFailed
        }
    }

    /// `paste-20261030-205012.png`, suffixed `-2`, `-3`… when the same second is reused.
    private func fileName(extension ext: String, in folder: URL, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "paste-\(formatter.string(from: now))"
        var candidate = "\(base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    /// `shortcut: magic-byte sniffing covers png/jpeg/gif/webp; anything else falls back to png naming
    /// and may render broken — transcode through NSBitmapImageRep when users paste exotic formats`.
    public static func fileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if bytes.count >= 12, bytes[0..<4].elementsEqual([0x52, 0x49, 0x46, 0x46]), bytes[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return "webp" }
        return "png"
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "jpeg"
        case "gif": return "gif"
        case "webp": return "webp"
        default: return "png"
        }
    }
}
