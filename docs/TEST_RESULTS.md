# Regression Test Results

Summary of the successful full regression (`docker run --rm <image>` →
`npm test` → `scripts/test_all.sh`) on the frozen aligned implementation.
Final line of the run: `ALL REGRESSION TESTS PASSED`.

| Suite | Result |
|---|---:|
| Circom positive witnesses | 5/5 PASS |
| Circom negative witnesses | 20/20 REJECTED |
| Isolated Schnorr vectors | 8/8 PASS |
| Groth16 proof verification | 5/5 PASS |
| Groth16 tampered-public-signal rejection | 4/4 REJECTED |
| Noir common tests | 6/6 PASS |
| Noir Schnorr tests | 8/8 PASS |
| Noir positive proofs | 5/5 PASS |
| Noir negative tests | 20/20 REJECTED |
| Noir tampered-public-input rejection | 20/20 REJECTED (4 per proof × 5 proofs) |
| Patient binding | 4/4 PASS |
| Cross-backend canonical | 17/17 equal |
| Cross-backend doctor1 | 17/17 equal |
| Cross-backend doctor2 | 17/17 equal |
| Cross-backend doctor3 | 17/17 equal |
| Cross-backend edge | 17/17 equal |
| Cross-backend zero | 17/17 equal |
| Registry generator | 4/4 equal |
| Patient binding cross-backend | 1/1 equal |
| TOTAL cross-backend | 107/107 equal |

"Isolated Schnorr vectors 8/8 PASS" means the one valid signature was accepted
and all seven invalid ones were rejected.

## What the negative tests cover

| Test category | Examples |
|---|---|
| Signature | invalid s, s+l, wrong PK, wrong commitment, off-curve R/PK |
| Registry | modified path, wrong doctor, wrong key, wrong root, invalid direction |
| Prescription | modified medicine, prescription ID, expiry, threshold |
| Policy | expired prescription, slot_index >= threshold |

Each negative vector is a single attempt that must fail. A test passes only if
witness generation (Circom) or execution (Noir) is rejected by a circuit
constraint, not by a tool or input error.

## Reading the raw logs

Lines such as `PASS: NT-001 rejected by circuit (Error in template SchnorrBJJ_46)`
report **where** the expected constraint failure occurred (here: inside the
Schnorr verifier). The template name and its numeric suffix are Circom's
internal location identifiers. They are not errors in the test run and do not
indicate repeated executions. The Noir suite reports the equivalent location as
a source line, e.g. `src/main.nr:121`.

The raw logs are kept unchanged for audit and debugging.
