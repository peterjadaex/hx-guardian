#!/bin/zsh
# HX-Guardian Development Start Script
# Starts the server WITHOUT LaunchDaemon (runner must be started separately as root).
#
# Terminal 1 (root — runner):
#   sudo python3 app/backend/hxg_runner.py
#
# Terminal 2 (admin — server):
#   zsh app/start-dev.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$APP_DIR/backend"

export PYTHONPATH="$BACKEND_DIR"
export PATH="/Users/admin/Library/Python/3.9/bin:/opt/homebrew/bin:$PATH"

echo "Starting HX-Guardian web server..."
echo "Dashboard: http://127.0.0.1:8000"
echo "API docs:  http://127.0.0.1:8000/api/docs"
echo ""

cd "$BACKEND_DIR"
python3 -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
