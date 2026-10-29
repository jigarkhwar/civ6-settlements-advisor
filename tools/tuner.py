#!/usr/bin/env python3
"""Own FireTuner client for Civilization VI (the macOS build writes no Lua.log).

Protocol facts (community knowledge, verified on 1.0.12.x):
  frame   = uint32 LE payload length | uint32 LE tag | payload (UTF-8, NUL-terminated)
  tag 4   handshake: "APP:" -> app id; "LSQ:" -> "idx\\0name\\0idx\\0name..."
  tag 3   command:   "CMD:<state idx>:<lua>"
  tag 0xFFFFFFFF output: "O\\0<state>: <text>\\0"
The game accepts one tuner client at a time, so `serve` owns the connection and other
commands go through it when it runs. Requires `EnableTuner 1` in AppOptions.txt; this
tool never edits that file.

Commands:
  serve                         keep the connection, log output to logs/tuner.log
  states                        list Lua states
  exec [-s STATE] CODE | -f F   run Lua; prints its output; JSON after "SA_JSON:" is decoded
  assert [-s STATE] EXPR WANT   evaluate a Lua expression, compare tostring(result) with WANT
Exit codes: 0 ok, 1 Lua error or failed assert, 2 connection problem, 3 timeout.
"""

import argparse
import datetime
import json
import os
import queue
import socket
import socketserver
import struct
import sys
import threading
import time
import uuid

HOST = "127.0.0.1"
GAME_PORT = 4318
CONTROL_PORT = 43181
TAG_COMMAND, TAG_HANDSHAKE, TAG_OUTPUT = 3, 4, 0xFFFFFFFF
HEADER = struct.Struct("<II")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(ROOT, "logs", "tuner.log")
DEFAULT_STATE = "SA_Main"


class TunerError(Exception):
    pass


class Game:
    """One connection to the game's tuner port."""

    def __init__(self, on_output=None):
        self.sock = None
        self.states = {}
        self.lines = queue.Queue()
        self.handshake = queue.Queue()
        self.on_output = on_output
        self.lock = threading.Lock()

    def connect(self, timeout=5.0):
        try:
            self.sock = socket.create_connection((HOST, GAME_PORT), timeout=timeout)
        except OSError as e:
            raise TunerError(
                f"cannot connect to {HOST}:{GAME_PORT} ({e}). Is the game running with "
                "EnableTuner 1 in AppOptions.txt?") from e
        self.sock.settimeout(None)
        threading.Thread(target=self._reader, daemon=True).start()
        try:
            self._send(TAG_HANDSHAKE, "APP:")
            self.handshake.get(timeout=timeout)
            self._send(TAG_HANDSHAKE, "LSQ:")
            parts = self.handshake.get(timeout=timeout)
        except queue.Empty as e:
            raise TunerError("the game did not answer the handshake (another tuner client connected?)") from e
        self.states = {}
        for i in range(0, len(parts) - 1, 2):
            if parts[i].isdigit():
                self.states[parts[i + 1]] = int(parts[i])

    def _send(self, tag, text):
        data = text.encode("utf-8") + b"\0"
        with self.lock:
            self.sock.sendall(HEADER.pack(len(data), tag) + data)

    def _read_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise TunerError("connection closed by the game")
            buf += chunk
        return buf

    def _reader(self):
        try:
            while True:
                length, tag = HEADER.unpack(self._read_exact(HEADER.size))
                payload = self._read_exact(length).decode("utf-8", "replace")
                parts = [p for p in payload.split("\0")]
                if tag == TAG_OUTPUT:
                    text = "\0".join(parts[1:]).rstrip("\0") if parts and parts[0] == "O" else payload
                    for line in text.split("\n"):
                        self.lines.put(line)
                        if self.on_output:
                            self.on_output(line)
                elif tag == TAG_HANDSHAKE:
                    self.handshake.put([p for p in parts if p != ""])
        except (TunerError, OSError):
            self.lines.put(None)

    def run(self, state, code, timeout=30.0):
        """Runs code in a Lua state and returns (ok, printed lines between markers)."""
        if state not in self.states:
            raise TunerError(f"no Lua state {state!r}; known: {', '.join(sorted(self.states))}")
        nonce = uuid.uuid4().hex[:8]
        wrapped = (
            f'print("SA_BEGIN:{nonce}") '
            f'local ok, err = pcall(function() {code}\nend) '
            f'if not ok then print("SA_ERROR:" .. tostring(err)) end '
            f'print("SA_END:{nonce}")'
        )
        self._send(TAG_COMMAND, f"CMD:{self.states[state]}:{wrapped}")
        out, inside, ok = [], False, True
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self.lines.get(timeout=max(0.1, deadline - time.time()))
            except queue.Empty:
                break
            if line is None:
                raise TunerError("connection closed by the game")
            body = line.split(": ", 1)[1] if ": " in line else line
            if body == f"SA_BEGIN:{nonce}":
                inside = True
            elif body == f"SA_END:{nonce}":
                return ok, out
            elif inside:
                if body.startswith("SA_ERROR:"):
                    ok = False
                out.append(body)
        raise TimeoutError("no answer from the game")


