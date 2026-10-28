# Circom / Groth16 implementation

Circom 2.2.3 + snarkjs 0.7.6 (Groth16, BN254) implementation of the protocol in
[`../docs/protocol_specification.md`](../docs/protocol_specification.md).
It implements the same relation as the Noir implementation and produces the
same protocol values (checked by the cross-backend KATs).

Research prototype — not a production system.

## Protocol circuits

| File | Content |
|---|---|
| `circuits/poseidon2.circom` | Poseidon2 permutation (t = 4, 8 + 56 rounds, x⁵), project sponge (`Hraw`), domain-tagged `H1`–`H6` |
| `circuits/poseidon2_constants.circom` | Round constants and internal diagonal — **generated**, see below |
| `circuits/lib_modules.circom` | `Commitment` (H1), `IdentityBinding` (H2), `Nullifier` (H3), u64 range-checked `ThresholdCheck` and `ExpiryCheck` |
| `circuits/05_doctor_registry_merkle_lib.circom` | `DoctorRegistry(DEPTH)`: leaf `H4(doctor_id, PKx, PKy)` computed in-circuit, `H5` Merkle path, binary direction bits |
| `circuits/06_schnorr_bjj.circom` | `SchnorrBJJ`: `c = Hraw(Rx, Ry, PKx, PKy, C)`, `s·B8 = R + c·(8·PK)`, PK/R on curve, `8·PK ≠ O`, `s < l`, full 254-bit `c` |
| `circuits/08_eprescription_main.circom` | Integrated Phase-4 redemption circuit, instantiated with `DEPTH = 2` for the four-doctor fixture |
| `circuits/09_patient_binding_issuance.circom` | Issuance side: `I = H2(patient_secret)`, `PB = H6(I, C)` (not part of redemption) |

Phase-4 public signals, in snarkjs order:
`[commitment_out, nullifier_out, current_date, root]`.
Private: prescription fields, patient secret, slot index, Merkle path, public
key and signature.

### Poseidon2 constants

`circuits/poseidon2_constants.circom` is generated from
`scripts/lib/poseidon2_constants.json`, which is extracted verbatim from
`noir-lang/noir` tag `v1.0.0-beta.24`,
`acvm-repo/bn254_blackbox_solver/src/poseidon2_constants.rs`
(the solver behind `std::hash::poseidon2_permutation`):

```bash
python3 scripts/lib/extract_poseidon2_constants.py poseidon2_constants.rs > scripts/lib/poseidon2_constants.json
node scripts/lib/gen_poseidon2_constants_circom.js > circuits/poseidon2_constants.circom
```

The permutation is checked against independent reference vectors and against
Noir on every regression run.

## Fixtures and scripts

| Path | Purpose |
|---|---|
| `scripts/build_canonical_fixture.js` | Single source of truth: builds the four-doctor registry (test keys `sk·Generator`, sk = 123–126), signs the canonical commitment, verifies every signature off-circuit, and writes all Circom and Noir vectors plus `testdata/kat/canonical_fixture.json` |
| `scripts/lib/poseidon2.js` | Off-circuit reference implementation of Poseidon2 / H1–H6 |
| `scripts/lib/schnorr_bjj.js` | Off-circuit signer/verifier for the protocol relation (fixture use only; deterministic test nonces) |
| `scripts/test_e2e.sh` | Circom regression (run by `npm test`) |
| `inputs/eprescription/canonical/` | `TV-001`…`TV-005` positive, `NT-001`…`NT-020` negative vectors |
| `inputs/unit/schnorr_canonical/` | Isolated signature-verifier vectors |
| `circuits/kat/` | Test harnesses (`kat_hashes`, `schnorr_unit`) — not protocol circuits |

`test_e2e.sh` compiles the Phase-4 circuit, checks every positive witness and
its public outputs against the fixture, requires every negative vector to be
rejected by a circuit assertion, runs the isolated Schnorr vectors, performs a
**local single-contributor development** Groth16 setup (fixed entropy; not a
production ceremony), proves and verifies every positive vector, and checks
that tampered public signals do not verify.

## Historical material (not used by the aligned protocol)

These files predate the protocol alignment and use circomlib Poseidon v1
without domain separation. They are kept for reference only; no current test
or fixture depends on them:

* standalone unit circuits `01_commitment`, `02_identity_binding`,
  `03_nullifier`, `04_threshold`, `05_merkle_parameterized`;
* `inputs/merkle/`, `inputs/unit/{commitment,identity,nullifier,threshold,schnorr_bjj}.json`;
* scripts `build_registry.js`, `make_merkle_input.js`,
  `make_merkle_depth2_all_inputs.js`, `merkle_tree.js`, `test_merkle_tree.js`,
  `test_merkle_tree_16.js`, `test_schnorr_bjj.js`;
* `inputs/eprescription/historical/` — the pre-alignment depth-4 integrated
  vectors, kept byte-identical.
