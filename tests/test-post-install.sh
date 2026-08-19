#!/usr/bin/env bash
set -u -o pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/post-install.sh"
set +e

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
passed=0
failed=0

pass() {
  printf 'PASS: %s\n' "$1"
  ((passed += 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  ((failed += 1))
}

assert_eq() {
  local expected=$1 actual=$2 message=$3
  if [[ $actual == "$expected" ]]; then
    pass "$message"
  else
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' \
      "$message" "$expected" "$actual" >&2
    ((failed += 1))
  fi
}

assert_fails_with() {
  local expected=$1
  shift
  local output status
  output=$("$@" 2>&1)
  status=$?
  if ((status == 0)); then
    fail "expected failure from: $*"
  elif [[ $output == *"$expected"* ]]; then
    pass "rejects input with: $expected"
  else
    printf 'FAIL: missing error %q in %q\n' "$expected" "$output" >&2
    ((failed += 1))
  fi
}

assert_file_eq() {
  local expected=$1 path=$2 message=$3 actual
  actual=$(<"$path")
  assert_eq "$expected" "$actual" "$message"
}

assert_file_excludes() {
  local unexpected=$1 path=$2 message=$3 actual
  actual=$(<"$path")
  if [[ $actual != *"$unexpected"* ]]; then
    pass "$message"
  else
    printf 'FAIL: %s\n  unexpected: %q\n  actual:     %q\n' \
      "$message" "$unexpected" "$actual" >&2
    ((failed += 1))
  fi
}

assert_file_starts_with() {
  local expected=$1 path=$2 message=$3 actual
  actual=$(<"$path")
  if [[ $actual == "$expected"* ]]; then
    pass "$message"
  else
    printf 'FAIL: %s\n  expected prefix: %q\n  actual:          %q\n' \
      "$message" "$expected" "$actual" >&2
    ((failed += 1))
  fi
}

assert_succeeds() {
  local message=$1
  shift
  local output status
  output=$("$@" 2>&1)
  status=$?
  if ((status == 0)); then
    pass "$message"
  else
    printf 'FAIL: %s\n  status: %d\n  output: %s\n' "$message" "$status" "$output" >&2
    ((failed += 1))
  fi
}

assert_file_exists() {
  local path=$1 message=$2
  if [[ -f $path ]]; then
    pass "$message"
  else
    fail "$message (missing: $path)"
  fi
}

write_config() {
  local name=$1
  shift
  printf '%s\n' "$@" >"$TEST_TMP/$name"
}

write_config valid.conf \
  '# comment' '[pacman]' 'micro' 'fcitx5' '' \
  '[aur]' 'auto-cpufreq' \
  '[remove]' 'file-roller' \
  '[reminders]' 'Enable Bluetooth manually'

parse_config "$TEST_TMP/valid.conf"
assert_eq 'micro fcitx5' "${PACMAN_PACKAGES[*]}" 'parses official packages'
assert_eq 'auto-cpufreq' "${AUR_PACKAGES[*]}" 'parses AUR packages'
assert_eq 'file-roller' "${REMOVE_PACKAGES[*]}" 'parses removal packages'
assert_eq 'Enable Bluetooth manually' "${REMINDERS[*]}" 'preserves reminder text'

write_config unknown.conf '[pacman]' 'micro' '[other]' 'value'
assert_fails_with 'unknown section [other]' parse_config "$TEST_TMP/unknown.conf"

write_config repeated.conf '[pacman]' 'micro' '[pacman]' 'fcitx5'
assert_fails_with 'repeated section [pacman]' parse_config "$TEST_TMP/repeated.conf"

write_config outside.conf 'micro' '[pacman]' 'fcitx5'
assert_fails_with 'content outside a section' parse_config "$TEST_TMP/outside.conf"

write_config invalid.conf '[pacman]' 'bad package'
assert_fails_with 'invalid package name: bad package' parse_config "$TEST_TMP/invalid.conf"

write_config duplicate.conf '[pacman]' 'micro' '[aur]' 'micro'
assert_fails_with 'duplicate package: micro' parse_config "$TEST_TMP/duplicate.conf"

write_config empty.conf '[pacman]' '[aur]' '[remove]' 'file-roller'
assert_fails_with 'at least one install package is required' parse_config "$TEST_TMP/empty.conf"

ORIGINAL_PATH=$PATH

setup_mocks() {
  MOCK_BIN="$TEST_TMP/bin"
  MOCK_LOG="$TEST_TMP/commands.log"
  mkdir -p "$MOCK_BIN"
  : >"$MOCK_LOG"
  export MOCK_LOG MOCK_FAIL='' MOCK_INSTALLED='' MOCK_QUERY_FAIL=''

  local name
  for name in pacman yay sudo; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'command_name=$(basename -- "$0")' \
      'command_line="$command_name $*"' \
      'if [[ $command_name == pacman && ${1:-} == -Qq ]]; then' \
      '  [[ -z ${MOCK_QUERY_FAIL:-} ]] || exit 2' \
      '  if (($# == 1)); then' \
      '    for installed_package in ${MOCK_INSTALLED:-}; do printf "%s\n" "$installed_package"; done' \
      '    exit 0' \
      '  fi' \
      '  [[ " ${MOCK_INSTALLED:-} " == *" ${2:-} "* ]]' \
      '  exit' \
      'fi' \
      'printf "%s\n" "$command_line" >>"$MOCK_LOG"' \
      '[[ ${MOCK_FAIL:-} != "$command_line" ]]' >"$MOCK_BIN/$name"
    chmod +x "$MOCK_BIN/$name"
  done
  PATH="$MOCK_BIN:$ORIGINAL_PATH"
  export PATH
}

setup_mocks

PACMAN_PACKAGES=(micro fcitx5)
AUR_PACKAGES=(auto-cpufreq)
: >"$MOCK_LOG"
assert_succeeds 'installs official packages before AUR packages' install_packages
assert_file_eq $'sudo pacman -Syu --needed micro fcitx5\nyay -S --needed --removemake --cleanafter auto-cpufreq' \
  "$MOCK_LOG" 'uses the approved install commands in order'

PACMAN_PACKAGES=()
AUR_PACKAGES=(auto-cpufreq)
: >"$MOCK_LOG"
assert_succeeds 'skips an empty official package transaction' install_packages
assert_file_eq 'yay -S --needed --removemake --cleanafter auto-cpufreq' \
  "$MOCK_LOG" 'runs only the nonempty AUR transaction'

PACMAN_PACKAGES=(micro)
AUR_PACKAGES=()
: >"$MOCK_LOG"
assert_succeeds 'skips an empty AUR package transaction' install_packages
assert_file_eq 'sudo pacman -Syu --needed micro' \
  "$MOCK_LOG" 'runs only the nonempty official transaction'

PACMAN_PACKAGES=(micro)
AUR_PACKAGES=(auto-cpufreq)
: >"$MOCK_LOG"
export MOCK_FAIL='yay -S --needed --removemake --cleanafter auto-cpufreq'
assert_fails_with 'stage failed: Install AUR packages' install_packages
export MOCK_FAIL=''

assert_succeeds 'accepts commands that are available' require_commands bash pacman yay sudo
assert_fails_with 'missing command: command-that-does-not-exist' \
  require_commands command-that-does-not-exist

: >"$MOCK_LOG"
assert_succeeds 'main authenticates and installs from a supplied config' \
  main "$TEST_TMP/valid.conf" "$TEST_TMP/unused-checklist.txt"
assert_file_starts_with $'sudo -v\nsudo pacman -Syu --needed micro fcitx5\nyay -S --needed --removemake --cleanafter auto-cpufreq' \
  "$MOCK_LOG" 'main authenticates before ordered installs'

REMOVE_PACKAGES=(file-roller missing-package)
export MOCK_INSTALLED='file-roller'
: >"$MOCK_LOG"
assert_succeeds 'removes only configured packages that are installed' \
  remove_configured_packages
assert_file_eq 'sudo pacman -Rns file-roller' "$MOCK_LOG" \
  'uses one explicit removal transaction'

REMOVE_PACKAGES=(file-roller)
export MOCK_INSTALLED=''
: >"$MOCK_LOG"
assert_succeeds 'skips removal when no configured package is installed' \
  remove_configured_packages
assert_file_eq '' "$MOCK_LOG" 'does not start an empty removal transaction'

REMOVE_PACKAGES=(file-roller)
export MOCK_QUERY_FAIL=1
: >"$MOCK_LOG"
assert_fails_with 'cannot query installed packages' remove_configured_packages
assert_file_eq '' "$MOCK_LOG" \
  'does not start removal when the installed-package query fails'
export MOCK_QUERY_FAIL=''

: >"$MOCK_LOG"
assert_succeeds 'removes orphans before clearing caches' clean_system
assert_file_eq $'yay -Yc\nyay -Scc' "$MOCK_LOG" \
  'uses conservative orphan detection and full cache cleanup in order'

export MOCK_FAIL='yay -Yc'
: >"$MOCK_LOG"
assert_fails_with 'stage failed: Remove orphaned dependencies' clean_system
assert_file_excludes 'yay -Scc' "$MOCK_LOG" \
  'does not clear caches after orphan cleanup fails'

export MOCK_FAIL='yay -Scc'
: >"$MOCK_LOG"
assert_fails_with 'stage failed: Clear package caches' clean_system
export MOCK_FAIL=''

export MOCK_INSTALLED='file-roller'
: >"$MOCK_LOG"
assert_succeeds 'main runs removal and cleanup after successful installs' \
  main "$TEST_TMP/valid.conf" "$TEST_TMP/unused-checklist.txt"
assert_file_eq $'sudo -v\nsudo pacman -Syu --needed micro fcitx5\nyay -S --needed --removemake --cleanafter auto-cpufreq\nsudo pacman -Rns file-roller\nyay -Yc\nyay -Scc' \
  "$MOCK_LOG" 'main preserves the approved destructive-stage order'

export MOCK_FAIL='sudo pacman -Rns file-roller'
: >"$MOCK_LOG"
assert_fails_with 'stage failed: Remove configured packages' \
  main "$TEST_TMP/valid.conf" "$TEST_TMP/unused-checklist.txt"
assert_file_excludes 'yay -Yc' "$MOCK_LOG" \
  'does not remove orphans after explicit removal fails'
assert_file_excludes 'yay -Scc' "$MOCK_LOG" \
  'does not clear caches after explicit removal fails'
export MOCK_FAIL=''

REMINDERS=('Enable Bluetooth' 'Configure Fcitx5')
checklist="$TEST_TMP/checklist.txt"
assert_succeeds 'writes a manual checklist' write_checklist "$checklist"
assert_file_eq $'Manual post-install checklist\n==============================\n[ ] 1. Enable Bluetooth\n[ ] 2. Configure Fcitx5' \
  "$checklist" 'writes numbered reminders with a stable heading'

directory_destination="$TEST_TMP/checklist-directory"
mkdir "$directory_destination"
assert_fails_with 'checklist destination is a directory:' \
  write_checklist "$directory_destination"
directory_contents=$(find "$directory_destination" -mindepth 1 -maxdepth 1 -print)
assert_eq '' "$directory_contents" \
  'does not move a temporary checklist into a directory destination'

temporary_failure_destination="$TEST_TMP/temporary-failure.txt"
printf 'existing checklist\n' >"$temporary_failure_destination"
mktemp() {
  return 1
}
assert_fails_with 'cannot create checklist temporary file in:' \
  write_checklist "$temporary_failure_destination"
unset -f mktemp
assert_file_eq 'existing checklist' "$temporary_failure_destination" \
  'preserves the previous checklist when temporary creation fails'

export MOCK_INSTALLED='file-roller'
export MOCK_FAIL=''
: >"$MOCK_LOG"
final_checklist="$TEST_TMP/final.txt"
assert_succeeds 'main generates a checklist after every package stage succeeds' \
  main "$TEST_TMP/valid.conf" "$final_checklist"
assert_file_eq $'sudo -v\nsudo pacman -Syu --needed micro fcitx5\nyay -S --needed --removemake --cleanafter auto-cpufreq\nsudo pacman -Rns file-roller\nyay -Yc\nyay -Scc' \
  "$MOCK_LOG" 'complete execution retains the approved command order'
assert_file_eq $'Manual post-install checklist\n==============================\n[ ] 1. Enable Bluetooth manually' \
  "$final_checklist" 'main writes reminders from the supplied config'

printf 'old checklist\n' >"$final_checklist"
export MOCK_FAIL='yay -S --needed --removemake --cleanafter auto-cpufreq'
: >"$MOCK_LOG"
assert_fails_with 'stage failed: Install AUR packages' \
  main "$TEST_TMP/valid.conf" "$final_checklist"
assert_file_eq 'old checklist' "$final_checklist" \
  'does not replace a checklist after installation failure'
assert_file_excludes 'pacman -Rns' "$MOCK_LOG" \
  'does not remove packages after installation failure'
assert_file_excludes 'yay -Yc' "$MOCK_LOG" \
  'does not remove orphans after installation failure'
assert_file_excludes 'yay -Scc' "$MOCK_LOG" \
  'does not clear caches after installation failure'
export MOCK_FAIL=''

printf 'old checklist\n' >"$final_checklist"
export MOCK_FAIL='sudo pacman -Syu --needed micro fcitx5'
: >"$MOCK_LOG"
assert_fails_with 'stage failed: Install official packages' \
  main "$TEST_TMP/valid.conf" "$final_checklist"
assert_file_eq $'sudo -v\nsudo pacman -Syu --needed micro fcitx5' \
  "$MOCK_LOG" 'stops immediately when the first package transaction fails'
assert_file_eq 'old checklist' "$final_checklist" \
  'preserves the checklist after official package installation failure'
export MOCK_FAIL=''

printf 'old checklist\n' >"$final_checklist"
export MOCK_FAIL='yay -Scc'
: >"$MOCK_LOG"
assert_fails_with 'stage failed: Clear package caches' \
  main "$TEST_TMP/valid.conf" "$final_checklist"
assert_file_eq $'sudo -v\nsudo pacman -Syu --needed micro fcitx5\nyay -S --needed --removemake --cleanafter auto-cpufreq\nsudo pacman -Rns file-roller\nyay -Yc\nyay -Scc' \
  "$MOCK_LOG" 'reports failure from the final cache-cleanup stage'
assert_file_eq 'old checklist' "$final_checklist" \
  'preserves the checklist after cache cleanup failure'
export MOCK_FAIL=''

portable_copy="$TEST_TMP/portable-copy"
mkdir "$portable_copy"
cp "$PROJECT_DIR/post-install.sh" "$PROJECT_DIR/post-install.conf" "$portable_copy/"
: >"$MOCK_LOG"
(
  cd "$TEST_TMP" || exit 1
  bash "$portable_copy/post-install.sh"
) >/dev/null 2>&1
portable_status=$?
assert_eq '0' "$portable_status" 'runs successfully outside the script directory'
assert_file_exists "$portable_copy/manual-post-install-checklist.txt" \
  'writes the default checklist beside the script'

printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
