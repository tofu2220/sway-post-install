## Content

Install micro
```bash
sudo pacman -S micro
```

Set `micro` to basic color
```bash
set colorscheme simple
```

Add `micro` to `.bashrc`
```bash
micro ~/.bashrc

# Append line
export EDITOR="micro"
```

Install fcitx5 + uniKey
```bash
sudo pacman -S fcitx5 fcitx5-unikey fcitx5-configtool
```

Autostart fcitx5
```bash
micro ~/.config/sway/config.d/autostart_applications

exec fcitx5
```

Finally run `fcitx5-configtool`
- Global Option:
  - Toggle Input Method: Alt + Left Shift
  - Tempoararily Toggle Input Method: [Disable]
- Addons:
  - Clipboard: [Disable]

Install wayland display
```bash
sudo pacman -S nwg-displays

# nwg-displays to output
micro ~/.config/sway/config.d/output

# Append these line
include ~/.config/sway/outputs
```

Install mpv
```bash
sudo pacman -S mpv
```

Install compression tool
```bash
sudo pacman -Rns file-roller

sudo pacman -S xarchiver

sudo pacman -S zip 7zip
```

Install auto-cpufreq
```bash
# Install autocpu freq
yay -S auto-cpufreq

# Masked power-profiles-daemon.service manually
sudo systemctl mask power-profiles-daemon.service

# Start and enable auto-cpufreq
sudo systemctl enable auto-cpufreq.service
```

Install program tools
```bash
sudo pacman -S zed

sudo pacman -S github-cli # For private repo
yay -S github-desktop-bin # For gui manage

sudo pacman -S uv # python manager

sudo pacman -S zoxide # jump to directory faster

# Init zoxide through bash
echo 'eval "$(zoxide init bash)"' >> ~/.bashrc

# Edit ps1
sed -i '/^[[:space:]]*PS1=/c\
RESET='\''\\[\\e[0m\\]'\''\
BOLD='\''\\[\\e[1m\\]'\''\
BLUE='\''\\[\\e[38;5;75m\\]'\''\
GREEN='\''\\[\\e[38;5;114m\\]'\''\
PURPLE='\''\\[\\e[38;5;141m\\]'\''\
GRAY='\''\\[\\e[38;5;245m\\]'\''\
\
PS1="${GRAY}╭─${GREEN}\\u${GRAY}@${BLUE}\\h ${PURPLE}\\w${RESET}\\n${GRAY}╰─${BOLD}\\$ ${RESET}"' ~/.bashrc

yay -S docker-desktop
```

Enable bluetooth
```bash
sudo systemctl enable bluetooth

sudo pacman -S blueman

# Then open auto-cpufreq > bluetooth on boot > off
```

Add bluetooth to autostart
```bash
micro ~/.config/sway/config.d/autostart_applications

# Bluetooth Applet
exec blueman-applet
```

Install qBittorrent

```bash
sudo pacman -S qbittorrent
```

## Reference
https://github.com/EndeavourOS-Community-Editions/sway
