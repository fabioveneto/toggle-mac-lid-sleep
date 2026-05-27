#!/usr/bin/env bash
# Removes Toggle Sleep and restores default sleep behaviour.
# Run with sudo: sudo bash uninstall.sh
set -euo pipefail

echo "==> Quitting Toggle Sleep (if running)…"
pkill -f "Toggle Sleep" || true

echo "==> Restoring default sleep behaviour (disablesleep 0)…"
# Do this while the sudoers rule still exists so it runs without a password.
/usr/bin/pmset -a disablesleep 0

echo "==> Removing sudoers rule…"
rm -f /etc/sudoers.d/toggle-sleep

echo "==> Removing app from /Applications…"
rm -rf "/Applications/Toggle Sleep.app"

echo "==> Removing app preferences…"
defaults delete com.fabio.togglesleep 2>/dev/null || true

echo ""
echo "Done. Toggle Sleep has been fully removed."
