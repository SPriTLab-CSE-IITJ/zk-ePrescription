#!/usr/bin/env bash
# zk-ePrescription — benchmark driver (host side), harness v1.4.1.
#
# v1.4.1: output folder handed back to the calling user after each container
# stage (no sudo on native Linux); SOURCE_COMMIT for ZIP downloads. The
# measured commands are unchanged.
#
# v1.4 = v1.3 (used for the published laptop results, run 083403Z) adapted to
# the restructured repository: circuit and package names, and preflight checks
# against this checkout instead of the external frozen manifests. The
# measurement stage (bench_in_container.sh) is unchanged apart from names.
#
# Usage (from the repository root, after `docker build -t zkep .`):
#   bash bench/run_benchmark.sh <platform-label> [--plan]
#
#   <platform-label>  laptop-x86_64-wsl2 | pi5-aarch64 | ...
#   --plan            run every preflight check, record host metadata, and do a
#                     DRY RUN inside the image that records every command the
#                     benchmark would execute — without executing any of them.
#
# Methodology (approved): witness/prove/verify 1 warm-up + 5 measured;
# compile 1 warm-up + 3 measured; Powers of Tau, Groth16 setup, VK export,
# nargo info, bb gates, bb write_vk once. Overrides: WARMUP, REPS, COMPILE_REPS.
#
# Image check: the image's /workspace must be byte-identical to this checkout
# (source manifest, .gitignore excepted). Optional: EXPECTED_IMAGE_ID=<id>.
# The repository must be a clean git checkout (ALLOW_DIRTY=1 for test runs).
#
# The harness never modifies the repository. Output (gitignored):
#   results/bench/<label>_<UTC>[_plan]/   (override with BENCH_OUT=<dir>)
#
# Source downloaded as a ZIP instead of cloned: set SOURCE_COMMIT=<full sha> to
# record the commit the ZIP was taken from; it is stored as "declared", and the
# source manifest in host_env/ is the evidence that the files match it.
set -euo pipefail

LABEL="${1:?usage: run_benchmark.sh <platform-label> [--plan]}"
MODE="${2:-run}"
case "$MODE" in run|--plan) ;; *) echo "unknown mode $MODE"; exit 2;; esac
B="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$B/.." && pwd)"
MANIFEST="$B/source_manifest.js"
WARMUP="${WARMUP:-1}"
REPS="${REPS:-5}"
COMPILE_REPS="${COMPILE_REPS:-3}"
EXPECTED_IMAGE_ID="${EXPECTED_IMAGE_ID:-any}"
EXP_R1CS=12291; EXP_ACIR=16681; EXP_GATES=22182
BASE_IMAGE="${IMAGE:-zkep}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BENCH_OUT:-$REPO/results/bench}/${LABEL}_${TS}"; [ "$MODE" = "--plan" ] && OUT="${OUT}_plan"
HARNESS_FILES="run_benchmark.sh bench_in_container.sh summarize.js validate_outputs.js print_summary.js Dockerfile.bench source_manifest.js"

stop() { echo "STOP: $*" | tee -a "$OUT/STOP.txt" >&2; exit 1; }
mkdir -p "$OUT/host_env"
[ -f "$REPO/docs/protocol_specification.md" ] || stop "run from the repository folder"
echo "== zk-ePrescription benchmark ($MODE) label=$LABEL"
echo "== Output: $OUT"

CHECKS="$OUT/host_env/preflight_checks.txt"; : > "$CHECKS"
pass() { echo "PASS  $*" | tee -a "$CHECKS"; }

repo_manifest() {
    if command -v node >/dev/null 2>&1; then
        node "$MANIFEST" "$1"
    else
        docker run --rm -i --entrypoint node -v "$1:/src:ro" "$BASE_IMAGE" - /src < "$MANIFEST"
    fi
}

# ---------------------------------------------------------------- preflight
COMMIT=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "not a git checkout")
if [ "$COMMIT" = "not a git checkout" ] && [ -n "${SOURCE_COMMIT:-}" ]; then
    COMMIT="declared $SOURCE_COMMIT (not a git checkout)"
