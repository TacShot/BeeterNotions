import Charts
import PDFKit
import SwiftUI
import WebKit

struct NoteEditorView: View {
    @Binding var note: NoteDocument
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                editorHero

                VStack(alignment: .leading, spacing: 24) {
                    pageMetaRow
                    propertiesCard
                    blockToolbar
                    subpagesSection
                    linksSection
                    blockEditor
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .background(UITheme.window)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let id = store.selectedNoteID {
                        store.toggleFavorite(noteID: id)
                    }
                } label: {
                    Label("Favorite", systemImage: note.isFavorite ? "star.fill" : "star")
                }
            }
        }
    }

    private var editorHero: some View {
        Rectangle()
            .fill(coverGradient)
            .frame(height: 250)
            .overlay(alignment: .topLeading) {
                heroTopBar
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 18) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(UITheme.elevated.opacity(0.95))
                        .frame(width: 90, height: 90)
                        .overlay {
                            Image(systemName: note.icon)
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.properties.subject.isEmpty ? "Private" : note.properties.subject)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                        Text(note.title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
            }
    }

    private var heroTopBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                BreadcrumbsView(note: note)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    compactActionButton("New subpage", systemImage: "plus") {
                        store.createChildNote(parentID: note.id)
                    }
                    compactActionButton("Settings", systemImage: "gearshape") {
                        store.activePane = .settings
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                BreadcrumbsView(note: note)
                HStack(spacing: 10) {
                    compactActionButton("New subpage", systemImage: "plus") {
                        store.createChildNote(parentID: note.id)
                    }
                    compactActionButton("Settings", systemImage: "gearshape") {
                        store.activePane = .settings
                    }
                }
            }
        }
    }

    private var pageMetaRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Page title", text: $note.title)
                .font(.system(size: 38, weight: .bold))
                .textFieldStyle(.plain)
                .lineLimit(2)

            HStack(spacing: 8) {
                StatusBadge(status: note.properties.status)
                if note.isFavorite {
                    Label("Favorite", systemImage: "star.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.yellow)
                }
                ForEach(note.properties.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(UITheme.subtleSelection)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var propertiesCard: some View {
        DisclosureGroup("Properties") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    propertyLabel("Course")
                    TextField("Course", text: $note.properties.course)
                }
                GridRow {
                    propertyLabel("Subject")
                    TextField("Subject", text: $note.properties.subject)
                }
                GridRow {
                    propertyLabel("Summary")
                    TextField("Summary", text: $note.properties.summary)
                }
                GridRow {
                    propertyLabel("Status")
                    Picker("Status", selection: $note.properties.status) {
                        ForEach(NoteStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    propertyLabel("Due Date")
                    DatePicker(
                        "Due Date",
                        selection: Binding(
                            get: { note.properties.dueDate ?? .now },
                            set: { note.properties.dueDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
                GridRow {
                    propertyLabel("Cover")
                    Picker("Cover", selection: $note.cover) {
                        ForEach(CoverStyle.allCases) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
                GridRow {
                    propertyLabel("Tags")
                    TextField("Comma-separated tags", text: tagsBinding)
                }
            }
        }
        .padding(20)
        .background(UITheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(UITheme.border.opacity(0.35), lineWidth: 1)
        }
    }

    private var blockToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                addBlockButton("Text", "text.alignleft") { note.blocks.append(.paragraph("")) }
                addBlockButton("Heading", "textformat.size.larger") { note.blocks.append(.heading("New heading")) }
                addBlockButton("Bullet List", "list.bullet") { note.blocks.append(.bulletedList(["List item"])) }
                addBlockButton("Callout", "exclamationmark.bubble") { note.blocks.append(.callout("Add a concise highlight or important note.")) }
                addBlockButton("Toggle", "chevron.right") { note.blocks.append(.toggle(title: "Toggle title", body: "Hidden content")) }
                addBlockButton("Divider", "minus") { note.blocks.append(.divider()) }
                addBlockButton("Code", "curlybraces") { note.blocks.append(.code("// Paste code here", language: "swift")) }
                addBlockButton("Table", "tablecells") { note.blocks.append(.table(headers: ["Column 1", "Column 2"], rows: [["", ""], ["", ""]])) }
                addBlockButton("Chart", "chart.bar.xaxis") { note.blocks.append(.chart(title: "Untitled Chart", points: [ChartPoint(label: "A", value: 3), ChartPoint(label: "B", value: 7)])) }
            }
        }
    }

    private var subpagesSection: some View {
        let subpages = store.childNotes(of: note.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Subpages")
                    .font(.headline)
                Spacer()
                Button("Add") {
                    store.createChildNote(parentID: note.id)
                }
                .buttonStyle(.borderless)
            }

            if subpages.isEmpty {
                Text("No nested pages yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subpages) { child in
                    Button {
                        store.selectedNoteID = child.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: child.icon)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(child.title)
                                    .fontWeight(.medium)
                                Text(child.properties.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(UITheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var linksSection: some View {
        let outgoing = store.outgoingLinks(for: note.id)
        let resolvedOutgoing = store.resolvedOutgoingLinks(for: note.id).reduce(into: [String: NoteDocument]()) { result, linkedNote in
            result[linkedNote.title.lowercased()] = linkedNote
            result[linkedNote.slug.lowercased()] = linkedNote
            for alias in linkedNote.aliases {
                result[alias.lowercased()] = linkedNote
            }
        }
        let backlinks = store.backlinks(for: note.id)
        let tags = Array(Set(note.properties.tags + store.derivedTags(for: note.id))).sorted()

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Identity")
                    .font(.headline)
                Text("Slug: \(note.slug)")
                    .foregroundStyle(.secondary)
                if !note.aliases.isEmpty {
                    Text("Aliases: \(note.aliases.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
            }

            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.headline)
                    FlowTagList(tags: tags)
                }
            }

            if !outgoing.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Links")
                        .font(.headline)
                    ForEach(outgoing, id: \.self) { link in
                        if let target = resolvedOutgoing[link.lowercased()] {
                            Button {
                                store.open(noteID: target.id)
                            } label: {
                                Text("[[\(link)]]")
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("[[\(link)]]")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !backlinks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backlinks")
                        .font(.headline)
                    ForEach(backlinks) { linkedNote in
                        Button {
                            store.open(noteID: linkedNote.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: linkedNote.icon)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(linkedNote.title)
                                        .foregroundStyle(.primary)
                                    Text(linkedNote.properties.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(UITheme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var blockEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(note.blocks.enumerated()), id: \.element.id) { index, _ in
                BlockEditorRow(
                    block: $note.blocks[index],
                    onDelete: { note.blocks.remove(at: index) },
                    onMoveUp: { moveBlock(from: index, direction: -1) },
                    onMoveDown: { moveBlock(from: index, direction: 1) }
                )
            }

            Button {
                note.blocks.append(.paragraph(""))
            } label: {
                Label("Type '/' or add another block", systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
    }

    private func propertyLabel(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
            .frame(width: 96, alignment: .leading)
    }

    private func addBlockButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(UITheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(UITheme.border.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func compactActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(UITheme.elevated.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var coverGradient: LinearGradient {
        switch note.cover {
        case .sand:
            LinearGradient(colors: [Color(red: 0.84, green: 0.73, blue: 0.62), Color(red: 0.95, green: 0.83, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .moss:
            LinearGradient(colors: [Color(red: 0.35, green: 0.46, blue: 0.34), Color(red: 0.74, green: 0.82, blue: 0.67)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dusk:
            LinearGradient(colors: [Color(red: 0.36, green: 0.33, blue: 0.50), Color(red: 0.83, green: 0.61, blue: 0.54)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:
            LinearGradient(colors: [Color(red: 0.14, green: 0.36, blue: 0.53), Color(red: 0.43, green: 0.74, blue: 0.87)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { note.properties.tags.joined(separator: ", ") },
            set: { note.properties.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        )
    }

    private func moveBlock(from index: Int, direction: Int) {
        let target = index + direction
        guard note.blocks.indices.contains(target) else { return }
        let block = note.blocks.remove(at: index)
        note.blocks.insert(block, at: target)
    }
}

private struct FlowTagList: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(UITheme.subtleSelection)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

private struct BreadcrumbsView: View {
    let note: NoteDocument
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        HStack(spacing: 8) {
            Text("Home")
                .lineLimit(1)
            if let parentID = note.parentID, let parent = store.notes.first(where: { $0.id == parentID }) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(parent.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(note.title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockEditorRow: View {
    @Binding var block: NoteBlock
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var showSlashMenu = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Menu {
                    Button("Text") { block = .paragraph(textValue(from: block) ?? "") }
                    Button("Heading") { block = .heading(textValue(from: block) ?? "Heading") }
                    Button("Bullet List") { block = .bulletedList(listValue(from: block) ?? ["List item"]) }
                    Button("Callout") { block = .callout(textValue(from: block) ?? "Important note") }
                    Button("Toggle") { block = .toggle(title: "Toggle title", body: textValue(from: block) ?? "") }
                    Button("Divider") { block = .divider() }
                    Button("Code") { block = .code(codeValue(from: block)?.snippet ?? "", language: codeValue(from: block)?.language ?? "swift") }
                    Button("Table") { block = .table(headers: ["Column 1", "Column 2"], rows: [["", ""]]) }
                    Button("Chart") { block = .chart(title: "Untitled Chart", points: [ChartPoint(label: "A", value: 1)]) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)

                Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                switch block.payload {
                case let .text(text):
                    textEditor(text: text)
                case let .list(items):
                    listEditor(items: items)
                case let .toggle(toggle):
                    toggleEditor(toggle: toggle)
                case let .code(code):
                    codeEditor(code: code)
                case let .table(table):
                    tableEditor(table: table)
                case let .chart(chart):
                    chartEditor(chart: chart)
                case let .file(file):
                    ImportedFileBlockView(file: file)
                case .empty:
                    Divider().padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }

    private func textEditor(text: String) -> some View {
        let binding = Binding(
            get: { text },
            set: { newValue in
                if newValue.hasPrefix("/") && newValue.count > 1 {
                    applySlashCommand(newValue)
                } else {
                    block.payload = .text(newValue)
                }
            }
        )

        return Group {
            if block.type == .heading {
                TextField("Heading", text: binding, axis: .vertical)
                    .font(.system(size: 30, weight: .semibold))
                    .textFieldStyle(.plain)
            } else if block.type == .callout {
                TextField("Callout", text: binding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(UITheme.subtleSelection)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                TextField("Type '/' for commands", text: binding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func listEditor(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, value in
                HStack(alignment: .top, spacing: 10) {
                    Text("•")
                    TextField(
                        "List item",
                        text: Binding(
                            get: { value },
                            set: { newValue in
                                var updated = items
                                updated[index] = newValue
                                block.payload = .list(updated)
                            }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                }
            }

            Button("Add item") {
                var updated = items
                updated.append("")
                block.payload = .list(updated)
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleEditor(toggle: TogglePayload) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { toggle.isExpanded },
                set: { block.payload = .toggle(.init(title: toggle.title, body: toggle.body, isExpanded: $0)) }
            )
        ) {
            TextField(
                "Body",
                text: Binding(
                    get: { toggle.body },
                    set: { block.payload = .toggle(.init(title: toggle.title, body: $0, isExpanded: toggle.isExpanded)) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .padding(.leading, 6)
        } label: {
            TextField(
                "Toggle title",
                text: Binding(
                    get: { toggle.title },
                    set: { block.payload = .toggle(.init(title: $0, body: toggle.body, isExpanded: toggle.isExpanded)) }
                )
            )
            .textFieldStyle(.plain)
        }
    }

    private func codeEditor(code: CodePayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Language",
                text: Binding(
                    get: { code.language },
                    set: { block.payload = .code(.init(language: $0, snippet: code.snippet)) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)

            TextEditor(
                text: Binding(
                    get: { code.snippet },
                    set: { block.payload = .code(.init(language: code.language, snippet: $0)) }
                )
            )
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 180)
            .padding(10)
            .background(Color(red: 0.09, green: 0.1, blue: 0.14))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func tableEditor(table: TablePayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(table.headers.count, 1)), spacing: 8) {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { columnIndex, header in
                    TextField(
                        "Header",
                        text: Binding(
                            get: { header },
                            set: { newValue in
                                var updated = table
                                updated.headers[columnIndex] = newValue
                                block.payload = .table(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, value in
                        TextField(
                            "Value",
                            text: Binding(
                                get: { value },
                                set: { newValue in
                                    var updated = table
                                    updated.rows[rowIndex][columnIndex] = newValue
                                    block.payload = .table(updated)
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Button("Add Row") {
                    var updated = table
                    updated.rows.append(Array(repeating: "", count: max(updated.headers.count, 1)))
                    block.payload = .table(updated)
                }
                Button("Add Column") {
                    var updated = table
                    updated.headers.append("Column \(updated.headers.count + 1)")
                    updated.rows = updated.rows.map { row in
                        var row = row
                        row.append("")
                        return row
                    }
                    block.payload = .table(updated)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func chartEditor(chart: ChartPayload) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(
                "Chart title",
                text: Binding(
                    get: { chart.title },
                    set: { block.payload = .chart(.init(title: $0, points: chart.points)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            Chart(chart.points) { point in
                BarMark(
                    x: .value("Label", point.label),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(.blue.gradient)
            }
            .frame(height: 220)

            ForEach(Array(chart.points.enumerated()), id: \.element.id) { index, point in
                HStack {
                    TextField(
                        "Label",
                        text: Binding(
                            get: { point.label },
                            set: { newValue in
                                var updated = chart
                                updated.points[index].label = newValue
                                block.payload = .chart(updated)
                            }
                        )
                    )
                    TextField(
                        "Value",
                        value: Binding(
                            get: { point.value },
                            set: { newValue in
                                var updated = chart
                                updated.points[index].value = newValue
                                block.payload = .chart(updated)
                            }
                        ),
                        format: .number
                    )
                    .frame(width: 120)
                }
            }

            Button("Add Data Point") {
                var updated = chart
                updated.points.append(.init(label: "New", value: 0))
                block.payload = .chart(updated)
            }
            .buttonStyle(.borderless)
        }
    }

    private func applySlashCommand(_ rawValue: String) {
        let command = rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch command {
        case "/h1", "/heading":
            block = .heading("Heading")
        case "/bullet", "/list":
            block = .bulletedList(["List item"])
        case "/callout":
            block = .callout("Important note")
        case "/toggle":
            block = .toggle(title: "Toggle title", body: "")
        case "/divider":
            block = .divider()
        case "/code":
            block = .code("", language: "swift")
        case "/table":
            block = .table(headers: ["Column 1", "Column 2"], rows: [["", ""]])
        case "/chart":
            block = .chart(title: "Untitled Chart", points: [.init(label: "A", value: 1)])
        default:
            block.payload = .text(rawValue)
        }
    }

    private func textValue(from block: NoteBlock) -> String? {
        if case let .text(value) = block.payload { return value }
        return nil
    }

    private func listValue(from block: NoteBlock) -> [String]? {
        if case let .list(items) = block.payload { return items }
        return nil
    }

    private func codeValue(from block: NoteBlock) -> CodePayload? {
        if case let .code(code) = block.payload { return code }
        return nil
    }
}

private struct ImportedFileBlockView: View {
    let file: ImportedFilePayload
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.displayName)
                        .font(.headline)
                    Text("Imported \(file.kind.rawValue.uppercased()) file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let url = store.attachmentURL(for: file) {
                switch file.kind {
                case .html:
                    HTMLPreview(url: url)
                        .frame(minHeight: 380)
                case .pdf:
                    PDFPreview(url: url)
                        .frame(minHeight: 480)
                case .csv:
                    CSVPreview(url: url)
                case .image:
                    ImagePreview(url: url)
                }
            } else {
                Text("File unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(UITheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(UITheme.border.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct ImagePreview: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text("Image preview unavailable")
                .foregroundStyle(.secondary)
        }
    }
}

private struct HTMLPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}

private struct CSVPreview: View {
    let url: URL

    private var rows: [[String]] {
        guard let data = try? String(contentsOf: url) else { return [] }
        return data
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: ",", omittingEmptySubsequences: false).map {
                    String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
    }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 1) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            Text(value)
                                .frame(width: 160, alignment: .leading)
                                .padding(8)
                                .background(UITheme.surface)
                        }
                    }
                }
            }
        }
    }
}