def log_line(line):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    stamp = datetime.datetime.now().isoformat(timespec="milliseconds")
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"{stamp} {line}\n")


def serve():
    game = Game(on_output=log_line)
    game.connect()
    print(f"connected; states: {', '.join(sorted(game.states))}; control port {CONTROL_PORT}")

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            req = json.loads(self.rfile.readline().decode("utf-8"))
            try:
                if req["cmd"] == "states":
                    resp = {"ok": True, "states": game.states}
                else:
                    ok, out = game.run(req["state"], req["code"], req.get("timeout", 30.0))
                    resp = {"ok": ok, "out": out}
            except (TunerError, TimeoutError) as e:
                resp = {"ok": False, "error": str(e)}
            self.wfile.write((json.dumps(resp) + "\n").encode("utf-8"))

    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer((HOST, CONTROL_PORT), Handler) as srv:
        srv.serve_forever()


def via_daemon(req):
    try:
        with socket.create_connection((HOST, CONTROL_PORT), timeout=2.0) as s:
            s.settimeout(req.get("timeout", 30.0) + 5.0)
            s.sendall((json.dumps(req) + "\n").encode("utf-8"))
            data = b""
            while not data.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
            return json.loads(data.decode("utf-8"))
    except OSError:
        return None


def request(req):
    resp = via_daemon(req)
    if resp is not None:
        return resp
    game = Game()
    game.connect()
    if req["cmd"] == "states":
        return {"ok": True, "states": game.states}
    ok, out = game.run(req["state"], req["code"], req.get("timeout", 30.0))
    return {"ok": ok, "out": out}


def print_out(lines):
    for line in lines:
        if line.startswith("SA_JSON:"):
            try:
                print(json.dumps(json.loads(line[len("SA_JSON:"):]), ensure_ascii=False, indent=2))
                continue
            except json.JSONDecodeError:
                pass
        print(line)


def main():
    ap = argparse.ArgumentParser(description="FireTuner client for Settlements Advisor")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("serve")
    sub.add_parser("states")
    ex = sub.add_parser("exec")
    ex.add_argument("-s", "--state", default=DEFAULT_STATE)
    ex.add_argument("-f", "--file")
    ex.add_argument("code", nargs="?")
    ex.add_argument("--timeout", type=float, default=30.0)
    asr = sub.add_parser("assert")
    asr.add_argument("-s", "--state", default=DEFAULT_STATE)
    asr.add_argument("expr")
    asr.add_argument("want")
    args = ap.parse_args()

    try:
        if args.cmd == "serve":
            serve()
            return 0
        if args.cmd == "states":
            resp = request({"cmd": "states"})
            for name, idx in sorted(resp["states"].items(), key=lambda kv: kv[1]):
                print(idx, name)
            return 0
        if args.cmd == "exec":
            code = open(args.file, encoding="utf-8").read() if args.file else args.code
            if not code:
                ap.error("exec needs CODE or -f FILE")
            resp = request({"cmd": "exec", "state": args.state, "code": code, "timeout": args.timeout})
            if "error" in resp:
                raise TunerError(resp["error"])
            print_out(resp["out"])
            return 0 if resp["ok"] else 1
        if args.cmd == "assert":
            code = f'print("SA_VALUE:" .. tostring({args.expr}))'
            resp = request({"cmd": "exec", "state": args.state, "code": code})
            if "error" in resp:
                raise TunerError(resp["error"])
            got = next((l[len("SA_VALUE:"):] for l in resp["out"] if l.startswith("SA_VALUE:")), None)
            if resp["ok"] and got == args.want:
                print(f"ok: {args.expr} == {args.want}")
                return 0
            print(f"FAIL: {args.expr} -> {got!r}, want {args.want!r}; output: {resp['out']}")
            return 1
    except TunerError as e:
        print(f"tuner: {e}", file=sys.stderr)
        return 2
    except TimeoutError as e:
        print(f"tuner: {e}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