fi
if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null)" ] && [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    stop "uncommitted changes in the repository (commit them, or set ALLOW_DIRTY=1 for a test run)"
fi
pass "repository commit $COMMIT"
repo_manifest "$REPO" 2>/dev/null | grep -v $'^\\.gitignore\t' > "$OUT/host_env/source_manifest_before.sha256" 2>/dev/null
pass "host source manifest recorded ($(grep -c . "$OUT/host_env/source_manifest_before.sha256") files)"

IMG_ID=$(docker image inspect "$BASE_IMAGE" --format '{{.Id}}' 2>/dev/null) || stop "image $BASE_IMAGE not found (docker build -t $BASE_IMAGE .)"
if [ "$EXPECTED_IMAGE_ID" != "any" ]; then
    [ "$IMG_ID" = "$EXPECTED_IMAGE_ID" ] || stop "image ID $IMG_ID != expected $EXPECTED_IMAGE_ID"
    pass "image ID == $EXPECTED_IMAGE_ID"
fi
IMG_ARCH=$(docker image inspect "$BASE_IMAGE" --format '{{.Architecture}}')
docker run --rm -i --entrypoint node "$BASE_IMAGE" - /workspace < "$MANIFEST" \
    > "$OUT/host_env/image_workspace_manifest.sha256" 2>/dev/null
cmp -s "$OUT/host_env/image_workspace_manifest.sha256" "$OUT/host_env/source_manifest_before.sha256" \
    || { diff "$OUT/host_env/source_manifest_before.sha256" "$OUT/host_env/image_workspace_manifest.sha256" | head -20; stop "image /workspace differs from this checkout (rebuild the image)"; }
pass "image $IMG_ID /workspace == this checkout ($(grep -c . "$OUT/host_env/image_workspace_manifest.sha256") files; arch $IMG_ARCH)"

EXP_JSON=$(sha256sum "$REPO/circom/inputs/eprescription/canonical/TV-001.json" | cut -d' ' -f1)
EXP_TOML=$(sha256sum "$REPO/noir/redemption/tests/positive/TV-001.toml" | cut -d' ' -f1)
EXP_FX=$(sha256sum "$REPO/testdata/kat/canonical_fixture.json" | cut -d' ' -f1)
pass "TV-001.json sha256 $EXP_JSON"
pass "TV-001.toml sha256 $EXP_TOML"
pass "canonical_fixture.json sha256 $EXP_FX"

BENCH_IMAGE="$BASE_IMAGE"; DERIVED="no"
if docker run --rm "$BASE_IMAGE" sh -c '/usr/bin/time -v true' >/dev/null 2>&1; then
    pass "GNU /usr/bin/time -v usable in $BASE_IMAGE (no derived image needed)"
else
    DERIVED="yes"
    echo "   GNU /usr/bin/time absent in $BASE_IMAGE -> building derived measurement image zkep:bench (base + Debian 'time' only)"
    docker build -t zkep:bench --build-arg BASE="$BASE_IMAGE" -f "$B/Dockerfile.bench" "$B" \
        > "$OUT/host_env/derived_image_build.log" 2>&1 || stop "derived image build failed (host_env/derived_image_build.log)"
    BENCH_IMAGE=zkep:bench
    [ "$(docker image inspect zkep:bench --format '{{index .Config.Labels "org.zkep.purpose"}}')" = "benchmark measurement env: base + GNU time only" ] \
        || stop "zkep:bench label mismatch"
    docker run --rm -i --entrypoint node "$BENCH_IMAGE" - /workspace < "$MANIFEST" \
        > "$OUT/host_env/derived_workspace_manifest.sha256" 2>/dev/null
    cmp -s "$OUT/host_env/derived_workspace_manifest.sha256" "$OUT/host_env/image_workspace_manifest.sha256" \
        || stop "derived image /workspace differs from the base image"
    for img in "$BASE_IMAGE" "$BENCH_IMAGE"; do
        docker run --rm --entrypoint bash "$img" -c 'circom --version; snarkjs --version 2>&1 | head -1; nargo --version | head -1; bb --version; node --version' \
            > "$OUT/host_env/tool_versions_${img//[:\/]/_}.txt" 2>&1
    done
    cmp -s "$OUT/host_env/tool_versions_${BASE_IMAGE//[:\/]/_}.txt" "$OUT/host_env/tool_versions_zkep_bench.txt" \
        || stop "tool versions differ between base and derived image"
    docker run --rm "$BENCH_IMAGE" sh -c '/usr/bin/time -v true' >/dev/null 2>&1 || stop "GNU time still unusable in derived image"
    pass "derived image zkep:bench $(docker image inspect zkep:bench --format '{{.Id}}'): /workspace identical, tool versions identical, GNU time usable"
