#!/usr/bin/env bash
# Installs Lua 5.1.5 (the dialect Civilization VI uses) into .tools/lua51 for offline tests.
# Idempotent: does nothing if the interpreter is already there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/.tools/lua51"

if [ ! -x "$TARGET/bin/lua" ]; then
  # --backend pip: works regardless of the installed uv version.
  pipx run --backend pip hererocks "$TARGET" -l 5.1 -r latest
fi

"$TARGET/bin/lua" -v
