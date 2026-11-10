#!/usr/bin/env bash
# Noir / UltraHonk checks for the redemption circuit.
#
#   library tests (noir/common) -> Schnorr unit tests (noir/redemption) ->
#   compile -> valid vectors (execute, public outputs equal
#   testdata/kat/canonical_fixture.json, bb prove + verify, tampered public
#   inputs must not verify) -> attack vectors (each must fail a circuit
#   assertion).
#
# ZKEP_SKIP_BB=1 skips only bb prove/verify (for machines that cannot download
# the Barretenberg CRS); the run is then reported as INCOMPLETE, never as PASS.
set -euo pipefail

# Zero-knowledge UltraHonk variant for every bb call (bb 5.x: noir-recursive =
# Poseidon2 transcript, ZK; the *-no-zk targets are not ZK).
BB_TARGET="${BB_TARGET:-noir-recursive}"
export BB_TARGET

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${ZKEP_RESULTS:-$REPO/results}/logs/noir.log"
# shellcheck source=lib/report.sh
. "$REPO/scripts/lib/report.sh"
: >"$LOG"

PKG=redemption
PKG_ROOT="$REPO/noir/$PKG"
FIXTURE="$REPO/testdata/kat/canonical_fixture.json"
SKIP_BB="${ZKEP_SKIP_BB:-0}"
: >"$RESULTS/noir_negative.tsv"
: >"$RESULTS/noir_outputs.tsv"

count_passed() { grep -oE '[0-9]+ tests? passed' "$1" | tail -1 | grep -oE '^[0-9]+'; }

# --- library and unit tests --------------------------------------------------
(cd "$REPO/noir/common" && nargo test) >"$RESULTS/logs/noir_common_test.log" 2>&1 \
    || { LOG="$RESULTS/logs/noir_common_test.log"; fail "Poseidon2 library tests (noir/common)" "test failed"; }
cat "$RESULTS/logs/noir_common_test.log" >>"$LOG"
n="$(count_passed "$RESULTS/logs/noir_common_test.log")"
record noir_common "$n/$n"
ok "Poseidon2 library tests (noir/common)" "$n/$n passed"

(cd "$PKG_ROOT" && nargo check && nargo test) >"$RESULTS/logs/noir_unit_test.log" 2>&1 \
    || { LOG="$RESULTS/logs/noir_unit_test.log"; fail "Schnorr unit tests (noir/$PKG)" "test failed"; }
cat "$RESULTS/logs/noir_unit_test.log" >>"$LOG"
n="$(count_passed "$RESULTS/logs/noir_unit_test.log")"
record noir_schnorr "$n/$n"
ok "Schnorr unit tests (1 valid, $((n - 1)) invalid)" "$n/$n as expected"

# --- compile -----------------------------------------------------------------
(cd "$PKG_ROOT" && nargo compile && nargo info) >"$RESULTS/logs/noir_compile.log" 2>&1 \
    || { LOG="$RESULTS/logs/noir_compile.log"; fail "compile noir/$PKG" "compiler error"; }
cat "$RESULTS/logs/noir_compile.log" >>"$LOG"
OPCODES="$(grep -E "^\| *$PKG *\| *main" "$RESULTS/logs/noir_compile.log" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"
record noir_acir_opcodes "$OPCODES"
ok "compile noir/$PKG" "$OPCODES ACIR opcodes"

if [ "$SKIP_BB" != "1" ]; then
    (cd "$PKG_ROOT" && bb write_vk -t "$BB_TARGET" -b "target/$PKG.json" -o target) >>"$LOG" 2>&1 \
        || fail "UltraHonk verification key" "bb write_vk failed (CRS download?)"
fi

