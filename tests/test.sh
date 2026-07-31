#!/usr/bin/env bash
#
# Exercises matrix.sh and asserts the emitted JSON. Run: bash tests/test.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX="${ROOT}/scripts/matrix.sh"

pass=0
fail=0
assert_eq() { # actual  expected  description
  if [ "$1" = "$2" ]; then
    echo "  ok   - $3"
    pass=$((pass + 1))
  else
    echo "  FAIL - $3 (got '$1', want '$2')"
    fail=$((fail + 1))
  fi
}

gen() { # rust arches platforms -> echoes the matrix json
  local out
  out="$(mktemp)"
  GITHUB_OUTPUT="${out}" INPUT_RUST_VERSION="$1" INPUT_ARCHITECTURES="$2" INPUT_PLATFORMS="$3" \
    bash "${MATRIX}" >/dev/null 2>&1
  sed -n 's/^matrix=//p' "${out}"
}

echo "single target:"
m="$(gen stable x86_64 linux)"
assert_eq "$(echo "${m}" | jq '.include | length')" "1" "one entry"
assert_eq "$(echo "${m}" | jq -r '.include[0].runner')" "ubuntu-latest" "runner = ubuntu-latest"
assert_eq "$(echo "${m}" | jq -r '.include[0].target')" "x86_64-unknown-linux-gnu" "target triple correct"
assert_eq "$(echo "${m}" | jq -r '.include[0]["rust-version"]')" "stable" "rust-version propagated"

echo "cartesian 2x2:"
m="$(gen 1.81.0 "x86_64 aarch64" "linux macos")"
assert_eq "$(echo "${m}" | jq '.include | length')" "4" "four entries (2 platforms x 2 arches)"
assert_eq "$(echo "${m}" | jq -r '[.include[].target] | sort | join(",")')" \
  "aarch64-apple-darwin,aarch64-unknown-linux-gnu,x86_64-apple-darwin,x86_64-unknown-linux-gnu" \
  "all four target triples present"
assert_eq "$(echo "${m}" | jq -r '.include[0]["rust-version"]')" "1.81.0" "explicit rust-version honoured"

echo "windows + comma-separated:"
m="$(gen stable "x86_64" "linux,windows")"
assert_eq "$(echo "${m}" | jq -r '[.include[] | select(.platform=="windows")][0].target')" \
  "x86_64-pc-windows-msvc" "windows target triple + comma list parsed"

echo "unsupported combo is skipped:"
m="$(gen stable "x86_64 riscv" linux)"
assert_eq "$(echo "${m}" | jq '.include | length')" "1" "unknown arch dropped, valid kept"

echo
echo "passed: ${pass}, failed: ${fail}"
[ "${fail}" -eq 0 ]
