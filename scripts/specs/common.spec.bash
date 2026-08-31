#!/usr/bin/env bash
# scripts/specs/common.spec.bash — shared assert library for all per-module specs.
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

# Bottom guard: when run standalone, print totals and exit on FAIL.
# When sourced by the combined runner (all.spec.bash), do nothing — the
# runner owns the single combined totals print.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'PASS: %d FAIL: %d\n' "$PASS" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi
