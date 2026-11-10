# Regression Test Results

Summary of the full regression of protocol v3 (`docker run --rm zkep test`,
which runs `scripts/test.sh`). Final line of the run:
`RESULT: ALL REGRESSION TESTS PASSED`. Protocol v3 adds the medication-list
digest D as a public output (docs/protocol_specification.md, Section 6.1) and
the pharmacy-view checks. The vectors and results of protocol v2 (24 attack
vectors, outputs `[C, N]`) are kept in `testdata/historical/v2/`, those of
protocol v1 (commit `f257cad`, 20 attack vectors, 107/107 cross-backend
values) in `testdata/historical/v1/`.

| Suite | Result |
|---|---:|
| Circom positive witnesses | 5/5 PASS |
| Circom negative witnesses | 25/25 REJECTED |
| Isolated Schnorr vectors | 8/8 PASS |
| Groth16 proof verification | 5/5 PASS |
| Groth16 tampered-public-signal rejection | 5/5 REJECTED |
| Circom public values (root, date, C, N, D only) | 5/5 PASS |
| Pharmacy view on a Groth16 proof | 8/8 as expected |
| Noir common tests | 7/7 PASS |
| Noir Schnorr tests | 8/8 PASS |
| Noir positive proofs | 5/5 PASS |
| Noir negative tests | 25/25 REJECTED (24 by a constraint, NT-024 by the u64 input type) |
| Noir public values (root, date, C, N, D only) | 5/5 PASS |
| Noir tampered-public-input rejection | 25/25 REJECTED (5 per proof × 5 proofs) |
| Pharmacy view on an UltraHonk proof | 8/8 as expected |
| Nullifier store, Circom outputs | 6/6 steps as expected |
| Nullifier store, Noir outputs | 6/6 steps as expected |
| Same C, N and D in both backends | 5/5 vectors |
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
| Prescription | digest of another medication list (NT-005), modified prescription ID, expiry, threshold |
| Policy | expired prescription, slot_index >= threshold |
| Patient binding (v2) | valid issuance record redeemed under a different patient secret, for slot 0 (NT-021) and for the last slot (NT-022) |
| Version mix-up | the doctor's valid v1 signature (commitment without I) used for the v2 commitment (NT-023); the doctor's valid v2 signature (single medicine code instead of the list digest D) used for v3 (NT-025) |
| Input range | refill slot 2^64, outside u64 (NT-024) |

NT-021 and NT-022 were accepted by the v1 circuits, each time with a fresh
nullifier; in v2 the commitment computed from the other secret is not the one
the doctor signed, and both backends reject them at the signature check.
NT-023 reuses the doctor's real v1 signature (checked against
`testdata/historical/v1/kat/canonical_fixture.json`); it fails the signature
check because the v2 commitment contains `I`. NT-024 is rejected by the 64-bit
range check in Circom; in Noir a value outside `u64` cannot even be passed to
the `u64` parameter, so `nargo` rejects it while decoding the input. NT-025
reuses the doctor's real v2 signature (checked against
`testdata/historical/v2/kat/canonical_fixture.json`); it fails the signature
check because the v3 commitment contains D instead of the medicine code.

## Pharmacy view (protocol v3)

`scripts/lib/pharmacy_cases.js` runs `scripts/pharmacy_verify.js` on the real
TV-001 proof of each backend, with the pharmacy's own root and date:

| Case | Expected |
|---|---|
| the doctor-signed medication list | ACCEPT, list shown (`results/pharmacy_view_<backend>.txt`) |
| one quantity raised (20 -> 40) | REJECT: digest differs from D |
| one medicine swapped for another | REJECT: digest differs from D |
| an extra medicine added | REJECT: digest differs from D |
| one medicine left out | REJECT: digest differs from D |
| an altered list with its own digest put into the public values | REJECT: proof does not verify |
| the pharmacy's date is the next day | REJECT: date is not the pharmacy's |
| the pharmacy's registry root differs | REJECT: root is not the pharmacy's |

## Public values

`scripts/lib/public_values_check.js` checks every valid redemption: Circom has
exactly 2 public inputs (date, root) and 3 outputs (C, N, D), Noir's ABI has
exactly the public parameters `registry_root` and `current_date` and returns
`[C, N, D]`, and neither the patient reference `I` nor `patient_secret` appears
among the public values.

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
`results/logs/` (`circom.log`, `noir.log`, `kat.log`, `nullifier_store.log`,
`pharmacy_circom.log`, `pharmacy_noir.log`).

The attack table names the check that rejected each vector in each backend:

| Name in the table | Circom location | Noir location |
|---|---|---|
| signature | `SchnorrBJJ`, signature equation | `src/main.nr:123` |
| s < l bound | `SchnorrBJJ`, scalar bound | `src/schnorr.nr:21` |
| registry | `DoctorRegistry`, root mismatch | `src/main.nr:122` |
| binary direction | `DoctorRegistry`, direction bit | `src/registry.nr:7` |
| expiry / slot < threshold | `EPrescriptionMain`, policy checks | `src/main.nr:121` / `:120` |
| point on curve / PK on curve / R on curve | `BabyCheck` | `src/schnorr.nr:19` / `:20` |

The two backends can name different checks for the same vector when it breaks
more than one condition. NT-018 (off-curve public key) is an example: Circom
evaluates the registry leaf first and fails there, Noir checks the curve
first. Both reject it; the isolated Schnorr vector `SIG-OFFCURVE-PK` exercises
the Circom curve check directly.
