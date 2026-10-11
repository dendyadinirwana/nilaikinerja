import Foundation
import UniformTypeIdentifiers

/// The result of inspecting a file's raw content signature.
enum FileValidationVerdict: Equatable {
    case valid(format: String, mime: String)
    case invalid(reason: String)
}

/// Deep content inspector and validator.
///
/// Rather than trusting filename extensions alone (which can be trivially spoofed,
/// e.g. renaming `trojan.exe` to `laporan.pdf` or `archive.zip` to `bukti.docx`),
/// this reads the raw magic bytes and binary file headers to ensure the file
/// is genuinely a supported document or image.
enum FileContentValidator {

    /// Inspects the file at `url` and validates its authenticity against known binary signatures.
    static func validate(url: URL) -> FileValidationVerdict {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .invalid(reason: "Berkas tidak ditemukan pada disk")
        }

        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return .invalid(reason: "Berkas tidak memiliki ekstensi format")
        }

        // Read up to 8KB of header data
        let headerData: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            headerData = handle.readData(ofLength: 8192)
        } catch {
            return .invalid(reason: "Gagal membaca isi berkas: \(error.localizedDescription)")
        }

        guard !headerData.isEmpty else {
            // An empty (0-byte) file cannot be a valid PDF, DOCX, XLSX, PPTX, or Image
            if ext == "txt" || ext == "text" || ext == "md" || ext == "markdown" {
                return .valid(format: "Teks Kosong", mime: "text/plain")
            }
            return .invalid(reason: "Ukuran berkas 0 byte (kosong atau rusak)")
        }

        let bytes = [UInt8](headerData)
        let byteCount = bytes.count

        // 1. Instant Rejection: Dangerous / Disguised Executable & Binary Signatures
        if byteCount >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A { // "MZ"
            return .invalid(reason: "Isi berkas adalah Executable Windows (MZ/PE), bukan Dokumen asli!")
        }
        if byteCount >= 4 && bytes[0] == 0x7F && bytes[1] == 0x45 && bytes[2] == 0x4C && bytes[3] == 0x46 { // "\x7fELF"
            return .invalid(reason: "Isi berkas adalah Binary Executable Linux (ELF), bukan Dokumen asli!")
        }
        if byteCount >= 4 {
            let b0 = bytes[0], b1 = bytes[1], b2 = bytes[2], b3 = bytes[3]
            // Mach-O macOS binaries
            if (b0 == 0xFE && b1 == 0xED && b2 == 0xFA && (b3 == 0xCE || b3 == 0xCF)) ||
               (b0 == 0xCE && b1 == 0xFA && b2 == 0xED && b3 == 0xFE) ||
               (b0 == 0xCF && b1 == 0xFA && b2 == 0xED && b3 == 0xFE) ||
               (b0 == 0xCA && b1 == 0xFE && b2 == 0xBA && b3 == 0xBE) { // Fat Binary / Mach-O / Java Class
                return .invalid(reason: "Isi berkas adalah Executable Binary macOS (Mach-O), bukan Dokumen asli!")
            }
        }

        // Script shebang when disguised as document/image
        if byteCount >= 2 && bytes[0] == 0x23 && bytes[1] == 0x21 && ext != "txt" && ext != "md" { // "#!"
            return .invalid(reason: "Isi berkas adalah Skrip Shell (Shebang), bukan Dokumen asli!")
        }

        // 2. Format-Specific Header Validation
        switch ext {
        case "pdf":
            // PDF must start with "%PDF-" in the first 1024 bytes
            let searchSlice = headerData.prefix(1024)
            if let str = String(data: searchSlice, encoding: .ascii), str.contains("%PDF") {
                return .valid(format: "PDF", mime: "application/pdf")
            }
            return .invalid(reason: "Isi berkas bukan PDF asli (header %PDF tidak ditemukan)")

        case "png":
            // PNG signature: 89 50 4E 47 0D 0A 1A 0A
            if byteCount >= 8 &&
                bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
                bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A {
                return .valid(format: "PNG", mime: "image/png")
            }
            return .invalid(reason: "Isi berkas bukan gambar PNG asli (header rusak atau salah)")

        case "jpg", "jpeg":
            // JPEG signature: FF D8 FF
            if byteCount >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
                return .valid(format: "JPEG", mime: "image/jpeg")
            }
            return .invalid(reason: "Isi berkas bukan foto JPEG asli (header rusak atau salah)")

        case "gif":
            if byteCount >= 6 {
                let sig = String(bytes: bytes.prefix(6), encoding: .ascii)
                if sig == "GIF87a" || sig == "GIF89a" {
                    return .valid(format: "GIF", mime: "image/gif")
                }
            }
            return .invalid(reason: "Isi berkas bukan gambar GIF asli")

        case "bmp":
            if byteCount >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D {
                return .valid(format: "BMP", mime: "image/bmp")
            }
            return .invalid(reason: "Isi berkas bukan gambar BMP asli")

        case "webp":
            if byteCount >= 12 &&
                bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && // "RIFF"
                bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 { // "WEBP"
                return .valid(format: "WebP", mime: "image/webp")
            }
            return .invalid(reason: "Isi berkas bukan gambar WebP asli")

        case "heic", "heif":
            // ftyp box at offset 4
            if byteCount >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
                return .valid(format: "HEIC", mime: "image/heic")
            }
            return .invalid(reason: "Isi berkas bukan foto HEIC asli")

        case "tiff", "tif":
            if byteCount >= 4 &&
                ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
                 (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A)) {
                return .valid(format: "TIFF", mime: "image/tiff")
            }
            return .invalid(reason: "Isi berkas bukan gambar TIFF asli")

        case "docx", "pptx", "xlsx", "odt", "odp", "ods", "key", "pages", "numbers":
            // Modern Office documents are ZIP containers starting with PK\x03\x04
            guard byteCount >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B &&
                  ((bytes[2] == 0x03 && bytes[3] == 0x04) || (bytes[2] == 0x05 && bytes[3] == 0x06)) else {
                return .invalid(reason: "Isi berkas bukan format dokumen Office (OpenXML) asli (bukan zip container)")
            }

            // Verify internal content marks
            if let text = String(data: headerData, encoding: .ascii) {
                if ext == "docx" && !text.contains("word/") && !text.contains("[Content_Types]") {
                    return .invalid(reason: "Berkas berformat ZIP biasa, bukan Dokumen Word (.docx) asli")
                }
                if ext == "pptx" && !text.contains("ppt/") && !text.contains("[Content_Types]") {
                    return .invalid(reason: "Berkas berformat ZIP biasa, bukan Presentasi PowerPoint (.pptx) asli")
                }
                if ext == "xlsx" && !text.contains("xl/") && !text.contains("[Content_Types]") {
                    return .invalid(reason: "Berkas berformat ZIP biasa, bukan Spreadsheet Excel (.xlsx) asli")
                }
            }
            return .valid(format: ext.uppercased(), mime: "application/vnd.openxmlformats")

        case "doc", "xls", "ppt":
            // Compound File Binary Format: D0 CF 11 E0 A1 B1 1A E1
            if byteCount >= 8 &&
                bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0 &&
                bytes[4] == 0xA1 && bytes[5] == 0xB1 && bytes[6] == 0x1A && bytes[7] == 0xE1 {
                return .valid(format: ext.uppercased(), mime: "application/msword")
            }
            return .invalid(reason: "Isi berkas bukan dokumen Microsoft Office legacy asli")

        case "rtf":
            if byteCount >= 5 &&
                bytes[0] == 0x7B && bytes[1] == 0x5C && bytes[2] == 0x72 && bytes[3] == 0x74 && bytes[4] == 0x66 { // "{\rtf"
                return .valid(format: "RTF", mime: "application/rtf")
            }
            return .invalid(reason: "Isi berkas bukan dokumen RTF asli")

        case "svg":
            if let text = String(data: headerData, encoding: .utf8) ?? String(data: headerData, encoding: .ascii) {
                if text.lowercased().contains("<svg") {
                    return .valid(format: "SVG", mime: "image/svg+xml")
                }
            }
            return .invalid(reason: "Isi berkas bukan dokumen vektor SVG asli")

        case "txt", "text", "md", "markdown":
            // Check for binary null bytes
            let nullCount = bytes.prefix(4096).filter { $0 == 0x00 }.count
            if nullCount > 0 {
                return .invalid(reason: "Berkas terdeteksi sebagai binary/arsip, bukan teks asli!")
            }
            return .valid(format: "Teks/Markdown", mime: "text/plain")

        default:
            return .invalid(reason: "Format .\(ext) tidak diizinkan")
        }
    }
}
