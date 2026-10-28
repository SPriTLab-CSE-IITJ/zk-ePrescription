#!/usr/bin/env bash
# zk-ePrescription — final benchmark, measurement stage (harness v1.4).
#
# Runs INSIDE the benchmark container (zkep:aligned, or the documented derived
# image that only adds GNU time). It measures the repository source baked
# into the image at /workspace and never modifies that source tree in the image
# (the container filesystem is ephemeral; only build outputs inside package
# target/ directories are created there, exactly as in the regression).
#
# Environment:
#   W              source root inside the container (default /workspace)
#   OUT            output directory, bind-mounted from the host (required)
#   LABEL          platform label written to every CSV row (required)
#   WARMUP         warm-up runs for repeated stages (default 1)
#   REPS           measured runs for witness/prove/verify (default 5)
#   COMPILE_REPS   measured runs for compilation (default 3)
#   EXP_TV001_JSON_SHA256 / EXP_TV001_TOML_SHA256 / EXP_FIXTURE_SHA256
#                  expected input hashes (computed by run_benchmark.sh from this checkout)
#   EXP_R1CS / EXP_ACIR / EXP_GATES   expected structural counts
#   DRY_RUN=1      plan mode: record every command that WOULD run, execute none
#   STRUCT_CHECK=1 (plan mode) additionally compile once, UNMEASURED, and verify
#                  R1CS / ACIR / gate counts from tool output (no timing recorded)
#   EXP_CIRCOM / EXP_SNARKJS / EXP_NARGO / EXP_BB / EXP_NODE_PREFIX
#                  pinned toolchain versions (STOP on mismatch)
#
# Never invokes scripts/benchmark.js.
set -uo pipefail

W="${W:-/workspace}"
: "${OUT:?OUT must be set}"
: "${LABEL:?LABEL must be set}"
WARMUP="${WARMUP:-1}"
REPS="${REPS:-5}"
COMPILE_REPS="${COMPILE_REPS:-3}"
DRY_RUN="${DRY_RUN:-0}"
TIME_BIN="${TIME_BIN:-/usr/bin/time}"
EXP_R1CS="${EXP_R1CS:-12291}"
EXP_ACIR="${EXP_ACIR:-16681}"
EXP_GATES="${EXP_GATES:-22182}"
STRUCT_CHECK="${STRUCT_CHECK:-0}"
EXP_CIRCOM="${EXP_CIRCOM:-circom compiler 2.2.3}"
EXP_SNARKJS="${EXP_SNARKJS:-snarkjs@0.7.6}"
EXP_NARGO="${EXP_NARGO:-nargo version = 1.0.0-beta.24}"
EXP_BB="${EXP_BB:-5.0.0-nightly.20260522}"
EXP_NODE_PREFIX="${EXP_NODE_PREFIX:-v18.20.}"

# All measured I/O happens on the container's own filesystem; results are
# copied to the bind-mounted OUT at exit, so host-filesystem latency
# (e.g. WSL /mnt/c) never enters a measurement.
DEST="$OUT"
OUT="${WORK:-/tmp/zkep-bench}"
rm -rf "$OUT"; mkdir -p "$OUT"
copy_out() { mkdir -p "$DEST"; cp -a "$OUT/." "$DEST/" 2>/dev/null || true; }
trap copy_out EXIT

A="$OUT/artifacts"
L="$OUT/logs"
RAW="$OUT/raw_runs.csv"
CMDS="$OUT/benchmark_commands.txt"
mkdir -p "$A/circom" "$A/noir" "$L"

die() { echo "STOP: $*" | tee -a "$L/STOP.txt"; exit 1; }

if [ "$DRY_RUN" != "1" ]; then
    [ -x "$TIME_BIN" ] || die "GNU time not found at $TIME_BIN"
fi

echo "platform_label,backend,stage,kind,run,wall_s,gnu_elapsed_s,user_s,sys_s,max_rss_kb,exit_code,artifact,artifact_bytes" > "$RAW"
printf 'backend\tstage\tkind\trun\tcommand\n' > "$CMDS"

