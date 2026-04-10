import Foundation

struct WorkspaceImportResult {
    var importedNotes: [NoteDocument]
    var importedFilesCount: Int
}

enum NotionWorkspaceImporter {
    static func importArchive(
        from archiveURL: URL,
        existingNotes: [NoteDocument],
        appDirectory: URL,
        copyAttachment: (URL) throws -> ImportedFilePayload?
    ) throws -> WorkspaceImportResult {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let resolvedRoot = try recursivelyExtractArchive(at: archiveURL, into: tempDirectory)
        return try importDirectory(
            from: resolvedRoot,
            existingNotes: existingNotes,
            appDirectory: appDirectory,
            copyAttachment: copyAttachment
        )
    }

    static func importDirectory(
        from rootURL: URL,
        existingNotes: [NoteDocument],
        appDirectory: URL,
        copyAttachment: (URL) throws -> ImportedFilePayload?
    ) throws -> WorkspaceImportResult {
        var state = ImportState(existingNotes: existingNotes)
        try importFolder(
            rootURL,
            parentID: nil,
            preferredCourse: cleanName(rootURL.deletingPathExtension().lastPathComponent),
            state: &state,
            copyAttachment: copyAttachment
        )
        return WorkspaceImportResult(importedNotes: state.importedNotes, importedFilesCount: state.importedFilesCount)
    }

