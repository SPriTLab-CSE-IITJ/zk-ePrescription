# zk-ePrescription

**Privacy-preserving electronic-prescription redemption with zero-knowledge proofs — one protocol, two independent proving stacks.**

This repository is a research artifact. It implements a single, normatively
specified prescription-redemption protocol twice:

| Backend | Circuit language | Proving system | Location |
|---|---|---|---|
| A | Circom 2.2.3 | Groth16 (snarkjs 0.7.6), BN254 | `circom/` |
| B | Noir 1.0.0-beta.24 | UltraHonk (Barretenberg 5.0.0-nightly.20260522), BN254 | `noir/` |

Both implementations follow the same specification
([`docs/protocol_specification.md`](docs/protocol_specification.md)) and use the
**same canonical Poseidon2 construction and domain separation**. For identical
inputs they produce identical protocol values; this is checked by cross-backend
known-answer tests (107/107 values equal) on every regression run.

It is **not** a production healthcare system.

---

## Protocol

```text
Protocol (Phase-4 redemption statement)
 ├─ Commitment                    C  = H1(prescription_id, doctor_id, medicine_code, expiry, threshold)
 ├─ Identity commitment           I  = H2(patient_secret)                 (issuance side)
 ├─ Patient-prescription binding  PB = H6(I, C)                           (issuance side)
 ├─ Nullifier                     N  = H3(patient_secret, C, slot_index)
 ├─ Doctor registry Merkle proof  L  = H4(doctor_id, PKx, PKy),  M = H5(left, right)
 ├─ BabyJubJub Schnorr            c  = Hraw(Rx, Ry, PKx, PKy, C);  s·B8 = R + 8·c·PK,  s < l
 └─ Expiry / threshold policy     current_date ≤ expiry,  slot_index < threshold
```

* **Hash.** Poseidon2 over the BN254 scalar field, t = 4, rate 3, x⁵ S-box,
  8 full + 56 partial rounds (the parameters of Noir's
  `std::hash::poseidon2_permutation`). Sponge with initial capacity
  `n · 2⁶⁴` (n = number of absorbed elements). `H1`–`H6` prepend domain tags
  1–6; `Hraw` (signature challenge) has no tag.
* **Registry/signature binding.** The registry leaf is computed inside the
  circuit from the same `doctor_id` and public key used for signature
  verification; a prover cannot combine one doctor's registry entry with
  another key's signature.
* **Public values.** Registry root and `current_date` (verifier-supplied) are
  public inputs; `C` and `N` are the public outputs. The patient secret and the
  prescription fields remain private witness values. `I = H2(patient_secret)`
  is **not** exposed by the redemption proof.
* **Registry depth** is a parameter of the generic verifier. The canonical
  experimental fixture uses four doctors, i.e. depth 2.

### Identity boundary

National / health-ID authentication happens **outside** the zero-knowledge
circuit, in an external enrolment system. The raw identifier never enters a
circuit. Enrolment provisions a protocol-specific patient secret; the
issuance-side binding `PB = H6(I, C)` associates that credential with a
prescription. The Phase-4 redemption proof does **not** perform fresh
national-ID authentication and does not verify `PB`.

### Replay handling

The circuit only **derives** the nullifier `N`. Single-use redemption requires
the external redemption service to store accepted nullifiers and reject
repeats. That service is outside this artifact.

---

## What the proof establishes — and what it does not

A valid Phase-4 proof establishes, under the usual assumptions on Poseidon2,
BabyJubJub Schnorr and the proving system, that the prover knows a witness
such that: the commitment is correctly computed; the policy holds for the
verifier-supplied date; the doctor identifier and key are in the registry; the
same key signed the commitment; and `N` is correctly derived from the private
patient secret, `C` and the slot.

This artifact makes **no** claims of anonymity, universal unlinkability,
collusion resistance, accountability/notification, or replay prevention by the
circuit alone. Commitments and nullifiers are public values and can be linked
when reused; application metadata may add linkability. There is no formal
security proof; [`docs/threat_model.md`](docs/threat_model.md) states the
intended properties and their assumptions.

---

## Reproducing the results

All toolchains are pinned in the [`Dockerfile`](Dockerfile).

```bash
docker build -t zkep:aligned .
docker run --rm zkep:aligned          # runs npm test -> scripts/test_all.sh
```

`scripts/test_all.sh` runs, in order:

1. **Circom / Groth16** (`circom/scripts/test_e2e.sh`): compile; 5 positive
   witnesses with public outputs checked against the canonical fixture;
   20 negative vectors (each must be rejected by a circuit assertion);
   8 isolated Schnorr vectors; local Groth16 setup; prove + verify for every
   positive vector; tampered public signals must fail verification.
