import SwiftUI

struct ReleaseNotesView: View {
    let markdown: String

    private var blocks: [Block] {
        Self.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, AppSpacing.xxs)
        case .paragraph(let text):
            inlineText(text)
                .font(AppTypography.secondary)
                .lineSpacing(3)
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text("•").font(AppTypography.secondary).foregroundStyle(.secondary)
                inlineText(text).font(AppTypography.secondary)
            }
            .padding(.leading, CGFloat(indent) * AppSpacing.md)
        case .numbered(let indent, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text("\(number).").font(AppTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
                inlineText(text).font(AppTypography.secondary)
            }
            .padding(.leading, CGFloat(indent) * AppSpacing.md)
        case .quote(let text):
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: 1).fill(AppColors.separator).frame(width: 3)
                inlineText(text).font(AppTypography.secondary).foregroundStyle(.secondary)
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(AppSpacing.sm)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: AppRadius.small))
        case .divider:
            Divider()
        }
    }

    private func inlineText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet(Int, String)
        case numbered(Int, Int, String)
        case quote(String)
        case code(String)
        case divider
    }

    private static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                } else {
                    flushParagraph()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            let leadingSpaces = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let indent = min(2, leadingSpaces / 2)

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(heading.level, heading.text))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(indent, String(trimmed.dropFirst(2))))
            } else if let numbered = numberedItem(from: trimmed) {
                flushParagraph()
                blocks.append(.numbered(indent, numbered.number, numbered.text))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("![") {
                flushParagraph()
                blocks.append(.paragraph(trimmed))
            } else {
                paragraph.append(trimmed)
            }
        }

        if inCode, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func numberedItem(from line: String) -> (number: Int, text: String)? {
        guard let match = line.firstMatch(of: /^(\d+)\.\s+(.+)$/),
              let number = Int(match.1) else { return nil }
        return (number, String(match.2))
    }
}
