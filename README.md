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

---

## Major claims

| Claim | Statement | Evidence |
|---|---|---|
| **C1** Equivalence | Both backends compute identical protocol values (Poseidon2 permutation and sponge, C, I, N, registry leaves, nodes and root, PB) for identical inputs. | E1: 107/107 equal |
| **C2** Soundness checks | Valid redemptions verify in both backends; every attack vector (20) is rejected by a circuit constraint, and tampered public inputs do not verify. | E2: summary table |
| **C3** x86-64 performance | Per-redemption cost of both stacks on two x86-64 machines (a laptop and a desktop), as reported in [`docs/BENCHMARK_RESULTS.md`](docs/BENCHMARK_RESULTS.md). | E3 |
| **C4** Raspberry Pi 5 | Native ARM64 results. | E4, pending |

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

### E3: x86-64 benchmark (claim C3)

About 10 compute minutes; runs on the host, not inside the container.

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

### E4: Raspberry Pi 5 (claim C4)

Pending: same harness, native ARM64 build.

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
bench/               benchmark harness v1.4.2
docs/                specification, threat model, architecture, toolchain, results
testdata/kat/        canonical fixture and KAT reference vectors
testdata/historical/ pre-alignment vectors, kept for provenance only
```

[`docs/architecture.md`](docs/architecture.md) describes every file and how the
vectors are generated.

## License

To be added.