2. **Noir / UltraHonk**: library and signature unit tests; positive suite
   (`nargo execute` with output check, `bb prove`, `bb verify`, tampered public
   inputs must fail); negative suite (20 vectors).
3. **Issuance-side patient binding** (Noir).
4. **Cross-backend KATs** (`scripts/kat/`): JS reference vs Circom witness vs
   Noir execution for the raw permutation (also against independent reference
   vectors), the sponge for 1–7 inputs, H1–H6, every registry leaf/node/root and
   authentication path, and the patient-binding circuits.

The Groth16 setup performed by the tests is a **local, single-contributor
development ceremony with fixed entropy**. It is not a production trusted setup.
All doctor keys in the fixtures are **test keys**.

### Canonical fixture

`prescription_id = 1001`, `doctor_id = 5001`, `medicine_code = 123`,
`patient_secret = 12345`, `expiry = 20261231`, `threshold = 3`,
`current_date = 20260630`; four registered doctors (5001–5004, test keys
`sk·Generator` with sk = 123–126).

| Value | |
|---|---|
| C | `0x2206c4274f31bb0a0545087c6da9b5e5f81932fbc8617bc1e596e1c04bc85e6b` |
| N (slot 0) | `0x13ffd498a119ba5754cfb86eb5122304b06afa08bb92751c13b2e86056b02bf8` |
| registry root | `0x16544d921c21aecda90ca6d6980706e4657c05de9f45b55a07ead664253bbc08` |

All vectors for both backends are generated from one source of truth:
`circom/scripts/build_canonical_fixture.js` →
`testdata/kat/canonical_fixture.json`.

### Structural size of the aligned circuits

Backend-native units — **not comparable with each other**:

| Metric | Value |
|---|---|
| Circom R1CS constraints | 12,291 (10,883 non-linear + 1,408 linear) |
| Noir ACIR opcodes | 16,681 |
| Barretenberg UltraHonk gates | 22,182 |

Performance measurements were produced by a separate benchmark harness; see
[docs/BENCHMARK_RESULTS.md](docs/BENCHMARK_RESULTS.md). Earlier benchmark tables in older revisions of this repository refer
to an obsolete circuit and must not be used.

## Reproducibility Results

- [Regression test results](docs/TEST_RESULTS.md)
- [Laptop benchmark results](docs/BENCHMARK_RESULTS.md)

The benchmark table summarizes the already validated laptop benchmark of the frozen aligned implementation; the raw measurements, metadata, validation output and artifact hashes remain available in the benchmark result directory.

---

## Repository layout

```text
circom/
  circuits/
    poseidon2.circom, poseidon2_constants.circom   canonical Poseidon2 (constants generated from Noir's solver)
    lib_modules.circom                             commitment, nullifier, u64 policy checks
    05_doctor_registry_merkle_lib.circom           H4 leaf + H5 Merkle path (generic DEPTH)
    06_schnorr_bjj.circom                          Schnorr verifier (same relation as Noir)
    08_eprescription_main.circom                   integrated Phase-4 circuit (DEPTH = 2 fixture)
    09_patient_binding_issuance.circom             issuance-side I and PB
    kat/                                           test harnesses (not protocol circuits)
    01_–05_merkle_parameterized, 04_threshold      historical standalone unit circuits (see circom/README.md)
  inputs/eprescription/canonical/                  aligned positive (TV-*) and negative (NT-*) vectors
  inputs/eprescription/historical/                 pre-alignment vectors, kept unchanged
  inputs/unit/schnorr_canonical/                   isolated signature vectors
  scripts/                                         fixture generator, JS reference (scripts/lib), e2e test
noir/
  common/                                          canonical Poseidon2 sponge + H1–H6
  phase4_orchestrator/                             integrated Phase-4 circuit, tests/{positive,negative}
  phase4_orchestrator/tests/historical/pre_alignment_depth4/   pre-alignment vectors, kept unchanged
  patient_binding_issuance/                        issuance-side I and PB
  cross_backend_kat/                               KAT harness (not a protocol circuit)
  phase2_policy/, phase3_registry/, components/    earlier development phases (see noir/README.md)
docs/
  protocol_specification.md                        normative specification
  threat_model.md, architecture.md, toolchain.md
scripts/
  test_all.sh                                      full regression (Docker entry point)
  kat/                                             cross-backend KAT driver
testdata/kat/                                      canonical fixture, KAT results, reference vectors
paper/                                             paper draft (see note in paper/paper.md)
Dockerfile, package.json
```

---

## Status

* Protocol and both implementations: aligned and frozen; full regression and
  cross-backend KATs pass.
* Paper: the draft in `paper/` predates the alignment and is being rewritten.
* Research prototype — not audited, not for clinical use.
