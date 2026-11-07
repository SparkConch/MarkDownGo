import Foundation

/// Timing and layout constants. Every entry states its evidence; a bare number here is a bug.
enum Layout {
    /// Document window: outline 170 + gutter/divider allowance + editor share + preview floor 260
    /// all fit with the editor near 56% of the remainder — verified against the split layout probe.
    static let windowSize = NSSize(width: 1180, height: 760)
    static let windowMinSize = NSSize(width: 900, height: 520)

    /// Outline sidebar's resting position (divider 0).
    static let outlineWidth: CGFloat = 200

    /// Editor takes this share of the space right of the outline (divider 1).
    static let editorShare: CGFloat = 0.56

    /// Preview refresh debounce. Sub-250 ms reads as instant on keystrokes while capping cmark
    /// renders to ~4/s on long documents.
    static let previewDebounce: TimeInterval = 0.25

    /// Scroll-binding loop guard: ignore programmatic echoes for this long after we drive the
    /// other pane. One round trip (scroll event → message → layout) stays well under it.
    static let scrollGuard: TimeInterval = 0.15

    /// Preview-side reporting suppression, slightly above `scrollGuard` so the echo dies before
    /// the guard window closes.
    static let scrollSuppressMS: Int = 180

    /// How long the launcher waits before appearing. Finder's "open with" and `open -a App file.md`
    /// deliver the open request shortly *after* launch, so showing the launcher immediately made it
    /// flash in front of a document the user had already asked for. Long enough to catch that
    /// request, short enough to feel instant on a plain launch.
    static let homeRevealDelay: TimeInterval = 0.45

    /// Settle time before a smoke hook acts after launch (home window + first layout).
    /// Verification-only; compiled out of Release.
    static let smokeLaunchDelay: TimeInterval = 0.8
}
