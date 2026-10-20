#!/usr/bin/env python3
import os
"""Stand-in for a Sony Bravia on this machine only.

Binds to 127.0.0.1. Refuses to start if any argument contains the real TV address.
The pre-shared key is compared and never written to the log.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Optional guard: refuse to start if any argument names your real TV.
FORBIDDEN = os.environ.get("POHSTEP_REAL_TV", "") or "\0"


class State:
    def __init__(self):
        self.power = "active"
        self.volume = 18
        self.muted = False
        self.port = 1


STATE = State()
EXPECTED = ""
LOG = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length)
        supplied = self.headers.get("X-Auth-PSK", "")
        if supplied == "":
            verdict = "absent"
        elif supplied == EXPECTED:
            verdict = "match"
        else:
            verdict = "mismatch"
        text = raw.decode("utf-8", errors="replace")
        method = ""
        ircc = ""
        if "IRCCCode" in text:
            start = text.find("<IRCCCode>")
            end = text.find("</IRCCCode>")
            if start != -1 and end != -1:
                ircc = text[start + len("<IRCCCode>") : end]
        else:
            try:
                payload = json.loads(text) if text else {}
                method = str(payload.get("method", ""))
            except json.JSONDecodeError:
                method = ""
        if LOG is not None:
            LOG.write(json.dumps({
                "path": self.path,
                "method": method,
                "ircc": ircc,
                "psk": verdict,
            }) + "\n")
            LOG.flush()
        if verdict != "match":
            body = b""
            self.send_response(403)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.wfile.write(body)
            return
        body = respond(self.path, method, text).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def respond(path, method, text):
    if method == "getPowerStatus":
        return json.dumps({"result": [{"status": STATE.power}], "id": 1})
    if method == "setPowerStatus":
        STATE.power = "active" if '"status": true' in text or '"status":true' in text else "standby"
        return json.dumps({"result": [], "id": 1})
    if method == "getVolumeInformation":
        return json.dumps({"result": [[{
            "target": "speaker",
            "volume": STATE.volume,
            "mute": STATE.muted,
            "maxVolume": 100,
            "minVolume": 0,
        }]], "id": 1})
    if method == "setAudioVolume":
        for token in text.replace(",", " ").split():
            if token.startswith('"volume"'):
                digits = "".join(ch for ch in token if ch.isdigit())
                if digits:
                    STATE.volume = int(digits)
        return json.dumps({"result": [], "id": 1})
    if method == "getCurrentExternalInputsStatus":
        rows = []
        for port in range(1, 5):
            rows.append({
                "uri": "extInput:hdmi?port=%d" % port,
                "title": "HDMI %d" % port,
                "label": "Apple TV" if port == 1 else "",
                "connection": port == STATE.port,
            })
        return json.dumps({"result": [rows], "id": 1})
    if method == "setPlayContent":
        for port in range(1, 5):
            if "port=%d" % port in text:
                STATE.port = port
        return json.dumps({"result": [], "id": 1})
    if method == "getPlayingContentInfo":
        return json.dumps({"result": [{"title": "HDMI %d" % STATE.port, "source": "extInput"}], "id": 1})
    if path == "/sony/ircc":
        return ""
    return json.dumps({"error": [404, "unknown"], "id": 1})


def main():
    blob = " ".join(sys.argv[1:])
    if FORBIDDEN in blob:
        sys.stderr.write("refusing the real television\n")
        return 3
    if len(sys.argv) != 4:
        sys.stderr.write("usage: pretend-tv.py PORT PSK LOGFILE\n")
        return 2
    global EXPECTED, LOG
    port = int(sys.argv[1])
    EXPECTED = sys.argv[2]
    LOG = open(sys.argv[3], "w", encoding="utf-8")
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    actual = server.server_address[1]
    sys.stdout.write("READY %d\n" % actual)
    sys.stdout.flush()
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
