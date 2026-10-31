# zk-ePrescription

**Privacy-preserving e-prescription redemption with zero-knowledge proofs: one protocol, two independent proving stacks.**

A patient proves to a pharmacy that a prescription was signed by a registered
doctor, has not been altered, has not expired and has redemptions left,
without revealing their secret, the doctor's identity or the prescription
fields. The same normative protocol
([`docs/protocol_specification.md`](docs/protocol_specification.md)) is
implemented twice:

| Backend | Circuit language | Proving system | Folder |
|---|---|---|---|
| A | Circom 2.2.3 | Groth16 (snarkjs 0.7.6), BN254 | `circom/` |
| B | Noir 1.0.0-beta.24 | UltraHonk (Barretenberg 5.0.0-nightly.20260522), BN254 | `noir/` |

Research artifact; not audited and not for clinical use.

---

## Quick start

Requirements: Docker. Network access is needed only for `docker build`, which
also downloads and caches Barretenberg's CRS; the commands below run offline.

```bash
docker build -t zkep .
docker run --rm zkep demo     # one redemption end to end, explained step by step
docker run --rm zkep test     # full regression with a summary table
docker run --rm zkep kat      # cross-backend equality of every protocol value
```

Each command prints one line per check; full tool output is written to
`results/logs/` inside the container (mount it with `-v "$PWD/results:/workspace/results"`
to keep it). `docker run --rm -it zkep bash` opens a shell with every tool.

## One command: clone, test and benchmark on your machine

```bash
git clone https://github.com/SPriTLab-CSE-IITJ/zk-ePrescription.git
cd zk-ePrescription
bash bench/run_device.sh        # sudo bash bench/run_device.sh if your user cannot run docker
```

`bench/run_device.sh` does everything in one go: records the machine, builds
the image, runs the full regression (E2), runs the benchmark (E3), prints a
summary, checks that your compiled circuits are identical to the published
ones, and packs the result into `results/<label>_bench.tgz`. It works on Linux
(x86-64 and ARM64, including Jetson and Raspberry Pi 5 with a 64-bit OS),
Windows through WSL2, and macOS with Docker Desktop. Allow about 12 GB of disk
and 20–40 minutes on a PC (1–3 hours on a small board, mostly the first build).

It changes nothing on your machine unless you ask: on a fresh Debian/Ubuntu
board with nothing installed, use
`sudo bash bench/run_device.sh --install-docker --add-swap --max-performance`.
Options are described in [`bench/README.md`](bench/README.md).

## Benchmark results

Both backends were measured with this procedure on five platforms. Every run
passed all 46 validation checks, and all five built byte-identical circuits.

![Time per redemption on five platforms](docs/figures/benchmark_prove_time.svg)

![Peak proving memory on five platforms](docs/figures/benchmark_prove_memory.svg)

| Median | Laptop | Desktop | Server | Jetson Orin Nano | Raspberry Pi 5* |
|---|---:|---:|---:|---:|---:|
| Groth16 prove / verify | 0.797 / 0.354 s | 0.588 / 0.224 s | 1.163 / 0.690 s | 2.479 / 0.854 s | 2.988 / 0.652 s |
| UltraHonk prove / verify | 0.421 / 0.009 s | 0.293 / 0.007 s | 0.367 / 0.017 s | 0.733 / 0.023 s | 1.618 / 0.033 s |
| Proof size, Groth16 / UltraHonk | 0.8 KB / 14.3 KB | same | same | same | same |

