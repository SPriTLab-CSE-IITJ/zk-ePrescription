#!/usr/bin/env bash
# Full regression for the aligned Phase-4 protocol
# (docs/protocol_specification.md). Canonical entry point of the Docker image.
#
#   1. Circom / Groth16: compile, positive witnesses (+ public-output check),
#      negative vectors, isolated Schnorr vectors, setup, prove, verify,
#      tampered public signals.
#   2. Noir / UltraHonk: unit tests, positive vectors (execute + output check
#      + bb prove/verify + tampered public inputs), negative vectors.
#   3. Issuance-side patient binding (Noir).
#   4. Cross-backend known-answer tests (JS reference vs Circom vs Noir).
#
# ZKEP_SKIP_BB=1 skips only bb prove/verify (see run_positive_suite.sh) and
# makes the overall run report INCOMPLETE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo
echo "=================================================="
echo " zk-ePrescription Full Regression Test"
echo "=================================================="

echo
echo "==================== CIRCOM ======================"

(
    cd "$ROOT/circom"
    npm test
)

echo
echo "===================== NOIR ======================="

(
    cd "$ROOT/noir/common"
    nargo test
)

(
    cd "$ROOT/noir/phase4_orchestrator"
    nargo check
    nargo test
)

(
    cd "$ROOT/noir/phase4_orchestrator/tests/scripts"
    ./run_positive_suite.sh
    ./run_negative_suite.sh
)

echo
echo "============== PATIENT BINDING ==================="

(
    cd "$ROOT/noir/patient_binding_issuance"
    nargo check
    nargo test
    nargo execute
)

echo
echo "============ CROSS-BACKEND KATs =================="

bash "$ROOT/scripts/kat/run_cross_backend_kat.sh"

echo
echo "=================================================="
if [ "${ZKEP_SKIP_BB:-0}" = "1" ]; then
    echo " REGRESSION INCOMPLETE: bb prove/verify skipped (ZKEP_SKIP_BB=1)"
else
    echo " ALL REGRESSION TESTS PASSED"
fi
echo "=================================================="
