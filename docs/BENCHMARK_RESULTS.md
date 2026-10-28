# Benchmark Results

## Laptop Evaluation

Platform:
- x86_64
- Intel Core i5-11400H @ 2.70 GHz
- 12 logical CPUs
- Windows host RAM: 15.73 GiB
- WSL/Docker visible RAM: 7.62 GiB
- Ubuntu 24.04.4 LTS (WSL2, kernel 6.18.33.2-microsoft-standard-WSL2)
- Docker 29.1.3

All measurements below are from the already validated laptop benchmark of the
frozen aligned implementation using canonical fixture TV-001
(result directory `laptop-x86_64-wsl2_20261004T083403Z`; 46/46 validation
checks passed).

The run used harness v1.3 before the repository was restructured, when the
circuit files were named `circom/circuits/08_eprescription_main.circom` and
`noir/phase4_orchestrator`. The compiled circuits are identical to today's
`redemption.circom` and `noir/redemption`: same R1CS
(`26cbeef7…0b56d1b`), same witness WASM and same ACIR bytecode. To reproduce,
see `bench/README.md` (harness v1.4, same measured commands).

| Metric | Circom / Groth16 | Noir / UltraHonk |
|---|---:|---:|
| Structural size | 12,291 R1CS constraints | 16,681 ACIR opcodes / 22,182 BB gates |
| Compile median | 0.404 s | 0.646 s |
| Witness / Execute median | 0.058 s | 0.263 s |
| Prove median | 0.797 s | 0.421 s |
| Verify median | 0.354 s | 0.009 s |
| Peak proving RSS | 588.10 MiB | 67.98 MiB |
| Peak verification RSS | 161.72 MiB | 9.21 MiB |
| Proof size | 802 B | 14,656 B |
| Verification key size | 3,480 B | 3,680 B |

- **Structural sizes are backend-native units.** R1CS constraints, ACIR opcodes
  and Barretenberg gates measure different things and must not be treated as
  directly comparable.
- **Median is the primary statistic** for all repeated stages. Peak RSS values
  are the median over the measured runs. No value in this table is estimated.
- Circom witness = `generate_witness.js`; Noir witness = `nargo execute`.
- Proof size: Groth16 `proof.json`; UltraHonk binary `proof`.

## One-Time Setup Costs

| Stage | Time |
|---|---:|
| Powers of Tau new | 1.113 s |
| Powers of Tau contribution | 10.292 s |
| Powers of Tau phase-2 preparation | 187.107 s |
| Groth16 setup | 7.950 s |
| zkey contribution | 1.482 s |
| Groth16 VK export | 0.361 s |
| UltraHonk VK generation | 0.125 s |

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

These are measurements on this specific platform; performance is
hardware-dependent.

- Noir/UltraHonk has lower median proving time than Circom/Groth16 in this
  experiment (0.421 s vs 0.797 s).
- Noir/UltraHonk uses substantially less peak proving RSS in this experiment
  (67.98 MiB vs 588.10 MiB; the Groth16 figure is for the snarkjs Node.js process).
- Groth16 produces a much smaller proof (802 B vs 14,656 B).
- UltraHonk verification is substantially faster in this experiment
  (0.009 s vs 0.354 s; the snarkjs figure includes Node.js startup).

Run-to-run spread of the measured proving runs: Groth16 0.775–0.970 s,
UltraHonk 0.417–0.469 s. All raw runs are preserved and the median remains the
primary statistic.

## Toolchain

- Circom 2.2.3
- snarkjs 0.7.6
- Nargo 1.0.0-beta.24
- Barretenberg 5.0.0-nightly.20260522
- Node v18.20.8
- benchmark image `sha256:af38ddc253718e6611309a3daf49e1c9b88bcc009d28f778ebf1319f6b53b8b8`
  (the frozen image `sha256:ad024e4e0422da927cd9fd1ddcc06c4508979c09b8fe136012bec4f00e0c4acb`
  plus GNU `time` only)

Raw measurements, metadata, validation output, and artifact hashes are retained
in the benchmark result directory.
