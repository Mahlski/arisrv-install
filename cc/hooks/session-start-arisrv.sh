#!/usr/bin/env bash
# arisrv SessionStart hook: injects the machine banner so the agent knows it is on the
# headless host and that EROFS outside the unit's write paths is by design. Read-only.

# jq builds the output; degrade silently without it.
command -v jq >/dev/null 2>&1 || exit 0

# Drain the payload; nothing in it is needed.
cat >/dev/null 2>&1

# `uname -n` not `hostname` — the hostname binary is absent here.
MACHINE=$(uname -n)

if [[ "$MACHINE" == arisrv ]]; then
  CTX="ACTIVE MACHINE: arisrv — headless fallback/offload host (no vault, no dotfiles, no Obsidian, no mail). Write deliverables to ~/drop/cc/. Sessions run under read-only home: writable only ~/work ~/drop ~/.claude ~/.cache ~/.local/share/claude ~/.local/state; EROFS elsewhere is expected, not a bug to work around."
else
  CTX="ACTIVE MACHINE: unknown host ${MACHINE} — ask user before machine-specific actions."
fi

jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
