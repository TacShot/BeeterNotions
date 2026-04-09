import Foundation

enum MarkdownVault {
    static func loadNotes(appDirectory: URL) throws -> [NoteDocument] {
        let pagesDirectory = try pagesDirectory(appDirectory: appDirectory)
        let files = try FileManager.default.contentsOfDirectory(
            at: pagesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }

        return try files
            .map { try loadNote(from: $0, relativeTo: pagesDirectory) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(note: NoteDocument, appDirectory: URL) throws -> NoteDocument {
        let pagesDirectory = try pagesDirectory(appDirectory: appDirectory)
        let relativePath = note.vaultRelativePath ?? defaultRelativePath(for: note)
        let destination = pagesDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        var updated = note
        updated.vaultRelativePath = relativePath
        let markdown = serialize(note: updated)
        try markdown.write(to: destination, atomically: true, encoding: .utf8)
        return updated
    }

    static func deleteMarkdownFile(for note: NoteDocument, appDirectory: URL) throws {
        guard let relativePath = note.vaultRelativePath else { return }
        let pagesDirectory = try pagesDirectory(appDirectory: appDirectory)
        let url = pagesDirectory.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func migrate(notes: [NoteDocument], appDirectory: URL) throws -> [NoteDocument] {
        try FileManager.default.createDirectory(at: pagesDirectory(appDirectory: appDirectory), withIntermediateDirectories: true)
        return try notes.map { try save(note: $0, appDirectory: appDirectory) }
    }

    private static func loadNote(from url: URL, relativeTo pagesDirectory: URL) throws -> NoteDocument {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let components = splitFrontmatter(from: raw)
        let metadata = parseFrontmatter(components.frontmatter)
        let body = components.body.trimmingCharacters(in: .whitespacesAndNewlines)

        return NoteDocument(
            id: UUID(uuidString: metadata["id"] ?? "") ?? UUID(),
            title: metadata["title"] ?? cleanTitle(from: url),
            slug: metadata["slug"] ?? NoteDocument.makeSlug(from: metadata["title"] ?? cleanTitle(from: url)),
            aliases: parseList(metadata["aliases"]),
            icon: metadata["icon"] ?? "doc.text",
            vaultRelativePath: url.path.replacingOccurrences(of: pagesDirectory.path + "/", with: ""),
            parentID: UUID(uuidString: metadata["parent_id"] ?? ""),
            isFavorite: parseBool(metadata["is_favorite"]),
            isInTrash: parseBool(metadata["is_in_trash"]),
            cover: CoverStyle(rawValue: metadata["cover"] ?? "") ?? .sand,
            properties: NoteProperties(
                course: metadata["course"] ?? "",
                subject: metadata["subject"] ?? "",
                summary: metadata["summary"] ?? "",
                status: NoteStatus(rawValue: metadata["status"] ?? "") ?? .notStarted,
                dueDate: parseDate(metadata["due_date"]),
                tags: parseList(metadata["tags"])
            ),
            createdAt: parseDate(metadata["created_at"]) ?? .now,
            updatedAt: parseDate(metadata["updated_at"]) ?? .now,
            blocks: parseBlocks(from: body)
        )
    }

    private static func serialize(note: NoteDocument) -> String {
        let frontmatter = [
            ("id", note.id.uuidString),
            ("title", escapeYAML(note.title)),
            ("slug", note.slug),
            ("aliases", "[\(note.aliases.map(escapeYAML).joined(separator: ", "))]"),
            ("icon", note.icon),
            ("parent_id", note.parentID?.uuidString ?? ""),
            ("is_favorite", note.isFavorite ? "true" : "false"),
            ("is_in_trash", note.isInTrash ? "true" : "false"),
            ("cover", note.cover.rawValue),
            ("course", escapeYAML(note.properties.course)),
            ("subject", escapeYAML(note.properties.subject)),
            ("summary", escapeYAML(note.properties.summary)),
            ("status", note.properties.status.rawValue),
            ("due_date", note.properties.dueDate.map(formatDate) ?? ""),
            ("tags", "[\(note.properties.tags.map(escapeYAML).joined(separator: ", "))]"),
            ("created_at", formatDate(note.createdAt)),
            ("updated_at", formatDate(note.updatedAt))
        ]
        .map { "\($0.0): \($0.1)" }
        .joined(separator: "\n")

        return """
        ---
        \(frontmatter)
        ---

        \(serializeBlocks(note.blocks))
        """
    }

    private static func serializeBlocks(_ blocks: [NoteBlock]) -> String {
        blocks.map { block in
            switch block.payload {
            case let .text(value):
                switch block.type {
                case .heading:
                    return "# \(value)"
                case .callout:
                    return "> [!note]\n> \(value.replacingOccurrences(of: "\n", with: "\n> "))"
                default:
                    return value
                }
            case let .list(items):
                return items.map { "- \($0)" }.joined(separator: "\n")
            case let .toggle(toggle):
                return """
                <details \(toggle.isExpanded ? "open" : "")>
                <summary>\(toggle.title)</summary>

                \(toggle.body)
                </details>
                """
            case let .code(code):
                return """
                ```\(code.language)
                \(code.snippet)
                ```
                """
            case let .table(table):
                let header = "| " + table.headers.joined(separator: " | ") + " |"
                let separator = "| " + Array(repeating: "---", count: table.headers.count).joined(separator: " | ") + " |"
                let rows = table.rows.map { "| " + $0.joined(separator: " | ") + " |" }.joined(separator: "\n")
                return ([header, separator, rows].filter { !$0.isEmpty }).joined(separator: "\n")
            case let .chart(chart):
                let lines = chart.points.map { "- \($0.label): \($0.value)" }.joined(separator: "\n")
                return "## \(chart.title)\n\(lines)"
            case let .file(file):
                switch file.kind {
                case .image:
                    return "![[\(file.storedFilename)|\(file.displayName)]]"
                default:
                    return "[[\(file.storedFilename)|\(file.displayName)]]"
                }
            case .empty:
                return "---"
            }
        }
        .joined(separator: "\n\n")
    }

    private static func parseBlocks(from body: String) -> [NoteBlock] {
        let lines = body.components(separatedBy: .newlines)
        var blocks: [NoteBlock] = []
        var paragraphBuffer: [String] = []
        var listBuffer: [String] = []
        var tableBuffer: [String] = []
        var codeLanguage = ""
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            let text = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if text.hasPrefix("> [!note]") {
                    blocks.append(.callout(text.replacingOccurrences(of: "> [!note]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    blocks.append(.paragraph(text))
                }
            }
            paragraphBuffer.removeAll()
        }

        func flushList() {
            if !listBuffer.isEmpty {
                blocks.append(.bulletedList(listBuffer))
                listBuffer.removeAll()
            }
        }

        func flushTable() {
            if tableBuffer.count >= 2 {
                let headers = markdownCells(tableBuffer[0])
                let rows = tableBuffer.dropFirst(2).map(markdownCells)
                if !headers.isEmpty {
                    blocks.append(.table(headers: headers, rows: rows))
                }
            }
            tableBuffer.removeAll()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if inCode {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(codeLines.joined(separator: "\n"), language: codeLanguage.isEmpty ? "text" : codeLanguage))
                    codeLines.removeAll()
                    codeLanguage = ""
                    inCode = false
                } else {
                    codeLines.append(rawLine)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                flushTable()
                inCode = true
                codeLanguage = String(trimmed.dropFirst(3))
                continue
            }

            if trimmed.hasPrefix("|") {
                flushParagraph()
                flushList()
                tableBuffer.append(trimmed)
                continue
            } else {
                flushTable()
            }

            if trimmed.hasPrefix("# ") {
                flushParagraph()
                flushList()
                blocks.append(.heading(String(trimmed.dropFirst(2))))
                continue
            }

            if trimmed == "---" {
                flushParagraph()
                flushList()
                blocks.append(.divider())
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushParagraph()
                listBuffer.append(String(trimmed.dropFirst(2)))
                continue
            }

            if trimmed.hasPrefix("![[") || trimmed.hasPrefix("[[") {
                flushParagraph()
                flushList()
                if let payload = parseFileReference(trimmed) {
                    blocks.append(.file(payload))
                }
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            paragraphBuffer.append(trimmed)
        }

        flushParagraph()
        flushList()
        flushTable()

        return blocks.isEmpty ? [.paragraph("Start writing here...")] : blocks
    }

    private static func parseFileReference(_ line: String) -> ImportedFilePayload? {
        let isImage = line.hasPrefix("![[")
        let trimmed = line
            .replacingOccurrences(of: "![[", with: "")
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
        let parts = trimmed.split(separator: "|", maxSplits: 1).map(String.init)
        guard let stored = parts.first else { return nil }
        let display = parts.count > 1 ? parts[1] : stored
        let ext = URL(fileURLWithPath: stored).pathExtension.lowercased()
        let kind = ImportedFilePayload.FileKind(fileExtension: ext) ?? (isImage ? .image : .pdf)
        return ImportedFilePayload(displayName: display, storedFilename: stored, kind: kind)
    }

    private static func pagesDirectory(appDirectory: URL) throws -> URL {
        let url = appDirectory.appendingPathComponent("Vault/Pages", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func defaultRelativePath(for note: NoteDocument) -> String {
        "\(safeFilename(note.title))-\(note.id.uuidString.prefix(8)).md"
    }

    private static func safeFilename(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "[/:\\\\?%*|\"<>]", with: "-", options: .regularExpression)
        return sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitFrontmatter(from raw: String) -> (frontmatter: String, body: String) {
        guard raw.hasPrefix("---\n") else { return ("", raw) }
        let components = raw.components(separatedBy: "\n---\n")
        guard components.count >= 2 else { return ("", raw) }
        return (components[0].replacingOccurrences(of: "---\n", with: ""), components.dropFirst().joined(separator: "\n---\n"))
    }

    private static func parseFrontmatter(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = value
        }
        return result
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: raw)
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseBool(_ raw: String?) -> Bool {
        raw == "true"
    }

    private static func parseList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func escapeYAML(_ value: String) -> String {
        if value.contains(":") || value.contains(",") || value.contains("[") || value.contains("]") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }

    private static func cleanTitle(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-[0-9A-Fa-f]{8}$", with: "", options: .regularExpression)
    }

    private static func markdownCells(_ line: String) -> [String] {
        line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.allSatisfy({ $0 == "-" }) }
    }
}
