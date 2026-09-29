#!/bin/bash
# arisrv Syncthing hub for CC memory sync: system unit, LAN-only, folder claude-memory,
# hub-only 30-day Trash Can versioning.
# Run after harden.sh, as root. Idempotent.
#   curl -fsSL https://raw.githubusercontent.com/Mahlski/arisrv-install/main/syncthing-hub.sh | sudo bash
# Afterwards pair each spoke with the printed device ID; spokes add this hub with a static
# address tcp://<hub-ip>:22000 (see the syncthing-cc-memory-sync runbook in the vault).
set -euo pipefail

USER_NAME=guido
HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
# Outside ~/.claude on purpose: claude-rc sessions get ~/.claude writable, and this path stays
# read-only to them under ProtectHome. A spoke's folder path is ~/.claude/projects; paths are per device.
ROOT="$HOME_DIR/sync/claude-memory"
# runuser keeps root's HOME; the cli finds ~/.local/state/syncthing via HOME.
as_user() { runuser -u "$USER_NAME" -- env HOME="$HOME_DIR" "$@"; }

pacman -S --needed --noconfirm syncthing

# .stignore must exist before the folder is added; it mirrors the spokes (memory only, no /tmp slugs).
# Name the parent too: install -d creates missing parents root-owned.
install -d -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/sync" "$ROOT"
if [ ! -f "$ROOT/.stignore" ]; then
  printf '%s\n' '/-tmp-*' '!**/memory' '!**/memory/**' '**' > "$ROOT/.stignore"
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
as_user syncthing cli config options natenabled set false
# Trash Can on the hub only: every spoke edit or delete arrives here as a received change,
# so the previous version survives 30 days. Spokes stay unversioned.
as_user syncthing cli config folders claude-memory versioning type set trashcan
as_user syncthing cli config folders claude-memory versioning params set cleanoutDays 30

echo "syncthing hub ready"
as_user syncthing cli show system | grep myID
