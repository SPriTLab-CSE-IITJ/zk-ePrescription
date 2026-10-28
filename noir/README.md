# Noir / UltraHonk implementation

Noir 1.0.0-beta.24 + Barretenberg 5.0.0-nightly.20260522 (UltraHonk, BN254)
implementation of the protocol in
[`../docs/protocol_specification.md`](../docs/protocol_specification.md).
It implements the same relation as the Circom implementation and produces the
same protocol values (checked by the cross-backend KATs).

Research prototype — not a production system.

## Packages used by the aligned protocol

### `common/`
Canonical Poseidon2 sponge over `std::hash::poseidon2_permutation`
(initial capacity `n·2⁶⁴`, rate 3) and the domain-tagged wrappers
`H1`–`H6` (`commitment_hash`, `identity_hash`, `nullifier_hash`,
`registry_leaf_hash`, `merkle_node_hash`, `patient_binding_hash`) plus the
untagged `poseidon2_hash_raw` used for the signature challenge.

### `phase4_orchestrator/`
Integrated Phase-4 redemption circuit:

* commitment `C = H1(prescription_id, doctor_id, medicine_code, expiry, threshold)`;
* policy `slot_index < quantity_threshold`, `current_date ≤ expiry_date` (u64);
* registry membership of `H4(doctor_id, PKx, PKy)` via a generic
  `verify_registry::<DEPTH>` (binary-constrained direction bits; `DEPTH = 2`
  for the four-doctor fixture);
* BabyJubJub Schnorr `s·B8 = R + 8·c·PK`, `c = Hraw(Rx, Ry, PKx, PKy, C)`,
  with on-curve checks, `8·PK ≠ O` and `s < l`;
* outputs `[C, N]` with `N = H3(patient_secret, C, slot_index)`.

Public inputs: `registry_root`, `current_date`. Return value (public): `[C, N]`.

Tests:

```bash
cd phase4_orchestrator
nargo test                               # isolated signature-verifier tests (src/fixture_tests.nr)
cd tests/scripts
./run_positive_suite.sh                  # TV-001..TV-005: execute, output check, bb prove/verify, tampered inputs
./run_negative_suite.sh                  # NT-001..NT-020: each must fail a circuit constraint
```

`tests/historical/pre_alignment_depth4/` holds the pre-alignment vectors,
kept byte-identical and not executed.

### `patient_binding_issuance/`
Issuance-side construction `I = H2(patient_secret)`, `PB = H6(I, C)`.
It is not part of the Phase-4 redemption statement.

### `cross_backend_kat/`
Test harness exposing the permutation, the sponge and H1–H6 for the
cross-backend known-answer tests (`../scripts/kat/`). Not a protocol circuit.

## Earlier development phases (historical)

`components/commitment_nullifier/phase1_core/`, `phase2_policy/` and
`phase3_registry/` are earlier, standalone development stages with their own
copies of the sponge. They are **not** the aligned protocol (e.g. the
`phase3_registry` commitment orders `threshold` before `expiry` and its
fixture uses placeholder keys). They are kept for reference only.

`phase3_registry/tools/registry_generator/` is still used: the cross-backend
KATs run it on the canonical four-doctor registry to check every leaf, path
and the root against the fixture.
