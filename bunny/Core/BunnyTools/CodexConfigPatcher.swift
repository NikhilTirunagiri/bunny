import Foundation

/// Rewrites the `[mcp_servers.bunny]` entry that `codex mcp add bunny --url …` leaves in Codex's
/// `config.toml`, so Codex sessions outside Bunny can reach the Bunny tools:
/// - `bearer_token_env_var` is removed. Bunny can't set that variable for sessions it doesn't launch,
///   and Codex merges a per-run `config.mcp_servers.bunny` into this entry key by key, so a leftover
///   variable name also breaks Bunny's own runs (docs/superpowers/research/mcp-http.md).
/// - `http_headers = { Authorization = "Bearer <token>" }` carries the token instead
///   (`codex mcp add` has no header flag).
/// - `default_tools_approval_mode = "approve"` lets `never`-policy sessions call the tools.
///
/// Text-based and line-oriented: everything outside the entry is left byte for byte. Nonisolated: the
/// installer runs it off the main thread (the app target defaults to main-actor isolation).
enum CodexConfigPatcher {
    /// `mcp_servers.<BunnyToolsEndpoint.serverName>`.
    nonisolated static let serverTable = "mcp_servers.bunny"
    nonisolated static let approvalMode = "approve"

    nonisolated private static let replacedKeys: Set<String> = ["bearer_token_env_var", "http_headers", "default_tools_approval_mode"]

    /// The patched text, or nil when the file has no `[mcp_servers.bunny]` table.
    nonisolated static func patch(_ text: String, token: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { tableName($0) == serverTable }) else { return nil }

        // A `[mcp_servers.bunny.http_headers]` sub-table would clash with the inline table written below.
        let headersTable = serverTable + ".http_headers"
        if let subIndex = lines.firstIndex(where: { tableName($0) == headersTable }) {
            let end = lines[(subIndex + 1)...].firstIndex(where: { tableName($0) != nil }) ?? lines.count
            lines.removeSubrange(subIndex..<end)
        }

        let sectionEnd = lines[(headerIndex + 1)...].firstIndex(where: { tableName($0) != nil }) ?? lines.count
        var body = Array(lines[(headerIndex + 1)..<sectionEnd])
        body.removeAll { line in key(of: line).map(replacedKeys.contains) ?? false }
        let added = [
            "http_headers = { Authorization = \(quoted("Bearer \(token)")) }",
            "default_tools_approval_mode = \(quoted(approvalMode))",
        ]
        // Keep the entry's own keys together, ahead of any blank lines that separate it from the next table.
        let insertAt = (body.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? -1) + 1
        body.insert(contentsOf: added, at: insertAt)
        lines.replaceSubrange((headerIndex + 1)..<sectionEnd, with: body)
        return lines.joined(separator: "\n")
    }

    /// The table name of a `[table]` header line (not `[[array]]`), or nil for any other line.
    nonisolated static func tableName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), !trimmed.hasPrefix("[["),
              let close = trimmed.firstIndex(of: "]") else { return nil }
        let name = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// The bare key of a `key = value` line, or nil for comments, blanks and other lines.
    nonisolated private static func key(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// A TOML basic string.
    nonisolated private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
