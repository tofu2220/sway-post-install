# EndeavourOS Sway Post-Install Automation Design

## Purpose

Create a focused post-install tool for the EndeavourOS Community Editions Sway environment. The tool installs the packages listed in `sway-eos.md`, removes unwanted packages, aggressively cleans installation residue, and produces a checklist for configuration that must remain manual.

The tool targets only a fresh EndeavourOS Community Editions Sway installation. Portability to other Arch-based distributions, desktop environments, or package helpers is out of scope.

## Deliverables

The implementation will add:

- `post-install.sh`: the executable Bash orchestration script.
- `post-install.conf`: a declarative, sectioned plain-text configuration file.
- `manual-post-install-checklist.txt`: generated only after a successful run and replaced atomically on subsequent successful runs.
- A dependency-free Bash test runner and fixtures under `tests/`.

## Configuration Format

`post-install.conf` will contain these sections:

- `[pacman]`: packages from official repositories.
- `[aur]`: packages installed through Yay.
- `[remove]`: explicitly unwanted installed packages.
- `[reminders]`: manual post-install actions, in display order.

Each package entry occupies one line. Blank lines and full-line comments beginning with `#` are allowed. Reminder entries are treated as literal text, not shell commands.

Before making any system change, the parser will reject:

- unknown or repeated sections;
- content outside a section;
- duplicate package entries, including duplicates across package sections;
- package entries containing characters outside the supported package-name syntax;
- a configuration with no packages in either install section.

Parsed values will remain Bash array elements. The script will never evaluate configuration content as shell code.

## Initial Package Configuration

The official repository package list will contain:

- `micro`
- `fcitx5`
- `fcitx5-unikey`
- `fcitx5-configtool`
- `nwg-displays`
- `mpv`
- `xarchiver`
- `zip`
- `7zip`
- `zed`
- `github-cli`
- `uv`
- `zoxide`
- `blueman`
- `qbittorrent`

The AUR list will contain:

- `auto-cpufreq`
- `github-desktop-bin`
- `docker-desktop`

The explicit removal list will contain `file-roller`.

## Execution Flow

The script will resolve its own directory and load `post-install.conf` from that directory, independently of the caller's working directory.

It will execute these stages in order:

1. Enable strict Bash error handling and refuse to run as root. Yay builds must run as the invoking user and will request privilege escalation through `sudo` when necessary.
2. Verify that Bash, `pacman`, `yay`, and `sudo` are available.
3. Parse and validate the complete configuration without changing the system.
4. Authenticate once with `sudo`.
5. Install and update official packages in one transaction with `sudo pacman -Syu --needed`. The system upgrade avoids creating an unsupported partial-upgrade state.
6. Install all configured AUR packages in one Yay operation with `yay -S --needed --removemake --cleanafter`. This removes unneeded make dependencies and untracked build files after installation.
7. Remove installed packages from `[remove]` with `sudo pacman -Rns`. Entries that are not installed are reported and skipped rather than treated as errors.
8. Run `yay -Yc` to find and remove remaining unneeded dependencies. The script will not use `yay -Ycc`, because optionally required packages are outside the intended orphan-cleanup scope.
9. Run `yay -Scc` to clear repository and AUR package caches.
10. Generate, atomically save, and print the manual checklist.

Package manager confirmations remain interactive. The script will not pass `--noconfirm`. This preserves a final human review before installations, removals, orphan deletion, and complete cache deletion.

## Failure Handling

The script is fail-fast. A failed or cancelled stage stops execution immediately, reports the stage that failed, and prevents every later stage from running. In particular:

- explicit removals never run after an installation failure;
- orphan and cache cleanup never run after an installation or explicit-removal failure;
- the checklist file is not created or replaced after any package-operation failure.

The script cannot roll back a transaction that a package manager already completed. Its ordered stages minimize the consequences: destructive cleanup occurs only after all requested software has been installed and all explicit removals have succeeded.

## Manual Checklist

The `[reminders]` section will cover:

- selecting Micro's `simple` colorscheme;
- setting `EDITOR=micro` in `.bashrc`;
- starting Fcitx5 from the Sway autostart configuration;
- setting the Fcitx5 input-method shortcuts and disabling its Clipboard add-on;
- including the `nwg-displays` generated output file in the Sway output configuration;
- initializing Zoxide in Bash;
- applying the custom multiline Bash prompt from `sway-eos.md`;
- masking `power-profiles-daemon.service` and enabling `auto-cpufreq.service`;
- enabling Bluetooth manually;
- disabling Bluetooth-on-boot in the auto-cpufreq UI;
- starting `blueman-applet` from the Sway autostart configuration.

The saved checklist will have a stable path beside the script: `manual-post-install-checklist.txt`. Generation will use a temporary file in the same directory followed by a rename, ensuring an interrupted write cannot leave a partial checklist.

## Testing

Tests will not invoke the real package manager or modify the workstation. A small Bash test runner will prepend a temporary directory of mocked `pacman`, `yay`, and `sudo` executables to `PATH` and record their arguments and order.

Coverage will include:

- valid parsing with comments and blank lines;
- rejection of unknown sections, repeated sections, invalid package names, duplicate packages, and missing install packages;
- the exact official, AUR, removal, orphan-cleanup, and cache-cleanup command sequence;
- use of `--needed`, `--removemake`, and `--cleanafter`;
- skipping an explicitly removed package that is not installed;
- immediate stopping after a failure at each mutating stage;
- absence of cleanup after an earlier failure;
- checklist output and atomic replacement only after complete success;
- correct behavior when the script is launched outside its own directory.

No external test framework will be installed on the target system.

## Non-Goals

The first version will not:

- edit Sway, Bash, Micro, Fcitx5, Bluetooth, or service configuration;
- automatically enable, disable, start, stop, or mask systemd services;
- run package operations without confirmation;
- support distributions or window-manager editions other than EndeavourOS Community Editions Sway;
- preserve package caches after successful cleanup;
- attempt transactional rollback across separate Pacman and Yay operations.
