#!/usr/bin/env bash
# Full regression for the zk-ePrescription redemption protocol
# (docs/protocol_specification.md), run in both backends:
#
#   [1] Circom / Groth16      scripts/circom_suite.sh
#   [2] Noir / UltraHonk      scripts/noir_suite.sh
#   [3] attack vectors        which check rejected each NT vector, per backend
#   [4] cross-backend KAT     scripts/kat/run_cross_backend_kat.sh
#
# One line per check on screen; full tool output in results/logs/.
# ZKEP_SKIP_BB=1 skips only bb prove/verify and reports the run as INCOMPLETE.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/report.sh
. "$REPO/scripts/lib/report.sh"
: >"$RESULTS/counts.env"

START=$(date +%s)
echo "zk-ePrescription: regression of the redemption protocol in both backends"
echo "toolchain: $(circom --version | sed 's/circom compiler //') circom | $(snarkjs --version 2>&1 | head -1 | sed 's/snarkjs@//') snarkjs | $(nargo --version | head -1 | sed 's/nargo version = //') nargo | $(bb --version) bb"
echo "full logs: results/logs/"

step "1/4" "Circom / Groth16"
bash "$REPO/scripts/circom_suite.sh"

step "2/4" "Noir / UltraHonk"
bash "$REPO/scripts/noir_suite.sh"

step "3/4" "Attack vectors: each one must fail a circuit constraint in both backends"
node "$REPO/scripts/lib/attacks.js" "$REPO" "$RESULTS" full

step "4/4" "Cross-backend equality: JS reference = Circom = Noir"
bash "$REPO/scripts/kat/run_cross_backend_kat.sh"

# shellcheck disable=SC1091
. "$RESULTS/counts.env"
ELAPSED=$(( $(date +%s) - START ))
{
    echo
    echo "SUMMARY                                   Circom / Groth16    Noir / UltraHonk"
    printf '  %-40s %-19s %s\n' "valid redemptions (outputs = fixture)" "$circom_valid/$circom_valid" "$noir_valid/$noir_valid"
    printf '  %-40s %-19s %s\n' "proofs generated and verified" "$circom_proofs" "$noir_proofs"
    printf '  %-40s %-19s %s\n' "attack vectors rejected" "$circom_attacks" "$noir_attacks"
    printf '  %-40s %-19s %s\n' "tampered public inputs rejected" "$circom_tampered" "$noir_tampered"
    printf '  %-40s %-19s %s\n' "Schnorr verifier vectors" "$circom_schnorr" "$noir_schnorr"
    printf '  %-40s %-19s %s\n' "circuit size (native units)" "$circom_constraints R1CS" "$noir_acir_opcodes ACIR opcodes"
    printf '  %-40s %s\n' "library tests / issuance binding (Noir)" "$noir_common / $noir_binding"
    printf '  %-40s %s\n' "cross-backend KAT" "$kat_total equal"
    echo
    if [ "${ZKEP_SKIP_BB:-0}" = "1" ]; then
        echo "RESULT: INCOMPLETE (bb prove/verify skipped by ZKEP_SKIP_BB=1) in ${ELAPSED}s"
    else
        echo "RESULT: ALL REGRESSION TESTS PASSED in ${ELAPSED}s"
    fi
} | tee "$RESULTS/summary.txt"
