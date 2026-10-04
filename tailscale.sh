#!/bin/bash
# arisrv: install + enable tailscaled. Operator runs `tailscale up` interactively (GitHub login).
# Run after `pacman -Syu` and a reboot if the kernel changed.
#   curl -fsSL https://raw.githubusercontent.com/Mahlski/arisrv-install/main/tailscale.sh | sudo bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
pacman -S --needed --noconfirm tailscale
install -d /etc/systemd/system/tailscaled.service.d
cat > /etc/systemd/system/tailscaled.service.d/restart.conf <<'DROPIN'
[Unit]
StartLimitIntervalSec=0
[Service]
RestartSec=10s
DROPIN
systemctl daemon-reload
modprobe tun || { echo "tun missing: reboot after kernel update, rerun" >&2; exit 1; }
systemctl enable --now tailscaled.service
systemctl is-active --quiet tailscaled.service
tailscale version
if tailscale status >/dev/null 2>&1; then
  tailscale status --self
else
  cat <<'NEXT'
Next, interactive:
  sudo tailscale up --accept-dns=false      # prints URL; open on aribook, log in with GitHub
Then: admin console -> Machines -> arisrv -> Disable key expiry.
Verify: tailscale ip -4 ; from aribook: ssh arisrv uname -n
NEXT
fi
