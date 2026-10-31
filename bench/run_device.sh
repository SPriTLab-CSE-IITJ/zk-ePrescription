#!/usr/bin/env bash
# zk-ePrescription — benchmark this checkout on the current machine, end to end.
#
#   bash bench/run_device.sh [options]          (sudo bash ... if Docker needs root)
#
# Steps: record the platform -> build the Docker image -> run the regression
# once -> benchmark harness (dry run, then measurement) -> print the summary ->
# pack the validated result directory into one .tgz to send back.
#
# It changes nothing on the machine unless asked:
#   --install-docker   install Docker with apt if it is missing (Debian/Ubuntu, needs root)
#   --add-swap         add a 6 GB /swapfile until reboot if RAM + swap < 9 GB (needs root)
#   --max-performance  lock clocks for stable timings, restored at the end (needs root):
#                      Jetson: jetson_clocks; other Linux: CPU governor 'performance'
# Other options:
#   --label NAME       result label (default: derived from the CPU / board model)
#   --skip-tests       skip the regression run (it is not part of the measurement)
#   -h, --help         this text
#
# Works on Linux (x86-64 and ARM64: PCs, servers, Jetson, Raspberry Pi 5 with a
# 64-bit OS), Windows through WSL2, and macOS with Docker Desktop. Needs about
# 12 GB of free disk and internet for the image build. Takes 20-40 minutes on a
# PC and 1-3 hours on a small board; most of it is the one-time image build.
set -euo pipefail

INSTALL_DOCKER=0; ADD_SWAP=0; MAX_PERF=0; SKIP_TESTS=0; LABEL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --install-docker) INSTALL_DOCKER=1 ;;
        --add-swap) ADD_SWAP=1 ;;
        --max-performance) MAX_PERF=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        --label) shift; LABEL="${1:?--label needs a name}" ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (see --help)"; exit 2 ;;
    esac
    shift
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
[ -f docs/protocol_specification.md ] || { echo "run from inside the zk-ePrescription repository"; exit 1; }
export IMAGE="${IMAGE:-zkep}"
OS="$(uname -s)"; ARCH="$(uname -m)"
RUN_USER="${SUDO_USER:-$(id -un)}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$REPO/results/device_run_$TS"
mkdir -p "$WORK"
LOG="$WORK/run_device.log"
exec > >(tee -a "$LOG") 2>&1

step() { echo; echo "=================== $* ($(date -u +%H:%M:%SZ))"; }
die()  { echo; echo "STOPPED: $*"; echo "Full log: $LOG"; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "$1 needs root: run again with sudo"; }

PAPER_R1CS=26cbeef7d32c609ddde24ca58757135400cbd6929f2d5c8199e4c487d0b56d1b
PAPER_UH_VK=4e8a56ad6641942847392b9b39eac1ffd3e82d3e0e1fb5879c809776ce244c2d

# ------------------------------------------------------------------ 0. platform
step "0. Platform"
KIND=linux; MODEL=""
if [ "$OS" = "Darwin" ]; then
    KIND=macos; MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo Mac)"
elif [ -r /etc/nv_tegra_release ]; then
    KIND=jetson; MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo Jetson)"
elif grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null; then
    KIND=pi; MODEL="$(tr -d '\0' < /proc/device-tree/model)"
else
    grep -qi microsoft /proc/version 2>/dev/null && KIND=wsl
    MODEL="$(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -1)"
fi
[ -n "$MODEL" ] || MODEL="$ARCH"
case "$ARCH" in x86_64|amd64|aarch64|arm64) ;; *) die "unsupported architecture $ARCH (use a 64-bit OS)";; esac
{
    echo "kind: $KIND"
    echo "model: $MODEL"
    echo "os: $(uname -srm)"
    [ "$OS" = "Darwin" ] && echo "macOS: $(sw_vers -productVersion)" || grep PRETTY_NAME /etc/os-release 2>/dev/null || true
    [ "$KIND" = jetson ] && echo "l4t: $(head -1 /etc/nv_tegra_release)"
    [ "$KIND" = jetson ] && command -v nvpmodel >/dev/null && nvpmodel -q 2>/dev/null | head -1
    [ "$KIND" = pi ] && echo "throttled since boot: $(vcgencmd get_throttled 2>/dev/null || echo n/a)  page size: $(getconf PAGESIZE)"
    if [ "$OS" = "Linux" ]; then
        echo "cpus: $(nproc)  governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo n/a)"
        echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"
        free -h
    else
        echo "cpus: $(sysctl -n hw.ncpu)  memory: $(( $(sysctl -n hw.memsize) / 1073741824 )) GiB"
    fi
    echo "git: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo 'not a git checkout')"
} | tee "$WORK/platform.txt"
if [ -z "$LABEL" ]; then
    LABEL="$(echo "$MODEL" | tr 'A-Z' 'a-z' | sed 's/nvidia//; s/developer kit//; s/ model .*//; s/ rev .*//; s/([^)]*)//g; s/cpu @.*//; s/ @.*//; s/ [0-9]*-core processor//; s/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')-$ARCH"
    [ "$KIND" = wsl ] && LABEL="$LABEL-wsl2"
