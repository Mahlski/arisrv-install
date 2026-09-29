#!/bin/bash
# arisrv headless hardening: key-only sshd, lid ignored, sleep disabled.
# Run after first boot, once your SSH key is in ~/.ssh/authorized_keys (ssh-copy-id):
#   curl -fsSL https://raw.githubusercontent.com/Mahlski/arisrv-install/main/harden.sh | sudo bash
set -euo pipefail

install -d /etc/ssh/sshd_config.d /etc/systemd/logind.conf.d /etc/systemd/sleep.conf.d

cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF

cat > /etc/systemd/logind.conf.d/lid.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF

cat > /etc/systemd/sleep.conf.d/disable-sleep.conf <<'EOF'
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF

sshd -t
systemctl reload sshd
systemctl reload systemd-logind
echo "hardening applied"
