# Regression Test Results

Summary of the successful full regression of the aligned implementation
(`docker run --rm zkep test`, which runs `scripts/test.sh`). Final line of the
run: `RESULT: ALL REGRESSION TESTS PASSED`. The circuits are byte-identical to
the ones benchmarked (same R1CS and ACIR bytecode); only file and package names
changed in the restructured layout.

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

## Reading the output

The screen shows one line per check; the full output of every tool is in
`results/logs/` (`circom.log`, `noir.log`, `kat.log`).

The attack table names the check that rejected each vector in each backend:

| Name in the table | Circom location | Noir location |
|---|---|---|
| signature | `SchnorrBJJ`, signature equation | `src/main.nr:121` |
| s < l bound | `SchnorrBJJ`, scalar bound | `src/schnorr.nr:21` |
| registry | `DoctorRegistry`, root mismatch | `src/main.nr:120` |
| binary direction | `DoctorRegistry`, direction bit | `src/registry.nr:7` |
| expiry / slot < threshold | `EPrescriptionMain`, policy checks | `src/main.nr:119` / `:118` |
| point on curve / PK on curve / R on curve | `BabyCheck` | `src/schnorr.nr:19` / `:20` |

The two backends can name different checks for the same vector when it breaks
more than one condition. NT-018 (off-curve public key) is an example: Circom
evaluates the registry leaf first and fails there, Noir checks the curve
first. Both reject it; the isolated Schnorr vector `SIG-OFFCURVE-PK` exercises
the Circom curve check directly.
