#!/bin/zsh
# HX-Guardian — Restart all services
# Run: sudo zsh app/restart.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"

zsh "$APP_DIR/stop.sh"
echo ""
zsh "$APP_DIR/start.sh"
