#!/usr/bin/env bash
# Links the mod into the game's Mods folder and validates its XML files.
# Refuses to replace a real folder with the same name (only a symlink is managed here).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/SettlementsAdvisor"
MODS="$HOME/Library/Application Support/Sid Meier's Civilization VI/Sid Meier's Civilization VI/Mods"
DEST="$MODS/SettlementsAdvisor"

status=0
while IFS= read -r -d '' f; do
  if ! xmllint --noout "$f"; then status=1; fi
done < <(find "$SRC" \( -name '*.xml' -o -name '*.modinfo' \) -print0)
if [ "$status" -ne 0 ]; then
  echo "XML validation failed" >&2
  exit 1
fi
echo "XML ok"

if [ ! -d "$MODS" ]; then
  echo "Mods folder not found: $MODS" >&2
  exit 1
fi

if [ -L "$DEST" ]; then
  if [ "$(readlink "$DEST")" != "$SRC" ]; then
    echo "Symlink points elsewhere: $DEST -> $(readlink "$DEST")" >&2
    exit 1
  fi
  echo "Link ok: $DEST"
elif [ -e "$DEST" ]; then
  echo "A real folder exists at $DEST; not touching it" >&2
  exit 1
else
  ln -s "$SRC" "$DEST"
  echo "Linked: $DEST -> $SRC"
fi