    private static func recursivelyExtractArchive(at archiveURL: URL, into tempRoot: URL) throws -> URL {
        var currentArchive = archiveURL
        var depth = 0

        while true {
            let outputDirectory = tempRoot.appendingPathComponent("level-\(depth)", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try unzipArchive(at: currentArchive, to: outputDirectory)

            let contents = try visibleContents(of: outputDirectory)
            if contents.count == 1, contents[0].pathExtension.lowercased() == "zip" {
                currentArchive = contents[0]
                depth += 1
                continue
            }
            return outputDirectory
        }
    }

    private static func unzipArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BeeterNotions.Import", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to unzip Notion export archive."
            ])
        }
    }

    private static func importFolder(
        _ folderURL: URL,
        parentID: UUID?,
        preferredCourse: String,
        state: inout ImportState,
        copyAttachment: (URL) throws -> ImportedFilePayload?
    ) throws {
        let contents = try visibleContents(of: folderURL)

        let htmlFiles = contents.filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
        let markdownFiles = contents.filter { $0.pathExtension.lowercased() == "md" }
        let csvFiles = contents.filter { $0.pathExtension.lowercased() == "csv" && !$0.lastPathComponent.lowercased().contains("_all.csv") }
        let pdfFiles = contents.filter { $0.pathExtension.lowercased() == "pdf" }
        let imageFiles = contents.filter { ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains($0.pathExtension.lowercased()) }
        let directories = contents.filter { isDirectory($0) }

        var folderNoteIDs: [String: UUID] = [:]

        for htmlFile in htmlFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let parsed = try parseHTMLNote(from: htmlFile, parentID: parentID, preferredCourse: preferredCourse)
            folderNoteIDs[normalizedKey(for: htmlFile)] = parsed.id
            state.importedNotes.append(parsed)
        }

        for markdownFile in markdownFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let parsed = try parseMarkdownNote(from: markdownFile, parentID: parentID, preferredCourse: preferredCourse, copyAttachment: copyAttachment)
            folderNoteIDs[normalizedKey(for: markdownFile)] = parsed.note.id
            state.importedNotes.append(parsed.note)
            state.importedFilesCount += parsed.importedFilesCount
        }

        for csvFile in csvFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let imported = try parseCSVWorkspace(from: csvFile, parentID: parentID, preferredCourse: preferredCourse)
            for note in imported {
                state.importedNotes.append(note)
                if note.parentID == parentID {
                    folderNoteIDs[normalizedKey(for: csvFile)] = note.id
                }
            }
        }

        if parentID != nil && htmlFiles.isEmpty && markdownFiles.isEmpty {
            var attachmentBlocks: [NoteBlock] = []

            for pdfFile in pdfFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let payload = try copyAttachment(pdfFile) {
                    attachmentBlocks.append(.file(payload))
                    state.importedFilesCount += 1
                }
            }

            for imageFile in imageFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let payload = try copyAttachment(imageFile) {
                    attachmentBlocks.append(.file(payload))
                    state.importedFilesCount += 1
                }
            }

            if !attachmentBlocks.isEmpty, let parentID {
                if let importedIndex = state.importedNotes.firstIndex(where: { $0.id == parentID }) {
                    state.importedNotes[importedIndex].blocks.append(contentsOf: attachmentBlocks)
                }
            }
        }

        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let key = normalizedDirectoryKey(for: directory)
            let nextParent = folderNoteIDs[key] ?? parentID
            let nextCourse = parentID == nil ? cleanName(directory.lastPathComponent) : preferredCourse
            try importFolder(
                directory,
                parentID: nextParent,
                preferredCourse: nextCourse,
                state: &state,
                copyAttachment: copyAttachment
            )
        }
    }

    private static func parseHTMLNote(from url: URL, parentID: UUID?, preferredCourse: String) throws -> NoteDocument {
        let html = try String(contentsOf: url, encoding: .utf8)
        let title = extractTitle(from: html) ?? cleanName(url.deletingPathExtension().lastPathComponent)
        var blocks: [NoteBlock] = [.heading(title)]

        let callouts = extractTagContents(named: "blockquote", from: html).map(stripHTML).filter { !$0.isEmpty }
        blocks.append(contentsOf: callouts.map(NoteBlock.callout))

        let headings = extractTagContents(named: "h2", from: html).map(stripHTML).filter { !$0.isEmpty && $0 != title }
        blocks.append(contentsOf: headings.map(NoteBlock.heading))

        let paragraphs = extractTagContents(named: "p", from: html).map(stripHTML).filter { !$0.isEmpty }
        blocks.append(contentsOf: paragraphs.map(NoteBlock.paragraph))

        let listItems = extractTagContents(named: "li", from: html).map(stripHTML).filter { !$0.isEmpty }
        if !listItems.isEmpty {
            blocks.append(.bulletedList(listItems))
        }

        let codeBlocks = extractTagContents(named: "pre", from: html).map(stripHTML).filter { !$0.isEmpty }
        blocks.append(contentsOf: codeBlocks.map { .code($0, language: "text") })
        blocks.append(contentsOf: extractTables(from: html))

        if blocks.count == 1 {
            let fallback = stripHTML(html)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            blocks.append(contentsOf: fallback.prefix(6).map { .paragraph(String($0)) })
        }

        let inferred = inferProperties(
            from: title,
            metadata: [:],
            bodyText: paragraphs.joined(separator: "\n"),
            preferredCourse: preferredCourse,
            containerName: cleanName(url.deletingLastPathComponent().lastPathComponent)
        )

        return NoteDocument(
            title: title,
            icon: inferred.icon,
            parentID: parentID,
            isFavorite: false,
            cover: inferred.cover,
            properties: .init(
                course: inferred.course,
                subject: inferred.subject,
                summary: inferred.summary,
                status: inferred.status,
                dueDate: inferred.dueDate,
                tags: inferred.tags
            ),
            blocks: blocks
        )
    }

    private static func parseMarkdownNote(
        from url: URL,
        parentID: UUID?,
        preferredCourse: String,
        copyAttachment: (URL) throws -> ImportedFilePayload?
    ) throws -> (note: NoteDocument, importedFilesCount: Int) {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let lines = markdown.components(separatedBy: .newlines)

        var title = cleanName(url.deletingPathExtension().lastPathComponent)
        var metadata: [String: String] = [:]
        var blocks: [NoteBlock] = []
        var paragraphBuffer: [String] = []
        var listBuffer: [String] = []
        var codeFenceLanguage = ""
        var codeFenceLines: [String] = []
        var inCodeFence = false
        var importedFilesCount = 0

        func flushParagraph() {
            let text = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphBuffer.removeAll()
        }

        func flushList() {
            if !listBuffer.isEmpty {
                blocks.append(.bulletedList(listBuffer))
            }
            listBuffer.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if inCodeFence {
                if line.hasPrefix("```") {
                    blocks.append(.code(codeFenceLines.joined(separator: "\n"), language: codeFenceLanguage.isEmpty ? "text" : codeFenceLanguage))
                    codeFenceLines.removeAll()
                    codeFenceLanguage = ""
                    inCodeFence = false
                } else {
                    codeFenceLines.append(rawLine)
                }
                continue
            }

            if line.hasPrefix("```") {
                flushParagraph()
                flushList()
                inCodeFence = true
                codeFenceLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if line.hasPrefix("# ") && blocks.isEmpty {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(.heading(title))
                continue
            }

            if let separatorIndex = line.firstIndex(of: ":"), !line.hasPrefix("|"), metadata.count < 8 {
                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if ["Course", "Date", "Status", "Summary", "Subject", "Tags"].contains(key), !value.isEmpty {
                    metadata[key] = value
                    continue
                }
            }

            if line == "---" {
                flushParagraph()
                flushList()
                blocks.append(.divider())
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                flushList()
                blocks.append(.heading(String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }

            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                flushParagraph()
                flushList()
                let heading = line.replacingOccurrences(of: "^#{2,3}\\s*", with: "", options: .regularExpression)
                blocks.append(.heading(heading))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                listBuffer.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }

            if line.hasPrefix("!["), let imagePath = markdownLinkTarget(from: line) {
                flushParagraph()
                flushList()
                let decodedPath = imagePath.removingPercentEncoding ?? imagePath
                let resolved = url.deletingLastPathComponent().appendingPathComponent(decodedPath)
                if let payload = try copyAttachment(resolved) {
                    blocks.append(.file(payload))
                    importedFilesCount += 1
                }
                continue
            }

            if line.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            paragraphBuffer.append(line)
        }

        flushParagraph()
        flushList()

        blocks = normalizeMarkdownTables(in: blocks, rawLines: lines)

        if blocks.isEmpty {
            blocks = [.heading(title), .paragraph("Imported from Notion Markdown export")]
        } else if blocks.first?.type != .heading {
            blocks.insert(.heading(title), at: 0)
        }

        let inferred = inferProperties(
            from: title,
            metadata: metadata,
            bodyText: markdown,
            preferredCourse: preferredCourse,
            containerName: cleanName(url.deletingLastPathComponent().lastPathComponent)
        )

        let note = NoteDocument(
            title: title,
            icon: inferred.icon,
            parentID: parentID,
            isFavorite: false,
            cover: inferred.cover,
            properties: .init(
                course: inferred.course,
                subject: inferred.subject,
                summary: inferred.summary,
                status: inferred.status,
                dueDate: inferred.dueDate,
                tags: inferred.tags
            ),
            blocks: blocks
        )

        return (note, importedFilesCount)
    }

    private static func normalizeMarkdownTables(in blocks: [NoteBlock], rawLines: [String]) -> [NoteBlock] {
        var output: [NoteBlock] = []
        var index = 0

        while index < rawLines.count {
            let trimmed = rawLines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|"),
               index + 1 < rawLines.count,
               rawLines[index + 1].contains("| ---") || rawLines[index + 1].contains("|---") {
                let headers = markdownTableCells(from: trimmed)
                index += 2
                var rows: [[String]] = []
                while index < rawLines.count {
                    let rowTrimmed = rawLines[index].trimmingCharacters(in: .whitespaces)
                    guard rowTrimmed.hasPrefix("|") else { break }
                    rows.append(markdownTableCells(from: rowTrimmed))
                    index += 1
                }
                if !headers.isEmpty {
                    output.append(.table(headers: headers, rows: rows))
                }
                continue
            }
            index += 1
        }

        if output.isEmpty {
            return blocks
        }

        return blocks.filter { $0.type != .table } + output
    }

    private static func markdownTableCells(from line: String) -> [String] {
        line
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func markdownLinkTarget(from line: String) -> String? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { return nil }
        return String(line[line.index(after: open)..<close])
    }

    private static func parseCSVWorkspace(from url: URL, parentID: UUID?, preferredCourse: String) throws -> [NoteDocument] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(csv)
        guard let header = rows.first else { return [] }
        let headers = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let dataRows = Array(rows.dropFirst())
        guard !headers.isEmpty else { return [] }

        let tableRows = dataRows.map { row in
            Array(row.prefix(headers.count)) + Array(repeating: "", count: max(0, headers.count - row.count))
        }

        let databaseTitle = cleanName(url.deletingPathExtension().lastPathComponent)
        let databaseID = UUID()
        var notes: [NoteDocument] = [
            NoteDocument(
                id: databaseID,
                title: databaseTitle,
                icon: "tablecells",
                parentID: parentID,
                cover: .moss,
                properties: .init(
                    course: preferredCourse,
                    subject: "Imported Database",
                    summary: "Imported \(dataRows.count) records from Notion CSV export",
                    status: .inProgress,
                    tags: ["csv", "database"]
                ),
                blocks: [
                    .heading(databaseTitle),
                    .table(headers: headers, rows: tableRows)
                ]
            )
        ]

        for row in dataRows {
            let padded = row + Array(repeating: "", count: max(0, headers.count - row.count))
            let dictionary = Dictionary(uniqueKeysWithValues: zip(headers, padded))
            let title = firstValue(in: dictionary, matching: ["Name", "Title", "Note Title"]) ?? "\(databaseTitle) Item"
            let summary = firstValue(in: dictionary, matching: ["Summary", "Description", "Notes"]) ?? "Imported workspace row"
            let course = firstValue(in: dictionary, matching: ["Course", "Workspace"]) ?? preferredCourse
            let subject = firstValue(in: dictionary, matching: ["Subject", "Category"]) ?? databaseTitle
            let status = NoteStatus(csvValue: firstValue(in: dictionary, matching: ["Status"]))
            let dueDate = parseDate(firstValue(in: dictionary, matching: ["Date", "Due Date", "Created time"]))
            let tags = firstValue(in: dictionary, matching: ["Tags"]).map {
                $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } ?? []

            let bodyLines = dictionary
                .filter { !["Name", "Title", "Note Title", "Summary", "Description", "Notes", "Course", "Workspace", "Subject", "Category", "Status", "Date", "Due Date", "Created time", "Tags"].contains($0.key) }
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value)" }

            notes.append(
                NoteDocument(
                    title: title,
                    icon: "doc.text",
                    parentID: databaseID,
                    cover: .sand,
                    properties: .init(
                        course: course,
                        subject: subject,
                        summary: summary,
                        status: status,
                        dueDate: dueDate,
                        tags: tags
                    ),
                    blocks: [
                        .heading(title),
                        .paragraph(summary),
                        .bulletedList(bodyLines.isEmpty ? ["Imported from database row"] : bodyLines)
                    ]
                )
            )
        }

        return notes
    }

    private static func extractTitle(from html: String) -> String? {
        if let h1 = extractTagContents(named: "h1", from: html).first {
            let title = stripHTML(h1)
            if !title.isEmpty { return title }
        }
        if let titleTag = extractTagContents(named: "title", from: html).first {
            let title = stripHTML(titleTag)
            if !title.isEmpty { return title }
        }
        return nil
    }

    private static func extractTagContents(named tag: String, from html: String) -> [String] {
        let pattern = tag == "t[hd]" ? "(?is)<t[hd]\\b[^>]*>(.*?)</t[hd]>" : "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }

    private static func extractTables(from html: String) -> [NoteBlock] {
        let tables = extractTagContents(named: "table", from: html)
        return tables.compactMap { tableHTML in
            let rows = extractTagContents(named: "tr", from: tableHTML).map { rowHTML in
                extractTagContents(named: "t[hd]", from: rowHTML).map(stripHTML).filter { !$0.isEmpty }
            }
            guard let firstRow = rows.first, !firstRow.isEmpty else { return nil }
            return .table(headers: firstRow, rows: Array(rows.dropFirst()).filter { !$0.isEmpty })
        }
    }

    private static func stripHTML(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "(?is)<br\\s*/?>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseCSV(_ raw: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false

        for character in raw {
            switch character {
            case "\"":
                isQuoted.toggle()
            case "," where !isQuoted:
                row.append(field)
                field = ""
            case "\n" where !isQuoted:
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            case "\r":
                continue
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.map { $0.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{feff}")) } }
    }

    private static func firstValue(in dictionary: [String: String], matching keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        if let date = formatter.date(from: raw) { return date }
        formatter.dateFormat = "M/d/yyyy"
        return formatter.date(from: raw)
    }

    private static func inferProperties(from title: String, metadata: [String: String], bodyText: String, preferredCourse: String, containerName: String) -> (course: String, subject: String, summary: String, status: NoteStatus, dueDate: Date?, tags: [String], icon: String, cover: CoverStyle) {
        let course = metadata["Course"] ?? preferredCourse
        let subject = metadata["Subject"] ?? (containerName == preferredCourse ? "" : containerName)
        let summary = metadata["Summary"] ?? bodyText.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Imported from Notion export"
        let status = metadata["Status"].map(NoteStatus.init(csvValue:)) ?? NoteStatus(textValue: (title + " " + bodyText).lowercased())
        let dueDate = parseDate(metadata["Date"]) ?? parseDate(in: bodyText)
        let tagString = metadata["Tags"] ?? ""
        let tags = (tagString.isEmpty ? [course, subject] : tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
        let lowerTitle = title.lowercased()
        let icon = lowerTitle.contains("assignment") ? "graduationcap" : (lowerTitle.contains("project") ? "hammer" : "doc.text")
        let cover: CoverStyle = lowerTitle.contains("security") ? .ocean : (lowerTitle.contains("project") ? .dusk : .sand)
        return (course, subject, summary, status, dueDate, tags, icon, cover)
    }

    private static func parseDate(in text: String) -> Date? {
        let patterns = [
            "\\b\\d{4}-\\d{2}-\\d{2}\\b",
            "\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b",
            "\\b(?:January|February|March|April|May|June|July|August|September|October|November|December) \\d{1,2}, \\d{4}\\b"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange), let range = Range(match.range, in: text) else { continue }
            if let date = parseDate(String(text[range])) {
                return date
            }
        }
        return nil
    }

    private static func visibleContents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func normalizedKey(for fileURL: URL) -> String {
        cleanName(fileURL.deletingPathExtension().lastPathComponent).lowercased()
    }

    private static func normalizedDirectoryKey(for directoryURL: URL) -> String {
        cleanName(directoryURL.lastPathComponent).lowercased()
    }

    private static func cleanName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "[-_ ]?([0-9a-fA-F]{32}|[0-9a-fA-F\\-]{36})$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImportState {
    let existingNotes: [NoteDocument]
    var importedNotes: [NoteDocument] = []
    var importedFilesCount: Int = 0
}

private extension NoteStatus {
    init(csvValue raw: String?) {
        self = NoteStatus(textValue: raw?.lowercased() ?? "")
    }

    init(textValue raw: String) {
        if raw.contains("complete") || raw.contains("done") || raw.contains("submitted") {
            self = .complete
        } else if raw.contains("progress") || raw.contains("doing") || raw.contains("active") {
            self = .inProgress
        } else {
            self = .notStarted
        }
    }
}
