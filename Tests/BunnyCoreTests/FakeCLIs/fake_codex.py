#!/usr/bin/env python3
"""Fake `codex app-server --stdio` (newline-delimited JSON-RPC 2.0) for BunnyCore runner tests.

Refuses to run unless argv is exactly ["app-server", "--stdio"]. With FAKE_CODEX_THREAD_ERROR
set, thread/start answers with a JSON-RPC error "thread boom". Supports initialize,
thread/start (thread id "th-1"), thread/resume, turn/start and turn/interrupt.
Keywords in the turn text pick the scenario:
  QUESTION -> agentMessage ending in a <bunny-question> marker, then turn/completed completed
  APPROVE  -> server request item/commandExecution/requestApproval (id 99); the turn finishes
              with "approval: <decision>" once the client replies
  POLICY   -> agentMessage "policy: <approvalPolicy> sandbox: <sandbox> roots: <writable roots json>"
  BADTURN  -> turn/completed failed with error "kaput"
  other    -> agentMessage "done: <text>", then turn/completed completed
"""
import json
import os
import sys

if sys.argv[1:] != ["app-server", "--stdio"]:
    sys.stderr.write("usage: fake_codex.py app-server --stdio (got %r)\n" % (sys.argv[1:],))
    sys.exit(2)

thread_params = {}
turn_counter = 0
pending_approval_turn = None


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def respond(rpc_id, result):
    out({"jsonrpc": "2.0", "id": rpc_id, "result": result})


def notify(method, params):
    out({"jsonrpc": "2.0", "method": method, "params": params})


def agent_message(turn_id, text):
    half = len(text) // 2
    notify("item/agentMessage/delta", {"threadId": "th-1", "turnId": turn_id, "itemId": "m1", "delta": text[:half]})
    notify("item/agentMessage/delta", {"threadId": "th-1", "turnId": turn_id, "itemId": "m1", "delta": text[half:]})
    notify("item/completed", {"threadId": "th-1", "turnId": turn_id,
                               "item": {"type": "agentMessage", "id": "m1", "text": text}})


def complete(turn_id, status="completed", error=None):
    turn = {"id": turn_id, "status": status, "items": []}
    if error is not None:
        turn["error"] = {"message": error}
    notify("turn/completed", {"threadId": "th-1", "turn": turn})


def handle_turn(turn_id, text):
    global pending_approval_turn
    notify("turn/started", {"threadId": "th-1", "turn": {"id": turn_id, "status": "inProgress", "items": []}})
    if "QUESTION" in text:
        agent_message(turn_id, "Need info\n<bunny-question>{\"question\":\"Which DB?\",\"options\":[\"pg\",\"sqlite\"]}</bunny-question>")
        complete(turn_id)
    elif "APPROVE" in text:
        notify("item/started", {"threadId": "th-1", "turnId": turn_id,
                                "item": {"type": "commandExecution", "id": "c1", "command": "rm -rf build"}})
        pending_approval_turn = turn_id
        out({"jsonrpc": "2.0", "id": 99, "method": "item/commandExecution/requestApproval",
             "params": {"threadId": "th-1", "turnId": turn_id, "itemId": "c1", "command": "rm -rf build"}})
    elif "POLICY" in text:
        roots = thread_params.get("config", {}).get("sandbox_workspace_write", {}).get("writable_roots", [])
        agent_message(turn_id, "policy: %s sandbox: %s roots: %s" % (
            thread_params.get("approvalPolicy"), thread_params.get("sandbox"), json.dumps(roots)))
        complete(turn_id)
    elif "BADTURN" in text:
        complete(turn_id, status="failed", error="kaput")
    else:
        agent_message(turn_id, "done: " + text)
        complete(turn_id)


def main():
    global thread_params, turn_counter, pending_approval_turn
    while True:
        line = sys.stdin.readline()
        if not line:
            return
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method = msg.get("method")
        rpc_id = msg.get("id")
        params = msg.get("params", {})

        if method is None:
            # A response to one of our server requests (approval).
            if rpc_id == 99 and pending_approval_turn is not None:
                decision = msg.get("result", {}).get("decision", "?")
                turn_id = pending_approval_turn
                pending_approval_turn = None
                agent_message(turn_id, "approval: " + decision)
                complete(turn_id)
            continue
        if rpc_id is None:
            continue  # notification, e.g. "initialized"

        if method == "initialize":
            respond(rpc_id, {"userAgent": "fake-codex/0.0"})
        elif method == "thread/start":
            if os.environ.get("FAKE_CODEX_THREAD_ERROR"):
                out({"jsonrpc": "2.0", "id": rpc_id, "error": {"code": -32000, "message": "thread boom"}})
                continue
            thread_params = params
            respond(rpc_id, {"thread": {"id": "th-1", "path": "/tmp/th-1.jsonl"}})
        elif method == "thread/resume":
            respond(rpc_id, {"thread": {"id": params.get("threadId"), "path": "/tmp/resumed.jsonl"}})
        elif method == "turn/start":
            turn_counter += 1
            turn_id = "turn-%d" % turn_counter
            text = "".join(i.get("text", "") for i in params.get("input", []) if i.get("type") == "text")
            respond(rpc_id, {"turn": {"id": turn_id, "status": "inProgress", "items": []}})
            handle_turn(turn_id, text)
        elif method == "turn/interrupt":
            respond(rpc_id, {})
            complete(params.get("turnId"), status="interrupted")
        else:
            out({"jsonrpc": "2.0", "id": rpc_id, "error": {"code": -32601, "message": "unknown method " + method}})


if __name__ == "__main__":
    main()
