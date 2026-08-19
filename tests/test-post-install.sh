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
  export MOCK_LOG MOCK_FAIL=''

  local name
  for name in pacman yay sudo; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'command_name=$(basename -- "$0")' \
      'command_line="$command_name $*"' \
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
assert_file_eq $'sudo -v\nsudo pacman -Syu --needed micro fcitx5\nyay -S --needed --removemake --cleanafter auto-cpufreq' \
  "$MOCK_LOG" 'main authenticates before ordered installs'

printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
