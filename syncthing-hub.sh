#!/bin/bash
# arisrv Syncthing hub for CC memory sync: system unit, LAN-only, folder claude-memory.
# Run after harden.sh, as root. Idempotent.
#   curl -fsSL https://raw.githubusercontent.com/Mahlski/arisrv-install/main/syncthing-hub.sh | sudo bash
# Afterwards pair each spoke with the printed device ID; spokes add this hub with a static
# address tcp://<hub-ip>:22000 (see the syncthing-cc-memory-sync runbook in the vault).
set -euo pipefail

USER_NAME=guido
HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
ROOT="$HOME_DIR/.claude/projects"
# runuser keeps root's HOME; the cli finds ~/.local/state/syncthing via HOME.
as_user() { runuser -u "$USER_NAME" -- env HOME="$HOME_DIR" "$@"; }

pacman -S --needed --noconfirm syncthing

# .stignore must exist before the folder is added, or the first scan indexes transcripts.
install -d -o "$USER_NAME" -g "$USER_NAME" "$ROOT"
if [ ! -f "$ROOT/.stignore" ]; then
  printf '%s\n' '/-home-guido-work*' '!**/memory' '!**/memory/**' '**' > "$ROOT/.stignore"
  chown "$USER_NAME:$USER_NAME" "$ROOT/.stignore"
fi

systemctl enable --now "syncthing@$USER_NAME"

# Wait for the REST API (config.xml + apikey appear on first start).
for _ in $(seq 1 30); do
  as_user syncthing cli show system >/dev/null 2>&1 && break
  sleep 1
done

if ! as_user syncthing cli config folders list | grep -qx claude-memory; then
  as_user syncthing cli config folders add --id claude-memory --label "Claude Memory" --path "$ROOT"
fi
as_user syncthing cli config options global-ann-enabled set false
as_user syncthing cli config options relays-enabled set false

echo "syncthing hub ready"
as_user syncthing cli show system | grep myID