fi
echo "label: $LABEL"

# ------------------------------------------------------------------ 1. Docker
step "1. Docker"
if ! command -v docker >/dev/null; then
    if [ "$INSTALL_DOCKER" = 1 ] && command -v apt-get >/dev/null; then
        need_root "--install-docker"
        DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
        systemctl enable --now docker >/dev/null 2>&1 || service docker start
    else
        die "Docker is not installed. Install it (https://docs.docker.com/get-docker/) or, on Debian/Ubuntu, rerun with: sudo bash bench/run_device.sh --install-docker"
    fi
fi
docker info >/dev/null 2>&1 || die "Docker is installed but not usable by $(id -un): start Docker, or rerun with sudo"
docker info --format 'Docker {{.ServerVersion}} {{.Architecture}} CPUs={{.NCPU}} Mem={{.MemTotal}} root={{.DockerRootDir}}' | tee -a "$WORK/platform.txt"
if [ "$OS" = "Linux" ]; then
    DROOT="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)"
    [ -d "$DROOT" ] || DROOT=/var/lib
    FREE_GB=$(df -BG --output=avail "$DROOT" 2>/dev/null | tail -1 | tr -dc 0-9 || echo 99)
    [ "${FREE_GB:-99}" -ge 12 ] || die "only ${FREE_GB} GB free for Docker ($DROOT); the image build needs about 12 GB"
fi

# ------------------------------------------------------------------ 2. optional machine changes
step "2. Machine settings (changed only when asked)"
RESTORE_GOV=""; RESTORE_CLOCKS=""; MON_PIDS=""
cleanup() {
    for p in $MON_PIDS; do kill "$p" 2>/dev/null || true; done
    if [ -n "$RESTORE_CLOCKS" ]; then jetson_clocks --restore "$RESTORE_CLOCKS" >/dev/null 2>&1 || true; fi
    if [ -n "$RESTORE_GOV" ]; then
        for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "$RESTORE_GOV" > "$g" 2>/dev/null || true; done
    fi
    [ "$(id -u)" -eq 0 ] && [ "$RUN_USER" != root ] && chown -R "$RUN_USER" "$REPO/results" 2>/dev/null || true
}
trap cleanup EXIT
if [ "$ADD_SWAP" = 1 ] && [ "$OS" = "Linux" ]; then
    need_root "--add-swap"
    MEM_MB=$(free -m | awk '/^Mem:/ {print $2}'); SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')
    if [ $((MEM_MB + SWAP_MB)) -lt 9000 ] && [ ! -f /swapfile ]; then
        fallocate -l 6G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=6144
        chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile && echo "added 6 GB /swapfile (until reboot)"
    else
        echo "swap: not needed (RAM + swap = $((MEM_MB + SWAP_MB)) MB)"
    fi
