# shellcheck shell=bash
# Shared output helpers for the zk-ePrescription test scripts.
#
# The screen shows one line per check; every tool's full output goes to a log
# file under results/logs/. On a failure the last lines of that log are shown.

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RESULTS="${ZKEP_RESULTS:-$REPO/results}"
LOGS="$RESULTS/logs"
mkdir -p "$LOGS"
: "${LOG:=$LOGS/run.log}"

# step "1/7" "Title"
step() { printf '\n[%s] %s\n' "$1" "$2"; }

# item "label" "result": one aligned result line
item() {
    local label="$1" result="$2" n
    n=$((50 - ${#label}))
    [ "$n" -lt 2 ] && n=2
    printf '      %s %s %s\n' "$label" "$(printf '%*s' "$n" '' | tr ' ' '.')" "$result"
}

ok() { item "$1" "$2  PASS"; }

# fail "label" "reason": print the failure and the end of the log, then stop
fail() {
    item "$1" "$2  FAIL"
    echo "      full log: ${LOG#"$REPO"/}"
    tail -n 15 "$LOG" 2>/dev/null | sed 's/^/      | /'
    exit 1
}

# quiet cmd...: run a command with all of its output appended to the log
quiet() { "$@" >>"$LOG" 2>&1; }

# record key value: counts that the final summary reads
record() { echo "$1=$2" >>"$RESULTS/counts.env"; }
