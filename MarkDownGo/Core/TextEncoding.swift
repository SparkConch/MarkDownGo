import Foundation

/// Text file encoding detection and round-trip-safe persistence.
///
/// Priority order matters: strict UTF-8 first (most files, and ASCII is a prefix of it), then a BOM
/// sniff for UTF-16, then the multi-byte candidates, and a lossless-by-construction single-byte
/// fallback last.
///

/// Known limitation, verified empirically: byte legality cannot separate GB18030, Big5, Shift-JIS
/// and EUC from each other — each reads the others' bytes without substitution characters. The
/// order below deliberately biases towards GB18030 (this project's primary audience). A
/// Traditional-Chinese or Japanese legacy file may therefore be *labelled* GB18030; that is
/// display-only: the bytes decode losslessly, and saving re-encodes to the identical byte sequence,
/// so no data is lost. Explicit per-file encoding choice belongs to a future open-panel iteration
/// — MarkEdit ships 13 encodings with a picker for exactly this reason.
public enum TextEncoding: Equatable {
    case utf8
    case utf16LE
    case utf16BE
    case gb18030
    case big5
    case shiftJIS
    case eucJP
    case eucKR
    case windows1252

    /// Ordered probe list. GB18030 before Big5/Shift-JIS: it is a superset of ASCII with a dense
    /// two-byte space, and misreading a Chinese file as Big5 is the worse failure.
    public static let detectionOrder: [TextEncoding] = [.utf8, .utf16LE, .utf16BE, .gb18030, .big5, .shiftJIS, .eucJP, .eucKR, .windows1252]

    public var cfEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .gb18030: return Self.legacy(.GB_18030_2000)
        case .big5: return Self.legacy(.big5)
        case .shiftJIS: return Self.legacy(.shiftJIS)
        case .eucJP: return Self.legacy(.EUC_JP)
        case .eucKR: return Self.legacy(.EUC_KR)
        case .windows1252: return .windowsCP1252
        }
    }

    /// CFStringEncoding and NSStringEncoding are different numbering schemes; the conversion
    /// function is the only correct bridge between them.
    private static func legacy(_ encoding: CFStringEncodings) -> String.Encoding {
        let cf = CFStringEncoding(encoding.rawValue)
        return String.Encoding(rawValue: UInt(CFStringConvertEncodingToNSStringEncoding(cf)))
    }

    public var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .gb18030: return "GB18030"
        case .big5: return "Big5"
        case .shiftJIS: return "Shift-JIS"
        case .eucJP: return "EUC-JP"
        case .eucKR: return "EUC-KR"
        case .windows1252: return "Windows-1252"
        }
    }

    /// Detect the encoding of `data`. Always succeeds — windows1252 cannot fail to decode.
    public static func detect(_ data: Data) -> TextEncoding {
        guard !data.isEmpty else { return .utf8 }

        // BOMs are authoritative when present.
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LE }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BE }

        for candidate in detectionOrder where candidate != .utf16LE && candidate != .utf16BE {
            if data.roundTrips(with: candidate) { return candidate }
        }
        return .windows1252
    }

    /// Encode `text` losslessly in this encoding, or nil when the text contains characters it
    /// cannot represent (callers fall back to UTF-8).
    public func encode(_ text: String) -> Data? {
        let data = text.data(using: cfEncoding, allowLossyConversion: false)
        guard let data else { return nil }
        // Some legacy encodings map unknown bytes to U+FFFD instead of failing; re-decode and
        // compare so "lossy success" is still reported as unrepresentable.
        guard String(data: data, encoding: cfEncoding) == text else { return nil }
        return data
    }
}

extension Data {
    /// A candidate wins only if decoding produces no substitution characters *and* re-encoding
    /// reproduces the exact bytes. Wrong-encoding readings of CJK text decode "successfully" but
    /// re-encode differently, which is what separates them.
    fileprivate func roundTrips(with encoding: TextEncoding) -> Bool {
        guard let text = String(data: self, encoding: encoding.cfEncoding),
              !text.contains("\u{FFFD}") else { return false }
        guard let reencoded = text.data(using: encoding.cfEncoding) else { return false }
        return reencoded == self
    }
}
