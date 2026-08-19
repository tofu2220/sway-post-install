#!/usr/bin/env bash
set -Eeuo pipefail

PACMAN_PACKAGES=()
AUR_PACKAGES=()
REMOVE_PACKAGES=()
REMINDERS=()

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
