# EndeavourOS Sway Post-Install Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a safe, config-driven Bash tool that installs the desired EndeavourOS Sway packages, removes unwanted packages and installation residue, and emits a persistent manual-configuration checklist.

**Architecture:** A single executable, `post-install.sh`, owns parsing and ordered orchestration while treating `post-install.conf` as inert data. Functions expose narrow Bash interfaces so a dependency-free test runner can source the script and replace system commands with temporary mocks; the executable entry point remains behind a standard `BASH_SOURCE` guard.

**Tech Stack:** Bash 5+, Pacman, Yay, sudo, coreutils, and a dependency-free Bash test runner.

**Spec:** `docs/superpowers/specs/2026-08-19-sway-post-install-design.md`

## Global Constraints

- Target only a fresh EndeavourOS Community Editions Sway installation.
- Do not edit Sway, Bash, Micro, Fcitx5, Bluetooth, or systemd configuration.
- Keep Pacman and Yay confirmation prompts; never pass `--noconfirm`.
- Parse config values as data and Bash array elements; never use `eval` or source the config.
- Stop on the first failed or cancelled mutating stage.
- Run cleanup only after every installation and explicit removal succeeds.
- Generate or replace the checklist only after complete success.
- Add no external runtime or test-framework dependency.

---

## File Map

- `post-install.sh`: config parser, validation, preflight checks, package-operation orchestration, cleanup, checklist generation, and guarded executable entry point.
- `post-install.conf`: official, AUR, removal, and manual-reminder data.
- `tests/test-post-install.sh`: minimal test runner, mock-command setup, assertions, and all behavior tests.
- `sway-eos.md`: retain as the source notes; implementation does not modify it.
- `manual-post-install-checklist.txt`: runtime output only; do not commit it.
- `.gitignore`: ignore the generated checklist.

### Task 1: Declarative Config and Strict Parser

**Files:**
- Create: `post-install.conf`
- Create: `post-install.sh`
- Create: `tests/test-post-install.sh`

**Interfaces:**
- Produces: `parse_config <path>`; populates global indexed arrays `PACMAN_PACKAGES`, `AUR_PACKAGES`, `REMOVE_PACKAGES`, and `REMINDERS`, returning nonzero with an `ERROR:` message on stderr for invalid input.
- Produces: `validate_package_name <value>`; returns success only for `^[[:alnum:]@._+:-]+$`.
- Produces: `die <message>`; prints `ERROR: <message>` to stderr and returns status 1 when called from a function.

- [ ] **Step 1: Create the test runner and failing parser tests**

Create `tests/test-post-install.sh` with strict mode, a temporary-directory cleanup trap, counters, and assertions:

```bash
#!/usr/bin/env bash
set -u -o pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/post-install.sh"
set +e

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
passed=0
failed=0

assert_eq() {
  local expected=$1 actual=$2 message=$3
  if [[ $actual == "$expected" ]]; then
    ((passed += 1))
  else
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$message" "$expected" "$actual" >&2
    ((failed += 1))
  fi
}

assert_fails_with() {
  local expected=$1; shift
  local output status
  output=$("$@" 2>&1); status=$?
  [[ $status -ne 0 ]] || { printf 'FAIL: expected failure: %s\n' "$*" >&2; ((failed += 1)); return; }
  [[ $output == *"$expected"* ]] && ((passed += 1)) || {
    printf 'FAIL: missing error %q in %q\n' "$expected" "$output" >&2
    ((failed += 1))
  }
}
```

Add concrete cases that write configs with `printf` and call `parse_config`:

```bash
valid_config="$TEST_TMP/valid.conf"
printf '%s\n' \
  '# comment' '[pacman]' 'micro' 'fcitx5' '' \
  '[aur]' 'auto-cpufreq' \
  '[remove]' 'file-roller' \
  '[reminders]' 'Enable Bluetooth manually' >"$valid_config"

parse_config "$valid_config"
assert_eq 'micro fcitx5' "${PACMAN_PACKAGES[*]}" 'parses official packages'
assert_eq 'auto-cpufreq' "${AUR_PACKAGES[*]}" 'parses AUR packages'
assert_eq 'file-roller' "${REMOVE_PACKAGES[*]}" 'parses removal packages'
assert_eq 'Enable Bluetooth manually' "${REMINDERS[*]}" 'preserves reminder text'
```

