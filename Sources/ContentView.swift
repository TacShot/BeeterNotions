import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        HSplitView {
            AppSidebarView()
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)

            switch store.activePane {
            case .workspace:
                WorkspaceContainerView()
            case .settings:
                SettingsPaneView()
            }
        }
        .navigationTitle("Beeter Notions")
        .background(UITheme.window)
        .safeAreaInset(edge: .bottom) {
            if let status = store.lastOperationStatus {
                HStack {
                    Text(status)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") {
                        store.lastOperationStatus = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial)
            }
        }
    }
}

private struct AppSidebarView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Home")
                .font(.system(size: 28, weight: .semibold))
                .padding(.top, 10)
                .foregroundStyle(.primary)

            searchField

            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                sidebarAction("All Notes", icon: "doc.text", isActive: store.activePane == .workspace && store.selectedView == .allNotes) {
                    store.activePane = .workspace
                    store.selectedView = .allNotes
                }
                sidebarAction("Favorites", icon: "star", isActive: store.activePane == .workspace && store.selectedView == .favorites) {
                    store.activePane = .workspace
                    store.selectedView = .favorites
                }
                sidebarAction("Assignments", icon: "tablecells", isActive: store.activePane == .workspace && store.selectedView == .assignments) {
                    store.activePane = .workspace
                    store.selectedView = .assignments
                }
            }

            Divider()

            Text("Pages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.rootNotes) { note in
                        PageTreeRow(note: note, level: 0)
                    }
                }
            }

            Divider()

            sidebarAction("Settings", icon: "gearshape", isActive: store.activePane == .settings) {
                store.activePane = .settings
                store.selectedNoteID = nil
            }

            Button {
                store.createNote()
            } label: {
                Label("New page", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(UITheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(UITheme.secondaryWindow)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search pages", text: $store.searchText)
                .textFieldStyle(.plain)
        }
        .padding(10)
        .background(UITheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(UITheme.border.opacity(0.35), lineWidth: 1)
        }
    }

    private func sidebarAction(_ title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? UITheme.selection : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct PageTreeRow: View {
    let note: NoteDocument
    let level: Int

    @EnvironmentObject private var store: NotesStore
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                store.open(noteID: note.id)
            } label: {
                HStack(spacing: 8) {
                    if !children.isEmpty {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .frame(width: 12)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Spacer()
                            .frame(width: 12)
                    }

                    Image(systemName: note.icon)
                        .foregroundStyle(.secondary)
                    Text(note.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.leading, CGFloat(level) * 14)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(store.selectedNoteID == note.id && store.activePane == .workspace ? UITheme.selection : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(children) { child in
                    PageTreeRow(note: child, level: level + 1)
                }
            }
        }
    }

    private var children: [NoteDocument] {
        store.childNotes(of: note.id)
    }
}

private struct WorkspaceContainerView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        Group {
            if store.splitViewEnabled, store.selectedNoteBinding() != nil {
                HSplitView {
                    PagesBrowserView()
                        .frame(minWidth: 360, idealWidth: 430, maxWidth: 520)
                    TabbedDetailWorkspace()
                }
            } else {
                ZStack {
                    PagesBrowserView()

                    if store.selectedNoteBinding() != nil {
                        SinglePaneDetailOverlay()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.24), value: store.selectedNoteID)
        .animation(.snappy(duration: 0.24), value: store.splitViewEnabled)
    }
}

private struct SinglePaneDetailOverlay: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(.black.opacity(0.08))
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.selectedNoteID = nil
                    }

                TabbedDetailWorkspace(showsCloseControl: true)
                    .frame(width: min(max(proxy.size.width * 0.68, 640), 1040))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(UITheme.border.opacity(0.4), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 28, x: 0, y: 18)
                    .padding(24)
            }
        }
    }
}

private struct PagesBrowserView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrowserHeader()

            Text(store.selectedView.title)
                .font(.system(size: 34, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 22)

            Text("Browse pages first, then open one when you want to edit.")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Picker("View", selection: $store.selectedView) {
                ForEach(WorkspaceView.allCases) { view in
                    Text(view.title).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Picker("Browser Mode", selection: $store.browserMode) {
                ForEach(BrowserMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Group {
                switch store.browserMode {
                case .list:
                    PagesListBrowser()
                case .table:
                    PagesTableBrowser()
                case .tree:
                    PagesTreeBrowser()
                case .graph:
                    PagesGraphBrowser()
                }
            }
        }
        .background(UITheme.window)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.selectedNoteID = nil
                } label: {
                    Label("Close Page", systemImage: "sidebar.right")
                }
                .disabled(store.selectedNoteID == nil)

                Button {
                    store.createNote()
                } label: {
                    Label("New", systemImage: "plus")
                }

                Button {
                    store.activePane = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }
}

private struct PagesTreeBrowser: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.rootNotes) { note in
                    TreeBrowserRow(note: note, level: 0)
                }
            }
            .padding(18)
        }
        .overlay {
            if store.rootNotes.isEmpty {
                ContentUnavailableView("No pages", systemImage: "list.bullet.indent", description: Text("Create a page or import a workspace from Settings."))
            }
        }
    }
}

