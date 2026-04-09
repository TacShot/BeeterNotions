import Foundation

struct NoteDocument: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var slug: String
    var aliases: [String]
    var icon: String
    var vaultRelativePath: String?
    var parentID: UUID?
    var isFavorite: Bool
    var isInTrash: Bool
    var cover: CoverStyle
    var properties: NoteProperties
    var createdAt: Date
    var updatedAt: Date
    var blocks: [NoteBlock]

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        slug: String? = nil,
        aliases: [String] = [],
        icon: String = "doc.text",
        vaultRelativePath: String? = nil,
        parentID: UUID? = nil,
        isFavorite: Bool = false,
        isInTrash: Bool = false,
        cover: CoverStyle = .sand,
        properties: NoteProperties = .init(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        blocks: [NoteBlock] = [.paragraph("Start writing here...")]
    ) {
        self.id = id
        self.title = title
        self.slug = slug ?? NoteDocument.makeSlug(from: title)
        self.aliases = aliases
        self.icon = icon
        self.vaultRelativePath = vaultRelativePath
        self.parentID = parentID
        self.isFavorite = isFavorite
        self.isInTrash = isInTrash
        self.cover = cover
        self.properties = properties
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.blocks = blocks
    }

    static func makeSlug(from title: String) -> String {
        let lowered = title.lowercased()
        let alnum = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let trimmed = alnum.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "untitled" : trimmed
    }
}

struct NoteProperties: Codable, Hashable {
    var course: String
    var subject: String
    var summary: String
    var status: NoteStatus
    var dueDate: Date?
    var tags: [String]

    init(
        course: String = "",
        subject: String = "",
        summary: String = "",
        status: NoteStatus = .notStarted,
        dueDate: Date? = nil,
        tags: [String] = []
    ) {
        self.course = course
        self.subject = subject
        self.summary = summary
        self.status = status
        self.dueDate = dueDate
        self.tags = tags
    }
}

enum NoteStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case notStarted
    case inProgress
    case complete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .complete: "Complete"
        }
    }

    var tintName: String {
        switch self {
        case .notStarted: "gray"
        case .inProgress: "orange"
        case .complete: "green"
        }
    }
}

enum CoverStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case sand
    case moss
    case dusk
    case ocean

    var id: String { rawValue }
}

struct NoteBlock: Codable, Identifiable, Hashable {
    enum BlockType: String, Codable, CaseIterable, Identifiable {
        case heading
        case paragraph
        case divider
        case bulletedList
        case callout
        case toggle
        case code
        case table
        case chart
        case file

        var id: String { rawValue }

        var label: String {
            switch self {
            case .heading: "Heading"
            case .paragraph: "Paragraph"
            case .divider: "Divider"
            case .bulletedList: "Bulleted List"
            case .callout: "Callout"
            case .toggle: "Toggle"
            case .code: "Code"
            case .table: "Table"
            case .chart: "Chart"
            case .file: "Imported File"
            }
        }
    }

    var id: UUID
    var type: BlockType
    var payload: BlockPayload

    init(id: UUID = UUID(), type: BlockType, payload: BlockPayload) {
        self.id = id
        self.type = type
        self.payload = payload
    }

    static func heading(_ text: String) -> NoteBlock {
        NoteBlock(type: .heading, payload: .text(text))
    }

    static func paragraph(_ text: String) -> NoteBlock {
        NoteBlock(type: .paragraph, payload: .text(text))
    }

    static func divider() -> NoteBlock {
        NoteBlock(type: .divider, payload: .empty)
    }

    static func bulletedList(_ items: [String]) -> NoteBlock {
        NoteBlock(type: .bulletedList, payload: .list(items))
    }

    static func callout(_ text: String) -> NoteBlock {
        NoteBlock(type: .callout, payload: .text(text))
    }

    static func toggle(title: String, body: String) -> NoteBlock {
        NoteBlock(type: .toggle, payload: .toggle(TogglePayload(title: title, body: body, isExpanded: true)))
    }

    static func code(_ snippet: String, language: String = "swift") -> NoteBlock {
        NoteBlock(type: .code, payload: .code(CodePayload(language: language, snippet: snippet)))
    }

