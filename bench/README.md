# Benchmark harness (v1.4.2)

Measures both backends on the canonical vector TV-001 inside the repository's
Docker image: compile, witness generation, proving, verification, peak memory
(GNU `time -v`), proof and key sizes, and the one-time setup stages.

```bash
docker build -t zkep .
bash bench/run_benchmark.sh <platform-label> --plan   # checks + dry run, measures nothing
bash bench/run_benchmark.sh <platform-label>          # 1 warm-up + 5 runs (compile: 3)
node bench/print_summary.js results/bench/<platform-label>_<UTC>
```

- Output goes to `results/bench/<label>_<UTC>/` (gitignored): raw runs,
  medians, metadata, artifact hashes and `validation.json`.
- Preflight stops unless the image's `/workspace` is byte-identical to this
  checkout and the checkout is a clean git tree (`ALLOW_DIRTY=1` for test runs).
- Source downloaded as a ZIP instead of cloned: preflight records "not a git
  checkout". Set `SOURCE_COMMIT=<full sha>` to record the commit the ZIP came
  from; the source manifest in `host_env/` is the evidence that it matches.
- No `sudo` needed: after each container stage the harness hands the output
  folder back to the calling user.
- macOS on Apple silicon (Docker Desktop) works as a host: the measurements
  run in Docker Desktop's arm64 Linux VM, and the host metadata comes from
  `sysctl`, `sw_vers` and `pmset` (model, cores, RAM, power source, Low Power
  Mode). Check that `uname -m` and the image architecture are both `arm64`;
  `amd64` means x86 emulation and the run is not valid for Apple silicon.
- The run is accepted only if every validation check passes, including:
  every proof verified, public outputs equal to the fixture, and the expected
  circuit sizes (12,291 R1CS constraints; 16,681 ACIR opcodes; 22,182 gates).

Version history: v1.3 produced the published laptop results (run
`laptop-x86_64-wsl2_20261004T083403Z`). v1.4 changes only circuit and package
names for the restructured layout, and checks against this checkout instead of
external frozen manifests; it produced the desktop results (run
`pc2-Intel-R-Core-TM-i7-14700-wsl2_20261028T100755Z`). v1.4.1 returns ownership
of the output folder to the calling user (v1.4 needed `sudo` on Linux
filesystems) and adds `SOURCE_COMMIT`. v1.4.2 adds macOS host support. The
measured commands are unchanged in every version.