Create separate invalid files and assert these exact diagnostics:

```bash
assert_fails_with 'unknown section [other]' parse_config "$TEST_TMP/unknown.conf"
assert_fails_with 'repeated section [pacman]' parse_config "$TEST_TMP/repeated.conf"
assert_fails_with 'content outside a section' parse_config "$TEST_TMP/outside.conf"
assert_fails_with 'invalid package name: bad package' parse_config "$TEST_TMP/invalid.conf"
assert_fails_with 'duplicate package: micro' parse_config "$TEST_TMP/duplicate.conf"
assert_fails_with 'at least one install package is required' parse_config "$TEST_TMP/empty.conf"
```

End the runner with:

```bash
printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
```

- [ ] **Step 2: Run the parser tests and verify they fail**

Run: `bash tests/test-post-install.sh`

Expected: FAIL while sourcing the missing `post-install.sh`, or with `parse_config: command not found` if the empty script has already been created.

- [ ] **Step 3: Implement the minimal parser**

Create `post-install.sh` with:

```bash
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
  PACMAN_PACKAGES=(); AUR_PACKAGES=(); REMOVE_PACKAGES=(); REMINDERS=()
  [[ -r $path ]] || { die "cannot read config: $path"; return 1; }

  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^\[([^][]+)\]$ ]]; then
      section=${BASH_REMATCH[1]}
      case $section in pacman|aur|remove|reminders) ;; *) die "unknown section [$section]"; return 1 ;; esac
      [[ -z ${seen_sections[$section]+x} ]] || { die "repeated section [$section]"; return 1; }
      seen_sections[$section]=1
      continue
    fi
    [[ -n $section ]] || { die "content outside a section at line $line_number"; return 1; }
    if [[ $section == reminders ]]; then
      REMINDERS+=("$line")
      continue
    fi
    validate_package_name "$line" || { die "invalid package name: $line"; return 1; }
    [[ -z ${seen_packages[$line]+x} ]] || { die "duplicate package: $line"; return 1; }
    seen_packages[$line]=1
    case $section in
      pacman) PACMAN_PACKAGES+=("$line") ;;
      aur) AUR_PACKAGES+=("$line") ;;
      remove) REMOVE_PACKAGES+=("$line") ;;
    esac
  done <"$path"
  ((${#PACMAN_PACKAGES[@]} + ${#AUR_PACKAGES[@]} > 0)) || {
    die 'at least one install package is required'; return 1;
  }
}
```

Populate `post-install.conf` with all exact package entries from the spec, using the four named sections. Copy each manual action and exact Fcitx5 setting from `sway-eos.md` into actionable `[reminders]` lines. For the multiline prompt, use the single reminder `Apply the custom multiline PS1 from sway-eos.md` so the line-oriented config remains valid.

- [ ] **Step 4: Run parser tests and syntax validation**

Run: `bash -n post-install.sh tests/test-post-install.sh && bash tests/test-post-install.sh`

Expected: syntax checks exit 0 and the runner reports `0 failed`.

- [ ] **Step 5: Commit the parser and config**

```bash
git add post-install.sh post-install.conf tests/test-post-install.sh
git commit -m "feat: add declarative post-install config parser"
```

### Task 2: Preflight and Ordered Package Installation

**Files:**
- Modify: `post-install.sh`
- Modify: `tests/test-post-install.sh`

