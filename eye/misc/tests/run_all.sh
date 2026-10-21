#!/usr/bin/env bash
#
# Run every headless suite and fail on test failures *or* engine/script errors.
#
# Godot returns exit code 0 even when a GDScript runtime error aborts a test, so
# the output is scanned as well. This is what makes the suite safe for CI.
#
# Usage:
#   misc/tests/run_all.sh
#   GODOT_BIN=/path/to/godot misc/tests/run_all.sh

set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
EYE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$EYE_DIR"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_all: '$GODOT_BIN' not found (set GODOT_BIN)." >&2
	exit 1
fi

echo "== importing =="
"$GODOT_BIN" --headless --import >/dev/null

failed=0
for suite in smoke movement threat world; do
	echo "== ${suite}_test =="
	log="$(mktemp)"
	if "$GODOT_BIN" --headless --script "res://misc/tests/${suite}_test.gd" 2>&1 | tee "$log"; then
		status=0
	else
		status=${PIPESTATUS[0]}
	fi

	if [ "$status" -ne 0 ]; then
		echo "run_all: ${suite}_test exited with $status." >&2
		failed=1
	elif grep -qE 'SCRIPT ERROR:|(^| )ERROR:|^  FAIL ' "$log"; then
		echo "run_all: ${suite}_test reported errors." >&2
		failed=1
	fi

	rm -f "$log"
done

if [ "$failed" -ne 0 ]; then
	echo "run_all: FAILED" >&2
	exit 1
fi

echo "run_all: all suites passed."
