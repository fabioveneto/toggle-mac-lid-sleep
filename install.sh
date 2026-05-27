#!/usr/bin/env bash
# One-command install: sudoers + build + copy to /Applications
set -euo pipefail

echo "==> Installing sudoers rule (requires your password once)…"
sudo bash scripts/install-sudoers.sh

echo "==> Building Toggle Sleep.app…"
bash build.sh

echo "==> Copying to /Applications…"
cp -r "Toggle Sleep.app" /Applications/

echo ""
echo "Done. Launch with:"
echo "  open \"/Applications/Toggle Sleep.app\""
echo ""
echo "To add to Login Items: System Settings → General → Login Items → add Toggle Sleep."
