#!/bin/zsh
set -e
S1_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
S1_PYTHON_PATH="$S1_PROJECT_DIR/dist/S1 Voice Bridge.app/Contents/Resources/python/bin/python3.12"
if [[ ! -x "$S1_PYTHON_PATH" ]]; then
  S1_PYTHON_PATH="$(cat "$S1_PROJECT_DIR/dist/S1 Voice Bridge.app/Contents/Resources/python-path.txt")"
fi
cd "$S1_PROJECT_DIR"
"$S1_PYTHON_PATH" -m unittest discover -s tests -v
"$S1_PROJECT_DIR/dist/S1 Voice Bridge.app/Contents/MacOS/S1VoiceBridge" --self-test
echo '离线自检完成；这不代表 S1 真机链路已通过。按回车退出。'
read
