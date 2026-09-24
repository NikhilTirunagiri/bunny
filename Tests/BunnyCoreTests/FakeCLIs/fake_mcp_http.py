#!/usr/bin/env python3
"""Minimal MCP Streamable-HTTP server (stdlib only) standing in for Bunny's tools in live agent tests.

usage: fake_mcp_http.py <token> <calls-log-path>
Listens on 127.0.0.1 on a free port and prints "PORT <n>" as its first stdout line. POST /mcp only;
every request needs "Authorization: Bearer <token>" (else 401). Requests get one JSON response,
notifications 202. Offers one tool, create_task(title, description?). Each tools/call is appended to
the log as a JSON line {"name", "arguments", "task": X-Bunny-Task header or null}.
See docs/superpowers/research/mcp-http.md for why this shape is enough for Claude Code and Codex.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = sys.argv[1]
LOG = sys.argv[2]
SUPPORTED = {"2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"}
TOOLS = [{
    "name": "create_task",
    "description": "Create a task in the user's Bunny task list",
    "inputSchema": {
        "type": "object",
        "properties": {"title": {"type": "string"}, "description": {"type": "string"}},
        "required": ["title"],
    },
}]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def reply(self, status, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(405, {"error": "POST only"})

    def do_POST(self):
        if not self.path.startswith("/mcp"):
            return self.reply(404, {"error": "not found"})
        if self.headers.get("Authorization", "") != "Bearer " + TOKEN:
            return self.reply(401, {"error": "unauthorized"})
        length = int(self.headers.get("Content-Length", 0))
        try:
            req = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self.reply(400, {"error": "invalid json"})
        if "id" not in req:
            return self.reply(202)
        method = req.get("method")
        params = req.get("params") or {}
        result, error = None, None
        if method == "initialize":
            version = params.get("protocolVersion")
            result = {
                "protocolVersion": version if version in SUPPORTED else "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "bunny", "version": "0.0-test"},
            }
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call" and params.get("name") == "create_task":
            with open(LOG, "a") as log:
                log.write(json.dumps({
                    "name": "create_task",
                    "arguments": params.get("arguments") or {},
                    "task": self.headers.get("X-Bunny-Task"),
                }) + "\n")
            result = {"content": [{"type": "text", "text": "Created the task."}]}
        elif method == "ping":
            result = {}
        else:
            error = {"code": -32601, "message": "method not found: %s" % method}
        response = {"jsonrpc": "2.0", "id": req["id"]}
        if error is not None:
            response["error"] = error
        else:
            response["result"] = result
        self.reply(200, response)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    sys.stdout.write("PORT %d\n" % server.server_address[1])
    sys.stdout.flush()
    server.serve_forever()
