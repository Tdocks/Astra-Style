#!/usr/bin/env python3
"""Loopback-only acceptance proxy; never logs request bodies or credentials."""
import http.server
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request


class FaultProxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream = ""
    token = ""
    lock = threading.Lock()
    rules = []
    delay = 0.15

    def log_message(self, *_args):
        pass

    def respond(self, status, data, headers=None):
        self.send_response(status)
        for key, value in (headers or {}).items():
            if key.lower() not in {"content-length", "transfer-encoding", "connection", "server", "date"}:
                self.send_header(key, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_request(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length > 1024 * 1024:
            self.respond(413, b"")
            return
        body = self.rfile.read(length) if length else None
        if self.path == "/__qa/faults":
            if self.headers.get("Authorization") != "Bearer " + self.token:
                self.respond(403, b"")
                return
            with self.lock:
                if self.command == "POST":
                    rule = json.loads(body or b"{}")
                    if (rule.get("mode") not in {"503", "drop_after"}
                            or rule.get("method") not in {"GET", "POST", "DELETE"}
                            or not str(rule.get("path", "")).startswith(("/rest/v1/", "/functions/v1/"))):
                        self.respond(400, b"")
                        return
                    count = int(rule.get("count", "1"))
                    if not 1 <= count <= 4:
                        self.respond(400, b"")
                        return
                    rule.update(remaining=count, injected=0, requests=0)
                    self.rules.append(rule)
                data = json.dumps(self.rules).encode()
            self.respond(200, data, {"Content-Type": "application/json"})
            return
        mode = None
        selected = None
        with self.lock:
            for rule in self.rules:
                matches = (rule["method"] == self.command
                           and self.path.split("?", 1)[0] == rule["path"])
                if matches:
                    rule["requests"] += 1
                if rule["remaining"] and matches:
                    rule["remaining"] -= 1
                    rule["injected"] += 1
                    mode = rule["mode"]
                    selected = rule
                    break
        time.sleep(self.delay)
        if mode == "503":
            self.respond(503, b'{"message":"Injected temporary connection failure"}',
                         {"Content-Type": "application/json", "Retry-After": "1"})
            return
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in {"host", "content-length", "connection", "accept-encoding"}}
        request = urllib.request.Request(self.upstream + self.path, data=body,
                                         headers=headers, method=self.command)
        try:
            response = urllib.request.urlopen(request, timeout=60)
        except urllib.error.HTTPError as error:
            response = error
        except (urllib.error.URLError, TimeoutError):
            self.respond(502, b"")
            return
        with response:
            if selected is not None:
                with self.lock:
                    selected["upstream_status"] = response.status
            data = response.read()
            if mode == "drop_after":
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            self.respond(response.status, data, dict(response.headers))

    do_GET = handle_request
    do_POST = handle_request
    do_PATCH = handle_request
    do_DELETE = handle_request
    do_PUT = handle_request


if __name__ == "__main__":
    FaultProxy.upstream = os.environ["ASTRA_QA_PROXY_UPSTREAM"]
    FaultProxy.token = os.environ["ASTRA_QA_PROXY_TOKEN"]
    if not FaultProxy.upstream.startswith("http://127.0.0.1:"):
        raise SystemExit("Only loopback upstreams are allowed")
    http.server.ThreadingHTTPServer(("127.0.0.1", int(os.environ["ASTRA_QA_PROXY_PORT"])), FaultProxy).serve_forever()
