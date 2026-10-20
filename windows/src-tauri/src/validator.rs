use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::Read;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub ok: bool,
    pub reason: String,
    pub file_name: String,
    pub file_size: u64,
    pub kind: String, // "doc", "presentation", "spreadsheet", "pdf", "image", "text", or "unknown"
    pub format: String,
}

pub fn validate_file(path_str: &str) -> ValidationResult {
    let path = Path::new(path_str);
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("Berkas")
        .to_string();

    if !path.exists() {
        return ValidationResult {
            ok: false,
            reason: "Berkas tidak ditemukan pada disk".into(),
            file_name,
            file_size: 0,
            kind: "unknown".into(),
            format: "".into(),
        };
    }

    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_lowercase())
        .unwrap_or_default();

    if ext.is_empty() {
        return ValidationResult {
            ok: false,
            reason: "Berkas tidak memiliki ekstensi format".into(),
            file_name,
            file_size: 0,
            kind: "unknown".into(),
            format: "".into(),
        };
    }

    let meta = match std::fs::metadata(path) {
        Ok(m) => m,
        Err(e) => {
            return ValidationResult {
                ok: false,
                reason: format!("Gagal membaca metadata berkas: {}", e),
                file_name,
                file_size: 0,
                kind: "unknown".into(),
                format: "".into(),
            };
        }
    };
    let file_size = meta.len();

    let mut file = match File::open(path) {
        Ok(f) => f,
        Err(e) => {
            return ValidationResult {
                ok: false,
                reason: format!("Gagal membuka berkas: {}", e),
                file_name,
                file_size,
                kind: "unknown".into(),
                format: "".into(),
            };
        }
    };

    let mut buffer = [0u8; 8192];
    let bytes_read = match file.read(&mut buffer) {
        Ok(n) => n,
        Err(e) => {
            return ValidationResult {
                ok: false,
                reason: format!("Gagal membaca isi berkas: {}", e),
                file_name,
                file_size,
                kind: "unknown".into(),
                format: "".into(),
            };
        }
    };

    let bytes = &buffer[..bytes_read];

    if bytes.is_empty() {
        if ext == "txt" || ext == "text" || ext == "md" || ext == "markdown" {
            return ValidationResult {
                ok: true,
                reason: "Teks Kosong".into(),
                file_name,
                file_size: 0,
                kind: "text".into(),
                format: "TXT".into(),
            };
        }
        return ValidationResult {
            ok: false,
            reason: "Ukuran berkas 0 byte (kosong atau rusak)".into(),
            file_name,
            file_size: 0,
            kind: "unknown".into(),
            format: "".into(),
        };
    }

    // 1. Instant Rejection: Dangerous / Disguised Executable & Binary Signatures
    // "MZ" - Windows PE Executable
    if bytes.len() >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A {
        return ValidationResult {
            ok: false,
            reason: "Isi berkas adalah Executable Windows (MZ/PE), bukan Dokumen asli!".into(),
            file_name,
            file_size,
            kind: "executable".into(),
            format: "EXE".into(),
        };
    }

    // "\x7fELF" - Linux Executable
    if bytes.len() >= 4 && bytes[0] == 0x7F && bytes[1] == 0x45 && bytes[2] == 0x4C && bytes[3] == 0x46 {
        return ValidationResult {
            ok: false,
            reason: "Isi berkas adalah Binary Executable Linux (ELF), bukan Dokumen asli!".into(),
            file_name,
            file_size,
            kind: "executable".into(),
            format: "ELF".into(),
        };
    }

    // Mach-O macOS binaries
    if bytes.len() >= 4 {
        let (b0, b1, b2, b3) = (bytes[0], bytes[1], bytes[2], bytes[3]);
        if (b0 == 0xFE && b1 == 0xED && b2 == 0xFA && (b3 == 0xCE || b3 == 0xCF))
            || (b0 == 0xCE && b1 == 0xFA && b2 == 0xED && b3 == 0xFE)
            || (b0 == 0xCF && b1 == 0xFA && b2 == 0xED && b3 == 0xFE)
            || (b0 == 0xCA && b1 == 0xFE && b2 == 0xBA && b3 == 0xBE)
        {
            return ValidationResult {
                ok: false,
                reason: "Isi berkas adalah Executable Binary macOS (Mach-O), bukan Dokumen asli!".into(),
                file_name,
                file_size,
                kind: "executable".into(),
                format: "Mach-O".into(),
            };
        }
    }

    // Script shebang "#!"
    if bytes.len() >= 2 && bytes[0] == 0x23 && bytes[1] == 0x21 && ext != "txt" && ext != "md" {
        return ValidationResult {
            ok: false,
            reason: "Isi berkas adalah Skrip Shell (Shebang), bukan Dokumen asli!".into(),
            file_name,
            file_size,
            kind: "executable".into(),
            format: "SHELL".into(),
        };
    }

    let ascii_slice = String::from_utf8_lossy(bytes);

    // 2. Format-Specific Signature Validation
    match ext.as_str() {
        "pdf" => {
            let search_slice = &bytes[..std::cmp::min(1024, bytes.len())];
            let search_str = String::from_utf8_lossy(search_slice);
            if search_str.contains("%PDF") {
                ValidationResult {
                    ok: true,
                    reason: "Dokumen PDF terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "pdf".into(),
                    format: "PDF".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan PDF asli (header %PDF tidak ditemukan)".into(),
                    file_name,
                    file_size,
                    kind: "unknown".into(),
                    format: "PDF".into(),
                }
            }
        }

        "png" => {
            if bytes.len() >= 8
                && bytes[0] == 0x89
                && bytes[1] == 0x50
                && bytes[2] == 0x4E
                && bytes[3] == 0x47
                && bytes[4] == 0x0D
                && bytes[5] == 0x0A
                && bytes[6] == 0x1A
                && bytes[7] == 0x0A
            {
                ValidationResult {
                    ok: true,
                    reason: "Gambar PNG terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "PNG".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan gambar PNG asli (header rusak atau salah)".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "PNG".into(),
                }
            }
        }

        "jpg" | "jpeg" => {
            if bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
                ValidationResult {
                    ok: true,
                    reason: "Foto JPEG terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "JPEG".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan foto JPEG asli".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "JPEG".into(),
                }
            }
        }

        "webp" => {
            if bytes.len() >= 12
                && &bytes[0..4] == b"RIFF"
                && &bytes[8..12] == b"WEBP"
            {
                ValidationResult {
                    ok: true,
                    reason: "Gambar WebP terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "WEBP".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan gambar WebP asli".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "WEBP".into(),
                }
            }
        }

        "gif" => {
            if bytes.len() >= 6 && (&bytes[0..6] == b"GIF87a" || &bytes[0..6] == b"GIF89a") {
                ValidationResult {
                    ok: true,
                    reason: "Gambar GIF terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "GIF".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan gambar GIF asli".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "GIF".into(),
                }
            }
        }

        "bmp" => {
            if bytes.len() >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D {
                ValidationResult {
                    ok: true,
                    reason: "Gambar BMP terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "BMP".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan gambar BMP asli".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "BMP".into(),
                }
            }
        }

        "docx" | "pptx" | "xlsx" | "odt" | "odp" | "ods" | "key" | "pages" | "numbers" => {
            let is_zip = bytes.len() >= 4
                && bytes[0] == 0x50
                && bytes[1] == 0x4B
                && ((bytes[2] == 0x03 && bytes[3] == 0x04) || (bytes[2] == 0x05 && bytes[3] == 0x06));

            if !is_zip {
                return ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan format Office (OpenXML) asli (bukan zip container)".into(),
                    file_name,
                    file_size,
                    kind: "doc".into(),
                    format: ext.to_uppercase(),
                };
            }

            if ext == "docx" && !ascii_slice.contains("word/") && !ascii_slice.contains("[Content_Types]") {
                return ValidationResult {
                    ok: false,
                    reason: "Berkas berformat ZIP biasa, bukan Dokumen Word (.docx) asli".into(),
                    file_name,
                    file_size,
                    kind: "doc".into(),
                    format: "DOCX".into(),
                };
            }

            if ext == "pptx" && !ascii_slice.contains("ppt/") && !ascii_slice.contains("[Content_Types]") {
                return ValidationResult {
                    ok: false,
                    reason: "Berkas berformat ZIP biasa, bukan Presentasi PowerPoint (.pptx) asli".into(),
                    file_name,
                    file_size,
                    kind: "presentation".into(),
                    format: "PPTX".into(),
                };
            }

            if ext == "xlsx" && !ascii_slice.contains("xl/") && !ascii_slice.contains("[Content_Types]") {
                return ValidationResult {
                    ok: false,
                    reason: "Berkas berformat ZIP biasa, bukan Spreadsheet Excel (.xlsx) asli".into(),
                    file_name,
                    file_size,
                    kind: "spreadsheet".into(),
                    format: "XLSX".into(),
                };
            }

            let kind = match ext.as_str() {
                "docx" | "odt" | "pages" => "doc",
                "pptx" | "odp" | "key" => "presentation",
                "xlsx" | "ods" | "numbers" => "spreadsheet",
                _ => "doc",
            };

            ValidationResult {
                ok: true,
                reason: format!("Dokumen {} terverifikasi", ext.to_uppercase()),
                file_name,
                file_size,
                kind: kind.into(),
                format: ext.to_uppercase(),
            }
        }

        "doc" | "xls" | "ppt" => {
            // Compound File Binary Format: D0 CF 11 E0 A1 B1 1A E1
            if bytes.len() >= 8
                && bytes[0] == 0xD0
                && bytes[1] == 0xCF
                && bytes[2] == 0x11
                && bytes[3] == 0xE0
                && bytes[4] == 0xA1
                && bytes[5] == 0xB1
                && bytes[6] == 0x1A
                && bytes[7] == 0xE1
            {
                let kind = match ext.as_str() {
                    "doc" => "doc",
                    "ppt" => "presentation",
                    _ => "spreadsheet",
                };
                ValidationResult {
                    ok: true,
                    reason: format!("Dokumen {} legacy terverifikasi", ext.to_uppercase()),
                    file_name,
                    file_size,
                    kind: kind.into(),
                    format: ext.to_uppercase(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan dokumen Microsoft Office legacy asli".into(),
                    file_name,
                    file_size,
                    kind: "doc".into(),
                    format: ext.to_uppercase(),
                }
            }
        }

        "txt" | "text" | "md" | "markdown" => {
            let null_count = bytes.iter().take(4096).filter(|&&b| b == 0).count();
            if null_count > 0 {
                ValidationResult {
                    ok: false,
                    reason: "Berkas terdeteksi sebagai binary/arsip, bukan teks asli!".into(),
                    file_name,
                    file_size,
                    kind: "text".into(),
                    format: "TXT".into(),
                }
            } else {
                ValidationResult {
                    ok: true,
                    reason: "Dokumen teks/markdown terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "text".into(),
                    format: ext.to_uppercase(),
                }
            }
        }

        "svg" => {
            if ascii_slice.to_lowercase().contains("<svg") {
                ValidationResult {
                    ok: true,
                    reason: "Dokumen vektor SVG terverifikasi".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "SVG".into(),
                }
            } else {
                ValidationResult {
                    ok: false,
                    reason: "Isi berkas bukan dokumen vektor SVG asli".into(),
                    file_name,
                    file_size,
                    kind: "image".into(),
                    format: "SVG".into(),
                }
            }
        }

        _ => ValidationResult {
            ok: false,
            reason: format!("Format .{} tidak didukung", ext),
            file_name,
            file_size,
            kind: "unknown".into(),
            format: ext.to_uppercase(),
        },
    }
}
