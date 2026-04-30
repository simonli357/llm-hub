#!/usr/bin/env python3
"""Codex compatibility gateway for llm-hub.

Codex uses the OpenAI Responses API and may include native OpenAI tool entries
such as image_generation or web_search. The local LiteLLM -> llama.cpp route
supports function tools, but llama.cpp rejects non-function tools. This gateway
keeps the normal OpenAI-compatible /v1 surface untouched while giving Codex a
dedicated /codex/v1 base URL that removes unsupported tool entries before
forwarding requests to LiteLLM.
"""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


HOST = os.environ.get("CODEX_PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("CODEX_PROXY_PORT", "4020"))
UPSTREAM_BASE_URL = os.environ.get(
    "CODEX_PROXY_UPSTREAM_BASE_URL",
    "http://127.0.0.1:4010",
).rstrip("/")
CODEX_PREFIX = os.environ.get("CODEX_PROXY_PATH_PREFIX", "/codex").rstrip("/")
SETUP_SCRIPT_PATH = os.environ.get(
    "CODEX_PROXY_SETUP_SCRIPT",
    "/app/setup-codex-cli.sh",
)


BASE_INSTRUCTIONS = (
    "You are Codex, a coding agent. Work carefully, use tools when useful, "
    "and keep responses concise."
)
MODEL_MESSAGES = {
    "instructions_template": BASE_INSTRUCTIONS + "\n\n{{ personality }}",
    "instructions_variables": {
        "personality_default": "",
        "personality_friendly": "",
        "personality_pragmatic": "",
    },
}


def _codex_model(
    slug: str,
    display_name: str,
    description: str,
    reasoning_description: str,
    priority: int,
) -> dict[str, object]:
    return {
        "slug": slug,
        "display_name": display_name,
        "description": description,
        "default_reasoning_level": "minimal",
        "supported_reasoning_levels": [
            {
                "effort": "minimal",
                "description": reasoning_description,
            }
        ],
        "shell_type": "shell_command",
        "visibility": "list",
        "supported_in_api": True,
        "priority": priority,
        "additional_speed_tiers": [],
        "availability_nux": None,
        "upgrade": None,
        "base_instructions": BASE_INSTRUCTIONS,
        "model_messages": MODEL_MESSAGES,
        "supports_reasoning_summaries": False,
        "default_reasoning_summary": "none",
        "support_verbosity": False,
        "default_verbosity": "low",
        "apply_patch_tool_type": "freeform",
        "web_search_tool_type": "text",
        "truncation_policy": {
            "mode": "tokens",
            "limit": 28000,
        },
        "supports_parallel_tool_calls": False,
        "supports_image_detail_original": False,
        "context_window": 32768,
        "max_context_window": 32768,
        "effective_context_window_percent": 85,
        "experimental_supported_tools": [],
        "input_modalities": ["text"],
        "supports_search_tool": False,
    }


CODEX_MODELS = {
    "models": [
        _codex_model(
            "qwen3.6-27b",
            "Local Qwen 27B",
            "Local Qwen3.6-27B through llm-hub, non-thinking mode.",
            "Use the non-thinking local model route.",
            100,
        ),
        _codex_model(
            "qwen3.6-27b-thinking",
            "Local Qwen 27B Thinking",
            "Local Qwen3.6-27B through llm-hub with llama.cpp thinking enabled.",
            "Thinking is controlled by this model alias.",
            101,
        ),
    ]
}


def _json_response(data: object) -> bytes:
    return json.dumps(data, separators=(",", ":")).encode("utf-8")


def _rewrite_path(path: str) -> str:
    parsed = urllib.parse.urlsplit(path)
    upstream_path = parsed.path
    if CODEX_PREFIX and upstream_path.startswith(CODEX_PREFIX + "/"):
        upstream_path = upstream_path[len(CODEX_PREFIX):]
    elif CODEX_PREFIX and upstream_path == CODEX_PREFIX:
        upstream_path = "/"
    return urllib.parse.urlunsplit(("", "", upstream_path, parsed.query, ""))


def _filter_responses_payload(body: bytes) -> bytes:
    if not body:
        return body

    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return body

    tools = payload.get("tools")
    if isinstance(tools, list):
        payload["tools"] = [
            tool
            for tool in tools
            if isinstance(tool, dict) and tool.get("type") == "function"
        ]

    return _json_response(payload)


def _header_csv_first(value: str | None) -> str | None:
    if not value:
        return None
    return value.split(",", 1)[0].strip() or None


def _looks_local_host(host: str) -> bool:
    name = host.split(":", 1)[0].strip("[]").lower()
    return (
        name in {"localhost", "127.0.0.1", "::1"}
        or name.startswith("10.")
        or name.startswith("192.168.")
        or any(name.startswith(f"172.{idx}.") for idx in range(16, 32))
    )


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        upstream_path = _rewrite_path(self.path)

        if upstream_path in ("/health", "/v1/health"):
            self._send_bytes(200, b"ok", "text/plain")
            return

        if upstream_path in ("/models", "/v1/models"):
            self._send_bytes(200, _json_response(CODEX_MODELS), "application/json")
            return

        if upstream_path == "/setup.sh":
            self._send_setup_script()
            return

        self._forward(upstream_path)

    def do_POST(self) -> None:
        self._forward(_rewrite_path(self.path))

    def _forward(self, upstream_path: str) -> None:
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""

        if upstream_path.endswith("/responses"):
            body = _filter_responses_payload(body)

        url = UPSTREAM_BASE_URL + upstream_path
        headers = {}
        for key in ("authorization", "content-type", "accept", "user-agent"):
            value = self.headers.get(key)
            if value:
                headers[key] = value

        req = urllib.request.Request(
            url,
            data=body if self.command != "GET" else None,
            headers=headers,
            method=self.command,
        )

        try:
            with urllib.request.urlopen(req, timeout=600) as response:
                self._send_upstream_response(response)
        except urllib.error.HTTPError as exc:
            self._send_upstream_response(exc)
        except Exception as exc:
            self._send_bytes(502, str(exc).encode("utf-8"), "text/plain")

    def _send_upstream_response(self, response) -> None:
        content_type = response.headers.get("content-type", "")
        is_event_stream = content_type.startswith("text/event-stream")

        self.send_response(response.status)
        for key, value in response.headers.items():
            if key.lower() in {
                "connection",
                "content-encoding",
                "content-length",
                "transfer-encoding",
            }:
                continue
            self.send_header(key, value)

        if is_event_stream:
            self.send_header("transfer-encoding", "chunked")
            self.end_headers()
            while True:
                chunk = response.read(8192)
                if not chunk:
                    break
                self.wfile.write(f"{len(chunk):x}\r\n".encode("ascii"))
                self.wfile.write(chunk)
                self.wfile.write(b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
            return

        data = response.read()
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_bytes(self, status: int, data: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_setup_script(self) -> None:
        try:
            with open(SETUP_SCRIPT_PATH, "r", encoding="utf-8") as handle:
                script = handle.read()
        except OSError as exc:
            self._send_bytes(404, str(exc).encode("utf-8"), "text/plain")
            return

        proto = (
            _header_csv_first(self.headers.get("x-forwarded-proto"))
            or _header_csv_first(self.headers.get("x-forwarded-protocol"))
            or "http"
        )
        host = (
            _header_csv_first(self.headers.get("x-forwarded-host"))
            or self.headers.get("host")
            or f"{HOST}:{PORT}"
        )
        if proto == "http" and not _looks_local_host(host):
            proto = "https"
        base_url = f"{proto}://{host}{CODEX_PREFIX}/v1"
        script = script.replace("__CODEX_LLM_HUB_BASE_URL__", base_url, 1)
        self._send_bytes(
            200,
            script.encode("utf-8"),
            "text/x-shellscript; charset=utf-8",
        )

    def log_message(self, fmt: str, *args) -> None:
        print(f"{self.address_string()} - {fmt % args}", file=sys.stderr)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Codex proxy listening on http://{HOST}:{PORT}{CODEX_PREFIX}/v1")
    print(f"Forwarding to {UPSTREAM_BASE_URL}/v1")
    server.serve_forever()


if __name__ == "__main__":
    main()
