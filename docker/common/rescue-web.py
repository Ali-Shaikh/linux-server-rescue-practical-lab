#!/usr/bin/env python3
"""Small local service used as an observable rescue target."""

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path not in {"/", "/health"}:
            self.send_error(404)
            return

        body = json.dumps(
            {
                "service": "rescue-web",
                "host": os.uname().nodename,
                "distribution": os.environ.get("LAB_DISTRO", "unknown"),
                "status": "healthy",
            }
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, message: str, *args: object) -> None:
        print(f"{self.address_string()} {message % args}", flush=True)


def main() -> None:
    port = int(os.environ.get("APP_PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"rescue-web listening on port {port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
