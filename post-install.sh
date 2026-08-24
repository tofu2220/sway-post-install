#!/usr/bin/env bash
set -euo pipefail

PACMAN_PKGS=(
  micro
  fcitx5
  fcitx5-unikey
  fcitx5-configtool
  nwg-displays
  mpv
  xarchiver
  zip
  7zip
  gnome-keyring
  zed
  github-cli
  uv
  zoxide
  blueman
  qbittorrent
  gitui
)

AUR_PKGS=(
  auto-cpufreq
  # github-desktop-bin
  # docker-desktop
)

REMOVE_PKGS=(
  file-roller
)

echo
echo "========================================"
echo " Package setup"
echo "========================================"
echo

echo "==> Installing official packages:"
printf '    %s\n' "${PACMAN_PKGS[@]}"
echo

sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

echo
echo "==> Official packages installed successfully."
echo

echo "==> Installing AUR packages:"
printf '    %s\n' "${AUR_PKGS[@]}"
echo
echo "    Make dependencies will be removed after building."
echo

yay -S --needed --noconfirm --removemake "${AUR_PKGS[@]}"

echo
echo "==> AUR packages installed successfully."
echo

echo "==> Removing unwanted packages:"
printf '    %s\n' "${REMOVE_PKGS[@]}"
echo

sudo pacman -Rns --noconfirm "${REMOVE_PKGS[@]}"

echo
echo "==> Unwanted packages removed successfully."
echo

echo "========================================"
echo " All automated stages completed!"
echo "========================================"
echo

echo "Reminders:"
echo
cat <<'EOF'
  - In Micro, run:
      set colorscheme simple

  - Add to ~/.bashrc:
      export EDITOR="micro"

  - Add to ~/.config/sway/config.d/autostart_applications:
      exec fcitx5

  - Run fcitx5-configtool and set Toggle Input Method to Alt + Left Shift

  - In fcitx5-configtool, disable Temporarily Toggle Input Method

  - In fcitx5-configtool, disable the Clipboard addon

  - Add to ~/.config/sway/config.d/output:
      include ~/.config/sway/outputs

  - Add to ~/.bashrc:
      eval "$(zoxide init bash)"

  - Apply the custom multiline PS1 from sway-eos.md

  - Run:
      sudo systemctl mask power-profiles-daemon.service

  - Run:
      sudo systemctl enable auto-cpufreq.service

  - Run:
      sudo systemctl enable bluetooth

  - In auto-cpufreq, turn Bluetooth on boot off

  - Add to ~/.config/sway/config.d/autostart_applications:
      exec blueman-applet
EOF

echo
echo "Done."