# measure BACKEND STAGE KIND RUN ARTIFACT -- cmd...
#   KIND: once | warmup | measured | prep (prep = not a measurement: CRS priming)
#   ARTIFACT: path whose byte size is recorded after the run ("-" for none)
# Wall clock: nanosecond clock around the GNU time wrapper.
# Peak RSS / user / sys / elapsed: GNU `time -v` of the measured command.
measure() {
    local backend="$1" stage="$2" kind="$3" run="$4" artifact="$5"; shift 6
    local base="$L/${backend}.${stage}.${kind}.${run}"
    { printf '%s\t%s\t%s\t%s\t' "$backend" "$stage" "$kind" "$run"; printf '%q ' "$@"; echo; } >> "$CMDS"
    if [ "$DRY_RUN" = "1" ]; then return 0; fi
    local t0 t1 rc
    t0=$(date +%s%N)
    "$TIME_BIN" -v -o "$base.time" "$@" > "$base.out" 2>&1
    rc=$?
    t1=$(date +%s%N)
    local wall rss user sys el bytes
    wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.6f", (b-a)/1e9}')
    rss=$(awk -F': ' '/Maximum resident set size/{print $2}' "$base.time")
    user=$(awk -F': ' '/User time \(seconds\)/{print $2}' "$base.time")
    sys=$(awk -F': ' '/System time \(seconds\)/{print $2}' "$base.time")
    el=$(awk -F': ' '/Elapsed \(wall clock\)/{print $2}' "$base.time" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }')
    bytes=""
    if [ "$artifact" != "-" ] && [ -f "$artifact" ]; then bytes=$(stat -c %s "$artifact"); fi
    echo "$LABEL,$backend,$stage,$kind,$run,$wall,$el,$user,$sys,$rss,$rc,${artifact#$OUT/},$bytes" >> "$RAW"
    if [ "$rc" -ne 0 ]; then
        echo "  [$backend/$stage/$kind/$run] exit $rc (see logs/$(basename "$base").out)"
    else
        echo "  [$backend/$stage/$kind/$run] ${wall}s rss=${rss}kB ${bytes:+bytes=$bytes}"
    fi
    return "$rc"
}

# repeat BACKEND STAGE NREPS ARTIFACT_PATTERN -- cmd...   ({i} -> warmup1, measured1, ...)
repeat() {
    local backend="$1" stage="$2" n="$3" pat="$4"; shift 5
    local i art args kind run
    for i in $(seq 1 $((WARMUP + n))); do
        kind=measured; run=$((i - WARMUP))
        if [ "$i" -le "$WARMUP" ]; then kind=warmup; run=$i; fi
        art="${pat//\{i\}/$kind$run}"
        args=(); for x in "$@"; do args+=("${x//\{i\}/$kind$run}"); done
        measure "$backend" "$stage" "$kind" "$run" "$art" -- "${args[@]}" \
            || die "$backend/$stage $kind run $run failed (exit non-zero)"
    done
}

live() { [ "$DRY_RUN" != "1" ]; }   # true when actually executing

# --------------------------------------------------------------------------
# Container environment + input validation (before any measurement)
# --------------------------------------------------------------------------
TV_JSON="$W/circom/inputs/eprescription/canonical/TV-001.json"
TV_TOML="$W/noir/redemption/tests/positive/TV-001.toml"
FIXTURE="$W/testdata/kat/canonical_fixture.json"
h_json=$(sha256sum "$TV_JSON" | cut -d' ' -f1)
h_toml=$(sha256sum "$TV_TOML" | cut -d' ' -f1)
h_fx=$(sha256sum "$FIXTURE" | cut -d' ' -f1)
{
  echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "uname=$(uname -a)"
  echo "kernel=$(uname -r)"
  echo "arch=$(uname -m)"
  echo "nproc=$(nproc)"
  grep -E '^(MemTotal|MemAvailable|SwapTotal)' /proc/meminfo
  echo "cpu_model=$(grep -m1 -E 'model name|Model' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
  echo "os_release=$(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "circom=$(circom --version 2>&1)"
  echo "snarkjs=$(snarkjs --version 2>&1 | head -1)"
  echo "nargo=$(nargo --version 2>&1 | tr '\n' ' ')"
  echo "bb=$(bb --version 2>&1)"
  echo "node=$(node --version)"
  echo "gnu_time=$( [ -x "$TIME_BIN" ] && "$TIME_BIN" --version 2>&1 | head -1 || echo absent)"
  echo "warmup=$WARMUP reps=$REPS compile_reps=$COMPILE_REPS dry_run=$DRY_RUN"
  echo "fixture_TV001_json_sha256=$h_json"
  echo "fixture_TV001_toml_sha256=$h_toml"
  echo "canonical_fixture_json_sha256=$h_fx"
} > "$OUT/container_env.txt"