fi
BENCH_ID=$(docker image inspect "$BENCH_IMAGE" --format '{{.Id}}')
IMG_CREATED=$(docker image inspect "$BASE_IMAGE" --format '{{.Created}}')
echo "base_image_id=$IMG_ID base_image_created=$IMG_CREATED base_image_arch=$IMG_ARCH benchmark_image=$BENCH_IMAGE benchmark_image_id=$BENCH_ID derived=$DERIVED" \
    > "$OUT/host_env/images.txt"

# ---------------------------------------------------------------- host metadata (measured only)
{ date -u +%Y-%m-%dT%H:%M:%SZ; uname -a; cat /etc/os-release 2>/dev/null || true; } > "$OUT/host_env/os.txt"
hostname > "$OUT/host_env/hostname.txt" 2>/dev/null || echo unavailable > "$OUT/host_env/hostname.txt"
lscpu > "$OUT/host_env/lscpu.txt" 2>&1 || echo "unavailable" > "$OUT/host_env/lscpu.txt"
nproc > "$OUT/host_env/nproc.txt"
cat /proc/meminfo > "$OUT/host_env/meminfo.txt"
if [ -r /proc/device-tree/model ]; then tr -d '\0' < /proc/device-tree/model > "$OUT/host_env/device_model.txt"; else echo "unavailable" > "$OUT/host_env/device_model.txt"; fi
docker version > "$OUT/host_env/docker_version.txt" 2>&1 || true
docker info --format 'NCPU={{.NCPU}} MemTotal={{.MemTotal}} OSType={{.OSType}} Architecture={{.Architecture}} KernelVersion={{.KernelVersion}} OperatingSystem={{.OperatingSystem}} ServerVersion={{.ServerVersion}}' \
    > "$OUT/host_env/docker_info.txt" 2>&1 || true
if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory; (Get-CimInstance Win32_Processor).Name; (Get-CimInstance Win32_OperatingSystem).Caption" \
        2>/dev/null | tr -d '\r' > "$OUT/host_env/windows_host.txt" || echo "unavailable" > "$OUT/host_env/windows_host.txt"
else
    echo "unavailable (no WSL interop on this host)" > "$OUT/host_env/windows_host.txt"
fi
for f in $HARNESS_FILES; do cp "$B/$f" "$OUT/host_env/harness_$f"; done
( cd "$B" && sha256sum $HARNESS_FILES ) > "$OUT/harness_sha256.txt"
pass "host metadata recorded; harness sha256 recorded"

# ---------------------------------------------------------------- container run (dry or live)
# Files written by the containers are owned by root; on native Linux that
# would stop the host side from writing into $OUT. Hand them back to the
# calling user after every container stage (a no-op on WSL /mnt/c).
reclaim_out() {
    docker run --rm -v "$OUT:/out" --entrypoint chown "$BENCH_IMAGE" -R "$(id -u):$(id -g)" /out >/dev/null 2>&1 || true
}
trap reclaim_out EXIT

RUN_ENV=(-e OUT=/out -e LABEL="$LABEL" -e WARMUP="$WARMUP" -e REPS="$REPS" -e COMPILE_REPS="$COMPILE_REPS"
         -e EXP_TV001_JSON_SHA256="$EXP_JSON" -e EXP_TV001_TOML_SHA256="$EXP_TOML" -e EXP_FIXTURE_SHA256="$EXP_FX"
         -e EXP_R1CS="$EXP_R1CS" -e EXP_ACIR="$EXP_ACIR" -e EXP_GATES="$EXP_GATES"
         -e EXP_CIRCOM="circom compiler 2.2.3" -e EXP_SNARKJS="snarkjs@0.7.6"
         -e EXP_NARGO="nargo version = 1.0.0-beta.24" -e EXP_BB="5.0.0-nightly.20260522" -e EXP_NODE_PREFIX="v18.20.")

