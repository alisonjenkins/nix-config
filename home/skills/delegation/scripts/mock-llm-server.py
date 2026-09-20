#!/usr/bin/env python3
"""Minimal stdlib-only OpenAI-compatible stand-in server, for exercising
delegate-to-local.sh's real queue/worker/process pipeline (switch, chat,
stop, concurrency) without a GPU or real model weights. Not a runtime you'd
use for real work — declare a profile with runtime = "mock" pointed at
this script to test the plumbing around it.

Usage: mock-llm-server.py --port N [--model NAME] [--delay SECONDS]
"""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def make_handler(model_name: str, delay: float):
    class Handler(BaseHTTPRequestHandler):
        def _send_json(self, obj, status=200):
            body = json.dumps(obj).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/v1/models":
                self._send_json({"data": [{"id": model_name}]})
            else:
                self._send_json({"error": "not found"}, status=404)

        def do_POST(self):
            if self.path != "/v1/chat/completions":
                self._send_json({"error": "not found"}, status=404)
                return
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            task = ""
            for msg in body.get("messages", []):
                if msg.get("role") == "user":
                    task = msg.get("content", "")
            if delay:
                time.sleep(delay)
            reply = f"mock response from {model_name}: {task}"
            self._send_json(
                {"choices": [{"message": {"content": reply}}]}
            )

        def log_message(self, format, *args):  # noqa: A002 - matches BaseHTTPRequestHandler's signature
            pass  # keep stdout/stderr quiet — the caller redirects them to a log file anyway

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model", default="mock-model")
    parser.add_argument("--delay", type=float, default=0.0, help="seconds to sleep before replying, to simulate a slow model")
    args = parser.parse_args()

    server = HTTPServer(("127.0.0.1", args.port), make_handler(args.model, args.delay))
    server.serve_forever()


if __name__ == "__main__":
    main()
