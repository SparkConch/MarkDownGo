import AppKit
import MarkDownGoCore

/// One Markdown file. Autosave-in-place is on (SPEC Q27/Q28), so the document is the text of record
/// and the editor writes through it on every change; "revert to opened state" restores the snapshot
/// taken when the file was read.
final class Document: NSDocument {
    var text = ""
    private var openedText: String?
    /// Encoding the file was read with; saving keeps it when the text still round-trips.
    private(set) var encoding: TextEncoding = .utf8

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    override func data(ofType typeName: String) throws -> Data {
        // Keep the file's original encoding when the content still fits it; fall back to UTF-8
        // (never lossy) when the user added characters the legacy encoding cannot represent.
        if let data = encoding.encode(text) { return data }
        encoding = .utf8
        return Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        encoding = TextEncoding.detect(data)
        text = String(data: data, encoding: encoding.cfEncoding) ?? String(decoding: data, as: UTF8.self)
        openedText = text
    }

    /// The file changed outside the editor (Finder edit, git checkout, sync). With autosave-in-place
    /// the document is rarely dirty, so a silent reload is the right default; a dirty document keeps
    /// its in-memory text (the user's typing wins over a race we cannot merge).
    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        let diskDate = (try? FileManager.default.attributesOfItem(atPath: fileURL?.path ?? ""))?[.modificationDate] as? Date
        switch FileChangePolicy.resolve(
            currentModificationDate: fileModificationDate,
            diskModificationDate: diskDate,
            hasUnsavedEdits: isDocumentEdited
        ) {
        case .reload:
            guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
            encoding = TextEncoding.detect(data)
            text = String(data: data, encoding: encoding.cfEncoding) ?? String(decoding: data, as: UTF8.self)
            openedText = text
            (windowControllers.first as? DocumentWindowController)?.editor.replaceText(text)
            updateChangeCount(.changeCleared)
        case .keepLocalEdits, .ignore:
            break
        }
    }

    func editorDidChange(_ newText: String) {
        text = newText
        updateChangeCount(.changeDone)
    }

    @objc func revertToOpenedState(_ sender: Any?) {
        guard let openedText else {
            NSSound.beep()
            return
        }
        text = openedText
        (windowControllers.first as? DocumentWindowController)?.editor.replaceText(openedText)
        updateChangeCount(.changeDone)
    }
}