\*The Pi 5 ran at 79–87 °C with firmware throttling; its times are an upper
bound. Full tables, run conditions and setup costs:
[`docs/BENCHMARK_RESULTS.md`](docs/BENCHMARK_RESULTS.md). The raw result
archives of all five runs, with a script that recomputes every number from the
individual runs, are in the release
[bench-evidence-2026-10-30](https://github.com/SPriTLab-CSE-IITJ/zk-ePrescription/releases/tag/bench-evidence-2026-10-30).

---

## Major claims

| Claim | Statement | Evidence |
|---|---|---|
| **C1** Equivalence | Both backends compute identical protocol values (Poseidon2 permutation and sponge, C, I, N, registry leaves, nodes and root, PB) for identical inputs. | E1: 107/107 equal |
| **C2** Soundness checks | Valid redemptions verify in both backends; every attack vector (20) is rejected by a circuit constraint, and tampered public inputs do not verify. | E2: summary table |
| **C3** Performance | Per-redemption cost of both stacks on three x86-64 machines (laptop, desktop, 128-core server), as reported in [`docs/BENCHMARK_RESULTS.md`](docs/BENCHMARK_RESULTS.md). | E3 |
| **C4** ARM64 boards | The same protocol runs and is benchmarked on NVIDIA Jetson Orin Nano and Raspberry Pi 5. | E4 |

## Experiments

### E1: cross-backend equality (claim C1)

Under a minute of compute after the image build.

```bash
docker run --rm zkep kat
```

Expected end of output:

```
      input set 'canonical': 17 protocol values ......... 17/17 equal  PASS
      ...
      registry generator: leaves, paths, root ........... 4/4 equal  PASS
      issuance binding circuits: I and PB ............... 1/1 equal  PASS
      TOTAL (JS reference = Circom = Noir) .............. 107/107 equal  PASS
```

Six input sets (canonical, three other doctors, edge and zero values) are
evaluated by an independent JavaScript reference, the Circom witness and Noir
execution; the raw permutation is also compared with independent reference
vectors (`testdata/kat/poseidon2_permutation_reference.json`).

### E2: regression (claim C2)

A few compute minutes; most of it is the one-time local Groth16 ceremony.

```bash
docker run --rm zkep test
```

The run prints four sections (Circom/Groth16, Noir/UltraHonk, the attack table,
cross-backend equality) and ends with:

```
SUMMARY                                   Circom / Groth16    Noir / UltraHonk
  valid redemptions (outputs = fixture)    5/5                 5/5
  proofs generated and verified            5/5                 5/5
  attack vectors rejected                  20/20               20/20
  tampered public inputs rejected          4/4                 20/20
  Schnorr verifier vectors                 8/8                 8/8
  circuit size (native units)              12291 R1CS          16681 ACIR opcodes
  library tests / issuance binding (Noir)  6/6 / 4/4
  cross-backend KAT                        107/107 equal

RESULT: ALL REGRESSION TESTS PASSED
```

The attack table names, for every vector, what the attacker changed and which
check rejected it in each backend (signature, registry, expiry,
slot < threshold, s < l bound, point on curve, binary direction).
[`docs/TEST_RESULTS.md`](docs/TEST_RESULTS.md) explains each line.

### E3: benchmark (claim C3)

About 10 compute minutes; runs on the host, not inside the container.
`bash bench/run_device.sh` does all of this in one command; the individual steps are:

```bash
docker build -t zkep .
bash bench/run_benchmark.sh my-laptop --plan   # preflight and dry run, measures nothing
bash bench/run_benchmark.sh my-laptop          # 1 warm-up + 5 measured runs per stage
node bench/print_summary.js results/bench/my-laptop_<UTC>
```

Compare the printed medians with the table in
[`docs/BENCHMARK_RESULTS.md`](docs/BENCHMARK_RESULTS.md). Absolute times depend
on the hardware; circuit sizes, proof sizes and verification-key sizes must
match exactly. See [`bench/README.md`](bench/README.md).

### E4: ARM64 boards (claim C4)

The same command on the board (64-bit OS):

```bash
sudo bash bench/run_device.sh --install-docker --add-swap --max-performance
```

`--max-performance` locks the clocks (`jetson_clocks` on Jetson, the CPU
governor elsewhere) and restores them at the end. Use active cooling on a
Raspberry Pi 5: without it the board throttles, as in the published run.

---

## Protocol in brief

```text
C  = H1(prescription_id, doctor_id, medicine_code, expiry, threshold)   commitment, public
N  = H3(patient_secret, C, slot_index)                                  nullifier, public
L  = H4(doctor_id, PKx, PKy),  M = H5(left, right)                      doctor registry (Merkle)
c  = Hraw(Rx, Ry, PKx, PKy, C);  s*B8 = R + 8*c*PK,  s < l             Schnorr on Baby Jubjub
current_date <= expiry,  slot_index < threshold                         policy (date set by the verifier)
I  = H2(patient_secret),  PB = H6(I, C)                                 issuance side, not in redemption
```

Poseidon2 over the BN254 scalar field (t = 4, rate 3, x^5, 8 + 56 + 8 rounds);
`H1`–`H6` prepend domain tags 1–6. Public inputs: registry root and
`current_date`; public outputs: `C` and `N`. Everything else is private.

## Scope and non-claims

- National or health-ID authentication happens at enrollment, outside the
  circuit; the redemption proof is not a fresh identity check.
- The circuit only derives `N`; single-use redemption needs the redemption
  service to store accepted nullifiers.
- `C` and `N` are public, so redemptions of one prescription are linkable. No
  anonymity, unlinkability or collusion-resistance claim is made; see
  [`docs/threat_model.md`](docs/threat_model.md). There is no formal security proof.
- The Groth16 setup in the tests and the benchmark is a local single-contributor
  development ceremony, not a production trusted setup. All keys are test keys.
- Circuit sizes are backend-native units (R1CS constraints, ACIR opcodes,
  Barretenberg gates) and are not comparable with each other.

## Repository map

```text
circom/circuits/     redemption.circom (entry), issuance_binding.circom,
                     lib_modules, registry, schnorr_bjj, poseidon2(+constants), kat/ harnesses
circom/inputs/       TV-001..005 and NT-001..020 vectors, Schnorr unit vectors
circom/scripts/      build_canonical_fixture.js (generates every vector), lib/ JS reference
noir/common/         Poseidon2 sponge and H1-H6 (the only Poseidon2 source in Noir)
noir/redemption/     redemption circuit (entry), tests/positive, tests/negative
noir/issuance_binding/, noir/kat/, noir/registry_generator/
scripts/             run.sh (container entry point), test.sh, demo.sh, suites, kat/
bench/               run_device.sh (one-command run), benchmark harness v1.4.2
docs/                specification, threat model, architecture, toolchain, results
testdata/kat/        canonical fixture and KAT reference vectors
testdata/historical/ pre-alignment vectors, kept for provenance only
```

[`docs/architecture.md`](docs/architecture.md) describes every file and how the
vectors are generated.

## License

To be added.
