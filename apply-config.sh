#!/usr/bin/env bash
set -euo pipefail

echo
echo "========================================"
echo " Configuration setup"
echo "========================================"
echo

echo "==> Configuring Bash..."

grep -Fqx 'export EDITOR="micro"' ~/.bashrc || \
  echo 'export EDITOR="micro"' >> ~/.bashrc

grep -Fqx 'eval "$(zoxide init bash)"' ~/.bashrc || \
  echo 'eval "$(zoxide init bash)"' >> ~/.bashrc

sed -i '/^[[:space:]]*PS1=/c\
RESET='\''\\[\\e[0m\\]'\''\
BOLD='\''\\[\\e[1m\\]'\''\
BLUE='\''\\[\\e[38;5;75m\\]'\''\
GREEN='\''\\[\\e[38;5;114m\\]'\''\
PURPLE='\''\\[\\e[38;5;141m\\]'\''\
GRAY='\''\\[\\e[38;5;245m\\]'\''\
\
PS1="${GRAY}╭─${GREEN}\\u${GRAY}@${BLUE}\\h ${PURPLE}\\w${RESET}\\n${GRAY}╰─${BOLD}\\$ ${RESET}"' ~/.bashrc

echo "==> Configuring Sway..."

AUTOSTART=~/.config/sway/config.d/autostart_applications
OUTPUT=~/.config/sway/config.d/output

mkdir -p ~/.config/sway/config.d
touch "$AUTOSTART" "$OUTPUT"

grep -Fqx 'exec fcitx5' "$AUTOSTART" || \
  echo 'exec fcitx5' >> "$AUTOSTART"

grep -Fqx 'exec blueman-applet' "$AUTOSTART" || \
  echo 'exec blueman-applet' >> "$AUTOSTART"

grep -Fqx 'include ~/.config/sway/outputs' "$OUTPUT" || \
  echo 'include ~/.config/sway/outputs' >> "$OUTPUT"

echo "==> Configuring services..."

sudo systemctl mask power-profiles-daemon.service
sudo systemctl enable auto-cpufreq.service
sudo systemctl enable bluetooth.service

echo
echo "========================================"
echo " Configuration completed!"
echo "========================================"
echo

echo "Manual GUI configuration:"
echo
cat <<'EOF'
  - In Micro, run:
      set colorscheme simple

  - Run fcitx5-configtool:
      Toggle Input Method: Alt + Left Shift
      Temporarily Toggle Input Method: Disabled
      Clipboard addon: Disabled

  - In auto-cpufreq:
      Turn Bluetooth on boot off
EOF

echo
echo "Log out and log back in to apply all changes."
echo
