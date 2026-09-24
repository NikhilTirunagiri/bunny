import Foundation
import Testing
@testable import BunnyCore

/// Inputs mirror what `codex mcp add` (codex-cli 0.155.0) writes; see docs/superpowers/research/mcp-http.md.
struct CodexConfigPatcherTests {
    private static let afterAdd = """
    model = "gpt-5.6-luna"

    [mcp_servers.other]
    url = "http://127.0.0.1:18802/mcp"

    [mcp_servers.other.http_headers]
    Authorization = "Bearer other"

    [mcp_servers.bunny]
    url = "http://127.0.0.1:47823/mcp"
    bearer_token_env_var = "BUNNY_TOKEN"

    [tui]
    animations = false
    """

    @Test func replacesTheEnvVarWithInlineHeadersAndApproval() throws {
        let patched = try #require(CodexConfigPatcher.patch(Self.afterAdd, token: "abc123"))
        #expect(patched == """
        model = "gpt-5.6-luna"

        [mcp_servers.other]
        url = "http://127.0.0.1:18802/mcp"

        [mcp_servers.other.http_headers]
        Authorization = "Bearer other"

        [mcp_servers.bunny]
        url = "http://127.0.0.1:47823/mcp"
        http_headers = { Authorization = "Bearer abc123" }
        default_tools_approval_mode = "approve"

        [tui]
        animations = false
        """)
    }

    @Test func isIdempotentAndReplacesAnOldToken() throws {
        let once = try #require(CodexConfigPatcher.patch(Self.afterAdd, token: "old"))
        let twice = try #require(CodexConfigPatcher.patch(once, token: "new"))
        #expect(twice == CodexConfigPatcher.patch(Self.afterAdd, token: "new"))
        #expect(!twice.contains("old"))
    }

    /// Any later `codex mcp add` rewrites the file and turns the inline table into a sub-table.
    @Test func replacesAHeadersSubTable() throws {
        let rewritten = """
        [mcp_servers.bunny]
        url = "http://127.0.0.1:47823/mcp"
        default_tools_approval_mode = "approve"

        [mcp_servers.bunny.http_headers]
        Authorization = "Bearer stale"

        [mcp_servers.other2]
        url = "http://127.0.0.1:1/mcp"
        """
        let patched = try #require(CodexConfigPatcher.patch(rewritten, token: "fresh"))
        #expect(patched == """
        [mcp_servers.bunny]
        url = "http://127.0.0.1:47823/mcp"
        http_headers = { Authorization = "Bearer fresh" }
        default_tools_approval_mode = "approve"

        [mcp_servers.other2]
        url = "http://127.0.0.1:1/mcp"
        """)
    }

    @Test func entryAtEndOfFile() throws {
        let text = "[mcp_servers.bunny]\nurl = \"http://127.0.0.1:47823/mcp\"\n"
        let patched = try #require(CodexConfigPatcher.patch(text, token: "t"))
        #expect(patched == """
        [mcp_servers.bunny]
        url = "http://127.0.0.1:47823/mcp"
        http_headers = { Authorization = "Bearer t" }
        default_tools_approval_mode = "approve"

        """)
    }

    @Test func leavesOtherServersAlone() throws {
        let text = """
        [mcp_servers.bunnyish]
        bearer_token_env_var = "KEEP"

        [mcp_servers.bunny]
        url = "u"
        """
        let patched = try #require(CodexConfigPatcher.patch(text, token: "t"))
        #expect(patched.contains("bearer_token_env_var = \"KEEP\""))
    }

    @Test func missingEntryReturnsNil() {
        #expect(CodexConfigPatcher.patch("[mcp_servers.other]\nurl = \"u\"\n", token: "t") == nil)
    }

    @Test func serverTableMatchesTheServerName() {
        #expect(CodexConfigPatcher.serverTable == "mcp_servers.\(BunnyToolsEndpoint.serverName)")
    }

    @Test func tableNames() {
        #expect(CodexConfigPatcher.tableName("  [mcp_servers.bunny]  ") == "mcp_servers.bunny")
        #expect(CodexConfigPatcher.tableName("[[array]]") == nil)
        #expect(CodexConfigPatcher.tableName("url = \"[x]\"") == nil)
    }
}