**Interfaces:**
- Consumes: `parse_config <path>` and its four global arrays from Task 1.
- Produces: `require_commands <name...>`; reports every missing required executable and returns nonzero.
- Produces: `run_stage <label> <command...>`; prints `==> <label>`, runs the array-safe command, and returns its status with `ERROR: stage failed: <label>` on failure.
- Produces: `install_packages`; executes official packages first and AUR packages second, skipping an empty group.
- Produces: `main [config_path] [checklist_path]`; performs preflight and parsing, rejects UID 0, authenticates with `sudo -v`, and invokes stages. Default paths are beside the script.

- [ ] **Step 1: Add mock-command infrastructure and failing install tests**

In `tests/test-post-install.sh`, add `setup_mocks` that creates executable mock commands under `$TEST_TMP/bin` and exports `MOCK_LOG`, `MOCK_FAIL`, and `MOCK_INSTALLED`:

```bash
setup_mocks() {
  MOCK_BIN="$TEST_TMP/bin"; MOCK_LOG="$TEST_TMP/commands.log"
  mkdir -p "$MOCK_BIN"; : >"$MOCK_LOG"
  export MOCK_LOG MOCK_FAIL='' MOCK_INSTALLED=''
  for name in pacman yay sudo; do
    printf '%s\n' '#!/usr/bin/env bash' \
      'printf "%s %s\n" "$(basename "$0")" "$*" >>"$MOCK_LOG"' \
      '[[ ${MOCK_FAIL:-} != "$(basename "$0") $*" ]]' >"$MOCK_BIN/$name"
    chmod +x "$MOCK_BIN/$name"
  done
  PATH="$MOCK_BIN:$PATH"
}
```

Add tests that parse a minimal config, call `install_packages`, and assert the exact log:

```text
sudo pacman -Syu --needed micro fcitx5
yay -S --needed --removemake --cleanafter auto-cpufreq
```

Add separate cases proving an empty `[pacman]` or `[aur]` group causes no empty transaction. Add a failure case with `MOCK_FAIL='yay -S --needed --removemake --cleanafter auto-cpufreq'` and assert a nonzero return plus `stage failed: Install AUR packages`.

- [ ] **Step 2: Run tests and verify the new cases fail**

Run: `bash tests/test-post-install.sh`

Expected: FAIL with `install_packages: command not found`.

- [ ] **Step 3: Implement preflight, stage reporting, and installs**

Add:

```bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

require_commands() {
  local command missing=0
  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || { printf 'ERROR: missing command: %s\n' "$command" >&2; missing=1; }
  done
  return "$missing"
}

run_stage() {
  local label=$1; shift
  printf '==> %s\n' "$label"
  "$@" || { die "stage failed: $label"; return 1; }
}

install_packages() {
  ((${#PACMAN_PACKAGES[@]} == 0)) ||
    run_stage 'Install official packages' sudo pacman -Syu --needed "${PACMAN_PACKAGES[@]}" || return 1
  ((${#AUR_PACKAGES[@]} == 0)) ||
    run_stage 'Install AUR packages' yay -S --needed --removemake --cleanafter "${AUR_PACKAGES[@]}" || return 1
}
```

Add `main` with these exact preflight decisions:

```bash
main() {
  local config_path=${1:-"$SCRIPT_DIR/post-install.conf"}
  local checklist_path=${2:-"$SCRIPT_DIR/manual-post-install-checklist.txt"}
  ((EUID != 0)) || { die 'run this script as a regular user, not root'; return 1; }
  require_commands bash pacman yay sudo mktemp mv || return 1
  parse_config "$config_path" || return 1
  run_stage 'Authenticate sudo' sudo -v || return 1
  install_packages || return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
```

Mark the script executable with `chmod +x post-install.sh`. Task 3 will append removal and cleanup calls after the successful `install_packages` call.

- [ ] **Step 4: Run all tests and syntax checks**

Run: `bash -n post-install.sh tests/test-post-install.sh && bash tests/test-post-install.sh`

Expected: all checks exit 0 and the runner reports `0 failed`.

- [ ] **Step 5: Commit install orchestration**

```bash
git add post-install.sh tests/test-post-install.sh
git commit -m "feat: orchestrate post-install package installation"
```

