#!/usr/bin/env bash
# zk-ePrescription entry point (the Docker image's ENTRYPOINT).
#
#   demo   one redemption end to end in both backends, explained   (claims C1, C2)
#   test   full regression with a summary table                     (claim C2)
#   kat    cross-backend equality of every protocol value           (claim C1)
#   help   this text
#
# Any other command is executed as given, e.g. `docker run -it zkep bash`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmd="${1:-test}"

case "$cmd" in
    demo) exec bash "$REPO/scripts/demo.sh" ;;
    test) exec bash "$REPO/scripts/test.sh" ;;
    kat)
        echo "zk-ePrescription: cross-backend equality (JS reference = Circom = Noir)"
        echo "full log: results/logs/kat.log"
        exec bash "$REPO/scripts/kat/run_cross_backend_kat.sh" ;;
    help|-h|--help)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        echo
        echo "Benchmark (claim C3) runs on the host, not in this container: see bench/README.md" ;;
    *) exec "$@" ;;
esac
