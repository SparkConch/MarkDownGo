import AppKit
import MarkDownGoCore

/// One Markdown file. Autosave-in-place is on (SPEC Q27/Q28), so the document is the text of record
/// and the editor writes through it on every change; "revert to opened state" restores the snapshot
/// taken when the file was read.
final class Document: NSDocument {
    var text = ""
    private var openedText: String?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        openedText = text
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
