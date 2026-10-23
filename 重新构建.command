#!/bin/zsh
set -e
S1_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 "$S1_PROJECT_DIR/scripts/build.py"
echo '构建与离线自检已完成。按回车退出。'
read
