# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

Build, test and package a Rust project across a **dynamic** platform/architecture
matrix, in pure shell. Two pieces:

1. A composite **action** (`action.yml` + `scripts/matrix.sh`) that **emits a JSON
   build matrix** — the dynamic-matrix generator.
2. A reusable **workflow** (`.github/workflows/rust-release.yml`,
   `on: workflow_call`) that fans out over that matrix: installs Rust, runs
   `cargo build --release` + `cargo test` per target, then packages each target
   as a **zip** (release binary + release notes), uploads it as a workflow
   artifact, and optionally attaches it to the GitHub Release.

Only external actions used: `actions/checkout`, `dtolnay/rust-toolchain`,
`actions/upload-artifact`.

## The dynamic matrix (the crux — do not "fix" this into a static matrix)

A composite action can't spawn its own matrix, so this repo uses the
**generator-emits-JSON → consumer `fromJSON`** pattern:

- `scripts/matrix.sh` reads `INPUT_RUST_VERSION`, `INPUT_ARCHITECTURES`,
  `INPUT_PLATFORMS`, takes the cartesian product, maps each `platform:arch` to a
  **native runner + Rust target triple**, and writes
  `matrix={"include":[{platform,arch,runner,target,rust-version},…]}` to
  `$GITHUB_OUTPUT`. Unsupported combos are skipped with `::warning::`.
- `action.yml` exposes that as its `matrix` output.
- In the reusable workflow, the `matrix` job runs the action; the `build` job
  consumes it: `strategy: matrix: ${{ fromJSON(needs.matrix.outputs.matrix) }}`
  and `runs-on: ${{ matrix.runner }}`.

**Native-runner mapping is deliberate** — each target builds on its own OS/arch
runner so `cargo test` actually runs (no cross-compilation). The mapping
(`scripts/matrix.sh`):

| platform / arch | runner            | target triple               |
| --------------- | ----------------- | --------------------------- |
| linux x86_64    | `ubuntu-latest`   | `x86_64-unknown-linux-gnu`  |
| linux aarch64   | `ubuntu-24.04-arm`| `aarch64-unknown-linux-gnu` |
| macos x86_64    | `macos-15-intel`  | `x86_64-apple-darwin`       |
| macos aarch64   | `macos-latest`    | `aarch64-apple-darwin`      |
| windows x86_64  | `windows-latest`  | `x86_64-pc-windows-msvc`    |
| windows aarch64 | `windows-11-arm`  | `aarch64-pc-windows-msvc`   |

`macos-15-intel` replaced `macos-13` (the old Intel image is being retired);
`windows-11-arm` has limited availability.

## Layout

- `action.yml` — the matrix generator (composite; one shell step → `matrix`).
- `scripts/matrix.sh` — the platform×arch → runner+target mapping + JSON.
- `.github/workflows/rust-release.yml` — the reusable workflow.
- `.github/workflows/ci.yml` — shellcheck + tests.
- `tests/test.sh` — asserts over `matrix.sh` JSON (uses `jq`).
- `README.md`, `LICENSE` (MIT).

## Reusable-workflow behaviour

- Inputs: `rust-version` (default `stable` = latest), `architectures`,
  `platforms`, `bin-name` (default: the `[package] name` in Cargo.toml),
  `release-notes` (default `RELEASE_NOTES.md`), `upload-to-release` (bool).
- Per target: install toolchain + target, `cargo build --release --target …`,
  then a **test step that auto-skips when the crate has no tests** — it greps for
  `#[test]` / `#[cfg(test)]` in `src` or `tests/*.rs`; if none, emits a
  `::notice::` and skips instead of failing. Then it packages a zip (binary,
  plus `.exe` on Windows, + the release notes) using `zip` on Linux/macOS and
  `7z` on Windows, uploads an artifact, and `gh release upload`s on a tag when
  `upload-to-release` is set.

## Commands

```bash
bash tests/test.sh                 # asserts matrix.sh output (needs jq)
shellcheck -x --severity=warning scripts/*.sh tests/*.sh
```

The multi-OS build itself can only really be exercised on GitHub runners; a live
demo lives on the `test/rust-release` branch of `mrdoodles/versioning-tests`.

## Coding style

Pure `bash`, `set -euo pipefail`, clean under `shellcheck -x --severity=warning`.
The matrix logic is unit-tested with `jq` assertions — change the mapping and the
tests together. See the bundled **shell-scripting** skill
(`.claude/skills/shell-scripting/`) for the shared gotchas (quote `done`,
`set -e` function returns, `INPUT_*` via `env:`, the dynamic-matrix pattern,
cross-OS packaging).

## Versioning & releasing (manual — no release workflow)

Cut releases by hand: `git tag -a vX.Y.Z`, force-move the major tag
(`git tag -f -a vN`), push both, `gh release create`. History: **v1.0.0**
(initial) → **v1.0.1** (`macos-15-intel`) → **v1.1.0** (test auto-skip). `@v1` is
the moving major tag.

**The reusable workflow references the action as `mrdoodles/rust-release@v1`** —
keep the action tag and the workflow tag on the same `v1`, and after a breaking
change cut the release so the workflow's `@v1` resolves to the matched code.

## Gotchas

- **Reusable-workflow permissions:** it declares `contents: write`; the *caller*
  must grant at least that, or the run is a `startup_failure` (a caller with only
  `contents: read` fails to start).
- Native-runner mapping avoids cross-compilation; some runners are constrained
  (`macos-15-intel` Intel is slower/being phased out; `windows-11-arm` limited).
  Unsupported `platform/arch` combos are skipped, not errored.
- Packaging branches on `$RUNNER_OS` (`zip` vs `7z`); binary name defaults to the
  Cargo.toml package name and gets `.exe` on Windows.
