import SwiftUI
import AppKit

// MARK: - Markdown Block Model

enum MarkdownBlock: Identifiable, Equatable {
    var id: String {
        switch self {
        case .heading(let level, let text):
            return "h-\(level)-\(text)"
        case .codeBlock(let lang, let code):
            return "c-\(lang)-\(code.hashValue)"
        case .blockquote(let text):
            return "q-\(text.hashValue)"
        case .bullet(let text):
            return "b-\(text.hashValue)"
        case .numbered(let index, let text):
            return "n-\(index)-\(text.hashValue)"
        case .divider(let id):
            return "d-\(id)"
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        }
    }

    case heading(level: Int, text: String)
    case codeBlock(language: String, code: String)
    case blockquote(text: String)
    case bullet(text: String)
    case numbered(index: String, text: String)
    case divider(id: String)
    case paragraph(text: String)
}

// MARK: - Markdown Parser

enum MarkdownParser {
    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        var inCodeBlock = false
        var codeLang = ""
        var codeLines: [String] = []
        var paragraphLines: [String] = []
        var dividerCount = 0

        func flushParagraph() {
            if !paragraphLines.isEmpty {
                let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    blocks.append(.paragraph(text: text))
                }
                paragraphLines.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block toggle (```)
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Closing code fence
                    let code = codeLines.joined(separator: "\n")
                    blocks.append(.codeBlock(language: codeLang, code: code))
                    codeLines.removeAll()
                    codeLang = ""
                    inCodeBlock = false
                } else {
                    // Opening code fence
                    flushParagraph()
                    inCodeBlock = true
                    let after = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = after
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                i += 1
                continue
            }

            // Horizontal dividers: --- or *** or ___
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                dividerCount += 1
                blocks.append(.divider(id: "\(dividerCount)"))
                i += 1
                continue
            }

            // Headings: #, ##, ###, ####
            if trimmed.hasPrefix("#") {
                var level = 0
                var temp = trimmed
                while temp.hasPrefix("#") {
                    level += 1
                    temp.removeFirst()
                }
                if temp.hasPrefix(" ") {
                    flushParagraph()
                    let title = temp.trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: title))
                    i += 1
                    continue
                }
            }

            // Blockquotes: >
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(text: quote))
                i += 1
                continue
            }

            // Bullet list item: - , * , •
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushParagraph()
                let itemText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.bullet(text: itemText))
                i += 1
                continue
            }

            // Numbered list item: 1. or 1)
            let numPattern = #"^(\d+)[\.\)]\s+(.*)$"#
            if let regex = try? NSRegularExpression(pattern: numPattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               match.numberOfRanges >= 3,
               let numRange = Range(match.range(at: 1), in: trimmed),
               let textRange = Range(match.range(at: 2), in: trimmed) {
                flushParagraph()
                let num = String(trimmed[numRange])
                let text = String(trimmed[textRange])
                blocks.append(.numbered(index: num, text: text))
                i += 1
                continue
            }

            // Blank line separates paragraphs
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Regular paragraph line
            paragraphLines.append(line)
            i += 1
        }

        // Flush in-progress streaming code block
        if inCodeBlock {
            let code = codeLines.joined(separator: "\n")
            blocks.append(.codeBlock(language: codeLang, code: code))
        }
        flushParagraph()

        return blocks
    }
}

// MARK: - Inline Markdown Text

struct MarkdownInlineText: View {
    let text: String
    var font: Font = .system(size: 13.5)
    var color: Color = .white.opacity(0.92)

    private var attributedContent: AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    var body: some View {
        Text(attributedContent)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(3.5)
            .textSelection(.enabled)
    }
}

// MARK: - Code Block View with Copy

@MainActor
final class CodeCopyState: ObservableObject {
    @Published var copied: Bool = false

    func copy(code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        NSSound(named: "Glass")?.play()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation { self?.copied = false }
        }
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String

    @StateObject private var state = CodeCopyState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                    Text(language.isEmpty ? "CODE" : language.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Button {
                    state.copy(code: code)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: state.copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(state.copied ? "Tersalin!" : "Salin")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(state.copied ? Color(hex: 0x34D399) : .white.opacity(0.70))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: 0x141519))

            Divider().opacity(0.12)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE2E8F0))
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
        .background(Color(hex: 0x0B0C0E))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case .heading(let level, let text):
                    renderHeading(level: level, text: text)

                case .codeBlock(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                        .padding(.vertical, 2)

                case .blockquote(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color(hex: 0x3B82F6))
                            .frame(width: 3)
                            .clipShape(Capsule())

                        MarkdownInlineText(
                            text: text,
                            font: .system(size: 13, weight: .regular),
                            color: .white.opacity(0.80)
                        )
                        .italic()
                    }
                    .padding(.vertical, 2)

                case .bullet(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color(hex: 0x60A5FA))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)

                        MarkdownInlineText(text: text)
                    }

                case .numbered(let index, let text):
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(index).")
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x60A5FA))
                            .frame(minWidth: 16, alignment: .trailing)
                            .padding(.top, 1)

                        MarkdownInlineText(text: text)
                    }

                case .divider:
                    Divider()
                        .overlay(Color.white.opacity(0.12))
                        .padding(.vertical, 4)

                case .paragraph(let text):
                    MarkdownInlineText(text: text)
                }
            }
        }
    }

    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        switch level {
        case 1:
            MarkdownInlineText(
                text: text,
                font: .system(size: 16, weight: .bold),
                color: .white
            )
            .padding(.top, 4)

        case 2:
            MarkdownInlineText(
                text: text,
                font: .system(size: 15, weight: .bold),
                color: Color(hex: 0x93C5FD)
            )
            .padding(.top, 3)

        default:
            MarkdownInlineText(
                text: text,
                font: .system(size: 14, weight: .semibold),
                color: Color(hex: 0xBAE6FD)
            )
            .padding(.top, 2)
        }
    }
}

// MARK: - Thinking / Reasoning Disclosure View

@MainActor
final class ThinkingState: ObservableObject {
    @Published var isExpanded: Bool = false
}

struct ThinkingDisclosureView: View {
    let thinking: String
    let isStreaming: Bool

    @StateObject private var state = ThinkingState()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    state.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .semibold))
                    Text(isStreaming ? "Sedang menalar..." : "Proses Penalaran AI")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0x60A5FA))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: 0x2563EB).opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(hex: 0x60A5FA).opacity(0.30), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            if state.isExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(thinking)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineSpacing(2.5)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
        .padding(.vertical, 2)
    }
}

