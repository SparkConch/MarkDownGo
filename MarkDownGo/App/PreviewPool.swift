import WebKit

/// Preheats the WebContent process at launch so the first document window does not pay for it.
/// `take()` hands out the warm view (already past its shell navigation); an empty pool builds cold.
final class PreviewPool {
    static let shared = PreviewPool()
    private var warm: PreviewView?

    private init() {}

    func prewarm() {
        guard warm == nil else { return }
        warm = PreviewView()
    }

    func take() -> PreviewView {
        defer { warm = nil }
        return warm ?? PreviewView()
    }
}