### Task 3: Explicit Removal and Aggressive Cleanup

**Files:**
- Modify: `post-install.sh`
- Modify: `tests/test-post-install.sh`

**Interfaces:**
- Consumes: `run_stage`, `REMOVE_PACKAGES`, and successful completion of `install_packages`.
- Produces: `collect_installed_removals`; prints installed configured removal targets as NUL-delimited values so names remain array-safe.
- Produces: `remove_configured_packages`; skips absent targets and otherwise runs one `sudo pacman -Rns` transaction.
- Produces: `clean_system`; runs `yay -Yc` followed by `yay -Scc`, stopping if orphan cleanup fails.

- [ ] **Step 1: Extend Pacman mocks and write failing cleanup tests**

Make the Pacman mock recognize queries without logging false mutations:

```bash
if [[ $1 == -Qq ]]; then
  [[ " ${MOCK_INSTALLED:-} " == *" $2 "* ]]
  exit
fi
```

Add tests with `REMOVE_PACKAGES=(file-roller missing-package)` and `MOCK_INSTALLED='file-roller'`. Assert `remove_configured_packages` logs exactly:

```text
sudo pacman -Rns file-roller
```

Add a no-installed-target case and assert no `pacman -Rns` command is logged. Add a cleanup-order case asserting:

```text
yay -Yc
yay -Scc
```

Add fail-fast cases:

- failed `sudo pacman -Rns file-roller` means neither cleanup command runs;
- failed `yay -Yc` means `yay -Scc` does not run;
- failed `yay -Scc` returns nonzero.

- [ ] **Step 2: Run tests and verify the new cases fail**

Run: `bash tests/test-post-install.sh`

Expected: FAIL because `remove_configured_packages` and `clean_system` are undefined.

- [ ] **Step 3: Implement removal and cleanup functions**

Add:

```bash
collect_installed_removals() {
  local package
  for package in "${REMOVE_PACKAGES[@]}"; do
    if pacman -Qq "$package" >/dev/null 2>&1; then
      printf '%s\0' "$package"
    else
      printf 'Skipping absent package: %s\n' "$package" >&2
    fi
  done
}

remove_configured_packages() {
  local -a installed=()
  mapfile -d '' -t installed < <(collect_installed_removals)
  ((${#installed[@]} == 0)) ||
    run_stage 'Remove configured packages' sudo pacman -Rns "${installed[@]}"
}

clean_system() {
  run_stage 'Remove orphaned dependencies' yay -Yc || return 1
  run_stage 'Clear package caches' yay -Scc
}
```

Extend `main` immediately after `install_packages`:

```bash
remove_configured_packages || return 1
clean_system || return 1
```

- [ ] **Step 4: Run cleanup tests and the full suite**

Run: `bash -n post-install.sh tests/test-post-install.sh && bash tests/test-post-install.sh`

Expected: all checks exit 0, commands occur in install → explicit removal → orphan cleanup → cache cleanup order, and the runner reports `0 failed`.

- [ ] **Step 5: Commit destructive-stage orchestration**

```bash
git add post-install.sh tests/test-post-install.sh
git commit -m "feat: remove unwanted packages and installation residue"
```

### Task 4: Atomic Checklist and End-to-End Verification

**Files:**
- Create: `.gitignore`
- Modify: `post-install.sh`
- Modify: `tests/test-post-install.sh`

**Interfaces:**
- Consumes: global `REMINDERS` populated by `parse_config` and the `checklist_path` selected by `main`.
- Produces: `write_checklist <path>`; writes a numbered checklist to a same-directory temporary file, atomically renames it, then prints the completed checklist.
- Completes: `main [config_path] [checklist_path]`; checklist generation becomes its final stage.

- [ ] **Step 1: Write failing checklist and end-to-end tests**

Add unit tests with `REMINDERS=('Enable Bluetooth' 'Configure Fcitx5')` that call `write_checklist "$TEST_TMP/checklist.txt"` and assert this exact file content:

