#!/usr/bin/env python3
import http.server
import os
import platform
import subprocess
import time
import urllib.parse
from typing import Optional, Set, Tuple


def log(message: str) -> None:
    print(f"[plannotator-opener] {message}", flush=True)


def get_tailscale_ip() -> Optional[str]:
    explicit = os.environ.get("PLANNOTATOR_LISTENER_HOST")
    if explicit:
        return explicit

    commands = [
        ["tailscale", "ip", "-4"],
        ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "ip", "-4"],
    ]
    for command in commands:
        try:
            result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)
        except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            continue
        ip = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""
        if ip:
            return ip
    return None


def parse_allowed_hosts() -> Set[str]:
    host = os.environ.get("PLANNOTATOR_TAILNET_HOST", "devbox")
    suffix = os.environ.get("PLANNOTATOR_TAILNET_SUFFIX", "").strip().strip(".")
    extra = os.environ.get("PLANNOTATOR_ALLOWED_HOSTS", "")
    hosts = {host}
    if suffix and "." not in host:
        hosts.add(f"{host}.{suffix}")
    hosts.update(h.strip() for h in extra.split(",") if h.strip())
    return {h.lower().rstrip(".") for h in hosts}


def parse_port_range() -> Tuple[int, int]:
    base = int(os.environ.get("PLANNOTATOR_PORT_BASE", "19432"))
    count = int(os.environ.get("PLANNOTATOR_PORT_COUNT", "16"))
    return base, base + count - 1


ALLOWED_HOSTS = parse_allowed_hosts()
PORT_MIN, PORT_MAX = parse_port_range()


def is_allowed_url(raw_url: str) -> Tuple[bool, str]:
    try:
        parsed = urllib.parse.urlparse(raw_url)
    except ValueError as exc:
        return False, f"invalid URL: {exc}"

    if parsed.scheme not in {"http", "https"}:
        return False, "scheme must be http or https"

    host = (parsed.hostname or "").lower().rstrip(".")
    if not host:
        return False, "missing host"

    try:
        port = parsed.port
    except ValueError as exc:
        return False, f"invalid port: {exc}"

    if parsed.scheme == "https":
        return True, "ok"

    if host not in ALLOWED_HOSTS:
        return False, f"host {host!r} not allowed"

    if port is None or not (PORT_MIN <= port <= PORT_MAX):
        return False, f"port must be in {PORT_MIN}-{PORT_MAX}"

    return True, "ok"


def open_url(raw_url: str) -> None:
    if platform.system() == "Darwin":
        subprocess.Popen(["open", raw_url])
    elif platform.system() == "Windows":
        subprocess.Popen(["cmd", "/c", "start", "", raw_url])
    else:
        subprocess.Popen(["xdg-open", raw_url])


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "PlannotatorOpener/1.0"

    def log_message(self, format: str, *args: object) -> None:
        log(f"{self.address_string()} - {format % args}")

    def do_GET(self) -> None:
        self.handle_open()

    def do_POST(self) -> None:
        self.handle_open()

    def handle_open(self) -> None:
        parsed_path = urllib.parse.urlparse(self.path)
        if parsed_path.path != "/open":
            self.send_response(404)
            self.end_headers()
            return

        params = urllib.parse.parse_qs(parsed_path.query)
        if self.command == "POST":
            length = int(self.headers.get("Content-Length", "0") or "0")
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            params.update(urllib.parse.parse_qs(body))

        raw_url = params.get("url", [""])[0]
        allowed, reason = is_allowed_url(raw_url)
        if not allowed:
            log(f"rejected {raw_url!r}: {reason}")
            self.send_response(403)
            self.end_headers()
            self.wfile.write(reason.encode("utf-8"))
            return

        log(f"opening {raw_url}")
        open_url(raw_url)
        self.send_response(204)
        self.end_headers()


def main() -> int:
    port = int(os.environ.get("PLANNOTATOR_OPENER_PORT", "19500"))
    while True:
        bind_host = get_tailscale_ip()
        if bind_host:
            break
        log("waiting for Tailscale IP...")
        time.sleep(5)

    server = http.server.ThreadingHTTPServer((bind_host, port), Handler)
    log(f"listening on http://{bind_host}:{port}/open; allowed_hosts={sorted(ALLOWED_HOSTS)} ports={PORT_MIN}-{PORT_MAX}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
