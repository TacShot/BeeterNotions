import Foundation
import Testing
@testable import BeeterNotions

@Test
func htmlExportArchiveImportsWorkspaceNotes() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/hysarthak/Documents/code/BeeterNotions/notion html export.zip")
    #expect(FileManager.default.fileExists(atPath: archiveURL.path))

    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let attachments = tempRoot.appendingPathComponent("attachments", isDirectory: true)
    try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let result = try NotionWorkspaceImporter.importArchive(
        from: archiveURL,
        existingNotes: [],
        appDirectory: tempRoot
    ) { url in
        guard let kind = ImportedFilePayload.FileKind(fileExtension: url.pathExtension.lowercased()) else { return nil }
        let destination = attachments.appendingPathComponent(UUID().uuidString + "." + url.pathExtension.lowercased())
        try FileManager.default.copyItem(at: url, to: destination)
        return ImportedFilePayload(displayName: url.lastPathComponent, storedFilename: destination.lastPathComponent, kind: kind)
    }

    #expect(!result.importedNotes.isEmpty)
    #expect(result.importedNotes.contains { $0.title.contains("College Assignments") })
    #expect(result.importedNotes.contains { $0.title.contains("Assignment 2") || $0.title.contains("Assignment 02") })
}

@Test
func markdownExportArchiveImportsMetadataAndMarkdownPages() throws {
    let archiveURL = URL(fileURLWithPath: "/Users/hysarthak/Documents/code/BeeterNotions/notion markdown and csv export.zip")
    #expect(FileManager.default.fileExists(atPath: archiveURL.path))

    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let attachments = tempRoot.appendingPathComponent("attachments", isDirectory: true)
    try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let result = try NotionWorkspaceImporter.importArchive(
        from: archiveURL,
        existingNotes: [],
        appDirectory: tempRoot
    ) { url in
        guard let kind = ImportedFilePayload.FileKind(fileExtension: url.pathExtension.lowercased()) else { return nil }
        let destination = attachments.appendingPathComponent(UUID().uuidString + "." + url.pathExtension.lowercased())
        try FileManager.default.copyItem(at: url, to: destination)
        return ImportedFilePayload(displayName: url.lastPathComponent, storedFilename: destination.lastPathComponent, kind: kind)
    }

    #expect(!result.importedNotes.isEmpty)

    let matches = result.importedNotes.filter { $0.title.contains("2025CSET653: Assignment 05 S25MCAG0075") }
    #expect(matches.count == 1)

    if let target = matches.first {
        #expect(target.properties.course == "Master of Computer Applications")
        #expect(target.properties.status == .complete)
        #expect(target.properties.summary == "Computer Network-Layers and Protocols")
        #expect(target.blocks.contains { block in
            if case let .code(code) = block.payload {
                return !code.snippet.isEmpty
            }
            return false
        })
    }
}
