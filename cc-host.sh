#!/bin/bash
# arisrv Claude Code host: Remote Control server under a sandboxed systemd user unit.
# Run after syncthing-hub.sh, as root. Idempotent; never overwrites existing settings or unit.
#   curl -fsSL https://raw.githubusercontent.com/Mahlski/arisrv-install/main/cc-host.sh | sudo bash
# Manual steps it cannot do are printed at the end (login, trust, Remote Control consent).
set -euo pipefail

USER_NAME=guido
HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
as_user() { runuser -u "$USER_NAME" -- env HOME="$HOME_DIR" "$@"; }

# bubblewrap, socat, ripgrep: CC Bash sandbox dependencies on Linux.
pacman -S --needed --noconfirm tmux bubblewrap socat ripgrep
loginctl enable-linger "$USER_NAME"

if [ ! -x "$HOME_DIR/.local/bin/claude" ]; then
  as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi
grep -q '\.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null ||
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME_DIR/.bashrc"

as_user mkdir -p "$HOME_DIR/work" "$HOME_DIR/drop/cc" "$HOME_DIR/.cache" \
  "$HOME_DIR/.local/share/claude" "$HOME_DIR/.local/state" "$HOME_DIR/.config/systemd/user"

# Keep arisrv's own sessions (~/work slugs) out of the synced memory folder.
STIGNORE="$HOME_DIR/.claude/projects/.stignore"
if [ -f "$STIGNORE" ] && ! grep -q '^/-home-guido-work\*' "$STIGNORE"; then
  sed -i '1i /-home-guido-work*' "$STIGNORE"
fi

# Deny rules guard the synced memory folders and config; the unit below enforces the rest.
SETTINGS="$HOME_DIR/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  as_user tee "$SETTINGS" >/dev/null <<'EOF'
{
  "permissions": {
    "defaultMode": "auto",
    "additionalDirectories": ["~/drop"],
    "deny": [
      "Edit(~/.claude.json)",
      "Edit(~/.claude/settings.json)",
      "Edit(~/.claude/.credentials.json)",
      "Edit(~/.claude/projects/.stignore)",
      "Edit(~/.claude/projects/-home-guido/**)",
      "Edit(~/.claude/projects/-home-guido-M*/**)",
      "Edit(~/.claude/projects/-home-guido-c*/**)",
      "Edit(~/.claude/projects/-home-guido-d*/**)",
      "Edit(~/.claude/projects/-home-guido-s*/**)",
      "Edit(~/.claude/projects/-tmp-*/**)",
      "Edit(~/.ssh/**)",
      "Edit(~/.config/**)",
      "Edit(~/.local/**)",
      "Edit(~/.bashrc)",
      "Edit(~/.bash_profile)",
      "Edit(~/backups/**)"
    ]
  },
  "model": "opus",
  "sandbox": {
    "enabled": true
  },
  "promptSuggestionEnabled": false,
  "awaySummaryEnabled": false,
  "theme": "dark",
  "autoCompactEnabled": false,
  "inputNeededNotifEnabled": true,
  "agentPushNotifEnabled": true
}
EOF
fi

# Permission deny rules cannot express "only ~/work and ~/drop", and auto mode lets the
# Write tool write elsewhere in $HOME; the read-only mounts below close that gap.
UNIT="$HOME_DIR/.config/systemd/user/claude-rc.service"
if [ ! -f "$UNIT" ]; then
  as_user tee "$UNIT" >/dev/null <<'EOF'
[Unit]
Description=Claude Code Remote Control server (arisrv)

[Service]
WorkingDirectory=%h/work
ExecStart=%h/.local/bin/claude remote-control --spawn same-dir --permission-mode auto --name arisrv
Restart=always
RestartSec=30
# Sessions may write only here; the rest of the filesystem is read-only.
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
ReadWritePaths=%h/.claude.json %h/work %h/drop %h/.claude %h/.cache %h/.local/share/claude %h/.local/state

[Install]
WantedBy=default.target
EOF
fi

cat <<'EOF'

Done. Finish as guido, from a machine with a browser:
  ssh -t guido@<ip> '~/.local/bin/claude auth login'            # open URL, paste code
  ssh -t guido@<ip> 'cd ~/work && ~/.local/bin/claude'          # accept trust, /exit
  ssh -t guido@<ip> 'cd ~/work && ~/.local/bin/claude remote-control'  # answer y, Ctrl+C
  ssh guido@<ip> 'systemctl --user enable --now claude-rc.service'
EOF
