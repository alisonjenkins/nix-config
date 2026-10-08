"""Does the server keep the text of tool-call arguments byte for byte?

Sends a tools request through /v1/chat/completions (the parsed path) and the
same prompt through /apply-template + /completion (raw model text), then
reports what the parsed arguments carry against what the model wrote.

Scenarios:
  whitespace  an edit call whose strings start with eight spaces; parsers that
              trim one character return seven
  newlines    a write call with four consecutive lines; a model or parser that
              doubles newlines returns blank lines between them
"""

import argparse
import json
import urllib.request

EDIT_TOOL = {
    "type": "function",
    "function": {
        "name": "edit",
        "description": "Replace oldString with newString in a file.",
        "parameters": {
            "type": "object",
            "properties": {
                "filePath": {"type": "string"},
                "oldString": {"type": "string"},
                "newString": {"type": "string"},
            },
            "required": ["filePath", "oldString", "newString"],
        },
    },
}
WRITE_TOOL = {
    "type": "function",
    "function": {
        "name": "write",
        "description": "Write content to a file.",
        "parameters": {
            "type": "object",
            "properties": {"filePath": {"type": "string"}, "content": {"type": "string"}},
            "required": ["filePath", "content"],
        },
    },
}
SYSTEM = {"role": "system", "content": "You edit files by calling tools."}
SCENARIOS = {
    "whitespace": {
        "tools": [EDIT_TOOL],
        "messages": [
            SYSTEM,
            {
                "role": "user",
                "content": (
                    "Call the edit tool exactly once. filePath is /tmp/x.py. oldString is "
                    "eight spaces followed by 'return 1'. newString is eight spaces followed "
                    "by 'return 2'. Both strings must start with exactly eight spaces."
                ),
            },
        ],
    },
    "newlines": {
        "tools": [WRITE_TOOL],
        "messages": [
            SYSTEM,
            {
                "role": "user",
                "content": (
                    "Call the write tool exactly once. filePath is /tmp/t.py. content is "
                    "exactly these four lines, each directly after the previous one with no "
                    "blank line between them:\nimport os\nimport sys\nimport json\nimport re"
                ),
            },
        ],
    },
}


def post(url, path, body):
    req = urllib.request.Request(
        url + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read())


def lead(text):
    return len(text) - len(text.lstrip(" "))


def blank_lines(text):
    return sum(1 for line in text.split("\n") if line == "")


def parsed(url, scenario, temperature, extra):
    body = {
        "messages": scenario["messages"],
        "tools": scenario["tools"],
        "temperature": temperature,
        "max_tokens": 600,
        **extra,
    }
    msg = post(url, "/v1/chat/completions", body)["choices"][0]["message"]
    calls = msg.get("tool_calls") or []
    out = {"n_calls": len(calls), "content_head": (msg.get("content") or "")[:120]}
    if calls:
        args = json.loads(calls[0]["function"]["arguments"])
        out["args"] = args
        if "oldString" in args:
            out["old_lead"] = lead(args["oldString"])
            out["new_lead"] = lead(args.get("newString", ""))
        if "content" in args:
            out["blank_lines_in_content"] = blank_lines(args["content"])
    return out


def raw(url, scenario, temperature):
    prompt = post(url, "/apply-template", {"messages": scenario["messages"], "tools": scenario["tools"]})["prompt"]
    text = post(url, "/completion", {"prompt": prompt, "temperature": temperature, "n_predict": 600})["content"]
    return {"prompt_tail": prompt[-160:], "raw": text}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--scenario", choices=sorted(SCENARIOS), default="whitespace")
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--extra", default="{}", help="JSON merged into the chat request")
    a = ap.parse_args()
    chosen = SCENARIOS[a.scenario]
    extra = json.loads(a.extra)
    for i in range(a.runs):
        print(f"--- parsed run {i + 1} ({a.scenario})")
        print(json.dumps(parsed(a.url, chosen, a.temperature, extra), indent=1))
    print("--- raw completion")
    r = raw(a.url, chosen, a.temperature)
    print("prompt tail:", repr(r["prompt_tail"]))
    print("raw text:", repr(r["raw"]))
