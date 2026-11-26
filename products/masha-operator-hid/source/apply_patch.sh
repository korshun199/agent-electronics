#!/usr/bin/env bash
set -euo pipefail

# Применяет проверенные патчи к чистому Betaflight 4.5.4 и его config-submodule.
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="${1:-}"
expected_commit="25356b59a96dc975d777844f896b7c7855ea90e6"
expected_config_commit="8057d261bb43a706764f73928b919af62666c247"

if [[ -z "$source_dir" ]] || ! git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Ошибка: укажи путь к checkout Betaflight 4.5.4.\n' >&2
    exit 2
fi

actual_commit="$(git -C "$source_dir" rev-parse HEAD)"
if [[ "$actual_commit" != "$expected_commit" ]]; then
    printf 'Ошибка: нужен Betaflight commit %s, найден %s.\n' "$expected_commit" "$actual_commit" >&2
    exit 2
fi

if ! git -C "$source_dir/src/config" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Ошибка: не инициализирован src/config submodule.\n' >&2
    exit 2
fi

actual_config_commit="$(git -C "$source_dir/src/config" rev-parse HEAD)"
if [[ "$actual_config_commit" != "$expected_config_commit" ]]; then
    printf 'Ошибка: нужен src/config commit %s, найден %s.\n' "$expected_config_commit" "$actual_config_commit" >&2
    exit 2
fi

if [[ -n "$(git -C "$source_dir" status --porcelain)" || -n "$(git -C "$source_dir/src/config" status --porcelain)" ]]; then
    printf 'Ошибка: checkout или config-submodule не чистые; патч не применён.\n' >&2
    exit 2
fi

git -C "$source_dir" apply --check "$package_dir/patches/betaflight.patch"
git -C "$source_dir/src/config" apply --check "$package_dir/patches/target-config.patch"
git -C "$source_dir" apply "$package_dir/patches/betaflight.patch"
git -C "$source_dir/src/config" apply "$package_dir/patches/target-config.patch"
printf 'Патчи применены к %s. Ничего на плату не записывалось.\n' "$source_dir"