if [ "$MODE" = "--plan" ]; then
    echo "== DRY RUN inside $BENCH_IMAGE (records commands; executes none of them; unmeasured structural check)"
    set +e
    docker run --rm -i -v "$OUT:/out" "${RUN_ENV[@]}" -e DRY_RUN=1 -e STRUCT_CHECK=1 "$BENCH_IMAGE" bash -s \
        < "$B/bench_in_container.sh" 2>&1 | tee "$OUT/host_env/dry_run_console.log"
    rc=${PIPESTATUS[0]}; set -e; reclaim_out
    [ "$rc" -eq 0 ] || stop "dry run failed (input hash or environment check)"
    pass "inside image: input hashes == this checkout; toolchain == pinned versions; GNU time usable"
    pass "inside image (unmeasured): $(tr '\n' ';' < "$OUT/structural_check/structural_summary.txt")"
    pass "dry-run command accounting: $(($(grep -c . "$OUT/benchmark_commands.txt") - 1)) commands recorded, none executed"
else
    echo "== MEASURING inside $BENCH_IMAGE"
    set +e
    docker run --rm -i -v "$OUT:/out" "${RUN_ENV[@]}" "$BENCH_IMAGE" bash -s \
        < "$B/bench_in_container.sh" 2>&1 | tee "$OUT/host_env/bench_console.log"
    rc=${PIPESTATUS[0]}; set -e; reclaim_out
    [ "$rc" -eq 0 ] || stop "measurement stopped (see $OUT/logs/STOP.txt and host_env/bench_console.log)"
fi

# ---------------------------------------------------------------- run plan
{
  echo "zk-ePrescription final benchmark — run plan"
  echo "label=$LABEL mode=$MODE generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo=$REPO"
  echo "hostname=$(cat "$OUT/host_env/hostname.txt")"
  echo "base_image=$BASE_IMAGE $IMG_ID (arch $IMG_ARCH, created $IMG_CREATED)"
  echo "benchmark_image=$BENCH_IMAGE $BENCH_ID (derived=$DERIVED)"
  echo "warmup=$WARMUP measured: witness/prove/verify=$REPS compile=$COMPILE_REPS; one-time stages once"
  echo "input=TV-001  json $EXP_JSON  toml $EXP_TOML  fixture $EXP_FX"
  echo "expected structural counts (verified from tool output, STOP on mismatch): R1CS $EXP_R1CS, ACIR $EXP_ACIR, BB gates $EXP_GATES"
  echo
  echo "REPETITIONS"
  echo "  compile (circom, noir): $WARMUP warm-up + $COMPILE_REPS measured"
  echo "  witness/execute, prove, verify (both backends): $WARMUP warm-up + $REPS measured"
  echo "  once: ptau new/contribute/prepare, groth16 setup, zkey contribute, vk export, r1cs info, nargo info, bb gates, bb write_vk"
  echo "  excluded from statistics: warm-ups; noir crs_priming (CRS download/cache)"
  echo
  echo "PREFLIGHT CHECKS"
  cat "$CHECKS"
  echo
  echo "COMMANDS (exact, as recorded by the in-image dry run; tab-separated)"
  cat "$OUT/benchmark_commands.txt"
  echo
  echo "IN-RUN STOP CONDITIONS"
  echo "  any invocation exits non-zero (measured, once, or CRS priming)"
  echo "  input hashes inside the image != this checkout"
  echo "  R1CS / ACIR / gate count != expected"
  echo "  any Circom public.json or Noir public_inputs != fixture TV-001 (read from canonical_fixture.json)"
  echo "  any nargo execute output != [C, N] of fixture TV-001"
  echo "  any Groth16 verify without OK!, any bb verify without 'verified successfully'"
  echo
  echo "POST-RUN VALIDATION (validation.json)"
  echo "  public outputs == fixture; sanity C/N == values recorded at freeze (independent check)"
  echo "  repetition counts as approved; one-time stages exactly once"
  echo "  every generated proof verified once (verify run i checks the proof of prove run i)"
  echo "  artifact provenance (path, bytes, SHA-256): Circom R1CS, WASM, proof.json, verification_key.json; Noir ACIR JSON, witness, proof, vk"
  echo "  source tree unchanged (re-manifest)"
} > "$OUT/run_plan.txt"

