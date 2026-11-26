#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="${1:-}"
expected_commit="25356b59a96dc975d777844f896b7c7855ea90e6"
expected_config_commit="8057d261bb43a706764f73928b919af62666c247"

if [[ -z "$source_dir" ]] || ! git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'ERROR: pass the clean Betaflight 4.5.4 checkout path.\n' >&2
    exit 2
fi
if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$expected_commit" ]]; then
    printf 'ERROR: unexpected Betaflight commit.\n' >&2
    exit 2
fi
if ! git -C "$source_dir/src/config" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
   [[ "$(git -C "$source_dir/src/config" rev-parse HEAD)" != "$expected_config_commit" ]]; then
    printf 'ERROR: unexpected or missing src/config submodule.\n' >&2
    exit 2
fi
if [[ -n "$(git -C "$source_dir" status --porcelain)" || -n "$(git -C "$source_dir/src/config" status --porcelain)" ]]; then
    printf 'ERROR: checkout and config submodule must be clean; no patch applied.\n' >&2
    exit 2
fi

git -C "$source_dir" apply --check "$package_dir/patches/betaflight.patch"
git -C "$source_dir/src/config" apply --check "$package_dir/patches/target-config.patch"
git -C "$source_dir" apply "$package_dir/patches/betaflight.patch"
git -C "$source_dir/src/config" apply "$package_dir/patches/target-config.patch"
printf 'Keyboard + mouse patches applied. No device was written.\n'
