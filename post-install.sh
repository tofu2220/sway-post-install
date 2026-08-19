#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

PACMAN_PACKAGES=()
AUR_PACKAGES=()
REMOVE_PACKAGES=()
REMINDERS=()
INSTALLED_REMOVALS=()

die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

validate_package_name() {
  [[ $1 =~ ^[[:alnum:]@._+:-]+$ ]]
}

parse_config() {
  local path=$1 line section='' line_number=0
  local -A seen_sections=() seen_packages=()

  PACMAN_PACKAGES=()
  AUR_PACKAGES=()
  REMOVE_PACKAGES=()
  REMINDERS=()

  [[ -r $path ]] || {
    die "cannot read config: $path"
    return 1
  }

  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    line=${line%$'\r'}

    [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue

    if [[ $line =~ ^\[([^][]+)\]$ ]]; then
      section=${BASH_REMATCH[1]}
      case $section in
        pacman | aur | remove | reminders) ;;
        *)
          die "unknown section [$section]"
          return 1
          ;;
      esac
      [[ -z ${seen_sections[$section]+x} ]] || {
        die "repeated section [$section]"
        return 1
      }
      seen_sections[$section]=1
      continue
    fi

    [[ -n $section ]] || {
      die "content outside a section at line $line_number"
      return 1
    }

    if [[ $section == reminders ]]; then
      REMINDERS+=("$line")
      continue
    fi

    validate_package_name "$line" || {
      die "invalid package name: $line"
      return 1
    }
    [[ -z ${seen_packages[$line]+x} ]] || {
      die "duplicate package: $line"
      return 1
    }
    seen_packages[$line]=1

    case $section in
      pacman) PACMAN_PACKAGES+=("$line") ;;
      aur) AUR_PACKAGES+=("$line") ;;
      remove) REMOVE_PACKAGES+=("$line") ;;
    esac
  done <"$path"

  ((${#PACMAN_PACKAGES[@]} + ${#AUR_PACKAGES[@]} > 0)) || {
    die 'at least one install package is required'
    return 1
  }
}

require_commands() {
  local command missing=0
  for command in "$@"; do
    if ! command -v "$command" >/dev/null 2>&1; then
      printf 'ERROR: missing command: %s\n' "$command" >&2
      missing=1
    fi
  done
  return "$missing"
}

run_stage() {
  local label=$1
  shift
  printf '==> %s\n' "$label"
  "$@" || {
    die "stage failed: $label"
    return 1
  }
}

install_packages() {
  if ((${#PACMAN_PACKAGES[@]} > 0)); then
    run_stage 'Install official packages' \
      sudo pacman -Syu --needed "${PACMAN_PACKAGES[@]}" || return 1
  fi
  if ((${#AUR_PACKAGES[@]} > 0)); then
    run_stage 'Install AUR packages' \
      yay -S --needed --removemake --cleanafter "${AUR_PACKAGES[@]}" || return 1
  fi
}

collect_installed_removals() {
  local package installed_package installed_output
  local -A installed_packages=()

  INSTALLED_REMOVALS=()
  installed_output=$(pacman -Qq) || {
    die 'cannot query installed packages'
    return 1
  }

  while IFS= read -r installed_package; do
    [[ -n $installed_package ]] && installed_packages[$installed_package]=1
  done <<<"$installed_output"

  for package in "${REMOVE_PACKAGES[@]}"; do
    if [[ -n ${installed_packages[$package]+x} ]]; then
      INSTALLED_REMOVALS+=("$package")
    else
      printf 'Skipping absent package: %s\n' "$package" >&2
    fi
  done
}

remove_configured_packages() {
  collect_installed_removals || return 1
  if ((${#INSTALLED_REMOVALS[@]} > 0)); then
    run_stage 'Remove configured packages' \
      sudo pacman -Rns "${INSTALLED_REMOVALS[@]}"
  fi
}

clean_system() {
  run_stage 'Remove orphaned dependencies' yay -Yc || return 1
  run_stage 'Clear package caches' yay -Scc
}

write_checklist() {
  local destination=$1 directory temporary index
  [[ ! -d $destination ]] || {
    die "checklist destination is a directory: $destination"
    return 1
  }
  directory=$(dirname -- "$destination")
  temporary=$(mktemp --tmpdir="$directory" '.manual-post-install.XXXXXX') || {
    die "cannot create checklist temporary file in: $directory"
    return 1
  }

  {
    printf 'Manual post-install checklist\n'
    printf '==============================\n'
    for index in "${!REMINDERS[@]}"; do
      printf '[ ] %d. %s\n' "$((index + 1))" "${REMINDERS[$index]}"
    done
  } >"$temporary" || {
    rm -f -- "$temporary"
    die 'cannot write checklist'
    return 1
  }

  mv -T -- "$temporary" "$destination" || {
    rm -f -- "$temporary"
    die "cannot replace checklist: $destination"
    return 1
  }

  printf '==> Manual configuration remains\n'
  cat -- "$destination" || {
    die "cannot read checklist after saving: $destination"
    return 1
  }
  printf 'Saved checklist: %s\n' "$destination"
}

main() {
  local config_path=${1:-"$SCRIPT_DIR/post-install.conf"}
  local checklist_path=${2:-"$SCRIPT_DIR/manual-post-install-checklist.txt"}

  ((EUID != 0)) || {
    die 'run this script as a regular user, not root'
    return 1
  }
  require_commands bash pacman yay sudo mktemp mv dirname cat rm || return 1
  parse_config "$config_path" || return 1
  run_stage 'Authenticate sudo' sudo -v || return 1
  install_packages || return 1
  remove_configured_packages || return 1
  clean_system || return 1
  write_checklist "$checklist_path" || return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