if [ "$MODE" = "--plan" ]; then
    repo_manifest "$REPO" 2>/dev/null | grep -v $'^\\.gitignore\t' > "$OUT/host_env/source_manifest_after.sha256" 2>/dev/null
    cmp -s "$OUT/host_env/source_manifest_after.sha256" "$OUT/host_env/source_manifest_before.sha256" || stop "source tree changed during plan"
    echo "PASS  source tree unchanged after plan" | tee -a "$CHECKS" >> "$OUT/run_plan.txt"
    echo
    cat "$OUT/run_plan.txt"
    echo
    echo "PLAN COMPLETE — no measurement executed. Output: $OUT"
    exit 0
fi

# ---------------------------------------------------------------- metadata + summary + validation
docker run --rm -i -v "$OUT:/out" \
    -e LABEL="$LABEL" -e BASE_IMAGE="$BASE_IMAGE" -e COMMIT="$COMMIT" -e BASE_ID="$IMG_ID" -e IMG_CREATED="$IMG_CREATED" -e BENCH_IMAGE="$BENCH_IMAGE" -e BENCH_ID="$BENCH_ID" -e DERIVED="$DERIVED" \
    -e WARMUP="$WARMUP" -e REPS="$REPS" -e COMPILE_REPS="$COMPILE_REPS" \
    "$BENCH_IMAGE" node - <<'JS'