[ -z "${EXP_TV001_JSON_SHA256:-}" ] || [ "$h_json" = "$EXP_TV001_JSON_SHA256" ] || die "TV-001.json hash $h_json != expected $EXP_TV001_JSON_SHA256"
[ -z "${EXP_TV001_TOML_SHA256:-}" ] || [ "$h_toml" = "$EXP_TV001_TOML_SHA256" ] || die "TV-001.toml hash $h_toml != expected $EXP_TV001_TOML_SHA256"
[ -z "${EXP_FIXTURE_SHA256:-}" ] || [ "$h_fx" = "$EXP_FIXTURE_SHA256" ] || die "canonical_fixture.json hash $h_fx != expected $EXP_FIXTURE_SHA256"
echo "== Input hashes verified against the host checkout"

# Pinned toolchain (Dockerfile ARGs) — STOP on any mismatch.
v_circom=$(circom --version 2>&1 | head -1)
v_snarkjs=$(snarkjs --version 2>&1 | head -1)
v_nargo=$(nargo --version 2>&1 | head -1)
v_bb=$(bb --version 2>&1 | head -1)
v_node=$(node --version)
[ "$v_circom" = "$EXP_CIRCOM" ] || die "circom version '$v_circom' != pinned '$EXP_CIRCOM'"
[ "$v_snarkjs" = "$EXP_SNARKJS" ] || die "snarkjs version '$v_snarkjs' != pinned '$EXP_SNARKJS'"
[ "$v_nargo" = "$EXP_NARGO" ] || die "nargo version '$v_nargo' != pinned '$EXP_NARGO'"
[ "$v_bb" = "$EXP_BB" ] || die "bb version '$v_bb' != pinned '$EXP_BB'"
case "$v_node" in "$EXP_NODE_PREFIX"*) ;; *) die "node version '$v_node' does not start with pinned '$EXP_NODE_PREFIX'";; esac
echo "== Toolchain verified: $v_circom | $v_snarkjs | $v_nargo | bb $v_bb | node $v_node"
if [ -x "$TIME_BIN" ] && "$TIME_BIN" -v true >/dev/null 2>&1; then
    echo "gnu_time_usable=yes" >> "$OUT/container_env.txt"; echo "== GNU time usable at $TIME_BIN"
else
    echo "gnu_time_usable=no" >> "$OUT/container_env.txt"; echo "== GNU time NOT usable at $TIME_BIN"
fi

