#!/usr/bin/env python3
"""Loopback-only OpenAI Responses stub for the local Kyra acceptance run."""

import json
import os
import re
import hmac
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("ASTRA_LOCAL_KYRA_STUB_PORT", "18765"))
TOKEN = os.environ.get("ASTRA_LOCAL_KYRA_STUB_TOKEN", "")
ITEM_IDS = [value for value in os.environ.get("ASTRA_LOCAL_KYRA_ITEM_IDS", "").split(",") if value]
UUID_PATTERN = re.compile(r"^[0-9a-fA-F-]{36}$")


def validate_ids():
    if len(ITEM_IDS) < 3 or len(set(ITEM_IDS)) != len(ITEM_IDS):
        raise SystemExit("The local Kyra stub requires at least three distinct seeded item IDs.")
    for item_id in ITEM_IDS:
        if not UUID_PATTERN.fullmatch(item_id):
            raise SystemExit("A local Kyra fixture item ID is malformed.")
        uuid.UUID(item_id)


class Handler(BaseHTTPRequestHandler):
    server_version = "AstraLocalKyraStub/1.0"

    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_POST(self):
        if self.path != "/v1/responses":
            self.send_error(404)
            return
        supplied_token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        if not TOKEN or not hmac.compare_digest(supplied_token, TOKEN):
            self.send_error(401)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 1_048_576:
                self.send_error(413)
                return
            body = json.loads(self.rfile.read(size))
            inputs = body.get("input", [])
            tool_outputs = [
                item for item in inputs
                if isinstance(item, dict) and item.get("type") == "function_call_output"
            ]
            if tool_outputs:
                result = json.loads(tool_outputs[-1].get("output", "{}"))
                outfit_id = result.get("outfit_id")
                item_ids = result.get("item_ids")
                if not isinstance(outfit_id, str) or not isinstance(item_ids, list):
                    self.send_error(502)
                    return
                payload = {
                    "message": "I built this outfit from your local test closet.",
                    "intent": "daily_outfit",
                    "cards": [{
                        "type": "outfit",
                        "outfit_id": outfit_id,
                        "item_ids": item_ids,
                        "reason": "A deterministic local acceptance result.",
                    }],
                    "suggested_actions": [],
                    "memory_proposals": [],
                    "confidence": 0.99,
                }
                output = [{
                    "type": "message",
                    "content": [{"type": "output_text", "text": json.dumps(payload)}],
                }]
            else:
                output = [{
                    "type": "function_call",
                    "call_id": "call_local_create_outfit",
                    "name": "create_outfit",
                    "arguments": json.dumps({
                        "item_ids": ITEM_IDS,
                        "product_candidate_ids": [],
                        "occasion_tags": ["casual"],
                        "name": "Local QA outfit",
                        "reason": "A deterministic local acceptance outfit.",
                    }),
                }]
            response = {
                "id": "resp_local_qa",
                "object": "response",
                "status": "completed",
                "model": "local-kyra-stub",
                "output": output,
                "usage": {"input_tokens": 0, "output_tokens": 0},
            }
            encoded = json.dumps(response).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
        except (ValueError, TypeError, json.JSONDecodeError):
            self.send_error(400)


if __name__ == "__main__":
    validate_ids()
    if len(TOKEN) < 32:
        raise SystemExit("The local Kyra stub requires a random per-run bearer token.")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