const fs = require("fs");
const rd = (p) => { try { return fs.readFileSync("/out/" + p, "utf8"); } catch { return null; } };
const kv = (t) => Object.fromEntries((t || "").split("\n").filter((l) => l.includes("=")).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
const mem = (t, k) => { const m = (t || "").match(new RegExp("^" + k + ":\\s+(\\d+) kB", "m")); return m ? Number(m[1]) : null; };
const ce = kv(rd("container_env.txt"));
const meminfo = rd("host_env/meminfo.txt");
const lscpu = rd("host_env/lscpu.txt") || "";
const g = (re) => { const m = lscpu.match(re); return m ? m[1].trim() : null; };
const os = (rd("host_env/os.txt") || "").split("\n");
const win = (rd("host_env/windows_host.txt") || "").trim().split("\n");
const dinfo = kv((rd("host_env/docker_info.txt") || "").trim().split(" ").join("\n"));
const dver = rd("host_env/docker_version.txt") || "";
const meta = {
  platform_label: process.env.LABEL,
  timestamp_utc: os[0],
  hostname: (rd("host_env/hostname.txt") || "").trim(),
  host: {
    uname: os[1],
    kernel: (os[1] || "").split(" ")[2] || null,
    os_release: ((rd("host_env/os.txt") || "").match(/PRETTY_NAME="([^"]+)"/) || [])[1] || null,
    architecture: g(/Architecture:\s*(.+)/),
    cpu_model: g(/Model name:\s*(.+)/),
    logical_cpus: Number((rd("host_env/nproc.txt") || "").trim()) || null,
    device_model: (rd("host_env/device_model.txt") || "").trim(),
    linux_visible_memtotal_kb: mem(meminfo, "MemTotal"),
    swaptotal_kb: mem(meminfo, "SwapTotal"),
    windows_host_physical_ram_bytes: /^\d+$/.test(win[0] || "") ? Number(win[0]) : "unavailable",
    windows_host_cpu: win[1] || "unavailable",
    windows_host_os: win[2] || "unavailable",
  },
  docker: {
    server_version: dinfo.ServerVersion || null,
    client_version: ((dver.match(/Client:[\s\S]*?Version:\s*(\S+)/) || [])[1]) || null,
    docker_visible_ncpu: Number(dinfo.NCPU) || null,
    docker_visible_memtotal_bytes: Number(dinfo.MemTotal) || null,
    docker_architecture: dinfo.Architecture || null,
    docker_kernel: dinfo.KernelVersion || null,
    base_image: process.env.BASE_IMAGE, base_image_id: process.env.BASE_ID, base_image_created: process.env.IMG_CREATED,
    benchmark_image: process.env.BENCH_IMAGE, benchmark_image_id: process.env.BENCH_ID,
    derived_image_used: process.env.DERIVED === "yes",
    derived_image_change: process.env.DERIVED === "yes" ? "Debian package 'time' (GNU time) added; /workspace and tool versions verified identical to base" : null,
  },
  container: { nproc: Number(ce.nproc) || null, memtotal_kb: mem(rd("container_env.txt"), "MemTotal"),
    cpu_model: ce.cpu_model, os_release: ce.os_release, kernel: ce.kernel, arch: ce.arch },
  toolchain: { circom: ce.circom, snarkjs: ce.snarkjs, nargo: ce.nargo, bb: ce.bb, node: ce.node, gnu_time: ce.gnu_time },
  input: {
    vector: "TV-001 (canonical aligned fixture)",
    circom_input: "circom/inputs/eprescription/canonical/TV-001.json", circom_input_sha256: ce.fixture_TV001_json_sha256,
    noir_input: "noir/redemption/tests/positive/TV-001.toml", noir_input_sha256: ce.fixture_TV001_toml_sha256,
    canonical_fixture: "testdata/kat/canonical_fixture.json", canonical_fixture_sha256: ce.canonical_fixture_json_sha256,
    fixture_commitment: ce.fixture_TV001_C, fixture_nullifier: ce.fixture_TV001_N,
  },
  methodology: {
    warmup: Number(process.env.WARMUP), measured_runs_witness_prove_verify: Number(process.env.REPS),
    measured_runs_compile: Number(process.env.COMPILE_REPS), primary_statistic: "median",
    peak_memory: "GNU time -v 'Maximum resident set size' (kB) of the measured process; user/sys CPU and elapsed also from GNU time",
    wall_clock: "nanosecond clock around each invocation",
    once_stages: ["circom ptau_new", "circom ptau_contribute", "circom ptau_prepare_phase2", "circom groth16_setup", "circom zkey_contribute",
                  "circom vk_export", "circom r1cs_info", "noir nargo_info", "noir bb_gates", "noir write_vk"],
    excluded_from_statistics: ["warm-up runs", "noir crs_priming (prep: CRS download/cache)"],
    noir_prove: "bb prove with precomputed VK (-k); write_vk measured separately",
    ptau_note: "Powers of Tau is development/setup infrastructure, not per-redemption latency",
    configuration_note: "Current machine configuration as-is; not a reproduction of any historical benchmark configuration",
  },
  harness_sha256: rd("harness_sha256.txt"),
  source_commit: process.env.COMMIT,
};
fs.writeFileSync("/out/benchmark_metadata.json", JSON.stringify(meta, null, 2) + "\n");
JS

docker run --rm -i -v "$OUT:/out" "$BENCH_IMAGE" node - /out < "$B/summarize.js" > /dev/null
echo "== Validation"
set +e
docker run --rm -i -v "$OUT:/out" -e WARMUP="$WARMUP" -e REPS="$REPS" -e COMPILE_REPS="$COMPILE_REPS" "$BENCH_IMAGE" \
    node - /out /workspace/testdata/kat/canonical_fixture.json < "$B/validate_outputs.js" | tee "$OUT/host_env/validation_console.txt"
VALID=${PIPESTATUS[0]}
set -e
reclaim_out

echo "== Postflight"
repo_manifest "$REPO" 2>/dev/null | grep -v $'^\\.gitignore\t' > "$OUT/host_env/source_manifest_after.sha256" 2>/dev/null
if cmp -s "$OUT/host_env/source_manifest_after.sha256" "$OUT/host_env/source_manifest_before.sha256"; then
    echo "PASS  source tree unchanged after benchmark" | tee -a "$CHECKS"
else
    echo "FAIL  source tree changed during benchmark" | tee -a "$CHECKS"; VALID=1
fi
for pair in "circom/inputs/eprescription/canonical/TV-001.json:$EXP_JSON" "noir/redemption/tests/positive/TV-001.toml:$EXP_TOML" "testdata/kat/canonical_fixture.json:$EXP_FX"; do
    f="${pair%%:*}"; h="${pair##*:}"
    if [ "$(sha256sum "$REPO/$f" | cut -d' ' -f1)" = "$h" ]; then echo "PASS  $f unchanged" | tee -a "$CHECKS"; else echo "FAIL  $f changed" | tee -a "$CHECKS"; VALID=1; fi
done

cat "$OUT/benchmark_report.txt"
if [ "$VALID" -ne 0 ]; then
    echo "BENCHMARK RESULTS NOT ACCEPTED — validation failed (see validation.json, host_env/preflight_checks.txt)"
    exit 1
fi
echo "BENCHMARK RESULTS VALIDATED — $OUT"
