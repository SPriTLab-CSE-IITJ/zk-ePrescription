# Architecture and code map

Both backends implement the redemption statement of
[`protocol_specification.md`](protocol_specification.md) (Section 16). Every
test vector for both backends comes from one generator, so the two
implementations are always checked against the same values.

## Circom / Groth16 (`circom/`)

| File | Content |
|---|---|
| `circuits/redemption.circom` | Redemption circuit: commitment, policy, registry, signature, nullifier. Public signals in snarkjs order: `[C, N, current_date, root]`. Instantiated with `DEPTH = 2` for the four-doctor fixture. |
| `circuits/lib_modules.circom` | `Commitment` (H1), `IdentityBinding` (H2), `Nullifier` (H3), 64-bit range-checked `ThresholdCheck` and `ExpiryCheck` |
| `circuits/registry.circom` | `DoctorRegistry(DEPTH)`: leaf `H4(doctor_id, PKx, PKy)` computed in-circuit, `H5` Merkle path, binary direction bits |
| `circuits/schnorr_bjj.circom` | `SchnorrBJJ`: `c = Hraw(Rx, Ry, PKx, PKy, C)`, `s*B8 = R + c*(8*PK)`, PK and R on curve, `8*PK != O`, `s < l`, full 254-bit `c` |
| `circuits/poseidon2.circom` | Poseidon2 permutation (t = 4, 8 + 56 rounds, x^5), sponge `Hraw`, tagged `H1`–`H6` |
| `circuits/poseidon2_constants.circom` | Round constants and internal diagonal, generated (see below) |
| `circuits/issuance_binding.circom` | Issuance side: `I = H2(patient_secret)`, `PB = H6(I, C)`; not part of redemption |
| `circuits/kat/` | Test harnesses (`kat_hashes`, `schnorr_unit`), not protocol circuits |
| `scripts/build_canonical_fixture.js` | The single source of every vector (below) |
| `scripts/lib/poseidon2.js`, `schnorr_bjj.js` | Off-circuit JavaScript reference for Poseidon2/H1–H6 and the signature relation |

## Noir / UltraHonk (`noir/`)

| Package | Content |
|---|---|
| `common/` | Poseidon2 sponge and `H1`–`H6` on `std::hash::poseidon2_permutation`; the only Poseidon2 source in Noir |
| `redemption/` | Redemption circuit. `src/main.nr` calls `commitment.nr`, `policy.nr`, `registry.nr`, `schnorr.nr` (with `bjj_core.nr`), `outputs.nr`; public inputs `registry_root`, `current_date`; returns `[C, N]`. `tests/positive`, `tests/negative` hold the vectors; `src/fixture_tests.nr` holds the 8 Schnorr unit tests. |
| `issuance_binding/` | Issuance-side `PB = H6(H2(patient_secret), C)` |
| `kat/` | Cross-backend KAT harness, not a protocol circuit |
| `registry_generator/` | Rebuilds the four-doctor registry (leaves, paths, root) in Noir for the KAT |

Invalid conditions (bad signature, key not in the registry, expired
prescription, slot >= threshold, changed prescription fields, off-curve points,
out-of-range scalar) are hard constraint failures: no proof can be generated.

## Vectors: one generator for both backends

`node circom/scripts/build_canonical_fixture.js` builds the four-doctor
registry (test keys `sk*Generator`, sk = 123–126), signs the canonical
commitment with deterministic test nonces, verifies every signature
off-circuit, and writes:

- `testdata/kat/canonical_fixture.json` (expected public outputs of every vector);
- `circom/inputs/eprescription/canonical/TV-*.json`, `NT-*.json` and `circom/inputs/unit/schnorr_canonical/`;
- `noir/redemption/tests/{positive,negative}/*.toml`, `noir/redemption/Prover.toml`, `noir/redemption/src/fixture_tests.nr`;
- `noir/issuance_binding/Prover.toml`, `noir/registry_generator/Prover.toml`, `circom/inputs/eprescription/patient_binding_issuance.json`.

Re-running it reproduces every committed vector byte for byte.

## Poseidon2 constants

`circom/circuits/poseidon2_constants.circom` is generated from
`circom/scripts/lib/poseidon2_constants.json`, extracted verbatim from
`noir-lang/noir` tag `v1.0.0-beta.24`,
`acvm-repo/bn254_blackbox_solver/src/poseidon2_constants.rs` (the solver
behind `std::hash::poseidon2_permutation`):

```bash
python3 circom/scripts/lib/extract_poseidon2_constants.py poseidon2_constants.rs > circom/scripts/lib/poseidon2_constants.json
node circom/scripts/lib/gen_poseidon2_constants_circom.js > circom/circuits/poseidon2_constants.circom
```

## Test scripts

| Script | Runs |
|---|---|
| `scripts/run.sh` | Container entry point: `demo`, `test`, `kat`, `help`; any other command is executed as given |
| `scripts/test.sh` | `circom_suite.sh`, `noir_suite.sh`, the attack table, the KAT; writes `results/summary.txt` |
| `scripts/circom_suite.sh` | Compile, TV witnesses and outputs, NT rejections, Schnorr vectors, local Groth16 setup, prove and verify, tampered public signals |
| `scripts/noir_suite.sh` | Library and Schnorr tests, compile, TV execution and outputs, `bb` prove and verify, tampered public inputs, NT rejections, issuance binding |
| `scripts/kat/run_cross_backend_kat.sh` | JS reference vs Circom vs Noir for 6 input sets, the registry generator and the issuance circuits |
| `scripts/demo.sh` | TV-001 end to end in both backends, one attack, one replay |
| `bench/run_device.sh` | One-command benchmark of the current machine: platform record, image build, regression, harness, summary, packed result |
| `bench/run_benchmark.sh` | Benchmark harness v1.4.2 (host side) |

## History

Development phases that preceded the aligned protocol (standalone Circom unit
circuits using circomlib Poseidon, Noir `phase2_policy`, `phase3_registry`,
`components/`, depth-4 Merkle tooling) are not part of this branch. They are
preserved at the git tag `legacy/pre-restructure`. Pre-alignment test vectors
cited by the provenance records are kept in `testdata/historical/`.
