#!/usr/bin/env bash
#
# Emit a dynamic build matrix (JSON) for a Rust release from a list of
# platforms and architectures. Each platform/arch combination is mapped to a
# GitHub runner label and a Rust target triple, so every target builds and
# tests natively (no cross-compilation).
#
# Inputs (env):
#   INPUT_RUST_VERSION    Rust toolchain (default: stable = latest stable).
#   INPUT_ARCHITECTURES   Space/comma list, e.g. "x86_64 aarch64".
#   INPUT_PLATFORMS       Space/comma list, e.g. "linux macos windows".
#
# Output (to $GITHUB_OUTPUT):
#   matrix   {"include":[{platform,arch,runner,target,rust-version}, ...]}
#
set -euo pipefail

: "${GITHUB_OUTPUT:=/dev/stdout}"

RUST_VERSION="${INPUT_RUST_VERSION:-stable}"

normalize() { echo "$1" | tr ',' ' ' | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//'; }
ARCHES="$(normalize "${INPUT_ARCHITECTURES:-x86_64}")"
PLATFORMS="$(normalize "${INPUT_PLATFORMS:-linux}")"

# platform:arch -> "runner|target-triple" (empty = unsupported)
map_target() {
  case "$1:$2" in
    linux:x86_64)    echo "ubuntu-latest|x86_64-unknown-linux-gnu" ;;
    linux:aarch64)   echo "ubuntu-24.04-arm|aarch64-unknown-linux-gnu" ;;
    macos:x86_64)    echo "macos-13|x86_64-apple-darwin" ;;
    macos:aarch64)   echo "macos-latest|aarch64-apple-darwin" ;;
    windows:x86_64)  echo "windows-latest|x86_64-pc-windows-msvc" ;;
    windows:aarch64) echo "windows-11-arm|aarch64-pc-windows-msvc" ;;
    *)               echo "" ;;
  esac
}

items=""
for platform in ${PLATFORMS}; do
  for arch in ${ARCHES}; do
    mapping="$(map_target "${platform}" "${arch}")"
    if [ -z "${mapping}" ]; then
      echo "::warning::Unsupported platform/arch combination '${platform}/${arch}'; skipping."
      continue
    fi
    runner="${mapping%%|*}"
    target="${mapping##*|}"
    items="${items}{\"platform\":\"${platform}\",\"arch\":\"${arch}\",\"runner\":\"${runner}\",\"target\":\"${target}\",\"rust-version\":\"${RUST_VERSION}\"},"
    echo "  + ${platform}/${arch} -> ${runner} (${target})"
  done
done

if [ -z "${items}" ]; then
  echo "::error::No valid platform/architecture combinations were produced."
  exit 1
fi

matrix="{\"include\":[${items%,}]}"
echo "matrix=${matrix}" >> "${GITHUB_OUTPUT}"
echo "matrix=${matrix}"
