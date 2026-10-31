import Foundation

/// What to do when the file on disk changed behind our back.
/// Pure so the ambiguity is testable; NSDocument's presenter machinery just executes this.
public enum FileChangePolicy {
    public enum Action: Equatable {
        /// Reload the file's contents into the editor.
        case reload
        /// The document has unsaved edits; keep them and leave the disk version alone.
        case keepLocalEdits
        /// The notification is stale (disk not actually newer).
        case ignore
    }

    public static func resolve(currentModificationDate: Date?, diskModificationDate: Date?, hasUnsavedEdits: Bool) -> Action {
        guard let disk = diskModificationDate else { return .ignore }
        if let current = currentModificationDate, disk <= current { return .ignore }
        return hasUnsavedEdits ? .keepLocalEdits : .reload
    }
}
