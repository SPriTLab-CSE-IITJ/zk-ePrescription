#!/usr/bin/env bash
# Noir negative suite for the integrated Phase-4 circuit.
# Every vector in tests/negative/ must be rejected by a circuit assertion
# ("Failed constraint") during nargo execute.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PKG="phase4_orchestrator"

echo
echo "==============================================="
echo "Running Negative Suite"
echo "Package : $PKG"
echo "==============================================="

(
    cd "$PKG_ROOT"
    nargo compile
)

for VECTOR in "$PKG_ROOT/tests/negative"/*.toml
do
    NAME="$(basename "$VECTOR" .toml)"

    echo
    echo ">>> $NAME: $(head -1 "$VECTOR" | sed 's/^# [A-Z0-9-]*: //')"

    cp "$VECTOR" "$PKG_ROOT/_vector.toml"

    LOG_FILE="$(mktemp)"

    if (
        cd "$PKG_ROOT"
        nargo execute --prover-name _vector >"$LOG_FILE" 2>&1
    ); then
        echo "FAIL (unexpectedly succeeded)"
        cat "$LOG_FILE"
        rm -f "$LOG_FILE" "$PKG_ROOT/_vector.toml"
        exit 1
    elif grep -q "Failed constraint" "$LOG_FILE"; then
        echo "PASS (expected constraint failure at $(grep -m1 -oE 'src/[a-z_]+\.nr:[0-9]+' "$LOG_FILE"))"
    else
        echo "FAIL (execution, parsing, or toolchain error)"
        cat "$LOG_FILE"
        rm -f "$LOG_FILE" "$PKG_ROOT/_vector.toml"
        exit 1
    fi

    rm -f "$LOG_FILE" "$PKG_ROOT/_vector.toml"
done

echo
echo "==============================================="
echo "ALL NEGATIVE TESTS PASSED"
echo "==============================================="
