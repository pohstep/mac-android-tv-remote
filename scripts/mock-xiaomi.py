#!/usr/bin/env python3
"""Experimental stand-in for the community TV API on port 6095.

Binds to 127.0.0.1 only. Not a real television. The pre-shared-key style
guard matches scripts/pretend-tv.py: set POHSTEP_REAL_TV to an address that
must never appear in the arguments.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

FORBIDDEN = os.environ.get("POHSTEP_REAL_TV", "") or "\0"
LOG = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        self.reply()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length:
            self.rfile.read(length)
        self.reply()

    def reply(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        action = (query.get("action") or [""])[0]
        if LOG is not None:
            LOG.write(json.dumps({
                "path": parsed.path,
                "action": action,
                "keycode": (query.get("keycode") or [""])[0],
                "packagename": (query.get("packagename") or [""])[0],
                "source": (query.get("source") or [""])[0],
            }) + "\n")
            LOG.flush()
        if parsed.path == "/request" and action == "isalive":
            body = json.dumps({
                "status": 0,
                "msg": "success",
                "data": {"devicename": "Mock TV"},
            }).encode("utf-8")
        elif parsed.path == "/controller" and action in ("keyevent", "startapp", "changesource"):
            body = json.dumps({"status": 0, "msg": "success"}).encode("utf-8")
        else:
            body = json.dumps({"status": -1, "msg": "unknown"}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    blob = " ".join(sys.argv[1:])
    if FORBIDDEN in blob:
        sys.stderr.write("refusing the real television\n")
        return 3
    if len(sys.argv) != 3:
        sys.stderr.write("usage: mock-xiaomi.py PORT LOGFILE\n")
        return 2
    global LOG
    port = int(sys.argv[1])
    LOG = open(sys.argv[2], "w", encoding="utf-8")
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    actual = server.server_address[1]
    sys.stdout.write("READY %d\n" % actual)
    sys.stdout.flush()
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