```text
Manual post-install checklist
==============================
[ ] 1. Enable Bluetooth
[ ] 2. Configure Fcitx5
```

Add an atomic-failure test by making the destination directory non-writable in a subprocess, assert the pre-existing checklist content remains unchanged, and restore its permissions before test cleanup.

Add an end-to-end test that invokes `main "$valid_config" "$TEST_TMP/final.txt"` with mocks and verifies this complete command order:

```text
sudo -v
sudo pacman -Syu --needed micro fcitx5
yay -S --needed --removemake --cleanafter auto-cpufreq
sudo pacman -Rns file-roller
yay -Yc
yay -Scc
```

Add another end-to-end case that fails the AUR install and asserts the old checklist remains unchanged, with no removal or cleanup commands logged.

Finally, run the executable from `$TEST_TMP` rather than the project directory, with the default config path and a temporary copy of the script/config, proving path resolution is relative to the script.

- [ ] **Step 2: Run tests and verify the new cases fail**

Run: `bash tests/test-post-install.sh`

Expected: FAIL because `write_checklist` is undefined and `main` does not create the checklist.

- [ ] **Step 3: Implement atomic checklist generation**

Add:

```bash
write_checklist() {
  local destination=$1 directory temporary index
  directory=$(dirname -- "$destination")
  temporary=$(mktemp --tmpdir="$directory" '.manual-post-install.XXXXXX') || {
    die "cannot create checklist temporary file in: $directory"; return 1;
  }
  {
    printf 'Manual post-install checklist\n'
    printf '==============================\n'
    for index in "${!REMINDERS[@]}"; do
      printf '[ ] %d. %s\n' "$((index + 1))" "${REMINDERS[$index]}"
    done
  } >"$temporary" || { rm -f -- "$temporary"; die 'cannot write checklist'; return 1; }
  mv -- "$temporary" "$destination" || { rm -f -- "$temporary"; die "cannot replace checklist: $destination"; return 1; }
  printf '==> Manual configuration remains\n'
  cat -- "$destination"
  printf 'Saved checklist: %s\n' "$destination"
}
```

Add `dirname` and `cat` to `require_commands`, and finish `main` with:

```bash
write_checklist "$checklist_path" || return 1
```

Create `.gitignore` containing:

```gitignore
/manual-post-install-checklist.txt
```

- [ ] **Step 4: Run focused and full verification**

Run:

```bash
bash -n post-install.sh tests/test-post-install.sh
bash tests/test-post-install.sh
git diff --check
```

Expected: syntax validation exits 0; tests report `0 failed`; `git diff --check` emits no output and exits 0. Inspect the mock log from the end-to-end case and confirm no `--noconfirm`, service mutation, or configuration-edit command appears.

- [ ] **Step 5: Review behavior against the approved spec**

Run:

```bash
rg -n -- '--noconfirm|systemctl|eval|source .*post-install\.conf' post-install.sh
rg -n -- 'pacman -Syu --needed|--removemake|--cleanafter|pacman -Rns|yay -Yc|yay -Scc' post-install.sh
rg -n -- 'systemctl (mask power-profiles-daemon.service|enable auto-cpufreq.service|enable bluetooth)' post-install.conf
```

Expected: the executable-code forbidden-pattern search returns no matches; the required-operation search finds all six operation patterns; and service commands appear only in the inert reminder config. Manually compare `post-install.conf` reminders with the Manual Checklist section of the spec and every manual instruction in `sway-eos.md`.

- [ ] **Step 6: Commit the completed tool**

```bash
git add .gitignore post-install.sh tests/test-post-install.sh
git commit -m "feat: generate manual post-install checklist"
```

- [ ] **Step 7: Verify the final committed state**

Run:

```bash
git status --short
git log --oneline -4
bash tests/test-post-install.sh
```

Expected: working tree is clean, four feature commits appear after the design/plan history, and the test runner reports `0 failed`.
