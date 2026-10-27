#!/bin/zsh
set -e
S1_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
if [[ -x "$S1_PROJECT_DIR/releases/v0.3.0/S1 Voice Bridge.app/Contents/MacOS/S1VoiceBridge" ]]; then
  open "$S1_PROJECT_DIR/releases/v0.3.0/S1 Voice Bridge.app"
  exit 0
fi
if [[ ! -x "$S1_PROJECT_DIR/dist/S1 Voice Bridge.app/Contents/MacOS/S1VoiceBridge" ]]; then
  python3 "$S1_PROJECT_DIR/scripts/build.py"
fi
open "$S1_PROJECT_DIR/dist/S1 Voice Bridge.app"
