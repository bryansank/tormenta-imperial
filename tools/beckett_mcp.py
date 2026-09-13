"""Cliente MCP mínimo sobre HTTP para el servidor de Beckett embebido en el editor de Godot.

Uso (con el editor abierto y el plugin activo):
    python tools/beckett_mcp.py __list__
    python tools/beckett_mcp.py get_play_state
    python tools/beckett_mcp.py game_logs '{"level":"warning"}'
    python tools/beckett_mcp.py screenshot '{"target":"game"}' --png captura.png

Sirve como respaldo cuando la sesión de Claude Code no arrancó dentro de la carpeta
del proyecto (los MCP de .mcp.json solo se cargan al inicio de la sesión).
El token y el puerto se leen de .beckett/, que git ignora.
"""
import base64
import json
import sys
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
_BECKETT = ROOT / ".beckett"
PORT = (_BECKETT / "port").read_text().strip() if (_BECKETT / "port").exists() else "8770"
TOKEN = (_BECKETT / "token").read_text().strip()
URL = f"http://127.0.0.1:{PORT}/mcp/{TOKEN}"
_session = {"id": None}


def rpc(method, params=None, req_id=1, timeout=120):
    payload = {"jsonrpc": "2.0", "id": req_id, "method": method}
    if params is not None:
        payload["params"] = params
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if _session["id"]:
        headers["Mcp-Session-Id"] = _session["id"]
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        sid = resp.headers.get("Mcp-Session-Id")
        if sid:
            _session["id"] = sid
        body = resp.read().decode("utf-8", "replace")
    if not body.strip():
        return None
    if body.startswith("event:") or "\ndata:" in body:
        for line in body.splitlines():
            if line.startswith("data:"):
                body = line[5:].strip()
                break
    return json.loads(body)


def connect():
    rpc("initialize", {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "beckett-bridge", "version": "1.0"},
    })
    rpc("notifications/initialized")


def call(tool, args=None, timeout=120):
    return rpc("tools/call", {"name": tool, "arguments": args or {}}, timeout=timeout)


def text_of(res):
    if not res:
        return ""
    out = []
    for block in res.get("result", {}).get("content", []):
        if block.get("type") == "text":
            out.append(block.get("text", ""))
        else:
            out.append(f"<{block.get('type')}: {len(block.get('data', ''))} bytes>")
    if not out and "error" in res:
        return "ERROR: " + json.dumps(res["error"])[:500]
    return "\n".join(out)


def save_png(res, path):
    for block in res.get("result", {}).get("content", []):
        if block.get("type") == "image":
            Path(path).write_bytes(base64.b64decode(block["data"]))
            return True
    return False


if __name__ == "__main__":
    connect()
    tool = sys.argv[1]
    argv = sys.argv[2:]
    png = None
    if "--png" in argv:
        i = argv.index("--png")
        png = argv[i + 1]
        del argv[i:i + 2]
    args = json.loads(argv[0]) if argv else {}
    if tool == "__list__":
        for t in rpc("tools/list", {})["result"]["tools"]:
            print(f"{t['name']}: {t.get('description', '')[:110]}")
    else:
        res = call(tool, args)
        if png and save_png(res, png):
            print(f"guardado {png}")
        print(text_of(res))
