#!/usr/bin/env python3
"""Campus Notice Board API - one source tree, three release images.

Behaviour is selected by environment variables baked into the image by the
Dockerfile (APP_VERSION, STUDENT_ID) and, for 1.1.0 and later, by the runtime
variable FEATURE_PINNED.

  GET /notices   JSON list of notices
  GET /version   {"version": ..., "student": ..., "pod": <container hostname>}
  GET /healthz   200 when healthy, 503 otherwise

  1.0.0         baseline
  1.1.0         adds "category" to every notice and "pinned" to some; when
                FEATURE_PINNED=true pinned notices come first and the body
                contains "pinnedFirst": true (otherwise false)
  1.2.0-broken  identical to 1.1.0, but /healthz never returns 200

Every version reports unhealthy on /healthz for the first WARMUP_SECONDS (5)
after start-up. On SIGTERM the server keeps answering for DRAIN_SECONDS (5)
before it exits, so that Kubernetes has time to remove the Pod from the
Service endpoints and no in-flight request is refused.
"""
import json
import os
import signal
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_VERSION = os.environ.get("APP_VERSION", "1.0.0")
STUDENT_ID = os.environ.get("STUDENT_ID", "unknown")
PORT = int(os.environ.get("PORT", "8080"))
WARMUP_SECONDS = float(os.environ.get("WARMUP_SECONDS", "5"))
DRAIN_SECONDS = float(os.environ.get("DRAIN_SECONDS", "5"))

BASELINE = APP_VERSION == "1.0.0"          # 1.0.0: no category / pinned fields
BROKEN = APP_VERSION.endswith("-broken")   # 1.2.0-broken: never healthy
# Read once at start-up: a running process never sees later changes to its
# environment, which is exactly what Task 8 asks you to demonstrate.
FEATURE_PINNED = os.environ.get("FEATURE_PINNED", "false").strip().lower() == "true"

START = time.monotonic()

NOTICES = [
    {"id": 1, "title": "Library opening hours extended",
     "body": "The library stays open until 22:00 on weekdays during the exam period.",
     "category": "library", "pinned": False},
    {"id": 2, "title": "Mid-semester examination timetable published",
     "body": "Timetables are available at the Examination Section and on the VLE.",
     "category": "academic", "pinned": False},
    {"id": 3, "title": "Hostel fee payment deadline",
     "body": "Hostel fees must be paid to the Finance Office by the end of this month.",
     "category": "hostel", "pinned": True},
    {"id": 4, "title": "Inter-department sports day",
     "body": "Registration for football and volleyball closes on Friday.",
     "category": "events", "pinned": False},
]


def notices_payload():
    if BASELINE:
        # 1.0.0: only id, title and body
        return {"notices": [{k: n[k] for k in ("id", "title", "body")} for n in NOTICES]}
    items = [dict(n) for n in NOTICES]
    if FEATURE_PINNED:
        items.sort(key=lambda n: not n["pinned"])  # stable: pinned first, others keep order
    return {"pinnedFirst": FEATURE_PINNED, "notices": items}


def is_healthy():
    if BROKEN:
        return False
    return (time.monotonic() - START) >= WARMUP_SECONDS


class Handler(BaseHTTPRequestHandler):
    server_version = "NoticeBoard"
    # HTTP/1.0 (the default): the connection closes after every response, so no
    # keep-alive connection can stay pinned to a Pod that is being replaced.

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            if is_healthy():
                self._send(200, {"status": "ok"})
            else:
                self._send(503, {"status": "unhealthy" if BROKEN else "starting"})
        elif path == "/version":
            self._send(200, {"version": APP_VERSION, "student": STUDENT_ID,
                             "pod": socket.gethostname()})
        elif path == "/notices":
            self._send(200, notices_payload())
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        pass  # no per-request access log: the monitor alone makes 2 requests a second


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True

    def on_term(signum, _frame):
        print(f"signal {signum}: draining for {DRAIN_SECONDS}s", flush=True)
        threading.Timer(DRAIN_SECONDS, server.shutdown).start()

    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    print(f"notice-board {APP_VERSION} student={STUDENT_ID} port={PORT} "
          f"pinned={FEATURE_PINNED}", flush=True)
    server.serve_forever()
    server.server_close()
    print("stopped", flush=True)


if __name__ == "__main__":
    main()
