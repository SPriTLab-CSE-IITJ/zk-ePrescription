# Phase 4: Orchestrator

## Purpose

The Phase 4 orchestrator is the integrated redemption circuit of the Noir
implementation. It enforces every condition of the Phase-4 redemption
statement (`docs/protocol_specification.md`, Section 16); if any condition
fails, no witness exists and no proof can be produced.

## Modules

`commitment`, `policy`, `registry`, `schnorr`, `outputs`, `bjj_core`, and the
test-only module `fixture_tests`.

## Processing flow

1. **Commitment** — `C = H1(prescription_id, doctor_id, medicine_code, expiry_date, quantity_threshold)`.
2. **Policy** — `slot_index < quantity_threshold` and
   `current_date ≤ expiry_date`; `current_date` is a public, verifier-supplied input.
3. **Registry** — leaf `H4(doctor_id, PKx, PKy)` is computed in-circuit and
   proven to be under `registry_root` with `verify_registry::<DEPTH>`
   (`DEPTH = 2` for the four-doctor fixture).
4. **Schnorr** — the same `(PKx, PKy)` must verify the signature over `C`:
   `s·B8 = R + 8·c·PK`, `c = Hraw(Rx, Ry, PKx, PKy, C)`, `s < l`.
5. **Outputs** — `[C, N]` with `N = H3(patient_secret, C, slot_index)`.

Public inputs: `registry_root`, `current_date`. Public outputs: `[C, N]`.
