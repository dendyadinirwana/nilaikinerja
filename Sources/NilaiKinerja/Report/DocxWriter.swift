import Foundation

/// Minimal WordprocessingML writer. No third-party dependency, because adding
/// one to a local-only app is a supply-chain risk with no upside.
///
/// A .docx is a ZIP of XML parts. This writes the smallest valid subset:
/// the content-type manifest, the package relationship, and one document part
/// holding paragraphs and a bordered table.
enum DocxWriter {

    // A4 in twips (1/1440 inch).
    private static let pageWidth = 11906
    private static let pageHeight = 16838
    // Indonesian official documents commonly use 4 cm left/right, 3 cm top/bottom.
    private static let marginLeft = 2268
    private static let marginRight = 2268
    private static let marginTop = 1701
    private static let marginBottom = 1701
    private static var contentWidth: Int { pageWidth - marginLeft - marginRight }

    struct Column {
        let header: String
        /// Relative width. Normalised across the table, so the caller does not
        /// have to compute twips.
        let weight: Int
        let align: Align

        enum Align: String { case left, center, right }
    }

    // MARK: - Entry point

    static func write(
        paragraphs: [String],
        table: [(columns: [Column], rows: [[String]])],
        to destination: URL
    ) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        // Both directories must exist before writing: the `.rels` and `word`
        // parts live one level down, and `Data.write(to:)` will not create
        // intermediate directories.
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("word", isDirectory: true),
            withIntermediateDirectories: true
        )

        try writeText(contentTypesXML, to: staging.appendingPathComponent("[Content_Types].xml"))
        try writeText(packageRelsXML, to: staging.appendingPathComponent("_rels/.rels"))
        try writeText(
            documentXML(paragraphs: paragraphs, table: table),
            to: staging.appendingPathComponent("word/document.xml")
        )

        // System `zip` is present on every macOS install and handles the
        // container format correctly. Reimplementing ZIP in Swift to avoid
        // spawning a process would be more code and more risk.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.arguments = ["-r", "-X", "-q", destination.path, "."]
        task.currentDirectoryURL = staging
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(
                domain: "DocxWriter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal membuat berkas .docx"]
            )
        }
    }

    private static func writeText(_ string: String, to url: URL) throws {
        try string.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - Package parts

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let packageRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    // MARK: - Document body

    private static func documentXML(
        paragraphs: [String],
        table: [(columns: [Column], rows: [[String]])]
    ) -> String {
        var body = ""
        for paragraph in paragraphs {
            body += paragraphXML(paragraph, bold: false, size: 24, align: "both", spacing: 120)
        }
        for block in table {
            body += tableXML(columns: block.columns, rows: block.rows)
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(body)
            <w:sectPr>
              <w:pgSz w:w="\(pageWidth)" w:h="\(pageHeight)"/>
              <w:pgMar w:top="\(marginTop)" w:right="\(marginRight)" w:bottom="\(marginBottom)" w:left="\(marginLeft)" w:header="0" w:footer="0" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func paragraphXML(
        _ text: String,
        bold: Bool = false,
        size: Int = 22,
        align: String = "left",
        spacing: Int = 60
    ) -> String {
        """
        <w:p>
          <w:pPr>
            <w:spacing w:after="\(spacing)"/>
            <w:jc w:val="\(align)"/>
          </w:pPr>
          <w:r>
            \(bold ? "<w:rPr><w:b/></w:rPr>" : "")
            <w:rPr><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/></w:rPr>
            <w:t xml:space="preserve">\(escape(text))</w:t>
          </w:r>
        </w:p>
        """
    }

    private static func tableXML(columns: [Column], rows: [[String]]) -> String {
        let totalWeight = max(1, columns.reduce(0) { $0 + $1.weight })
        let widths = columns.map { Int(Double(contentWidth) * Double($0.weight) / Double(totalWeight)) }

        var grid = ""
        for width in widths {
            grid += "<w:gridCol w:w=\"\(width)\"/>"
        }

        var borders = ""
        for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
            borders += "<w:\(edge) w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"000000\"/>"
        }

        var body = ""
        // Header row, marked so Word repeats it across page breaks.
        body += row(cells: columns.map(\.header), widths: widths, bold: true)
        for row in rows {
            body += self.row(cells: row, widths: widths, bold: false, columns: columns)
        }

        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(contentWidth)" w:type="dxa"/>
            <w:tblBorders>\(borders)</w:tblBorders>
            <w:tblLayout w:type="fixed"/>
          </w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(body)
        </w:tbl>
        """
    }

    private static func row(
        cells: [String],
        widths: [Int],
        bold: Bool,
        columns: [Column] = []
    ) -> String {
        var xml = "<w:tr>"
        if bold {
            xml += "<w:trPr><w:tblHeader/></w:trPr>"
        }
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : widths.last ?? 1000
            let align = index < columns.count ? columns[index].align.rawValue : "left"

            // Multi-line cells use explicit newlines rather than <w:br/> so
            // the text stays greppable when the document is unzipped.
            let paragraphs = cell
                .components(separatedBy: "\n")
                .map { line -> String in
                    """
                    <w:p>
                      <w:pPr><w:jc w:val="\(align)"/><w:spacing w:after="20"/></w:pPr>
                      <w:r>
                        \(bold ? "<w:rPr><w:b/></w:rPr>" : "")
                        <w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
                        <w:t xml:space="preserve">\(escape(line))</w:t>
                      </w:r>
                    </w:p>
                    """
                }
                .joined()
            xml += """
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(width)" w:type="dxa"/>
              </w:tcPr>
              \(paragraphs)
            </w:tc>
            """
        }
        xml += "</w:tr>"
        return xml
    }

    /// XML-escapes text. Attribute-quote and ampersand handling matters here:
    /// a job title containing "&" is common enough that skipping this produces
    /// a document Word refuses to open.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
