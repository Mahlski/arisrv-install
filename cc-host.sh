#!/bin/bash
# arisrv Claude Code host: Remote Control server under a sandboxed systemd user unit.
# Run after syncthing-hub.sh, as root, from a clone (needs ./cc). Idempotent; never overwrites
# the unit, and only merges repo keys into existing settings.
#   git clone https://github.com/Mahlski/arisrv-install && sudo bash arisrv-install/cc-host.sh
# Manual steps it cannot do are printed at the end (login, trust, Remote Control consent).
set -euo pipefail

USER_NAME=guido
REPO=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)
[ -d "$REPO/cc" ] || { echo "cc/ not found next to cc-host.sh; run from a clone" >&2; exit 1; }
HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
as_user() { runuser -u "$USER_NAME" -- env HOME="$HOME_DIR" "$@"; }

# bubblewrap, socat, ripgrep: CC Bash sandbox dependencies on Linux. jq: settings merge,
# hook, statusline. nodejs: caveman plugin (a JS package).
pacman -S --needed --noconfirm tmux bubblewrap socat ripgrep jq nodejs
loginctl enable-linger "$USER_NAME"

if [ ! -x "$HOME_DIR/.local/bin/claude" ]; then
  as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi
grep -q '\.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null ||
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME_DIR/.bashrc"

as_user mkdir -p "$HOME_DIR/work" "$HOME_DIR/drop/cc" "$HOME_DIR/.cache" \
  "$HOME_DIR/.local/share/claude" "$HOME_DIR/.local/state/claude" "$HOME_DIR/.config/systemd/user"

# Deny rules guard config; the synced memory lives outside ~/.claude (syncthing-hub.sh) and the
# unit below keeps it read-only.
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

# Repo-owned global config: skill, statusline, SessionStart hook, CLAUDE.md. Overwritten
# on every run; edit in the repo, not on the box.
CC="$HOME_DIR/.claude"
for f in "$REPO"/cc/skills/grill-me/*; do
  as_user install -D -m 644 "$f" "$CC/skills/grill-me/${f##*/}"
done
as_user install -D -m 755 "$REPO/cc/statusline-command.sh" "$CC/statusline-command.sh"
as_user install -D -m 755 "$REPO/cc/hooks/session-start-arisrv.sh" "$CC/hooks/session-start-arisrv.sh"
as_user install -D -m 644 "$REPO/cc/CLAUDE.md" "$CC/CLAUDE.md"

# Deep-merge repo keys into settings.json; only rewrite (and back up) on a real change.
# jq `*` replaces arrays: merge's hooks.SessionStart wins, fine as arisrv has no other hooks.
# Deny edits to the auto-run config above: hooks and statusline run outside the Bash sandbox.
MERGED=$(jq -s '.[0] * .[1] | .permissions.deny = ((.permissions.deny // []) + [
  "Edit(~/.claude/hooks/**)", "Edit(~/.claude/statusline-command.sh)",
  "Edit(~/.claude/CLAUDE.md)", "Edit(~/.claude/skills/**)", "Edit(~/.claude/plugins/**)"
] | unique)' "$SETTINGS" "$REPO/cc/settings.merge.json")
if [ "$MERGED" != "$(jq . "$SETTINGS")" ]; then
  BAK="$SETTINGS.bak-$(date +%F)"
  [ -e "$BAK" ] || as_user cp -p "$SETTINGS" "$BAK"
  printf '%s\n' "$MERGED" | as_user tee "$SETTINGS.tmp" >/dev/null
  as_user mv "$SETTINGS.tmp" "$SETTINGS"
fi

# caveman plugin: marketplace + user-scope install; the list checks keep reruns quiet.
# Lists are captured first: `| grep -q` under pipefail can SIGPIPE the producer and misfire.
CLAUDE="$HOME_DIR/.local/bin/claude"
MKTS=$(as_user "$CLAUDE" plugin marketplace list 2>/dev/null || true)
grep -q 'JuliusBrussee/caveman' <<<"$MKTS" ||
  as_user "$CLAUDE" plugin marketplace add JuliusBrussee/caveman ||
  echo "caveman marketplace add failed; rerun after 'claude auth login'" >&2
PLUGINS=$(as_user "$CLAUDE" plugin list 2>/dev/null || true)
grep -q 'caveman@caveman' <<<"$PLUGINS" ||
  as_user "$CLAUDE" plugin install caveman@caveman -s user -y ||
  echo "caveman plugin install failed; rerun after 'claude auth login'" >&2

# Permission deny rules cannot express "only ~/work and ~/drop", and auto mode lets the
# Write tool write elsewhere in $HOME; the read-only mounts below close that gap.
UNIT="$HOME_DIR/.config/systemd/user/claude-rc.service"
if [ ! -f "$UNIT" ]; then
  as_user tee "$UNIT" >/dev/null <<'EOF'
[Unit]
Description=Claude Code Remote Control server (arisrv)

[Service]
WorkingDirectory=%h/work
# DNS is not up yet at boot; without this the first start dies on EAI_AGAIN
ExecStartPre=/bin/sh -c 'until getent hosts api.anthropic.com >/dev/null; do sleep 2; done'
ExecStart=%h/.local/bin/claude remote-control --spawn same-dir --permission-mode auto --name arisrv
Restart=always
RestartSec=30
# Sessions may write only here; the rest of the filesystem is read-only.
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
ReadWritePaths=%h/.claude.json %h/work %h/drop %h/.claude %h/.cache %h/.local/share/claude %h/.local/state/claude

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
