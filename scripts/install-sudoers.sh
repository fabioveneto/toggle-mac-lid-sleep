#!/usr/bin/env bash
# Run once with sudo: sudo bash scripts/install-sudoers.sh
set -euo pipefail

DEST=/etc/sudoers.d/toggle-sleep
TMP=$(mktemp)
WHOAMI=$(logname 2>/dev/null || echo "${SUDO_USER:-fabio}")

cat > "$TMP" <<EOF
# Toggle Sleep — passwordless sudo for exactly these commands
$WHOAMI ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
$WHOAMI ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
EOF

# Validate before installing — a broken sudoers file can lock out sudo entirely
visudo -cf "$TMP"

install -m 0440 -o root -g wheel "$TMP" "$DEST"
rm -f "$TMP"

echo "Installed $DEST for user: $WHOAMI"
echo "Verify with: sudo -n /usr/bin/pmset -a disablesleep 0"
