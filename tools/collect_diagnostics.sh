#!/usr/bin/env bash
# Collects what a bug report needs into one zip (macOS): the mod's log from tools/tuner.py,
# the game's logs, the newest saves, recent crash reports and the mod's state.
# Usage: tools/collect_diagnostics.sh [saves-count]   (default 2: newest quick/auto/manual saves)
# Output: logs/diagnostics-YYYYmmdd-HHMMSS.zip — attach it to the issue.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAVES_COUNT="${1:-2}"
GAME="$HOME/Library/Application Support/Sid Meier's Civilization VI"
LOGS="$GAME/Firaxis Games/Sid Meier's Civilization VI/Logs"
APPOPTIONS="$GAME/Firaxis Games/Sid Meier's Civilization VI/AppOptions.txt"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/logs/diagnostics-$STAMP"
mkdir -p "$OUT/game-logs" "$OUT/saves" "$OUT/crashes"

# Newest files first: find under the given roots, print paths by modification time.
newest() { # count name-pattern roots...
  local count="$1" pattern="$2"; shift 2
  find "$@" -type f -name "$pattern" -print0 2>/dev/null \
    | xargs -0 stat -f '%m%t%N' 2>/dev/null | sort -rn | head -n "$count" | cut -f2-
}

# 1. The mod's own log (print output of every Lua state, written by `tools/tuner.py serve`).
if [ -f "$ROOT/logs/tuner.log" ]; then
  cp "$ROOT/logs/tuner.log" "$OUT/tuner.log"
  grep -a -E "SA_(ERROR|SLOW|READY|DMT|PINS|PLAZA|MISMATCH)" "$ROOT/logs/tuner.log" | tail -n 300 > "$OUT/tuner-SA-lines.txt"
else
  echo "logs/tuner.log not found: start 'python3 -I tools/tuner.py serve' before playing" > "$OUT/tuner-MISSING.txt"
fi

# 2. The game's logs (Lua.log exists only where the game writes it, e.g. Windows).
for f in Lua.log Modding.log UserInterface.log Database.log Startup.log Engine.log UIWarnings.csv GameCoreAppConfig.log; do
  [ -f "$LOGS/$f" ] && cp "$LOGS/$f" "$OUT/game-logs/"
done

# 3. Newest saves (both save folders: the game uses one of them depending on the install).
newest "$SAVES_COUNT" "*.Civ6Save" "$GAME/Saves" "$GAME/Sid Meier's Civilization VI/Saves" \
  | while IFS= read -r f; do cp "$f" "$OUT/saves/"; done

# 4. Crash reports of the game from the last 2 days.
find "$HOME/Library/Logs/DiagnosticReports" -name "Civ6*" -mtime -2 -print0 2>/dev/null \
  | xargs -0 -I{} cp "{}" "$OUT/crashes/" 2>/dev/null

# 5. Versions and settings.
{
  echo "collected: $(date)"
  echo "macOS: $(sw_vers -productVersion 2>/dev/null)"
  echo "mod commit: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
  echo "mod local changes:"; git -C "$ROOT" status --short 2>/dev/null | sed 's/^/  /'
  echo "mod link: $(readlink "$GAME/Sid Meier's Civilization VI/Mods/SettlementsAdvisor" 2>/dev/null || echo 'not a link')"
  echo "AppOptions:"; grep -a -E "EnableTuner|RenderWidth|RenderHeight" "$APPOPTIONS" 2>/dev/null | tr -d '\r' | sed 's/^/  /'
  echo "game running: $(pgrep -q Civ6_Exe_Child && echo yes || echo no)"
  echo "enabled mods (Modding.log):"; grep -a -i -E "detailed map tacks|settlements advisor" "$LOGS/Modding.log" 2>/dev/null | tail -n 5 | sed 's/^/  /'
} > "$OUT/info.txt"

# 6. The mod's state in the running game (needs EnableTuner 1; skipped otherwise).
if pgrep -q Civ6_Exe_Child; then
  python3 -I "$ROOT/tools/tuner.py" exec -s SA_Main --timeout 5 '
    local pid = Game.GetLocalPlayer()
    print("turn " .. tostring(Game.GetCurrentGameTurn()))
    print("pins record " .. tostring(PlayerConfigurations[pid]:GetValue("SA_Pins")))
    print("jobs pending " .. tostring(SA_Scheduler.Pending()) .. ", last error " .. tostring(SA_Scheduler.LastError()))
    local u = UI.GetHeadSelectedUnit()
    if u then print("selected unit " .. tostring(GameInfo.Units[u:GetUnitType()].UnitType) .. " at " .. u:GetX() .. "," .. u:GetY()) end
  ' > "$OUT/state.txt" 2> "$OUT/state-error.txt" \
    || echo "tuner not reachable: in a loaded game, restart 'python3 -I tools/tuner.py serve' (it keeps a stale connection after the game restarts)" >> "$OUT/state.txt"
  [ -s "$OUT/state-error.txt" ] || rm -f "$OUT/state-error.txt"
fi

(cd "$ROOT/logs" && zip -qr "diagnostics-$STAMP.zip" "diagnostics-$STAMP") && rm -rf "$OUT"
echo "$ROOT/logs/diagnostics-$STAMP.zip"
du -h "$ROOT/logs/diagnostics-$STAMP.zip" | cut -f1
