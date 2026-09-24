#!/usr/bin/env python3
"""Fake `claude -p --input-format stream-json --output-format stream-json` for BunnyCore runner tests.

Reads user messages / control responses from stdin (one JSON object per line) and writes
stream-json lines to stdout. Keywords in the user message pick the scenario:
  ASK     -> can_use_tool AskUserQuestion (request_id "r1"); result echoes the answers
  APPROVE -> can_use_tool Bash (request_id "r2"); result echoes the behavior
  FAIL    -> writes "boom" to stderr and exits with code 3
  other   -> assistant text "working", then result "done: <text>"
Every result text ends with " | argv=<json of argv>" so tests can assert the flags.
"""
import json
import sys

ARGV = sys.argv[1:]


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def result(text, success=True):
    if success:
        out({"type": "result", "subtype": "success", "is_error": False,
             "result": text + " | argv=" + json.dumps(ARGV), "session_id": "sess-1"})
    else:
        out({"type": "result", "subtype": "error_during_execution", "is_error": True,
             "terminal_reason": text + " | argv=" + json.dumps(ARGV), "session_id": "sess-1"})


def main():
    initialized = False
    while True:
        line = sys.stdin.readline()
        if not line:
            return
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        kind = msg.get("type")

        if kind == "user":
            content = msg.get("message", {}).get("content", [])
            text = "".join(c.get("text", "") for c in content if c.get("type") == "text")
            if not initialized:
                out({"type": "system", "subtype": "init", "session_id": "sess-1", "cwd": "."})
                initialized = True
            if "FAIL" in text:
                sys.stderr.write("boom\n")
                sys.stderr.flush()
                sys.exit(3)
            if "ASK" in text:
                out({"type": "control_request", "request_id": "r1", "request": {
                    "subtype": "can_use_tool", "tool_name": "AskUserQuestion", "tool_use_id": "t1",
                    "input": {"questions": [{
                        "question": "Pick one?", "header": "Choice", "multiSelect": False,
                        "options": [{"label": "A", "description": "first"},
                                    {"label": "B", "description": "second"}]}]}}})
                continue
            if "APPROVE" in text:
                out({"type": "control_request", "request_id": "r2", "request": {
                    "subtype": "can_use_tool", "tool_name": "Bash", "tool_use_id": "t2",
                    "input": {"command": "rm -rf build"}}})
                continue
            out({"type": "assistant", "session_id": "sess-1",
                 "message": {"content": [{"type": "text", "text": "working"}]}})
            result("done: " + text)

        elif kind == "control_response":
            response = msg.get("response", {})
            body = response.get("response", {})
            if response.get("request_id") == "r1":
                answers = body.get("updatedInput", {}).get("answers")
                result("answered: " + json.dumps(answers))
            else:
                result("approval: " + body.get("behavior", "?") + " " + json.dumps(body.get("updatedInput")))

        elif kind == "control_request" and msg.get("request", {}).get("subtype") == "interrupt":
            out({"type": "control_response", "response": {"subtype": "success", "request_id": msg.get("request_id")}})
            result("interrupted", success=False)


if __name__ == "__main__":
    main()
