#!/usr/bin/env bash
# scripts/specs/test-utils.bash — shared assert library for all per-module specs.
# Counter semantics: PASS/FAIL are shared across specs; sourcing this file never
# resets counters that already exist (the combined runner sources it once).
if [[ -z "${PASS+x}" || -z "${FAIL+x}" ]]; then
  PASS=0
  FAIL=0
fi

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: <%s>\n  actual:   <%s>\n' "$label" "$expected" "$actual" >&2
  fi
}

assert_status() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected status: <%s>\n  actual status:   <%s>\n' "$label" "$expected" "$actual" >&2
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected to contain: <%s>\n  actual: <%s>\n' "$label" "$needle" "$haystack" >&2
  fi
}

# Bottom guard shared by every spec: a standalone run prints totals and exits
# on FAIL; a sourced run (the combined runner) defers — the runner owns the
# single combined totals print. BASH_SOURCE[1] is the spec that called this,
# which equals $0 exactly when that spec is the executing script.
finish_spec() {
  if [[ "${BASH_SOURCE[1]}" == "$0" ]]; then
    printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
    if [[ "$FAIL" -gt 0 ]]; then
      exit 1
    fi
    exit 0
  fi
}

# Bottom guard for test-utils itself (standalone run of the library only).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
