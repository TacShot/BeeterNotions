import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteDocument] = []
    @Published private(set) var folders: [SidebarFolder] = []
    @Published private(set) var noteIndex: NoteIndex = .empty
    @Published var selectedNoteID: UUID?
    @Published var searchText: String = ""
    @Published var selectedView: WorkspaceView = .allNotes
    @Published var browserMode: BrowserMode = .table
    @Published var activePane: AppPane = .workspace
    @Published var lastOperationStatus: String?
    @Published var openTabIDs: [UUID] = []
    @Published var splitViewEnabled: Bool = false
    @Published var secondarySelectedNoteID: UUID?
    @Published private(set) var backHistory: [UUID] = []
    @Published private(set) var forwardHistory: [UUID] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() async {
        do {
            let appDirectory = try appDirectory()
            let vaultNotes = try MarkdownVault.loadNotes(appDirectory: appDirectory)
            folders = try loadFolders(appDirectory: appDirectory)

            if vaultNotes.isEmpty {
                let legacyURL = try notesIndexURL()
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    let data = try Data(contentsOf: legacyURL)
                    let legacyNotes = try decoder.decode([NoteDocument].self, from: data)
                    notes = try MarkdownVault.migrate(notes: legacyNotes, appDirectory: appDirectory)
                } else {
                    notes = try MarkdownVault.migrate(notes: Self.sampleNotes(), appDirectory: appDirectory)
                }
            } else {
                notes = vaultNotes
            }

            selectedNoteID = notes.first(where: { !$0.isInTrash })?.id
            openSelectedInTabs()
            rebuildIndex()
        } catch {
            notes = Self.sampleNotes()
            folders = []
            selectedNoteID = notes.first?.id
            openSelectedInTabs()
            rebuildIndex()
        }
    }

    func selectedNoteBinding() -> Binding<NoteDocument>? {
        guard let selectedNoteID else { return nil }
        return noteBinding(for: selectedNoteID)
    }

    func selectedNote() -> NoteDocument? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    func secondaryNoteBinding() -> Binding<NoteDocument>? {
        guard let secondarySelectedNoteID else { return nil }
        return noteBinding(for: secondarySelectedNoteID)
    }

    func noteBinding(for noteID: UUID) -> Binding<NoteDocument>? {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return nil }
        return Binding(
            get: { self.notes[index] },
            set: { updated in
                let previous = self.notes[index]
                var next = updated
                if next.title != previous.title {
                    next.aliases = Array(Set(next.aliases + [previous.title])).sorted()
                    next.slug = NoteDocument.makeSlug(from: next.title)
                    self.rewriteLinks(from: previous.title, to: next.title)
                }
                self.notes[index] = next
                self.notes[index].updatedAt = .now
                self.persistSafely()
            }
        )
    }

    var rootNotes: [NoteDocument] {
        notes
            .filter { $0.parentID == nil && $0.folderID == nil && !$0.isInTrash }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var rootFolders: [SidebarFolder] {
        folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func backlinks(for noteID: UUID) -> [NoteDocument] {
        let ids = noteIndex.backlinks[noteID] ?? []
        return ids.compactMap { id in notes.first(where: { $0.id == id }) }
    }

    func outgoingLinks(for noteID: UUID) -> [String] {
        noteIndex.outgoingLinks[noteID] ?? []
    }

    func resolvedOutgoingLinks(for noteID: UUID) -> [NoteDocument] {
        let ids = noteIndex.resolvedOutgoingLinks[noteID] ?? []
        return ids.compactMap { id in notes.first(where: { $0.id == id }) }
    }

    func derivedTags(for noteID: UUID) -> [String] {
        noteIndex.derivedTags[noteID] ?? []
    }

    var visibleNotes: [NoteDocument] {
        let base = notes.filter { !$0.isInTrash }

        let filteredByView: [NoteDocument]
        switch selectedView {
        case .allNotes:
            filteredByView = base.filter { $0.parentID == nil }
        case .favorites:
            filteredByView = base.filter { $0.isFavorite }
        case .assignments:
            filteredByView = base.filter { !$0.properties.course.isEmpty }
        }

        guard !searchText.isEmpty else {
            return filteredByView.sorted { $0.updatedAt > $1.updatedAt }
        }

        let query = searchText.lowercased()
        return filteredByView.filter { note in
            note.title.lowercased().contains(query) ||
            note.properties.course.lowercased().contains(query) ||
            note.properties.subject.lowercased().contains(query) ||
            note.properties.summary.lowercased().contains(query)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func childNotes(of noteID: UUID) -> [NoteDocument] {
        notes
            .filter { $0.parentID == noteID && !$0.isInTrash }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func notes(in folderID: UUID) -> [NoteDocument] {
        notes
            .filter { $0.folderID == folderID && $0.parentID == nil && !$0.isInTrash }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createNote(in folderID: UUID? = nil) {
        let note = NoteDocument(
            title: "Untitled",
            icon: "doc.text",
            folderID: folderID,
            cover: .sand,
            properties: .init(status: .notStarted),
            blocks: []
        )
        notes.insert(note, at: 0)
        activePane = .workspace
        open(noteID: note.id)
        persistSafely()
    }

    func createFolder(named name: String = "New Folder") {
        folders.append(SidebarFolder(name: name))
        persistSafely()
    }

    func createChildNote(parentID: UUID) {
        let note = NoteDocument(
            title: "Untitled",
            icon: "doc.on.doc",
            parentID: parentID,
            cover: .moss,
            properties: .init(status: .notStarted),
            blocks: []
        )
        notes.insert(note, at: 0)
        activePane = .workspace
        open(noteID: note.id)
        persistSafely()
    }

    func duplicateSelectedNote() {
        guard var note = selectedNote() else { return }
        note.id = UUID()
        note.title += " Copy"
        note.createdAt = .now
        note.updatedAt = .now
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        activePane = .workspace
        open(noteID: note.id)
        persistSafely()
    }

    func deleteSelectedNote() {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        notes[index].isInTrash = true
        self.selectedNoteID = visibleNotes.first?.id
        openTabIDs.removeAll { $0 == selectedNoteID }
        if secondarySelectedNoteID == selectedNoteID {
            secondarySelectedNoteID = nil
        }
        persistSafely()
    }

    func toggleFavorite(noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].isFavorite.toggle()
        notes[index].updatedAt = .now
        persistSafely()
    }

    func update(note: NoteDocument) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = .now
        notes[index] = updated
        persistSafely()
    }

    func open(noteID: UUID, recordHistory: Bool = true) {
        if recordHistory, let current = selectedNoteID, current != noteID {
            backHistory.append(current)
            forwardHistory.removeAll()
        }
        if !openTabIDs.contains(noteID) {
            openTabIDs.append(noteID)
        }
        selectedNoteID = noteID
        activePane = .workspace
    }

    var canGoBack: Bool {
        !backHistory.isEmpty
    }

    var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        if let current = selectedNoteID, current != previous {
            forwardHistory.append(current)
        }
        open(noteID: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        if let current = selectedNoteID, current != next {
            backHistory.append(current)
        }
        open(noteID: next, recordHistory: false)
    }

    func closeTab(noteID: UUID) {
        openTabIDs.removeAll { $0 == noteID }
        if selectedNoteID == noteID {
            selectedNoteID = openTabIDs.last
        }
        if secondarySelectedNoteID == noteID {
            secondarySelectedNoteID = nil
        }
    }

    func toggleSplitView() {
        splitViewEnabled.toggle()
        if splitViewEnabled && secondarySelectedNoteID == nil {
            secondarySelectedNoteID = openTabIDs.first(where: { $0 != selectedNoteID })
        }
        if !splitViewEnabled {
            secondarySelectedNoteID = nil
        }
    }

    func importFile(from sourceURL: URL) throws {
        if sourceURL.pathExtension.lowercased() == "zip" {
            try importNotionArchive(from: sourceURL)
            return
        }

        guard let note = selectedNote() else { return }
        let fileExtension = sourceURL.pathExtension.lowercased()
        let kind = ImportedFilePayload.FileKind(fileExtension: fileExtension)
        guard let kind else { return }

        let payload = try copyAttachment(from: sourceURL, kind: kind)
        var updated = note
        updated.blocks.append(.file(payload))
        update(note: updated)
        lastOperationStatus = "Imported \(sourceURL.lastPathComponent)"
    }

    func importedPayload(from sourceURL: URL) throws -> ImportedFilePayload? {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard let kind = ImportedFilePayload.FileKind(fileExtension: fileExtension) else {
            return nil
        }
        return try copyAttachment(from: sourceURL, kind: kind)
    }

    func importNotionArchive(from sourceURL: URL) throws {
        let result = try NotionWorkspaceImporter.importArchive(
            from: sourceURL,
            existingNotes: notes,
            appDirectory: try appDirectory(),
            copyAttachment: { [weak self] url in
                guard let self, let kind = ImportedFilePayload.FileKind(fileExtension: url.pathExtension.lowercased()) else {
                    return nil
                }
                return try self.copyAttachment(from: url, kind: kind)
            }
        )

        notes.insert(contentsOf: result.importedNotes, at: 0)
        selectedNoteID = result.importedNotes.first?.id ?? selectedNoteID
        activePane = .workspace
        lastOperationStatus = "Imported \(result.importedNotes.count) pages from \(sourceURL.lastPathComponent)"
        persistSafely()
    }

    func attachmentURL(for payload: ImportedFilePayload) -> URL? {
        try? attachmentsDirectory().appendingPathComponent(payload.storedFilename)
    }

    func exportSelectedNote(as format: ExportFormat) throws -> URL? {
        guard let note = selectedNote() else { return nil }
        let exportDirectory = try exportsDirectory()
        let safeTitle = note.title.replacingOccurrences(of: "/", with: "-")
        let destination = exportDirectory.appendingPathComponent("\(safeTitle).\(format.fileExtension)")

        switch format {
        case .json:
            let data = try encoder.encode(note)
            try data.write(to: destination, options: .atomic)
        case .html:
            let html = HTMLExporter.render(note: note)
            try html.write(to: destination, atomically: true, encoding: .utf8)
        case .csv:
            let csv = CSVExporter.render(note: note)
            try csv.write(to: destination, atomically: true, encoding: .utf8)
        case .pdfBundle:
            return try exportSelectedNoteAndSubpagesAsPDFBundle(rootNote: note, exportDirectory: exportDirectory)
        }

        lastOperationStatus = "Exported \(note.title) as \(format.title)"
        return destination
    }

    private func persist() throws {
        let appDirectory = try appDirectory()
        notes = try notes.map { note in
            try MarkdownVault.save(note: note, appDirectory: appDirectory)
        }
        let foldersData = try encoder.encode(folders)
        try foldersData.write(to: foldersURL(), options: .atomic)
        let url = try notesIndexURL()
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(notes)
        try data.write(to: url, options: .atomic)
        rebuildIndex()
    }

    private func persistSafely() {
        do {
            try persist()
        } catch {
            assertionFailure("Failed to persist notes: \(error)")
        }
    }

    private func rebuildIndex() {
        var outgoing: [UUID: [String]] = [:]
        var resolved: [UUID: [UUID]] = [:]
        var derived: [UUID: [String]] = [:]
        var lookup: [String: UUID] = [:]
        for note in notes {
            lookup[note.title.lowercased()] = note.id
            lookup[note.slug.lowercased()] = note.id
            for alias in note.aliases {
                lookup[alias.lowercased()] = note.id
            }
        }

        for note in notes {
            let text = flattenedText(for: note)
            let links = Self.extractWikiLinks(from: text)
            let tags = Array(Set(note.properties.tags + Self.extractTags(from: text))).sorted()
            outgoing[note.id] = links
            resolved[note.id] = links.compactMap { lookup[$0.lowercased()] }
            derived[note.id] = tags
        }

        var backlinks: [UUID: [UUID]] = [:]
        for note in notes {
            for targetID in resolved[note.id] ?? [] {
                backlinks[targetID, default: []].append(note.id)
            }
        }

        noteIndex = NoteIndex(outgoingLinks: outgoing, resolvedOutgoingLinks: resolved, backlinks: backlinks, derivedTags: derived)
    }

    private func flattenedText(for note: NoteDocument) -> String {
        note.blocks.map { block in
            switch block.payload {
            case let .text(value): value
            case let .list(items): items.joined(separator: "\n")
            case let .toggle(toggle): "\(toggle.title)\n\(toggle.body)"
            case let .code(code): code.snippet
            case let .table(table): ([table.headers] + table.rows).flatMap { $0 }.joined(separator: " ")
            case let .chart(chart): chart.title + " " + chart.points.map { $0.label }.joined(separator: " ")
            case let .file(file): file.displayName
            case .empty: ""
            }
        }
        .joined(separator: "\n")
    }

    private func openSelectedInTabs() {
        if let selectedNoteID {
            openTabIDs = [selectedNoteID]
        }
    }

    private static func extractWikiLinks(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]"#) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func extractTags(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\w)#([A-Za-z0-9_-]+)"#) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func rewriteLinks(from oldTitle: String, to newTitle: String) {
        for index in notes.indices {
            notes[index].blocks = notes[index].blocks.map { block in
                var block = block
                switch block.payload {
                case let .text(value):
                    block.payload = .text(value.replacingOccurrences(of: "[[\(oldTitle)]]", with: "[[\(newTitle)]]"))
                case let .list(items):
                    block.payload = .list(items.map { $0.replacingOccurrences(of: "[[\(oldTitle)]]", with: "[[\(newTitle)]]") })
                case let .toggle(toggle):
                    block.payload = .toggle(.init(
                        title: toggle.title.replacingOccurrences(of: "[[\(oldTitle)]]", with: "[[\(newTitle)]]"),
                        body: toggle.body.replacingOccurrences(of: "[[\(oldTitle)]]", with: "[[\(newTitle)]]"),
                        isExpanded: toggle.isExpanded
                    ))
                case let .code(code):
                    block.payload = .code(.init(language: code.language, snippet: code.snippet.replacingOccurrences(of: "[[\(oldTitle)]]", with: "[[\(newTitle)]]")))
                default:
                    break
                }
                return block
            }
        }
    }

    private func notesIndexURL() throws -> URL {
        try appDirectory().appendingPathComponent("notes.json")
    }

    private func foldersURL() throws -> URL {
        try appDirectory().appendingPathComponent("folders.json")
    }

    private func attachmentsDirectory() throws -> URL {
        let url = try appDirectory().appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func exportsDirectory() throws -> URL {
        let url = try appDirectory().appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func appDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = base.appendingPathComponent("BeeterNotions", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func exportSelectedNoteAndSubpagesAsPDFBundle(rootNote: NoteDocument, exportDirectory: URL) throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleFolder = tempRoot.appendingPathComponent(safeFilename(rootNote.title), isDirectory: true)
        try FileManager.default.createDirectory(at: bundleFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try writePDFHierarchy(for: rootNote, into: bundleFolder)

        let zipURL = exportDirectory.appendingPathComponent("\(safeFilename(rootNote.title)).zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", zipURL.path, bundleFolder.lastPathComponent]
        process.currentDirectoryURL = tempRoot
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BeeterNotions.Export", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create ZIP archive for PDF export."
            ])
        }

        return zipURL
    }

    private func writePDFHierarchy(for note: NoteDocument, into folderURL: URL) throws {
        let pdfURL = folderURL.appendingPathComponent("\(safeFilename(note.title)).pdf")
        try PDFExporter.render(note: note).write(to: pdfURL, options: .atomic)

        let children = childNotes(of: note.id)
        for child in children {
            let childFolder = folderURL.appendingPathComponent(safeFilename(child.title), isDirectory: true)
            try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
            try writePDFHierarchy(for: child, into: childFolder)
        }
    }

    private func safeFilename(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "[/:\\\\?%*|\"<>]", with: "-", options: .regularExpression)
        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    private func loadFolders(appDirectory: URL) throws -> [SidebarFolder] {
        let url = appDirectory.appendingPathComponent("folders.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([SidebarFolder].self, from: data)
    }

    private func copyAttachment(from sourceURL: URL, kind: ImportedFilePayload.FileKind) throws -> ImportedFilePayload {
        let fileExtension = sourceURL.pathExtension.lowercased()
        let storedFilename = "\(UUID().uuidString).\(fileExtension)"
        let destination = try attachmentsDirectory().appendingPathComponent(storedFilename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        return ImportedFilePayload(
            displayName: sourceURL.lastPathComponent,
            storedFilename: storedFilename,
            kind: kind
        )
    }

    func setCoverImage(noteID: UUID, from sourceURL: URL?) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        do {
            if let sourceURL {
                guard let payload = try importedPayload(from: sourceURL), payload.kind == .image else { return }
                notes[index].coverImageFilename = payload.storedFilename
            } else {
                notes[index].coverImageFilename = nil
            }
            notes[index].updatedAt = .now
            persistSafely()
        } catch {
            lastOperationStatus = "Cover update failed: \(error.localizedDescription)"
        }
    }

    func coverImageURL(for note: NoteDocument) -> URL? {
        guard let filename = note.coverImageFilename else { return nil }
        return try? attachmentsDirectory().appendingPathComponent(filename)
    }
}

extension ImportedFilePayload.FileKind {
    init?(fileExtension: String) {
        switch fileExtension {
        case "html", "htm":
            self = .html
        case "csv":
            self = .csv
        case "pdf":
            self = .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            self = .image
        default:
            return nil
        }
    }
}

enum WorkspaceView: String, CaseIterable, Identifiable {
    case allNotes
    case favorites
    case assignments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allNotes: "All Notes"
        case .favorites: "Favorites"
        case .assignments: "Assignments"
        }
    }

    var icon: String {
        switch self {
        case .allNotes: "doc.text"
        case .favorites: "star"
        case .assignments: "tablecells"
        }
    }
}

enum AppPane: String, Identifiable {
    case workspace
    case settings

    var id: String { rawValue }
}

enum BrowserMode: String, CaseIterable, Identifiable {
    case list
    case table
    case tree
    case graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .table: "Table"
        case .tree: "Tree"
        case .graph: "Graph"
        }
    }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .table: "tablecells"
        case .tree: "list.bullet.indent"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case json
    case html
    case csv
    case pdfBundle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON"
        case .html: "HTML"
        case .csv: "CSV"
        case .pdfBundle: "PDF Bundle"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdfBundle: "zip"
        default: rawValue
        }
    }
}

