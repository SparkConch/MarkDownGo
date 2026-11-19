import AppKit

/// Removing one entry from the system "recent documents" list.
///
/// `NSDocumentController` only exposes add and clear-all, and the SharedFileList API that could
/// delete a single item is deprecated. Clearing and re-adding the survivors is the supported path;
/// entries are re-added oldest first so the visible order is preserved.
enum RecentDocuments {
    static func remove(_ url: URL) {
        let controller = NSDocumentController.shared
        let target = url.standardizedFileURL
        let keep = controller.recentDocumentURLs.filter { $0.standardizedFileURL != target }
        guard keep.count != controller.recentDocumentURLs.count else { return }
        controller.clearRecentDocuments(nil)
        for item in keep.reversed() {
            controller.noteNewRecentDocumentURL(item)
        }
    }
}
