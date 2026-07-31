# Rust Release

Build, test and package a Rust project across a **dynamic** platform/architecture
matrix. Two pieces, in pure shell:

1. A composite **action** that emits a JSON build matrix (runner + Rust target
   triple per platform/arch) — consume it with `fromJSON` in your own workflow.
2. A **reusable workflow** that fans out over that matrix: installs Rust, runs
   `cargo build --release` + `cargo test` for each target, then packages each as
   a **zip** containing the release binary and the release notes.

## Reusable workflow (build + test + package)

```yaml
jobs:
  release:
    uses: mrdoodles/rust-release/.github/workflows/rust-release.yml@v1
    with:
      rust-version: stable            # optional; default: latest stable
      platforms: "linux macos windows"
      architectures: "x86_64 aarch64"
      release-notes: RELEASE_NOTES.md # included in each zip
      upload-to-release: true         # attach zips to the GitHub Release on a tag
```

### Workflow inputs

| Input               | Default            | Description                                            |
| ------------------- | ------------------ | ------------------------------------------------------ |
| `rust-version`      | `stable`           | Rust toolchain (latest stable).                        |
| `platforms`         | `linux`            | Space/comma list: `linux`, `macos`, `windows`.         |
| `architectures`     | `x86_64`           | Space/comma list: `x86_64`, `aarch64`.                 |
| `bin-name`          | Cargo.toml name    | Binary to package.                                     |
| `release-notes`     | `RELEASE_NOTES.md` | File included in each zip.                              |
| `upload-to-release` | `false`            | Attach zips to the GitHub Release when run for a tag.  |

Tests run automatically when the crate has any (`#[test]` / `#[cfg(test)]` in
`src`, or integration tests under `tests/`). If none are found, the test step is
skipped and a notice is emitted — the build still proceeds and packages.

## Matrix action only (dynamic matrix)

Use just the matrix generator and drive your own build job:

```yaml
jobs:
  matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.gen.outputs.matrix }}
    steps:
      - id: gen
        uses: mrdoodles/rust-release@v1
        with:
          platforms: "linux macos"
          architectures: "x86_64 aarch64"
  build:
    needs: matrix
    strategy:
      matrix: ${{ fromJSON(needs.matrix.outputs.matrix) }}
    runs-on: ${{ matrix.runner }}
    steps: [...]
```

The `matrix` output looks like:

```json
{"include":[
  {"platform":"linux","arch":"x86_64","runner":"ubuntu-latest","target":"x86_64-unknown-linux-gnu","rust-version":"stable"},
  {"platform":"macos","arch":"aarch64","runner":"macos-latest","target":"aarch64-apple-darwin","rust-version":"stable"}
]}
```

## Platform / architecture mapping

Each combination maps to a **native** runner (so tests run without
cross-compilation):

| platform / arch | runner            | target triple                |
| --------------- | ----------------- | ---------------------------- |
| linux x86_64    | `ubuntu-latest`   | `x86_64-unknown-linux-gnu`   |
| linux aarch64   | `ubuntu-24.04-arm`| `aarch64-unknown-linux-gnu`  |
| macos x86_64    | `macos-15-intel`  | `x86_64-apple-darwin`        |
| macos aarch64   | `macos-latest`    | `aarch64-apple-darwin`       |
| windows x86_64  | `windows-latest`  | `x86_64-pc-windows-msvc`     |
| windows aarch64 | `windows-11-arm`  | `aarch64-pc-windows-msvc`    |

Unsupported combinations are skipped with a warning.
