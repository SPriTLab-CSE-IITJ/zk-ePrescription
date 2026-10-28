#!/usr/bin/env bash
# Cross-backend known-answer tests (docs/protocol_specification.md Section 17).
#
# For each KAT input set, evaluates
#   - the JS reference      (circom/scripts/lib/poseidon2.js)
#   - the Circom backend    (circom/circuits/kat/kat_hashes.circom witness)
#   - the Noir backend      (noir/cross_backend_kat, nargo execute)
# on: raw Poseidon2 permutation (also vs independent zkhash vectors), sponge
# n = 1..7, H1..H6; plus the Noir registry generator (leaves, auth paths,
# root) against the canonical fixture. Results are written to
# testdata/kat/cross_backend_kat_results.json.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${TMPDIR:-/tmp}/zkep-kat"
rm -rf "$WORK"; mkdir -p "$WORK"

node "$REPO/scripts/kat/cross_backend_kat.js" prepare "$WORK"

echo "== Circom KAT harness =="
circom "$REPO/circom/circuits/kat/kat_hashes.circom" --wasm -o "$WORK" >/dev/null
for set in $(cat "$WORK/sets.txt"); do
    node "$WORK/kat_hashes_js/generate_witness.js" "$WORK/kat_hashes_js/kat_hashes.wasm" \
        "$WORK/$set.circom.json" "$WORK/$set.wtns"
    snarkjs wtns export json "$WORK/$set.wtns" "$WORK/$set.circom.wtns.json" >/dev/null
done

echo "== Noir KAT harness =="
(
    cd "$REPO/noir/cross_backend_kat"
    for set in $(cat "$WORK/sets.txt"); do
        nargo execute --prover-name "KAT_$set" > "$WORK/$set.noir.out" 2>&1
    done
)

echo "== Noir registry generator =="
# The generator package is nested inside noir/phase3_registry, and nargo
# resolves the enclosing package when invoked in place (pre-existing layout
# issue, also present before the alignment work). It is therefore executed
# from an unmodified copy.
cp -r "$REPO/noir/phase3_registry/tools/registry_generator" "$WORK/registry_generator"
(
    cd "$WORK/registry_generator"
    for i in 0 1 2 3; do
        sed "s/^doctor_index = .*/doctor_index = \"$i\"/" Prover.toml > "KAT_index_$i.toml"
        nargo execute --prover-name "KAT_index_$i" > "$WORK/registry_generator_$i.noir.out" 2>&1
    done
)

echo "== Patient binding circuits (issuance side) =="
circom "$REPO/circom/circuits/09_patient_binding_issuance.circom" --wasm -o "$WORK" >/dev/null
node "$WORK/09_patient_binding_issuance_js/generate_witness.js" \
    "$WORK/09_patient_binding_issuance_js/09_patient_binding_issuance.wasm" \
    "$REPO/circom/inputs/eprescription/patient_binding_issuance.json" "$WORK/pb.wtns"
snarkjs wtns export json "$WORK/pb.wtns" "$WORK/patient_binding.circom.wtns.json" >/dev/null
(
    cd "$REPO/noir/patient_binding_issuance"
    nargo execute > "$WORK/patient_binding.noir.out" 2>&1
)

echo "== Compare =="
node "$REPO/scripts/kat/cross_backend_kat.js" compare "$WORK"
