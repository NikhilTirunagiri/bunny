import Foundation

/// The Settings window's pages and rows. One list feeds the sidebar, every row's title and icon, and
/// the search (which matches row titles and keywords and jumps to the row).
enum SettingsCatalog {
    enum Page: String, CaseIterable, Identifiable, Sendable {
        case general, appearance, notes, agents, data, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .notes: return "Notes"
            case .agents: return "Agents"
            case .data: return "Data"
            case .about: return "About"
            }
        }

        /// SF Symbol name.
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .notes: return "checklist"
            case .agents: return "sparkles"
            case .data: return "externaldrive"
            case .about: return "info.circle"
            }
        }
    }

    enum RowID: String, CaseIterable, Sendable {
        // General
        case launchAtLogin, globalShortcut, menuBarNote, welcomeGuide, quit
        // Appearance
        case theme, backgroundImage
        // Notes
        case completedRetention, trashRetention, confirmDelete
        // Agents
        case claudeCode, codex, defaultAgent, openClaudeSessionsIn, openCodexSessionsIn, defaultFolder, advanced
        // Agents, under Advanced
        case claudePath, codexPath, claudeModel, claudeEffort, codexModel, codexEffort, permissions
        case toolsServer, toolsToken, toolsClaude, toolsCodex
        // Data
        case storage, export, emptyTrash, resetSettings, eraseAll
        // About
        case repository, checkForUpdates
    }

    struct Row: Equatable, Identifiable, Sendable {
        let id: RowID
        let page: Page
        let title: String
        /// SF Symbol name.
        let icon: String
        /// Extra words the search matches, besides the title.
        var keywords: [String] = []
        /// Sits inside the Agents page's folded Advanced part.
        var advanced = false
    }

    static let rows: [Row] = [
        Row(id: .launchAtLogin, page: .general, title: "Launch at login", icon: "power", keywords: ["start", "startup", "open", "boot"]),
        Row(id: .globalShortcut, page: .general, title: "Global shortcut", icon: "keyboard", keywords: ["hotkey", "keyboard", "key"]),
        Row(id: .menuBarNote, page: .general, title: "Show the pinned note in the menu bar", icon: "menubar.rectangle", keywords: ["pin", "status", "title", "timer"]),
        Row(id: .welcomeGuide, page: .general, title: "Welcome guide", icon: "hand.wave", keywords: ["onboarding", "intro", "tour", "help"]),
        Row(id: .quit, page: .general, title: "Quit Bunny", icon: "xmark.circle", keywords: ["exit", "close"]),

        Row(id: .theme, page: .appearance, title: "Theme", icon: "circle.lefthalf.filled", keywords: ["dark", "light", "system", "mode", "color", "colour"]),
        Row(id: .backgroundImage, page: .appearance, title: "Background image", icon: "photo", keywords: ["picture", "wallpaper", "blur"]),

        Row(id: .completedRetention, page: .notes, title: "Move completed notes to Trash", icon: "checkmark.circle", keywords: ["done", "finished", "retention", "24 hours", "7 days"]),
        Row(id: .trashRetention, page: .notes, title: "Empty Trash", icon: "trash", keywords: ["delete", "purge", "retention", "days", "automatically"]),
        Row(id: .confirmDelete, page: .notes, title: "Ask before deleting forever", icon: "questionmark.circle", keywords: ["confirm", "confirmation", "warning"]),

        Row(id: .claudeCode, page: .agents, title: "Claude Code", icon: "terminal", keywords: ["claude", "cli", "installed", "found", "anthropic", "enable", "turn on", "off", "switch"]),
        Row(id: .codex, page: .agents, title: "Codex", icon: "terminal", keywords: ["openai", "cli", "installed", "found", "enable", "turn on", "off", "switch"]),
        Row(id: .defaultAgent, page: .agents, title: "Default agent", icon: "sparkles", keywords: ["hand off", "handoff", "claude", "codex"]),
        Row(id: .openClaudeSessionsIn, page: .agents, title: "Open Claude Code sessions in", icon: "macwindow", keywords: ["terminal", "iterm", "ghostty", "warp", "kitty", "wezterm", "alacritty", "vs code", "vscode", "cursor", "other app", "resume", "claude app", "desktop"]),
        Row(id: .openCodexSessionsIn, page: .agents, title: "Open Codex sessions in", icon: "macwindow", keywords: ["terminal", "iterm", "ghostty", "warp", "kitty", "wezterm", "alacritty", "vs code", "vscode", "cursor", "other app", "resume", "codex app", "desktop", "openai"]),
        Row(id: .defaultFolder, page: .agents, title: "Default folder", icon: "folder", keywords: ["workspace", "directory", "project", "path", "bunny folder"]),
        Row(id: .advanced, page: .agents, title: "Advanced", icon: "slider.horizontal.3", keywords: ["more", "options"]),
        Row(id: .claudePath, page: .agents, title: "Claude Code path", icon: "point.topleft.down.to.point.bottomright.curvepath", keywords: ["cli", "detect", "binary", "location"], advanced: true),
        Row(id: .codexPath, page: .agents, title: "Codex path", icon: "point.topleft.down.to.point.bottomright.curvepath", keywords: ["cli", "detect", "binary", "location"], advanced: true),
        Row(id: .claudeModel, page: .agents, title: "Claude Code model", icon: "cpu", keywords: ["opus", "sonnet", "haiku", "fable", "custom"], advanced: true),
        Row(id: .claudeEffort, page: .agents, title: "Claude Code effort", icon: "gauge.with.dots.needle.50percent", keywords: ["reasoning", "thinking", "model"], advanced: true),
        Row(id: .codexModel, page: .agents, title: "Codex model", icon: "cpu", keywords: ["gpt", "custom"], advanced: true),
        Row(id: .codexEffort, page: .agents, title: "Codex effort", icon: "gauge.with.dots.needle.50percent", keywords: ["reasoning", "thinking", "model"], advanced: true),
        Row(id: .permissions, page: .agents, title: "Permissions", icon: "hand.raised", keywords: ["autonomy", "autonomous", "ask", "commands", "approve", "approval"], advanced: true),
        Row(id: .toolsServer, page: .agents, title: "Bunny tools server", icon: "server.rack", keywords: ["mcp", "port", "url", "copy", "enable", "turn on", "off", "switch", "notes"], advanced: true),
        Row(id: .toolsToken, page: .agents, title: "Access token", icon: "key", keywords: ["mcp", "regenerate", "bearer", "bunny tools", "security"], advanced: true),
        Row(id: .toolsClaude, page: .agents, title: "Bunny tools in all Claude Code sessions", icon: "wrench.and.screwdriver", keywords: ["mcp", "install", "uninstall", "global"], advanced: true),
        Row(id: .toolsCodex, page: .agents, title: "Bunny tools in all Codex sessions", icon: "wrench.and.screwdriver", keywords: ["mcp", "install", "uninstall", "global"], advanced: true),

        Row(id: .storage, page: .data, title: "Stored on this Mac", icon: "internaldrive", keywords: ["size", "disk", "space", "database", "attachments", "finder", "files"]),
        Row(id: .export, page: .data, title: "Export all notes", icon: "square.and.arrow.up", keywords: ["markdown", "backup", "save", "files"]),
        Row(id: .emptyTrash, page: .data, title: "Empty Trash", icon: "trash", keywords: ["delete", "forever", "now"]),
        Row(id: .resetSettings, page: .data, title: "Reset settings", icon: "arrow.counterclockwise", keywords: ["reset", "defaults", "restore", "settings", "preferences"]),
        Row(id: .eraseAll, page: .data, title: "Erase all data", icon: "exclamationmark.triangle", keywords: ["delete", "reset", "remove", "everything", "wipe"]),

        Row(id: .repository, page: .about, title: "Source code", icon: "chevron.left.forwardslash.chevron.right", keywords: ["github", "repository", "repo", "authors", "website", "link"]),
        Row(id: .checkForUpdates, page: .about, title: "Check for updates", icon: "arrow.down.circle", keywords: ["version", "release", "download", "new", "latest"]),
    ]

    static func row(_ id: RowID) -> Row {
        rows.first { $0.id == id }!
    }

    static func rows(on page: Page) -> [Row] {
        rows.filter { $0.page == page }
    }

    // MARK: - Search

    struct Result: Equatable {
        let page: Page
        let rows: [Row]
    }

    /// Pages with a row whose title or keywords contain every word of `query` (ignoring case and
    /// accents), in page order, each with its matching rows. A page whose own title matches is listed
    /// too. An empty query finds nothing.
    static func search(_ query: String, in rows: [Row] = rows) -> [Result] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ texts: [String]) -> Bool {
            let haystack = fold(texts.joined(separator: " "))
            return words.allSatisfy(haystack.contains)
        }
        return Page.allCases.compactMap { page in
            let found = rows.filter { $0.page == page && matches([$0.title] + $0.keywords) }
            guard !found.isEmpty || matches([page.title]) else { return nil }
            return Result(page: page, rows: found)
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
