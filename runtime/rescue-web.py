#!/usr/bin/env python3
"""Small local service used as an observable rescue target."""

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    service_name = "rescue-web"

    def do_GET(self) -> None:
        if self.path not in {"/", "/health"}:
            self.send_error(404)
            return

        body = json.dumps(
            {
                "service": self.service_name,
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
    config_path = Path(os.environ.get("APP_CONFIG", "/etc/rescue-web/config.json"))
    with config_path.open(encoding="utf-8") as config_file:
        config = json.load(config_file)

    if not isinstance(config, dict):
        raise ValueError("application configuration must be a JSON object")

    service_name = config.get("service_name")
    listen_port = config.get("listen_port")
    bind_host = config.get("bind_host")
    if not isinstance(service_name, str) or not service_name:
        raise ValueError("service_name must be a non-empty string")
    if isinstance(listen_port, bool) or not isinstance(listen_port, int):
        raise ValueError("listen_port must be an integer")
    if not 1 <= listen_port <= 65535:
        raise ValueError("listen_port must be between 1 and 65535")
    if not isinstance(bind_host, str) or not bind_host:
        raise ValueError("bind_host must be a non-empty string")

    Handler.service_name = service_name
    port = int(os.environ.get("APP_PORT", str(listen_port)))
    host = os.environ.get("APP_HOST", bind_host)
    data_dir = Path(os.environ.get("APP_DATA_DIR", "/var/lib/rescue-web"))
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "last-startup").write_text(
        f"pid={os.getpid()}\n",
        encoding="utf-8",
    )
    # Docker publishes this container listener only on the host loopback address.
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"rescue-web listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
