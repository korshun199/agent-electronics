#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if [[ -x .venv/bin/python ]]; then
    PYTHON_BIN=".venv/bin/python"
else
    PYTHON_BIN="${PYTHON:-python3}"
fi

DEFAULT_ARGS=(--effort low --no-stream)
exec "$PYTHON_BIN" client.py "${DEFAULT_ARGS[@]}" "$@"
