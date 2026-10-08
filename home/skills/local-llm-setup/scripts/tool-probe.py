"""Does the server keep leading whitespace in tool-call arguments?

Sends one tools request through /v1/chat/completions (the parsed path) and the
same prompt through /apply-template + /completion (raw model text), then
prints how many leading spaces each string carries.
"""

import argparse
import json
import urllib.request

EIGHT = " " * 8
USER = (
    "Call the edit tool exactly once. filePath is /tmp/x.py. oldString is "
    "eight spaces followed by 'return 1'. newString is eight spaces followed "
    "by 'return 2'. Both strings must start with exactly eight spaces."
)
TOOLS = [
    {
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
]
MESSAGES = [
    {"role": "system", "content": "You edit files by calling tools."},
    {"role": "user", "content": USER},
]


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


def parsed(url, extra):
    body = {"messages": MESSAGES, "tools": TOOLS, "temperature": 0, "max_tokens": 600, **extra}
    msg = post(url, "/v1/chat/completions", body)["choices"][0]["message"]
    calls = msg.get("tool_calls") or []
    out = {"n_calls": len(calls), "content_head": (msg.get("content") or "")[:120]}
    if calls:
        args = json.loads(calls[0]["function"]["arguments"])
        out["old_lead"] = lead(args.get("oldString", ""))
        out["new_lead"] = lead(args.get("newString", ""))
        out["args"] = args
    return out


def raw(url):
    prompt = post(url, "/apply-template", {"messages": MESSAGES, "tools": TOOLS})["prompt"]
    text = post(url, "/completion", {"prompt": prompt, "temperature": 0, "n_predict": 600})["content"]
    return {"prompt_tail": prompt[-160:], "raw": text}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--extra", default="{}", help="JSON merged into the chat request")
    a = ap.parse_args()
    extra = json.loads(a.extra)
    for i in range(a.runs):
        print(f"--- parsed run {i + 1}")
        print(json.dumps(parsed(a.url, extra), indent=1))
    print("--- raw completion")
    r = raw(a.url)
    print("prompt tail:", repr(r["prompt_tail"]))
    print("raw text:", repr(r["raw"]))
