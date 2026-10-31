# Benchmark harness (v1.4.2)

Measures both backends on the canonical vector TV-001 inside the repository's
Docker image: compile, witness generation, proving, verification, peak memory
(GNU `time -v`), proof and key sizes, and the one-time setup stages.

## Benchmark your machine (one command)

```bash
git clone https://github.com/SPriTLab-CSE-IITJ/zk-ePrescription.git
cd zk-ePrescription
bash bench/run_device.sh            # sudo bash bench/run_device.sh if Docker needs root
```

`run_device.sh` records the platform, builds the image, runs the regression
once, then runs the harness below (dry run, then measurement), prints the
summary and packs the validated result into `results/<label>_bench.tgz`. It
also says whether your compiled circuits are identical to the published runs.
It works on Linux (x86-64 and ARM64, including Jetson and Raspberry Pi 5 with a
64-bit OS), Windows through WSL2, and macOS with Docker Desktop. Plan for about
12 GB of disk, internet for the build, and 20–40 minutes on a PC (1–3 hours on
a small board, mostly the first image build).

It changes nothing on the machine unless asked:

| Option | Effect (needs root) |
|---|---|
| `--install-docker` | install Docker with apt if missing (Debian/Ubuntu) |
| `--add-swap` | add a 6 GB swap file until reboot if RAM + swap < 9 GB (needed to build on 4 GB boards) |
| `--max-performance` | lock clocks for stable timings, restored at the end: `jetson_clocks` on Jetson, CPU governor `performance` elsewhere |
| `--label NAME` | name of the result directory (default: CPU or board model + architecture) |
| `--skip-tests` | skip the regression run |

A fresh board with nothing installed:
`sudo bash bench/run_device.sh --install-docker --add-swap --max-performance`.

Compare the printed medians with [`docs/BENCHMARK_RESULTS.md`](../docs/BENCHMARK_RESULTS.md).
Absolute times depend on the hardware; circuit sizes, proof sizes and the
UltraHonk verification-key size must match exactly.

## The harness itself

```bash
docker build -t zkep .
bash bench/run_benchmark.sh <platform-label> --plan   # checks + dry run, measures nothing
bash bench/run_benchmark.sh <platform-label>          # 1 warm-up + 5 runs (compile: 3)
docker run --rm -v "$PWD/results:/workspace/results" --entrypoint node zkep \
  bench/print_summary.js results/bench/<platform-label>_<UTC>
```

- Output goes to `results/bench/<label>_<UTC>/` (gitignored): raw runs,
  medians, metadata, artifact hashes and `validation.json`.
- Preflight stops unless the image's `/workspace` is byte-identical to this
  checkout and the checkout is a clean git tree (`ALLOW_DIRTY=1` for test runs).
  After changing or pulling the code, rebuild the image.
- `IMAGE=<name>` uses another image name (useful on a shared Docker host).
- Source downloaded as a ZIP instead of cloned: preflight records "not a git
  checkout". Set `SOURCE_COMMIT=<full sha>` to record the commit the ZIP came
  from; the source manifest in `host_env/` is the evidence that it matches.
- No `sudo` needed for the output: after each container stage the harness hands
  the output folder back to the calling user.
- macOS on Apple silicon (Docker Desktop) works as a host: the measurements
  run in Docker Desktop's arm64 Linux VM, and the host metadata comes from
  `sysctl`, `sw_vers` and `pmset`. Check that `uname -m` and the image
  architecture are both `arm64`; `amd64` means x86 emulation and the run is not
  valid for Apple silicon.
- The run is accepted only if every validation check passes, including:
  every proof verified, public outputs equal to the fixture, and the expected
  circuit sizes (12,291 R1CS constraints; 16,681 ACIR opcodes; 22,182 gates).

Version history: v1.3 produced the laptop results (run
`laptop-x86_64-wsl2_20261004T083403Z`). v1.4 changes only circuit and package
names for the restructured layout and checks against this checkout; it produced
the desktop, server, Jetson and Raspberry Pi 5 results. v1.4.1 returns ownership of the output
folder to the calling user and adds `SOURCE_COMMIT`. v1.4.2 adds macOS host
support. The measured commands are unchanged in every version.