enum HTMLExporter {
    static func render(note: NoteDocument) -> String {
        let body = note.blocks.map(render(block:)).joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <title>\(escape(note.title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 920px; margin: 40px auto; line-height: 1.6; color: #202124; }
            h1, h2, h3 { margin-top: 1.4em; }
            pre { background: #111827; color: #f9fafb; padding: 16px; border-radius: 12px; overflow-x: auto; }
            table { border-collapse: collapse; width: 100%; margin: 16px 0; }
            th, td { border: 1px solid #d1d5db; padding: 10px; text-align: left; }
            hr { border: 0; border-top: 1px solid #d1d5db; margin: 24px 0; }
            .callout { border: 1px solid #d1d5db; border-radius: 12px; padding: 12px 16px; background: #f8fafc; }
            .file { border: 1px solid #d1d5db; border-radius: 12px; padding: 12px 16px; background: #f8fafc; }
          </style>
        </head>
        <body>
          <h1>\(escape(note.title))</h1>
          \(body)
        </body>
        </html>
        """
    }

    private static func render(block: NoteBlock) -> String {
        switch block.payload {
        case let .text(value):
            switch block.type {
            case .heading:
                return "<h2>\(escape(value))</h2>"
            case .callout:
                return "<div class=\"callout\">\(escape(value))</div>"
            default:
                return "<p>\(escape(value).replacingOccurrences(of: "\n", with: "<br/>"))</p>"
            }
        case let .list(items):
            return "<ul>\(items.map { "<li>\(escape($0))</li>" }.joined())</ul>"
        case let .toggle(toggle):
            return "<details \(toggle.isExpanded ? "open" : "")><summary>\(escape(toggle.title))</summary><p>\(escape(toggle.body))</p></details>"
        case let .code(code):
            return "<pre><code class=\"language-\(escape(code.language))\">\(escape(code.snippet))</code></pre>"
        case let .table(table):
            let header = table.headers.map { "<th>\(escape($0))</th>" }.joined()
            let rows = table.rows.map { row in
                "<tr>\(row.map { "<td>\(escape($0))</td>" }.joined())</tr>"
            }.joined()
            return "<table><thead><tr>\(header)</tr></thead><tbody>\(rows)</tbody></table>"
        case let .chart(chart):
            let items = chart.points.map { "<li>\(escape($0.label)): \($0.value)</li>" }.joined()
            return "<section><h3>\(escape(chart.title))</h3><ul>\(items)</ul></section>"
        case let .file(file):
            return "<div class=\"file\">Imported \(file.kind.rawValue.uppercased()): \(escape(file.displayName))</div>"
        case .empty:
            return "<hr/>"
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum CSVExporter {
    static func render(note: NoteDocument) -> String {
        var lines = ["block_type,primary_text,secondary_text"]

        for block in note.blocks {
            switch block.payload {
            case let .text(value):
                lines.append(csvLine(block.type.rawValue, value, ""))
            case let .list(items):
                lines.append(csvLine(block.type.rawValue, items.joined(separator: " | "), ""))
            case let .toggle(toggle):
                lines.append(csvLine(block.type.rawValue, toggle.title, toggle.body))
            case let .code(code):
                lines.append(csvLine(block.type.rawValue, code.language, code.snippet))
            case let .table(table):
                lines.append(csvLine(block.type.rawValue, table.headers.joined(separator: " | "), table.rows.map { $0.joined(separator: " | ") }.joined(separator: " || ")))
            case let .chart(chart):
                lines.append(csvLine(block.type.rawValue, chart.title, chart.points.map { "\($0.label):\($0.value)" }.joined(separator: " | ")))
            case let .file(file):
                lines.append(csvLine(block.type.rawValue, file.displayName, file.kind.rawValue))
            case .empty:
                lines.append(csvLine(block.type.rawValue, "", ""))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func csvLine(_ first: String, _ second: String, _ third: String) -> String {
        [first, second, third].map(escape).joined(separator: ",")
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum PDFExporter {
    @MainActor
    static func render(note: NoteDocument) throws -> Data {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.textContainerInset = NSSize(width: 36, height: 36)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 612, height: 792)
        textView.maxSize = NSSize(width: 612, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 540, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .white
        textView.textStorage?.setAttributedString(attributedString(for: note))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let requiredHeight = max(792, (textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 792) + 96)
        textView.frame = NSRect(x: 0, y: 0, width: 612, height: requiredHeight)
        return textView.dataWithPDF(inside: textView.bounds)
    }

    private static func attributedString(for note: NoteDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(line("\(note.title)\n", font: .systemFont(ofSize: 26, weight: .bold)))

        let metadata = [note.properties.course, note.properties.subject, note.properties.status.label]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        if !metadata.isEmpty {
            result.append(line("\(metadata)\n", font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        }
        if let dueDate = note.properties.dueDate {
            result.append(line("Due Date: \(dueDate.formatted(date: .abbreviated, time: .omitted))\n", font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        }
        result.append(line("\n", font: .systemFont(ofSize: 12)))

        for block in note.blocks {
            switch block.payload {
            case let .text(value):
                switch block.type {
                case .heading:
                    result.append(line("\(value)\n", font: .systemFont(ofSize: 18, weight: .semibold)))
                case .callout:
                    result.append(line("Callout: \(value)\n", font: .systemFont(ofSize: 12, weight: .medium)))
                default:
                    result.append(line("\(value)\n", font: .systemFont(ofSize: 12)))
                }
                result.append(line("\n", font: .systemFont(ofSize: 6)))
            case let .list(items):
                for item in items {
                    result.append(line("• \(item)\n", font: .systemFont(ofSize: 12)))
                }
                result.append(line("\n", font: .systemFont(ofSize: 6)))
            case let .toggle(toggle):
                result.append(line("\(toggle.title)\n", font: .systemFont(ofSize: 13, weight: .medium)))
                result.append(line("\(toggle.body)\n\n", font: .systemFont(ofSize: 12)))
            case let .code(code):
                result.append(line("Code (\(code.language))\n", font: .monospacedSystemFont(ofSize: 11, weight: .semibold)))
                result.append(line("\(code.snippet)\n\n", font: .monospacedSystemFont(ofSize: 11, weight: .regular)))
            case let .table(table):
                result.append(line(table.headers.joined(separator: " | ") + "\n", font: .systemFont(ofSize: 12, weight: .semibold)))
                for row in table.rows {
                    result.append(line(row.joined(separator: " | ") + "\n", font: .systemFont(ofSize: 12)))
                }
                result.append(line("\n", font: .systemFont(ofSize: 6)))
            case let .chart(chart):
                result.append(line("\(chart.title)\n", font: .systemFont(ofSize: 13, weight: .semibold)))
                for point in chart.points {
                    result.append(line("• \(point.label): \(point.value.formatted())\n", font: .systemFont(ofSize: 12)))
                }
                result.append(line("\n", font: .systemFont(ofSize: 6)))
            case let .file(file):
                result.append(line("Imported \(file.kind.rawValue.uppercased()): \(file.displayName)\n\n", font: .systemFont(ofSize: 12)))
            case .empty:
                result.append(line("────────────────────────\n\n", font: .systemFont(ofSize: 10), color: .tertiaryLabelColor))
            }
        }

        return result
    }

    private static func line(_ value: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: value, attributes: [
            .font: font,
            .foregroundColor: color
        ])
    }
}

extension NotesStore {
    static func sampleNotes() -> [NoteDocument] {
        let formatter = ISO8601DateFormatter()
        let assignmentsRootID = UUID()

        return [
            NoteDocument(
                id: assignmentsRootID,
                title: "College Assignments",
                icon: "books.vertical",
                isFavorite: true,
                cover: .sand,
                properties: .init(
                    course: "Master of Computer Applications",
                    subject: "Semester Work",
                    summary: "Offline assignment tracker with local page editing",
                    status: .inProgress,
                    dueDate: formatter.date(from: "2026-03-27T09:00:00Z"),
                    tags: ["college", "assignments"]
                ),
                blocks: [
                    .heading("College Assignments"),
                    .paragraph("This workspace is designed to feel much closer to Notion: page properties, subpages, a database-style list, and mixed rich-content blocks."),
                    .callout("Tip: add a paragraph starting with '/' to quickly convert it into another block type."),
                    .divider(),
                    .table(
                        headers: ["Course", "Due Date", "Status"],
                        rows: [
                            ["Network Security", "2026-03-27", "In Progress"],
                            ["Ethical Hacking", "2026-03-29", "Done"],
                            ["DBMS", "2026-04-01", "Draft"]
                        ]
                    ),
                    .code(
                        """
                        func submitAssignment(title: String) {
                            print("Submitting \\(title)")
                        }
                        """,
                        language: "swift"
                    ),
                    .chart(
                        title: "Assignment Load",
                        points: [
                            ChartPoint(label: "Security", value: 6),
                            ChartPoint(label: "DBMS", value: 4),
                            ChartPoint(label: "AI", value: 3)
                        ]
                    ),
                    .bulletedList(["Prepare viva notes", "Refactor CSV import", "Package app as a desktop binary"])
                ]
            ),
            NoteDocument(
                title: "Network Security Assignment 2",
                icon: "flag",
                parentID: assignmentsRootID,
                cover: .ocean,
                properties: .init(
                    course: "Master of Computer Applications",
                    subject: "System and Network Security",
                    summary: "Write-up for honeypots and Android malware topics",
                    status: .complete,
                    dueDate: formatter.date(from: "2026-03-17T09:00:00Z"),
                    tags: ["security", "report"]
                ),
                blocks: [
                    .heading("Answers"),
                    .paragraph("Offline page content can include tables, code snippets, and imported PDFs."),
                    .toggle(title: "Explain honeypots", body: "Architecture, data capture, interaction levels, and defensive research value."),
                    .code("print(\"Submit final PDF\")", language: "swift")
                ]
            ),
            NoteDocument(
                title: "Industrial Readiness Program",
                icon: "briefcase",
                isFavorite: true,
                cover: .dusk,
                properties: .init(
                    course: "Placement Prep",
                    subject: "Interview Practice",
                    summary: "Track projects, snippets, and reading notes",
                    status: .inProgress,
                    dueDate: formatter.date(from: "2026-04-01T10:00:00Z"),
                    tags: ["career", "prep"]
                ),
                blocks: [
                    .heading("Industrial Readiness"),
                    .paragraph("Use this page as a second sample to validate the sidebar and database view."),
                    .bulletedList(["System design prep", "DSA revision", "Resume edits"])
                ]
            )
        ]
    }
}