fi
if [ "$MAX_PERF" = 1 ] && [ "$OS" = "Linux" ]; then
    need_root "--max-performance"
    if [ "$KIND" = jetson ] && command -v jetson_clocks >/dev/null; then
        RESTORE_CLOCKS="$WORK/jetson_clocks_before.conf"
        jetson_clocks --store "$RESTORE_CLOCKS" && jetson_clocks && echo "jetson_clocks: clocks locked (restored at the end)"
        jetson_clocks --show > "$WORK/jetson_clocks.txt" 2>&1 || true
    elif [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        RESTORE_GOV="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
        for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g"; done
        echo "CPU governor: performance (was $RESTORE_GOV; restored at the end)"
    fi
fi
[ "$ADD_SWAP$MAX_PERF" = "00" ] && echo "none requested; current settings are recorded in platform.txt"

# ------------------------------------------------------------------ 3. image
step "3. Docker image '$IMAGE' (first build 5-15 min on a PC, up to 1-2 h on a small board; later builds are cached)"
if ! docker build -t "$IMAGE" . > "$WORK/docker_build.log" 2>&1; then
    if grep -qiE 'no matching manifest|not found: manifest' "$WORK/docker_build.log"; then
        echo "pinned base image not available for $ARCH -> building from the same tags without the digest"
        echo "FALLBACK: RUST_IMAGE=rust:1.96-bookworm NODE_IMAGE=node:18.20-bookworm" > "$WORK/build_fallback.txt"
        docker build --build-arg RUST_IMAGE=rust:1.96-bookworm --build-arg NODE_IMAGE=node:18.20-bookworm \
            -t "$IMAGE" . >> "$WORK/docker_build.log" 2>&1 || die "docker build failed (see $WORK/docker_build.log)"
    else
        tail -20 "$WORK/docker_build.log"
        die "docker build failed (network? run again; finished layers are cached). Log: $WORK/docker_build.log"
    fi
fi
echo "image $(docker image inspect "$IMAGE" --format '{{.Id}} {{.Architecture}}')"
grep -A3 'tool binaries' "$WORK/docker_build.log" | tail -3 || true

# ------------------------------------------------------------------ 4. regression
if [ "$SKIP_TESTS" = 0 ]; then
    step "4. Regression on this machine (5 min on a PC, up to 30 min on a small board)"
    docker run --rm "$IMAGE" test > "$WORK/test.log" 2>&1 || true
    sed -n '/^SUMMARY/,$p' "$WORK/test.log"
    grep -q "ALL REGRESSION TESTS PASSED" "$WORK/test.log" || {
        [ "$KIND" = pi ] && [ "$(getconf PAGESIZE)" != 4096 ] && echo "NOTE: this kernel uses $(getconf PAGESIZE)-byte pages; if a tool crashed, add kernel=kernel8.img to /boot/firmware/config.txt and reboot."
        die "regression failed (see $WORK/test.log)"; }
else
    step "4. Regression skipped (--skip-tests)"
fi

# ------------------------------------------------------------------ 5. benchmark
step "5. Benchmark dry run (checks only)"
bash bench/run_benchmark.sh "$LABEL" --plan > "$WORK/plan.log" 2>&1 || true
grep -E '^(PASS|STOP)' "$WORK/plan.log" | tail -6
grep -q "PLAN COMPLETE" "$WORK/plan.log" || die "dry run failed (see $WORK/plan.log)"

step "6. Benchmark (do not use the machine meanwhile)"
if [ "$OS" = "Linux" ]; then
    ( while true; do
        echo "$(date -u +%H:%M:%S) load=$(cut -d' ' -f1 /proc/loadavg) temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null) cpu0_kHz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null) $(vcgencmd get_throttled 2>/dev/null) top=$(ps -eo pcpu,comm --sort=-pcpu | sed -n 2p | tr -s ' ')"
        sleep 2
      done ) > "$WORK/monitor.log" 2>&1 &
    MON_PIDS="$!"
    if command -v tegrastats >/dev/null; then tegrastats --interval 1000 > "$WORK/tegrastats.log" 2>&1 & MON_PIDS="$MON_PIDS $!"; fi
fi
bash bench/run_benchmark.sh "$LABEL" 2>&1 | tee "$WORK/benchmark_console.log" | grep -E '^(== |PASS|FAIL|STOP|BENCHMARK)' || true
R="$(ls -td results/bench/"${LABEL}"_* 2>/dev/null | grep -v _plan | head -1 || true)"
[ -n "$R" ] && [ -f "$R/validation.json" ] && grep -q '"all_pass": true' "$R/validation.json" \
    || die "benchmark not validated (see $WORK/benchmark_console.log)"

# ------------------------------------------------------------------ 7. summary + package
step "7. Summary"
docker run --rm -v "$REPO/results:/workspace/results" --entrypoint node "$IMAGE" bench/print_summary.js "$R" || true
R1CS=$(awk '$1 == "artifacts/circom/redemption.r1cs" {print $3}' "$R/artifact_manifest.sha256")
UHVK=$(awk '$1 == "artifacts/noir/vk/vk" {print $3}' "$R/artifact_manifest.sha256")
if [ "$R1CS" = "$PAPER_R1CS" ] && [ "$UHVK" = "$PAPER_UH_VK" ]; then
    echo "Compiled circuits: identical to the published benchmarks (R1CS ${R1CS:0:12}..., UltraHonk VK ${UHVK:0:12}...)"
else
    echo "Compiled circuits: DIFFER from the published benchmarks (this checkout changed the circuits); compare with care"
fi
if [ -s "$WORK/monitor.log" ]; then
    echo "Max load during the run: $(awk '{print $2}' "$WORK/monitor.log" | cut -d= -f2 | sort -n | tail -1); max temperature: $(grep -o 'temp=[0-9.]*' "$WORK/monitor.log" | cut -d= -f2 | sort -n | tail -1) C"
fi
mkdir -p "$R/host_env/device_run"
cp "$WORK"/*.log "$WORK"/*.txt "$R/host_env/device_run/" 2>/dev/null || true
cp "$REPO/bench/run_device.sh" "$R/host_env/device_run/" 2>/dev/null || true
TGZ="$REPO/results/${LABEL}_bench.tgz"
tar czf "$TGZ" -C "$REPO/results/bench" "$(basename "$R")"
echo
echo "DONE. Result: $R"
echo "Packed for sharing: $TGZ ($(du -h "$TGZ" | cut -f1))"
