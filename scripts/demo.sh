#!/usr/bin/env bash
# One prescription redeemed end to end in both backends (canonical vector
# TV-001), with each step explained. Full tool output: results/logs/demo.log
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${ZKEP_RESULTS:-$REPO/results}/logs/demo.log"
# shellcheck source=lib/report.sh
. "$REPO/scripts/lib/report.sh"
: >"$LOG"

TMP="${TMPDIR:-/tmp}/zkep-demo"; rm -rf "$TMP"; mkdir -p "$TMP"
TV="$REPO/circom/inputs/eprescription/canonical/TV-001.json"
NOIR="$REPO/noir/redemption"
SNARKJS="${SNARKJS:-snarkjs}"
SKIP_BB="${ZKEP_SKIP_BB:-0}"
hexof() { node -e 'console.log("0x" + BigInt(process.argv[1]).toString(16).padStart(64, "0"))' "$1"; }
field() { node -e 'console.log(require(process.argv[1])[process.argv[2]])' "$TV" "$1"; }

echo "zk-ePrescription demo: one redemption, two proving stacks"
echo "The patient proves the prescription is valid without revealing the secret,"
echo "the doctor's identity or the prescription fields."

step "1/6" "The prescription (canonical vector TV-001)"
item "prescription id / medicine code" "$(field prescription_id) / $(field medicine_code)"
item "doctor id (registry has 4 doctors)" "$(field doctor_id)"
item "expiry / allowed redemptions" "$(field expiry) / $(field threshold)"
item "redemption slot" "$(field slot_index)"
item "today's date (public, set by the pharmacy)" "$(field current_date)"
echo "      private to the patient: secret, slot, all fields above except the date,"
echo "      the doctor's key and signature, and the registry path"

step "2/6" "Circom / Groth16: compute the public outputs and prove"
quiet circom "$REPO/circom/circuits/redemption.circom" --r1cs --wasm -o "$TMP" || fail "compile" "error"
quiet node "$TMP/redemption_js/generate_witness.js" "$TMP/redemption_js/redemption.wasm" "$TV" "$TMP/w.wtns" || fail "witness" "error"
quiet "$SNARKJS" wtns export json "$TMP/w.wtns" "$TMP/w.json"
C_CIRCOM="$(hexof "$(node -e 'console.log(require(process.argv[1])[1])' "$TMP/w.json")")"
N_CIRCOM="$(hexof "$(node -e 'console.log(require(process.argv[1])[2])' "$TMP/w.json")")"
item "commitment C" "$C_CIRCOM"
item "nullifier N" "$N_CIRCOM"
echo "      one-time Groth16 setup (local dev ceremony; a few minutes) ..."
(
    cd "$TMP"
    if [ -n "${ZKEP_PTAU:-}" ]; then
        cp "$ZKEP_PTAU" pf.ptau
    else
        quiet "$SNARKJS" powersoftau new bn128 15 p0.ptau
        quiet "$SNARKJS" powersoftau contribute p0.ptau p1.ptau --name=demo -e=demo-entropy
        quiet "$SNARKJS" powersoftau prepare phase2 p1.ptau pf.ptau
    fi
    quiet "$SNARKJS" groth16 setup redemption.r1cs pf.ptau k0.zkey
    quiet "$SNARKJS" zkey contribute k0.zkey k.zkey --name=demo -e=demo-zkey-entropy
    quiet "$SNARKJS" zkey export verificationkey k.zkey vk.json
    quiet "$SNARKJS" groth16 prove k.zkey w.wtns proof.json public.json
    "$SNARKJS" groth16 verify vk.json public.json proof.json >verify.txt 2>&1
    cat verify.txt >>"$LOG"
    grep -q "OK!" verify.txt
) || fail "Groth16 prove + verify" "error"
ok "Groth16 proof verified" "$(wc -c <"$TMP/proof.json" | tr -d ' ') B proof"

step "3/6" "Noir / UltraHonk: the same statement, a different proof system"
(cd "$NOIR" && nargo compile && nargo execute) >"$TMP/noir.txt" 2>&1 || { cat "$TMP/noir.txt" >>"$LOG"; fail "execute" "error"; }
cat "$TMP/noir.txt" >>"$LOG"
OUT="$(sed -n 's/.*Circuit output: \[\(.*\)\]/\1/p' "$TMP/noir.txt")"
C_NOIR="$(hexof "$(echo "$OUT" | cut -d, -f1 | tr -d ' ')")"
N_NOIR="$(hexof "$(echo "$OUT" | cut -d, -f2 | tr -d ' ')")"
item "commitment C" "$C_NOIR"
item "nullifier N" "$N_NOIR"
if [ "$SKIP_BB" = "1" ]; then
    item "UltraHonk prove + verify" "SKIPPED (ZKEP_SKIP_BB=1)"
else
    (
        cd "$NOIR"
        bb write_vk -b target/redemption.json -o target
        bb prove -b target/redemption.json -w target/redemption.gz -k target/vk -o target
        bb verify -k target/vk -p target/proof -i target/public_inputs
    ) >>"$LOG" 2>&1 || fail "UltraHonk prove + verify" "error"
    ok "UltraHonk proof verified" "$(wc -c <"$NOIR/target/proof" | tr -d ' ') B proof"
fi

step "4/6" "Both backends agree"
[ "$C_CIRCOM" = "$C_NOIR" ] && [ "$N_CIRCOM" = "$N_NOIR" ] || fail "C and N identical in both backends" "DIFFERENT"
ok "C and N identical in both backends" "yes"

step "5/6" "An attack: the signature scalar is changed (NT-001, s + 1)"
if node "$TMP/redemption_js/generate_witness.js" "$TMP/redemption_js/redemption.wasm" \
    "$REPO/circom/inputs/eprescription/canonical/NT-001.json" "$TMP/bad.wtns" >>"$LOG" 2>&1; then
    fail "Circom rejects the forged signature" "ACCEPTED"
fi
ok "Circom rejects the forged signature" "no witness exists"
cp "$NOIR/tests/negative/NT-001.toml" "$NOIR/_demo.toml"
if (cd "$NOIR" && nargo execute --prover-name _demo) >>"$LOG" 2>&1; then
    rm -f "$NOIR/_demo.toml"; fail "Noir rejects the forged signature" "ACCEPTED"
fi
rm -f "$NOIR/_demo.toml"
ok "Noir rejects the forged signature" "assertion fails"

step "6/6" "A replay: the same slot redeemed again on a later date (TV-004)"
cp "$NOIR/tests/positive/TV-004.toml" "$NOIR/_demo.toml"
OUT4="$(cd "$NOIR" && nargo execute --prover-name _demo 2>&1)"; rm -f "$NOIR/_demo.toml"
echo "$OUT4" >>"$LOG"
N4="$(hexof "$(echo "$OUT4" | sed -n 's/.*Circuit output: \[\(.*\)\]/\1/p' | cut -d, -f2 | tr -d ' ')")"
item "execution succeeds; its nullifier N" "$N4"
[ "$N4" = "$N_NOIR" ] || fail "same N as the first redemption" "different"
ok "same N as the first redemption" "replay detectable"
echo "      The circuit only derives N. The redemption service stores accepted"
echo "      nullifiers and refuses this one (protocol specification, Section 9.1)."
echo
echo "Demo complete. Next: 'test' runs every check; 'kat' compares all protocol values."
