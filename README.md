# BeeterNotions

Offline macOS SwiftUI app for local-first notes with a more Notion-like page database and block editor.

## Features

- Local JSON-backed note storage in `~/Library/Application Support/BeeterNotions`
- Page database view with title, course, date, status, and summary columns
- Sidebar with workspace sections, search, and favorites
- Page editor with cover styles, properties, breadcrumbs, subpages, and favorites
- Block editor with headings, paragraphs, dividers, bullet lists, callouts, toggles, code blocks, tables, and charts
- Slash commands such as `/heading`, `/list`, `/callout`, `/toggle`, `/code`, `/table`, and `/chart`
- Import support for single `.html`, `.csv`, `.pdf`, and Notion export `.zip` files
- Inline offline viewers for imported HTML, CSV, and PDF files
- Workspace ZIP importer that extracts Notion export archives, recreates page hierarchy, and maps database rows into page properties where possible
- Export support for note snapshots as `.html`, `.csv`, and `.json`

## Run

```bash
env HOME=/Users/hysarthak/Documents/code/Codex \
CLANG_MODULE_CACHE_PATH=/Users/hysarthak/Documents/code/Codex/.build/ModuleCache \
SWIFTPM_MODULECACHE_OVERRIDE=/Users/hysarthak/Documents/code/Codex/.build/ModuleCache \
swift run
```

## Notes

- Imported files are copied into `~/Library/Application Support/BeeterNotions/Attachments`
- Exported files are written to `~/Library/Application Support/BeeterNotions/Exports`
- ZIP workspace import uses local extraction and heuristic parsing for Notion HTML/CSV exports; compatibility is good for common exports but not yet complete for every Notion block/database edge case
- This is an offline local-first Notion-inspired clone in active development, not the official Notion client
