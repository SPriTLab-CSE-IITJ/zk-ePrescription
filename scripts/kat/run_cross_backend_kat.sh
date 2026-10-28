#!/usr/bin/env bash
# Cross-backend known-answer tests (docs/protocol_specification.md Section 17).
#
# For each KAT input set, evaluates
#   - the JS reference      (circom/scripts/lib/poseidon2.js)
#   - the Circom backend    (circom/circuits/kat/kat_hashes.circom witness)
#   - the Noir backend      (noir/kat, nargo execute)
# on: raw Poseidon2 permutation (also vs independent zkhash vectors), sponge
# n = 1..7, H1..H6; plus the Noir registry generator (leaves, auth paths,
# root) and the issuance-binding circuits against the canonical fixture.
# Results are written to testdata/kat/cross_backend_kat_results.json.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG="${ZKEP_RESULTS:-$REPO/results}/logs/kat.log"
# shellcheck source=../lib/report.sh
. "$REPO/scripts/lib/report.sh"
: >"$LOG"

WORK="${TMPDIR:-/tmp}/zkep-kat"
rm -rf "$WORK"; mkdir -p "$WORK"

quiet node "$REPO/scripts/kat/cross_backend_kat.js" prepare "$WORK" || fail "prepare KAT inputs" "error"

# Circom
quiet circom "$REPO/circom/circuits/kat/kat_hashes.circom" --wasm -o "$WORK" || fail "Circom KAT circuit" "compile error"
for set in $(cat "$WORK/sets.txt"); do
    quiet node "$WORK/kat_hashes_js/generate_witness.js" "$WORK/kat_hashes_js/kat_hashes.wasm" \
        "$WORK/$set.circom.json" "$WORK/$set.wtns" || fail "Circom KAT witness $set" "error"
    quiet snarkjs wtns export json "$WORK/$set.wtns" "$WORK/$set.circom.wtns.json"
done

# Noir
for set in $(cat "$WORK/sets.txt"); do
    (cd "$REPO/noir/kat" && nargo execute --prover-name "KAT_$set") >"$WORK/$set.noir.out" 2>&1 \
        || { cat "$WORK/$set.noir.out" >>"$LOG"; fail "Noir KAT execution $set" "error"; }
done

# Noir registry generator: rebuilds the 4-doctor registry from the fixture keys
for i in 0 1 2 3; do
    sed "s/^doctor_index = .*/doctor_index = \"$i\"/" "$REPO/noir/registry_generator/Prover.toml" \
        >"$REPO/noir/registry_generator/_kat_index.toml"
    (cd "$REPO/noir/registry_generator" && nargo execute --prover-name _kat_index) \
        >"$WORK/registry_generator_$i.noir.out" 2>&1 \
        || { rm -f "$REPO/noir/registry_generator/_kat_index.toml"; cat "$WORK/registry_generator_$i.noir.out" >>"$LOG"; fail "registry generator doctor $i" "error"; }
done
rm -f "$REPO/noir/registry_generator/_kat_index.toml"

# Issuance-side binding: Circom and Noir circuits
quiet circom "$REPO/circom/circuits/issuance_binding.circom" --wasm -o "$WORK" || fail "Circom issuance circuit" "compile error"
quiet node "$WORK/issuance_binding_js/generate_witness.js" \
    "$WORK/issuance_binding_js/issuance_binding.wasm" \
    "$REPO/circom/inputs/eprescription/patient_binding_issuance.json" "$WORK/pb.wtns"
quiet snarkjs wtns export json "$WORK/pb.wtns" "$WORK/patient_binding.circom.wtns.json"
(cd "$REPO/noir/issuance_binding" && nargo execute) >"$WORK/patient_binding.noir.out" 2>&1 \
    || { cat "$WORK/patient_binding.noir.out" >>"$LOG"; fail "Noir issuance circuit" "error"; }

# Compare JS reference, Circom and Noir
node "$REPO/scripts/kat/cross_backend_kat.js" compare "$WORK" >"$WORK/compare.txt" 2>&1 || CMP_FAILED=1
cat "$WORK/compare.txt" >>"$LOG"
[ -z "${CMP_FAILED:-}" ] || fail "cross-backend comparison" "mismatch (see log)"

while read -r name eq _; do
    case "$name" in
        canonical|doctor1|doctor2|doctor3|edge|zero) ok "input set '$name': 17 protocol values" "$eq equal" ;;
    esac
done <"$WORK/compare.txt"
reg="$(grep -c '^registry_generator doctor [0-9]: equal' "$WORK/compare.txt")"
ok "registry generator: leaves, paths, root" "$reg/4 equal"
grep -q '^patient binding circuits: equal' "$WORK/compare.txt" && ok "issuance binding circuits: I and PB" "1/1 equal"
total="$(sed -n 's/^TOTAL \([0-9]*\/[0-9]*\) equal$/\1/p' "$WORK/compare.txt")"
record kat_total "$total"
ok "TOTAL (JS reference = Circom = Noir)" "$total equal"
