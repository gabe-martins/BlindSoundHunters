#!/usr/bin/env bash
# Runs every static check and the mocked state-machine test.
# Requires lua5.1 (with luac5.1) and python3.
set -euo pipefail
cd "$(dirname "$0")/.."

MOD=Contents/mods/BlindSoundHunters

echo "== luac5.1 -p (syntax)"
luac5.1 -p $(find "$MOD/42/media/lua" -name '*.lua')
echo "OK"

echo "== dev/audit.py (Kahlua tokens + translations)"
python3 -I dev/audit.py .

echo "== dev/smoke.lua (state machine, mocked game API)"
lua5.1 dev/smoke.lua "$MOD/42/media/lua"