# --- valid vectors -----------------------------------------------------------
nv=0; np=0; nt=0
for VECTOR in "$PKG_ROOT"/tests/positive/*.toml; do
    NAME="$(basename "$VECTOR" .toml)"
    cp "$VECTOR" "$PKG_ROOT/_vector.toml"
    OUT="$(cd "$PKG_ROOT" && nargo execute --prover-name _vector 2>&1)" \
        || { echo "$OUT" >>"$LOG"; rm -f "$PKG_ROOT/_vector.toml"; fail "valid vector $NAME" "execution failed"; }
    rm -f "$PKG_ROOT/_vector.toml"
    echo "--- $NAME"$'\n'"$OUT" >>"$LOG"
    node -e '
const fx = require(process.argv[1]);
const id = process.argv[2];
const m = process.argv[3].match(/Circuit output: \[([^\]]*)\]/);
if (!m) { console.log(`${id}: no circuit output`); process.exit(1); }
const hex = (x) => "0x" + BigInt(x.trim()).toString(16).padStart(64, "0");
const [c, n, d] = m[1].split(",").map(hex);
const e = fx.expected_public_outputs[id];
console.log(`${id} C=${c} N=${n} D=${d}`);
if (c !== e.commitment || n !== e.nullifier || d !== e.medication_digest) { console.log(`expected C=${e.commitment} N=${e.nullifier} D=${e.medication_digest}`); process.exit(1); }
require("fs").appendFileSync(process.argv[4], [id, c, n, d].join("\t") + "\n");
' "$FIXTURE" "$NAME" "$OUT" "$RESULTS/noir_outputs.tsv" >>"$LOG" 2>&1 || fail "valid vector $NAME" "public outputs differ from the fixture"
    nv=$((nv + 1))

    [ "$SKIP_BB" = "1" ] && continue
    (
        cd "$PKG_ROOT"
        bb prove -t "$BB_TARGET" -b "target/$PKG.json" -w "target/$PKG.gz" -k target/vk -o target
        bb verify -t "$BB_TARGET" -k target/vk -p target/proof -i target/public_inputs
    ) >>"$LOG" 2>&1 || fail "UltraHonk proof $NAME" "prove or verify failed"
    np=$((np + 1))

    # Tampered public inputs: last byte of each 32-byte public input
    # incremented in turn (registry_root, current_date, C, N, D) must not verify.
    (
        cd "$PKG_ROOT"
        node -e '
const fs = require("fs");
const buf = fs.readFileSync("target/public_inputs");
const n = buf.length / 32;
for (let i = 0; i < n; i++) {
  const t = Buffer.from(buf);
  t[32 * i + 31] = (t[32 * i + 31] + 1) & 0xff;
  fs.writeFileSync(`target/public_inputs.tampered${i}`, t);
}
fs.writeFileSync("target/public_inputs.count", String(n));
'
    )
    COUNT="$(cat "$PKG_ROOT/target/public_inputs.count")"
    for i in $(seq 0 $((COUNT - 1))); do
        if (cd "$PKG_ROOT" && bb verify -t "$BB_TARGET" -k target/vk -p target/proof -i "target/public_inputs.tampered$i") >>"$LOG" 2>&1; then
            fail "tampered public input $i ($NAME)" "VERIFIED"
        fi
        nt=$((nt + 1))
    done

    # Pharmacy view on the real TV-001 proof: the medication list is shown
    # only if it is the signed one (Section 6.1).
    if [ "$NAME" = "TV-001" ]; then
        PH="$(node "$REPO/scripts/lib/pharmacy_cases.js" noir "$PKG_ROOT/target/vk" \
            "$PKG_ROOT/target/proof" "$PKG_ROOT/target/public_inputs" "$RESULTS" 2>&1)" \
            || { cat "$RESULTS/logs/pharmacy_noir.log" >>"$LOG" 2>/dev/null; fail "pharmacy view (Noir)" "$PH"; }
    fi
done
record noir_valid "$nv"
ok "valid vectors TV-001..$(printf '%03d' "$nv")" "$nv/$nv executed, outputs = fixture"

# --- public values: only root, date, C, N, D (I and the secret never public) -
PUBCHK="$(node "$REPO/scripts/lib/public_values_check.js" noir "$PKG_ROOT/target/$PKG.json" "$RESULTS/noir_outputs.tsv" 2>&1)" \
    || { echo "$PUBCHK" >>"$LOG"; fail "public values (Noir)" "$PUBCHK"; }
echo "$PUBCHK" >>"$LOG"
record noir_public "${PUBCHK%% redemptions*}/$nv"
ok "public values: root, date, C, N, D only" "I not public in ${PUBCHK%% redemptions*}/$nv executions"
if [ "$SKIP_BB" = "1" ]; then
    record noir_proofs "skipped"
    record noir_tampered "skipped"
    record noir_pharmacy "skipped"
    item "UltraHonk prove + verify" "SKIPPED (ZKEP_SKIP_BB=1)"
else
    record noir_proofs "$np/$nv"
    record noir_tampered "$nt/$nt"
    ok "UltraHonk prove + verify TV-001..$(printf '%03d' "$nv")" "$np/$nv proofs verified"
    ok "tampered public inputs ($((nt / nv)) per proof x $nv)" "$nt/$nt rejected"
    record noir_pharmacy "${PH%% as expected}"
    ok "pharmacy view: signed list shown, altered lists rejected" "${PH} (results/pharmacy_view_noir.txt)"
fi

# --- attack vectors ----------------------------------------------------------
n=0; total=0
for VECTOR in "$PKG_ROOT"/tests/negative/*.toml; do
    NAME="$(basename "$VECTOR" .toml)"
    total=$((total + 1))
    cp "$VECTOR" "$PKG_ROOT/_vector.toml"
    if (cd "$PKG_ROOT" && nargo execute --prover-name _vector) >"$RESULTS/logs/_nt.log" 2>&1; then
        rm -f "$PKG_ROOT/_vector.toml"
        cat "$RESULTS/logs/_nt.log" >>"$LOG"
        fail "attack vector $NAME" "unexpectedly ACCEPTED"
    fi
    rm -f "$PKG_ROOT/_vector.toml"
    { echo "--- $NAME"; cat "$RESULTS/logs/_nt.log"; } >>"$LOG"
    if grep -q "Failed constraint" "$RESULTS/logs/_nt.log"; then
        printf '%s\t%s\n' "$NAME" "$(grep -m1 -oE 'src/[a-z_]+\.nr:[0-9]+' "$RESULTS/logs/_nt.log")" >>"$RESULTS/noir_negative.tsv"
    elif head -1 "$VECTOR" | grep -q "outside u64" \
        && grep -q "does not fall within range of allowable values for a Integer { sign: Unsigned, width: 64 }" "$RESULTS/logs/_nt.log"; then
        # A value outside u64 cannot be given to a u64 parameter at all:
        # nargo rejects it while decoding the input (type check, not a constraint).
        printf '%s\t%s\n' "$NAME" "abi:u64" >>"$RESULTS/noir_negative.tsv"
    else
        fail "attack vector $NAME" "tool or input error, not a constraint"
    fi
    n=$((n + 1))
done
rm -f "$RESULTS/logs/_nt.log"
record noir_attacks "$n/$total"
nabi="$(grep -c 'abi:u64' "$RESULTS/noir_negative.tsv" || true)"
if [ "$nabi" -gt 0 ]; then
    ok "attack vectors NT-001..$(printf '%03d' "$total")" "$n/$total rejected ($((n - nabi)) by a constraint, $nabi by the u64 input type)"
else
    ok "attack vectors NT-001..$(printf '%03d' "$total")" "$n/$total rejected by a constraint"
fi