    static func table(headers: [String], rows: [[String]]) -> NoteBlock {
        NoteBlock(type: .table, payload: .table(TablePayload(headers: headers, rows: rows)))
    }

    static func chart(title: String, points: [ChartPoint]) -> NoteBlock {
        NoteBlock(type: .chart, payload: .chart(ChartPayload(title: title, points: points)))
    }

    static func file(_ file: ImportedFilePayload) -> NoteBlock {
        NoteBlock(type: .file, payload: .file(file))
    }
}

enum BlockPayload: Codable, Hashable {
    case text(String)
    case list([String])
    case toggle(TogglePayload)
    case code(CodePayload)
    case table(TablePayload)
    case chart(ChartPayload)
    case file(ImportedFilePayload)
    case empty

    enum CodingKeys: String, CodingKey {
        case kind
        case text
        case list
        case toggle
        case code
        case table
        case chart
        case file
    }

    enum PayloadKind: String, Codable {
        case text
        case list
        case toggle
        case code
        case table
        case chart
        case file
        case empty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(PayloadKind.self, forKey: .kind)

        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .list:
            self = .list(try container.decode([String].self, forKey: .list))
        case .toggle:
            self = .toggle(try container.decode(TogglePayload.self, forKey: .toggle))
        case .code:
            self = .code(try container.decode(CodePayload.self, forKey: .code))
        case .table:
            self = .table(try container.decode(TablePayload.self, forKey: .table))
        case .chart:
            self = .chart(try container.decode(ChartPayload.self, forKey: .chart))
        case .file:
            self = .file(try container.decode(ImportedFilePayload.self, forKey: .file))
        case .empty:
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(value):
            try container.encode(PayloadKind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case let .list(value):
            try container.encode(PayloadKind.list, forKey: .kind)
            try container.encode(value, forKey: .list)
        case let .toggle(value):
            try container.encode(PayloadKind.toggle, forKey: .kind)
            try container.encode(value, forKey: .toggle)
        case let .code(value):
            try container.encode(PayloadKind.code, forKey: .kind)
            try container.encode(value, forKey: .code)
        case let .table(value):
            try container.encode(PayloadKind.table, forKey: .kind)
            try container.encode(value, forKey: .table)
        case let .chart(value):
            try container.encode(PayloadKind.chart, forKey: .kind)
            try container.encode(value, forKey: .chart)
        case let .file(value):
            try container.encode(PayloadKind.file, forKey: .kind)
            try container.encode(value, forKey: .file)
        case .empty:
            try container.encode(PayloadKind.empty, forKey: .kind)
        }
    }
}

struct CodePayload: Codable, Hashable {
    var language: String
    var snippet: String
}

struct TogglePayload: Codable, Hashable {
    var title: String
    var body: String
    var isExpanded: Bool
}

struct TablePayload: Codable, Hashable {
    var headers: [String]
    var rows: [[String]]
}

struct ChartPayload: Codable, Hashable {
    var title: String
    var points: [ChartPoint]
}

struct ChartPoint: Codable, Hashable, Identifiable {
    var id: UUID
    var label: String
    var value: Double

    init(id: UUID = UUID(), label: String, value: Double) {
        self.id = id
        self.label = label
        self.value = value
    }
}

struct ImportedFilePayload: Codable, Hashable {
    enum FileKind: String, Codable, CaseIterable {
        case html
        case csv
        case pdf
        case image
    }

    var id: UUID
    var displayName: String
    var storedFilename: String
    var kind: FileKind
    var importedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        storedFilename: String,
        kind: FileKind,
        importedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.storedFilename = storedFilename
        self.kind = kind
        self.importedAt = importedAt
    }
}

struct NoteIndex {
    var outgoingLinks: [UUID: [String]]
    var resolvedOutgoingLinks: [UUID: [UUID]]
    var backlinks: [UUID: [UUID]]
    var derivedTags: [UUID: [String]]

    static let empty = NoteIndex(outgoingLinks: [:], resolvedOutgoingLinks: [:], backlinks: [:], derivedTags: [:])
}