private struct TreeBrowserRow: View {
    let note: NoteDocument
    let level: Int

    @EnvironmentObject private var store: NotesStore
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    if !children.isEmpty {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: children.isEmpty ? "circle.fill" : (isExpanded ? "chevron.down" : "chevron.right"))
                        .font(children.isEmpty ? .system(size: 5) : .caption2)
                        .frame(width: 12)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button {
                    store.open(noteID: note.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: note.icon)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if !note.properties.summary.isEmpty {
                                Text(note.properties.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(store.selectedNoteID == note.id ? UITheme.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(level) * 18)

            if isExpanded {
                ForEach(children) { child in
                    TreeBrowserRow(note: child, level: level + 1)
                }
            }
        }
    }

    private var children: [NoteDocument] {
        store.childNotes(of: note.id)
    }
}

private struct PagesGraphBrowser: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        GeometryReader { proxy in
            let notes = store.visibleNotes
            let positions = graphPositions(for: notes, size: proxy.size)

            ZStack {
                UITheme.window

                Canvas { context, size in
                    for note in notes {
                        guard let start = positions[note.id] else { continue }
                        for target in store.resolvedOutgoingLinks(for: note.id) {
                            guard let end = positions[target.id] else { continue }
                            var path = Path()
                            path.move(to: start)
                            path.addLine(to: end)
                            context.stroke(path, with: .color(UITheme.border.opacity(0.8)), lineWidth: 1)
                        }
                    }
                }

                ForEach(notes) { note in
                    if let point = positions[note.id] {
                        Button {
                            store.open(noteID: note.id)
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(store.selectedNoteID == note.id ? UITheme.accent : UITheme.accent.opacity(0.75))
                                    .frame(width: nodeSize(for: note), height: nodeSize(for: note))
                                    .overlay {
                                        Image(systemName: note.icon)
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                    }
                                Text(note.title)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 110)
                            }
                        }
                        .buttonStyle(.plain)
                        .position(point)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Graph View")
                    .font(.headline)
                Text("Nodes are pages. Lines are resolved wikilinks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func graphPositions(for notes: [NoteDocument], size: CGSize) -> [UUID: CGPoint] {
        guard !notes.isEmpty else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.33
        var result: [UUID: CGPoint] = [:]

        for (index, note) in notes.enumerated() {
            let angle = (Double(index) / Double(max(notes.count, 1))) * Double.pi * 2
            let r = radius * (0.7 + 0.3 * CGFloat((index % 3) + 1) / 3)
            result[note.id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
        }
        return result
    }

    private func nodeSize(for note: NoteDocument) -> CGFloat {
        let degree = CGFloat(store.resolvedOutgoingLinks(for: note.id).count + store.backlinks(for: note.id).count)
        return min(34 + degree * 3, 64)
    }
}

private struct PagesListBrowser: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        List(store.visibleNotes, selection: $store.selectedNoteID) { note in
            PageListRow(note: note)
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .overlay {
            if store.visibleNotes.isEmpty {
                ContentUnavailableView("No pages", systemImage: "doc.text", description: Text("Create a page or import a workspace from Settings."))
            }
        }
    }
}

private struct PageListRow: View {
    let note: NoteDocument
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        Button {
            store.open(noteID: note.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(UITheme.surface)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: note.icon)
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if !note.properties.course.isEmpty {
                                Text(note.properties.course)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        StatusBadge(status: note.properties.status)
                    }

                    Text(note.properties.summary.isEmpty ? "No summary" : note.properties.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        if let dueDate = note.properties.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                        if !store.childNotes(of: note.id).isEmpty {
                            Label("\(store.childNotes(of: note.id).count) subpages", systemImage: "arrow.turn.down.right")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(store.selectedNoteID == note.id ? UITheme.selection : UITheme.surface.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct PagesTableBrowser: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        Table(store.visibleNotes, selection: $store.selectedNoteID) {
            TableColumn("Title") { note in
                Button {
                    store.open(noteID: note.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: note.icon)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if !store.childNotes(of: note.id).isEmpty {
                                Text("\(store.childNotes(of: note.id).count) subpages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            TableColumn("Course") { note in
                Text(note.properties.course.isEmpty ? "Untitled" : note.properties.course)
            }
            TableColumn("Date") { note in
                Text(note.properties.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")
            }
            TableColumn("Status") { note in
                StatusBadge(status: note.properties.status)
            }
            TableColumn("Summary") { note in
                Text(note.properties.summary)
                    .lineLimit(1)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .overlay {
            if store.visibleNotes.isEmpty {
                ContentUnavailableView("No pages", systemImage: "doc.text", description: Text("Create a page or import a workspace from Settings."))
            }
        }
    }
}

private struct TabbedDetailWorkspace: View {
    @EnvironmentObject private var store: NotesStore
    var showsCloseControl: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            if store.splitViewEnabled, let primary = store.selectedNoteBinding(), let secondary = store.secondaryNoteBinding() {
                HSplitView {
                    NoteEditorView(note: primary)
                    NoteEditorView(note: secondary)
                }
            } else {
                NoteDetailContainer()
            }
        }
        .background(UITheme.window)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.openTabIDs, id: \.self) { noteID in
                    if let note = store.notes.first(where: { $0.id == noteID }) {
                        tabChip(for: note)
                    }
                }

                Button {
                    store.toggleSplitView()
                } label: {
                    Label(store.splitViewEnabled ? "Single" : "Split", systemImage: store.splitViewEnabled ? "rectangle" : "square.split.2x1")
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)

                if showsCloseControl {
                    Button {
                        store.selectedNoteID = nil
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(UITheme.elevated)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabChip(for note: NoteDocument) -> some View {
        HStack(spacing: 6) {
            Button {
                store.selectedNoteID = note.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: note.icon)
                        .foregroundStyle(.secondary)
                    Text(note.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 170, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(store.selectedNoteID == note.id ? UITheme.selection : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                if store.selectedNoteID != note.id {
                    store.secondarySelectedNoteID = note.id
                    store.splitViewEnabled = true
                }
            } label: {
                Image(systemName: "square.split.2x1")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Open in split view")

            Button {
                store.closeTab(noteID: note.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Close tab")
        }
        .padding(.vertical, 4)
    }
}

private struct BrowserHeader: View {
    var body: some View {
        HStack {
            Label("Beeter Workspace", systemImage: "books.vertical.fill")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(UITheme.surface)
    }
}

private struct SettingsPaneView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var importPickerPresented = false
    @State private var exportPickerPresented = false

    private let importTypes: [UTType] = [.html, .pdf, .commaSeparatedText, UTType(importedAs: "public.zip-archive")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Imports, exports, and workspace maintenance live here.")
                    .foregroundStyle(.secondary)

                settingsCard("Import") {
                    Text("Import a single file or a Notion export ZIP into the local workspace.")
                        .foregroundStyle(.secondary)
                    Button("Choose File") {
                        importPickerPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                settingsCard("Export") {
                    if let selected = store.selectedNote() {
                        Text("Current page: \(selected.title)")
                            .font(.headline)
                        ForEach(ExportFormat.allCases) { format in
                            Button("Export as \(format.title)") {
                                do {
                                    _ = try store.exportSelectedNote(as: format)
                                } catch {
                                    store.lastOperationStatus = "Export failed: \(error.localizedDescription)"
                                }
                            }
                        }
                    } else {
                        Text("Select a page first, then come back here to export it.")
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard("Workspace") {
                    Text("Storage location")
                        .font(.headline)
                    Text("~/Library/Application Support/BeeterNotions")
                        .foregroundStyle(.secondary)
                    Button("Go To Notes") {
                        store.activePane = .workspace
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(UITheme.window)
        .fileImporter(isPresented: $importPickerPresented, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let first = urls.first else { return }
            do {
                let access = first.startAccessingSecurityScopedResource()
                defer {
                    if access { first.stopAccessingSecurityScopedResource() }
                }
                try store.importFile(from: first)
            } catch {
                store.lastOperationStatus = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UITheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(UITheme.border.opacity(0.35), lineWidth: 1)
        }
    }
}

struct StatusBadge: View {
    let status: NoteStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .notStarted: Color.gray.opacity(0.14)
        case .inProgress: Color.orange.opacity(0.14)
        case .complete: Color.green.opacity(0.14)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .notStarted: .gray
        case .inProgress: .orange
        case .complete: .green
        }
    }
}

private struct NoteDetailContainer: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        if let binding = store.selectedNoteBinding() {
            NoteEditorView(note: binding)
        }
    }
}