# Expected public outputs: read from the canonical fixture (source of truth).
read -r FX_C FX_N FX_DATE FX_ROOT < <(node -e '
const e = require(process.argv[1]).expected_public_outputs["TV-001"];
console.log(e.commitment, e.nullifier, e.current_date, e.registry_root);' "$FIXTURE")
echo "fixture_TV001_C=$FX_C" >> "$OUT/container_env.txt"
echo "fixture_TV001_N=$FX_N" >> "$OUT/container_env.txt"
echo "== Fixture TV-001: C=$FX_C N=$FX_N current_date=$FX_DATE root=$FX_ROOT"

# check_circom_public FILE  /  check_noir_public FILE  — STOP on mismatch
check_circom_public() {
    node -e '
const [f, C, N, D, R] = process.argv.slice(1);
const p = require(f); const h = (x) => "0x" + BigInt(x).toString(16).padStart(64, "0");
const ok = h(p[0]) === C && h(p[1]) === N && BigInt(p[2]).toString() === D && h(p[3]) === R;
if (!ok) { console.error("public.json mismatch", p); process.exit(1); }' "$1" "$FX_C" "$FX_N" "$FX_DATE" "$FX_ROOT" \
        || die "Circom public signals in $1 inconsistent with fixture TV-001"
}
check_noir_public() {
    node -e '
const fs = require("fs"); const [f, C, N, D, R] = process.argv.slice(1);
const b = fs.readFileSync(f); const x = [];
for (let i = 0; i + 32 <= b.length; i += 32) x.push("0x" + b.subarray(i, i + 32).toString("hex"));
const want = [R, "0x" + BigInt(D).toString(16).padStart(64, "0"), C, N];
if (x.length !== 4 || x.some((v, i) => v !== want[i])) { console.error("public_inputs mismatch", x); process.exit(1); }' \
        "$1" "$FX_C" "$FX_N" "$FX_DATE" "$FX_ROOT" || die "Noir public inputs in $1 inconsistent with fixture TV-001"
}

if [ "$DRY_RUN" = "1" ] && [ "$STRUCT_CHECK" = "1" ]; then
    # UNMEASURED structural verification for plan mode: no timing, no CSV rows.
    S="$OUT/structural_check"; mkdir -p "$S/circom"
    circom "$W/circom/circuits/redemption.circom" --r1cs -o "$S/circom" > "$S/circom_compile.txt" 2>&1 || die "plan: circom compile failed"
    snarkjs r1cs info "$S/circom/redemption.r1cs" > "$S/r1cs_info.txt" 2>&1 || die "plan: snarkjs r1cs info failed"
    ( cd "$W/noir/redemption" && nargo compile --force > "$S/nargo_compile.txt" 2>&1 && nargo info > "$S/nargo_info.txt" 2>&1 ) || die "plan: nargo compile/info failed"
    bb gates -b "$W/noir/redemption/target/redemption.json" > "$S/bb_gates.txt" 2>&1 || die "plan: bb gates failed"
    p_r1cs=$(sed -n 's/.*# of Constraints: *\([0-9]*\).*/\1/p' "$S/r1cs_info.txt")
    p_nl=$(sed -n 's/^non-linear constraints: *\([0-9]*\).*/\1/p' "$S/circom_compile.txt")
    p_l=$(sed -n 's/^linear constraints: *\([0-9]*\).*/\1/p' "$S/circom_compile.txt")
    p_acir=$(sed -n 's/^| *redemption *| *main *| *\([0-9]*\) *|.*/\1/p' "$S/nargo_info.txt" | head -1)
    p_gates=$(sed -n 's/.*"circuit_size": *\([0-9]*\).*/\1/p' "$S/bb_gates.txt" | head -1)
    {
      echo "r1cs_constraints=$p_r1cs (expected $EXP_R1CS; non-linear $p_nl + linear $p_l)"
      echo "acir_opcodes=$p_acir (expected $EXP_ACIR)"
      echo "bb_gates=$p_gates (expected $EXP_GATES)"
    } | tee "$S/structural_summary.txt"
    [ "$p_r1cs" = "$EXP_R1CS" ] || die "plan: R1CS constraints $p_r1cs != $EXP_R1CS"
    [ "$p_acir" = "$EXP_ACIR" ] || die "plan: ACIR opcodes $p_acir != $EXP_ACIR"
    [ "$p_gates" = "$EXP_GATES" ] || die "plan: bb gates $p_gates != $EXP_GATES"
    echo "== Structural counts verified from tool output (unmeasured)"
fi

echo "== Benchmark start $(date -u +%Y-%m-%dT%H:%M:%SZ) label=$LABEL warmup=$WARMUP reps=$REPS compile_reps=$COMPILE_REPS dry_run=$DRY_RUN"

# --------------------------------------------------------------------------
# CIRCOM + GROTH16
# --------------------------------------------------------------------------
C="$A/circom"
CIRCUIT=redemption
SRC_CIRCUIT="$W/circom/circuits/$CIRCUIT.circom"
WASM="$C/${CIRCUIT}_js/$CIRCUIT.wasm"
GEN="$C/${CIRCUIT}_js/generate_witness.js"
R1CS="$C/$CIRCUIT.r1cs"

echo "== Circom: compile (1 warm-up + $COMPILE_REPS measured)"
repeat circom compile "$COMPILE_REPS" "$R1CS" -- circom "$SRC_CIRCUIT" --r1cs --wasm --sym -o "$C"
live && cp "$L/circom.compile.measured.1.out" "$C/compile_output.txt"

echo "== Circom: structural counts (once)"
measure circom r1cs_info once 1 - -- snarkjs r1cs info "$R1CS" || die "snarkjs r1cs info failed"
if live; then
    cp "$L/circom.r1cs_info.once.1.out" "$C/r1cs_info.txt"
    got=$(sed -n 's/.*# of Constraints: *\([0-9]*\).*/\1/p' "$C/r1cs_info.txt")
    [ "$got" = "$EXP_R1CS" ] || die "R1CS constraints $got != expected $EXP_R1CS"
    echo "   R1CS constraints = $got (expected $EXP_R1CS)"
fi

echo "== Circom: witness generation (1 warm-up + $REPS measured)"
repeat circom witness "$REPS" "$C/witness_{i}.wtns" -- node "$GEN" "$WASM" "$TV_JSON" "$C/witness_{i}.wtns"
live && cp "$C/witness_measured1.wtns" "$C/witness.wtns"

echo "== Circom: Powers of Tau (development/setup infrastructure, once each)"
measure circom ptau_new once 1 "$C/pot_0000.ptau" -- \
    snarkjs powersoftau new bn128 15 "$C/pot_0000.ptau" || die "ptau new failed"
measure circom ptau_contribute once 1 "$C/pot_0001.ptau" -- \
    snarkjs powersoftau contribute "$C/pot_0000.ptau" "$C/pot_0001.ptau" --name=zkep-bench -e=zkep-bench-entropy || die "ptau contribute failed"
measure circom ptau_prepare_phase2 once 1 "$C/pot_final.ptau" -- \
    snarkjs powersoftau prepare phase2 "$C/pot_0001.ptau" "$C/pot_final.ptau" || die "ptau prepare phase2 failed"

echo "== Circom: Groth16 circuit setup (once)"
measure circom groth16_setup once 1 "$C/circuit_0000.zkey" -- \
    snarkjs groth16 setup "$R1CS" "$C/pot_final.ptau" "$C/circuit_0000.zkey" || die "groth16 setup failed"
measure circom zkey_contribute once 1 "$C/circuit_final.zkey" -- \
    snarkjs zkey contribute "$C/circuit_0000.zkey" "$C/circuit_final.zkey" --name=zkep-bench -e=zkep-bench-zkey-entropy || die "zkey contribute failed"

echo "== Circom: verification-key export (once)"
measure circom vk_export once 1 "$C/verification_key.json" -- \
    snarkjs zkey export verificationkey "$C/circuit_final.zkey" "$C/verification_key.json" || die "vk export failed"

echo "== Circom: Groth16 prove (1 warm-up + $REPS measured)"
repeat circom prove "$REPS" "$C/proof_{i}.json" -- \
    snarkjs groth16 prove "$C/circuit_final.zkey" "$C/witness.wtns" "$C/proof_{i}.json" "$C/public_{i}.json"
if live; then for f in "$C"/public_*.json; do check_circom_public "$f"; done; echo "   all Circom public signals = fixture TV-001"; fi

echo "== Circom: Groth16 verify (1 warm-up + $REPS measured)"
# Each verify run checks the proof produced by the prove run of the same index,
# so every generated Groth16 proof (warm-up and measured) is verified once.
repeat circom verify "$REPS" - -- \
    snarkjs groth16 verify "$C/verification_key.json" "$C/public_{i}.json" "$C/proof_{i}.json"
if live; then for f in "$L"/circom.verify.*.out; do grep -q "OK!" "$f" || die "Groth16 verification did not print OK! ($f)"; done; fi

# --------------------------------------------------------------------------
# NOIR + ULTRAHONK
# --------------------------------------------------------------------------
N="$A/noir"
PKG="$W/noir/redemption"
JSON="$PKG/target/redemption.json"

# The prover input is copied byte-identically into the package directory of
# the ephemeral container filesystem so that nargo can read it by name.
cp "$TV_TOML" "$PKG/_bench.toml"
cmp -s "$TV_TOML" "$PKG/_bench.toml" || die "TV-001.toml copy mismatch"
cd "$PKG"

echo "== Noir: compile (1 warm-up + $COMPILE_REPS measured, --force so every run compiles)"
repeat noir compile "$COMPILE_REPS" "$JSON" -- nargo compile --force
live && cp "$JSON" "$N/redemption.json"

echo "== Noir: structural counts (once each)"
measure noir nargo_info once 1 - -- nargo info || die "nargo info failed"
measure noir bb_gates once 1 - -- bb gates -b "$N/redemption.json" || die "bb gates failed"
if live; then
    cp "$L/noir.nargo_info.once.1.out" "$N/nargo_info.txt"
    cp "$L/noir.bb_gates.once.1.out" "$N/bb_gates.txt"
    acir=$(sed -n 's/^| *redemption *| *main *| *\([0-9]*\) *|.*/\1/p' "$N/nargo_info.txt" | head -1)
    gates=$(sed -n 's/.*"circuit_size": *\([0-9]*\).*/\1/p' "$N/bb_gates.txt" | head -1)
    [ "$acir" = "$EXP_ACIR" ] || die "ACIR opcodes $acir != expected $EXP_ACIR"
    [ "$gates" = "$EXP_GATES" ] || die "Barretenberg gates $gates != expected $EXP_GATES"
    echo "   ACIR opcodes = $acir (expected $EXP_ACIR); Barretenberg gates = $gates (expected $EXP_GATES)"
fi

echo "== Noir: execute / witness (1 warm-up + $REPS measured)"
repeat noir execute "$REPS" "$PKG/target/w_{i}.gz" -- nargo execute --prover-name _bench "w_{i}"
if live; then
    cp "$PKG/target/w_measured1.gz" "$N/witness.gz"
    for f in "$L"/noir.execute.*.out; do
        grep -q "Circuit output: \[$FX_C, $FX_N\]" "$f" || die "nargo execute output inconsistent with fixture ($f)"
    done
    echo "   all nargo execute outputs = [C, N] of fixture TV-001"
fi

echo "== Noir: CRS priming (NOT a measurement; may download/cache the Barretenberg CRS)"
mkdir -p "$N/crs_priming"
measure noir crs_priming prep 1 - -- bb write_vk -b "$N/redemption.json" -o "$N/crs_priming" \
    || die "bb CRS priming (write_vk) failed"

echo "== Noir: verification key (once; precomputed VK for proving)"
mkdir -p "$N/vk"
measure noir write_vk once 1 "$N/vk/vk" -- bb write_vk -b "$N/redemption.json" -o "$N/vk" || die "bb write_vk failed"

echo "== Noir: UltraHonk prove with precomputed VK (1 warm-up + $REPS measured)"
for i in $(seq 1 $((WARMUP + REPS))); do
    if [ "$i" -le "$WARMUP" ]; then d="warmup$i"; else d="measured$((i - WARMUP))"; fi
    mkdir -p "$N/prove_$d"
done
repeat noir prove "$REPS" "$N/prove_{i}/proof" -- \
    bb prove -b "$N/redemption.json" -w "$N/witness.gz" -k "$N/vk/vk" -o "$N/prove_{i}"
if live; then for f in "$N"/prove_*/public_inputs; do check_noir_public "$f"; done; echo "   all Noir public inputs = fixture TV-001"; fi

echo "== Noir: UltraHonk verify (1 warm-up + $REPS measured)"
# Each verify run checks the proof produced by the prove run of the same index,
# so every generated UltraHonk proof (warm-up and measured) is verified once.
repeat noir verify "$REPS" - -- \
    bb verify -k "$N/vk/vk" -p "$N/prove_{i}/proof" -i "$N/prove_{i}/public_inputs"
if live; then for f in "$L"/noir.verify.*.out; do grep -q "verified successfully" "$f" || die "UltraHonk verification failed ($f)"; done; fi

rm -f "$PKG/_bench.toml"

# --------------------------------------------------------------------------
# Artifact provenance: path, bytes, SHA-256 of every generated artifact
# --------------------------------------------------------------------------
if live; then
    ( cd "$OUT" && find artifacts -type f -printf '%P\n' | LC_ALL=C sort | while read -r f; do
          printf '%s\t%s\t%s\n' "artifacts/$f" "$(stat -c %s "artifacts/$f")" "$(sha256sum "artifacts/$f" | cut -d' ' -f1)"
      done ) > "$OUT/artifact_manifest.sha256"
    echo "== Artifact manifest: $(grep -c . "$OUT/artifact_manifest.sha256") files"
    echo "== Benchmark measurements complete $(date -u +%Y-%m-%dT%H:%M:%SZ)"
else
    echo "== DRY RUN complete: $(($(grep -c . "$CMDS") - 1)) commands recorded, none executed"
fi
echo "== Results copied to the host output folder on exit"
