# Regression Test Results

Summary of the full regression of protocol v2 (`docker run --rm zkep test`,
which runs `scripts/test.sh`). Final line of the run:
`RESULT: ALL REGRESSION TESTS PASSED`. The results of protocol v1 (commit
`f257cad`, 20 attack vectors, 107/107 cross-backend values) are kept in
`testdata/historical/v1/`.

| Suite | Result |
|---|---:|
| Circom positive witnesses | 5/5 PASS |
| Circom negative witnesses | 22/22 REJECTED |
| Isolated Schnorr vectors | 8/8 PASS |
| Groth16 proof verification | 5/5 PASS |
| Groth16 tampered-public-signal rejection | 4/4 REJECTED |
| Noir common tests | 7/7 PASS |
| Noir Schnorr tests | 8/8 PASS |
| Noir positive proofs | 5/5 PASS |
| Noir negative tests | 22/22 REJECTED |
| Noir tampered-public-input rejection | 20/20 REJECTED (4 per proof × 5 proofs) |
| Nullifier store, Circom outputs | 6/6 steps as expected |
| Nullifier store, Noir outputs | 6/6 steps as expected |
| Same C and N in both backends | 5/5 vectors |
| Cross-backend canonical | 16/16 equal |
| Cross-backend doctor1 | 16/16 equal |
| Cross-backend doctor2 | 16/16 equal |
| Cross-backend doctor3 | 16/16 equal |
| Cross-backend edge | 16/16 equal |
| Cross-backend zero | 16/16 equal |
| Registry generator | 4/4 equal |
| TOTAL cross-backend | 100/100 equal |

"Isolated Schnorr vectors 8/8 PASS" means the one valid signature was accepted
and all seven invalid ones were rejected.

## What the negative tests cover

| Test category | Examples |
|---|---|
| Signature | invalid s, s+l, wrong PK, wrong commitment, off-curve R/PK |
| Registry | modified path, wrong doctor, wrong key, wrong root, invalid direction |
| Prescription | modified medicine, prescription ID, expiry, threshold |
| Policy | expired prescription, slot_index >= threshold |
| Patient binding (v2) | valid issuance record redeemed under a different patient secret, for slot 0 (NT-021) and for the last slot (NT-022) |

NT-021 and NT-022 were accepted by the v1 circuits, each time with a fresh
nullifier; in v2 the commitment computed from the other secret is not the one
the doctor signed, and both backends reject them at the signature check.

## Nullifier store

`scripts/lib/nullifier_store.js` replays the scenario in
`testdata/kat/canonical_fixture.json` (`nullifier_store_scenario`) against an
in-memory redemption service, once with the outputs of each backend: slots 0, 1
and 2 are accepted; slot 0 presented again on the expiry date (TV-004, same
nullifier) and a second presentation of TV-001 are rejected; a prescription
from another doctor (TV-005) is accepted.

Each negative vector is a single attempt that must fail. A test passes only if
witness generation (Circom) or execution (Noir) is rejected by a circuit
constraint, not by a tool or input error.

## Reading the output

The screen shows one line per check; the full output of every tool is in
`results/logs/` (`circom.log`, `noir.log`, `kat.log`, `nullifier_store.log`).

The attack table names the check that rejected each vector in each backend:

| Name in the table | Circom location | Noir location |
|---|---|---|
| signature | `SchnorrBJJ`, signature equation | `src/main.nr:125` |
| s < l bound | `SchnorrBJJ`, scalar bound | `src/schnorr.nr:21` |
| registry | `DoctorRegistry`, root mismatch | `src/main.nr:124` |
| binary direction | `DoctorRegistry`, direction bit | `src/registry.nr:7` |
| expiry / slot < threshold | `EPrescriptionMain`, policy checks | `src/main.nr:123` / `:122` |
| point on curve / PK on curve / R on curve | `BabyCheck` | `src/schnorr.nr:19` / `:20` |

The two backends can name different checks for the same vector when it breaks
more than one condition. NT-018 (off-curve public key) is an example: Circom
evaluates the registry leaf first and fails there, Noir checks the curve
first. Both reject it; the isolated Schnorr vector `SIG-OFFCURVE-PK` exercises
the Circom curve check directly.
