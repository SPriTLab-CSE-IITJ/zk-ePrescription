# Benchmark Results

Both backends were measured on the canonical fixture TV-001 on two x86-64
machines. Each run passed all 46 validation checks: every proof verified,
public outputs equal to the fixture, circuit sizes as expected, source tree
unchanged.

| | Laptop (P1) | Desktop (P2) |
|---|---|---|
| Result directory | `laptop-x86_64-wsl2_20261004T083403Z` | `pc2-Intel-R-Core-TM-i7-14700-wsl2_20261028T100755Z` |
| CPU | Intel Core i5-11400H @ 2.70 GHz | Intel Core i7-14700 |
| Logical CPUs visible | 12 | 8 (WSL2 limit) |
| Host RAM / WSL-visible RAM | 15.73 GiB / 7.62 GiB | 15.72 GiB / 11.68 GiB |
| OS | Ubuntu 24.04.4 LTS on WSL2, Windows 11 | Ubuntu 26.04 LTS on WSL2 (kernel 6.6.114.1), Windows 11 Pro |
| Docker | 29.1.3 | 29.8.0 |
| Harness | v1.3 (before the restructure) | v1.4 |
| Source | frozen tree, pre-restructure | commit `f257cad` (ZIP download; manifest `1cf2c52a…`, 154 files) |

The laptop run used harness v1.3 before the repository was restructured, when
the circuit files were named `circom/circuits/08_eprescription_main.circom` and
`noir/phase4_orchestrator`. The compiled circuits are identical to today's
`redemption.circom` and `noir/redemption`. Both runs produced the same R1CS
(`26cbeef7…0b56d1b`), witness WASM (`4ddf1b05…8119821`), ACIR bytecode and
UltraHonk verification key (`4e8a56ad…e244c2d`). The Groth16 keys differ
because each run performs its own local ceremony. To reproduce, see
`bench/README.md`.

## Per-redemption cost

Medians of 5 measured runs after 1 warm-up (compile: 3 after 1).

| Metric | Groth16 P1 | Groth16 P2 | UltraHonk P1 | UltraHonk P2 |
|---|---:|---:|---:|---:|
| Structural size | 12,291 R1CS | 12,291 R1CS | 16,681 ACIR / 22,182 gates | 16,681 ACIR / 22,182 gates |
| Compile | 0.404 s | 0.284 s | 0.646 s | 0.416 s |
| Witness / execute | 0.058 s | 0.041 s | 0.263 s | 0.204 s |
| Prove | 0.797 s | 0.588 s | 0.421 s | 0.293 s |
| Verify | 0.354 s | 0.224 s | 0.009 s | 0.007 s |
| Peak proving RSS | 588.10 MiB | 438.21 MiB | 67.98 MiB | 60.31 MiB |
| Peak verification RSS | 161.72 MiB | 132.13 MiB | 9.21 MiB | 8.50 MiB |
| Proof size | 802 B | 801 B | 14,656 B | 14,656 B |
| Verification key size | 3,480 B | 3,476 B | 3,680 B | 3,680 B |

- **Structural sizes are backend-native units.** R1CS constraints, ACIR opcodes
  and Barretenberg gates measure different things and must not be treated as
  directly comparable.
- **Median is the primary statistic** for all repeated stages. Peak RSS values
  are the median over the measured runs. No value in this table is estimated.
- Circom witness = `generate_witness.js`; Noir witness = `nargo execute`.
- Proof size: Groth16 `proof.json`; UltraHonk binary `proof`. The Groth16
  sizes are JSON text, so they vary by a few bytes with the encoding of the
  numbers (801–808 B across the P2 runs); the binary UltraHonk proof and both
  UltraHonk keys are fixed in size. The Groth16 VK size differs for the same
  reason.

## One-Time Setup Costs

| Stage | P1 | P2 |
|---|---:|---:|
| Powers of Tau new | 1.113 s | 0.738 s |
| Powers of Tau contribution | 10.292 s | 6.441 s |
| Powers of Tau phase-2 preparation | 187.107 s | 132.061 s |
| Groth16 setup | 7.950 s | 4.409 s |
| zkey contribution | 1.482 s | 0.941 s |
| Groth16 VK export | 0.361 s | 0.232 s |
| UltraHonk VK generation | 0.125 s | 0.105 s |

These are setup/preparation costs, each measured once. They are **not**
per-redemption latency. The Groth16 setup is a local single-contributor
development ceremony, not a production trusted setup.

## Measurement Methodology

- compile: 1 warm-up + 3 measured runs
- witness/execute/prove/verify: 1 warm-up + 5 measured runs
- median is primary
- mean/min/max/sample SD are retained
- peak RSS measured using GNU `/usr/bin/time -v` (Maximum resident set size)
- snarkjs timings include Node.js startup
- Noir proving uses the precomputed verification key (`bb prove -k`)
- CRS priming is excluded from statistics
- every generated proof was verified; public outputs were checked against the
  canonical fixture

## Important Observations

Performance is hardware-dependent; the comparisons below hold on both machines.

- UltraHonk proves faster than Groth16: 0.421 s vs 0.797 s (P1) and
  0.293 s vs 0.588 s (P2).
- UltraHonk uses far less peak proving memory: 67.98 vs 588.10 MiB (P1) and
  60.31 vs 438.21 MiB (P2). The Groth16 figure is the whole snarkjs Node.js
  process.
- Groth16 has a much smaller proof: about 0.8 KB vs 14.3 KB.
- UltraHonk verifies faster: 9 ms vs 354 ms (P1) and 7 ms vs 224 ms (P2). The
  snarkjs figure includes Node.js startup.
- P2 is faster than P1 at every per-redemption stage, by roughly 1.3× to 1.6×,
  and every relation above is the same on both.

Run-to-run spread of the measured proving runs: Groth16 0.775–0.970 s (P1),
0.574–0.635 s (P2); UltraHonk 0.417–0.469 s (P1), 0.282–0.312 s (P2). All raw
runs are preserved and the median remains the primary statistic.

P2 run notes: the source was downloaded as a ZIP of `f257cad`, so the harness
recorded "not a git checkout"; the ZIP's source manifest
(`host_env/source_manifest_zip_f257cad.sha256`, sha256 `1cf2c52a…`) matches the
merged tree, and preflight confirmed the image's `/workspace` equals it. The run
was started with `sudo` because harness v1.4 left the result folder owned by
root on a Linux filesystem; v1.4.1 fixes this and does not change any measured
command.

## Toolchain

- Circom 2.2.3
- snarkjs 0.7.6
- Nargo 1.0.0-beta.24
- Barretenberg 5.0.0-nightly.20260522
- Node v18.20.8
- P1 benchmark image `sha256:af38ddc253718e6611309a3daf49e1c9b88bcc009d28f778ebf1319f6b53b8b8`
  (the frozen image `sha256:ad024e4e0422da927cd9fd1ddcc06c4508979c09b8fe136012bec4f00e0c4acb`
  plus GNU `time` only)
- P2 image `sha256:a1d888f5b99ac5371a28296be4f6222ac9a6ee19cead5294e4d1bebb316fe275`
  (the pinned `Dockerfile` at `f257cad`, which includes GNU `time`)

Raw measurements, metadata, validation output, and artifact hashes are retained
in each benchmark result directory.
