# Protocol Specification

**Version 3.** Protocol v3 lets the pharmacy see, after verification, exactly
the medicines the doctor prescribed: the commitment contains the digest `D` of
the prescription's medication list (Section 6.1) in place of the single
medicine code of v2, and the redemption proof outputs `D`. The patient's app
sends the list in clear; the pharmacy shows it to the pharmacist only if it
hashes to `D`. In v2 the medicine was a private input, so the pharmacist could
not learn from the proof what to dispense. The v2 vectors are kept in
`testdata/historical/v2/`.

**Version 2.** Protocol v2 binds the patient secret to the signed prescription
by including the patient reference `I = H2(patient_secret)` in the commitment
`C` (Sections 6-8). Protocol v1, measured in the benchmark release
`bench-evidence-2026-10-30` (commit `f257cad`), used
`C = H1(prescription_id, doctor_id, medicine_code, expiry, threshold)` and an
issuance-side binding `PB = H6(I, C)` that the redemption circuit never
checked. Because the redemption circuit did not relate `patient_secret` to
`C`, a holder of a valid issuance record could redeem it under any other
secret and obtain a fresh nullifier for every slot, so v1 did not bound the
number of redemptions. The v1 vectors are kept in `testdata/historical/v1/`.

## 1. Purpose

This document defines the normative cryptographic and protocol semantics of the
privacy-preserving e-prescription redemption protocol implemented by this
repository.

The repository contains two independent implementations of the protocol:

- Circom + Groth16
- Noir + UltraHonk

The proving backends are different, but the logical protocol relation and
canonical cryptographic constructions are intended to be the same.

This specification is normative for protocol semantics. Implementation details
specific to Circom, Noir, Groth16, or UltraHonk are subordinate to these
definitions unless explicitly identified as backend-specific.

---

## 2. Protocol Scope

The protocol covers privacy-preserving prescription redemption using:

1. a prescription commitment;
2. policy enforcement;
3. an authorized-doctor Merkle registry;
4. a BabyJubJub-based Schnorr signature;
5. a patient secret held privately by the prover;
6. a deterministic redemption nullifier;
7. zero-knowledge proving of the required relations.

The protocol does not place national or health identifiers directly inside the
zero-knowledge circuit.

External identity authentication and enrollment establish the patient
credential/secret used by the protocol, but those operations are outside the
Phase-4 redemption circuit specified here.

---

## 3. Trust and Identity Boundary

### 3.1 External health-ID authentication

A national or health identifier may be used by an external authentication or
enrollment system.

The raw identifier MUST NOT be supplied as a circuit witness or public input.

The zero-knowledge circuit operates on the protocol-specific patient secret
derived or provisioned by the enrollment process.

Therefore:

```text
External identity system
        |
        v
Authentication / enrollment
        |
        v
Protocol-specific patient secret
        |
        v
ZK redemption circuit
```

The Phase-4 circuit does not perform fresh national/health-ID authentication.

---

## 4. Field and Hash Construction

All canonical protocol hashes operate over the BN254 scalar field.

The canonical hash primitive is Poseidon2 with:

- state width: `t = 4`
- rate: `3`
- capacity: `1`
- S-box: `x^5`
- full rounds: `8` at the beginning and `8` at the end
- partial rounds: `56`

Thus the total permutation consists of:

```text
8 full rounds
+ 56 partial rounds
+ 8 full rounds
```

**Permutation.** The permutation is the Poseidon2 instance used by Noir's
standard library (`std::hash::poseidon2_permutation`, Barretenberg) for
BN254 and `t = 4`:

1. initial external linear layer: `s <- M_E * s`;
2. 4 full rounds: add the round constants `RC[r][0..3]`, apply `x^5` to all
   four elements, `s <- M_E * s`;
3. 56 partial rounds: add `RC[r][0]` to `s0` only, apply `x^5` to `s0` only,
   `s <- M_I * s`;
4. 4 full rounds as in step 2.

with the external matrix and the internal matrix

```text
        [5 7 1 3]
M_E  =  [4 6 1 1]          M_I = J + diag(d0, d1, d2, d3)
        [1 3 5 7]          (J = all-ones 4x4 matrix), i.e.
        [1 1 4 6]          s_i <- d_i * s_i + (s0 + s1 + s2 + s3)
```

**Constants.** The 64 x 4 round constants `RC` (rows of partial rounds use
only their first element) and the internal diagonal `d` are taken verbatim
from noir-lang/noir tag `v1.0.0-beta.24`,
`acvm-repo/bn254_blackbox_solver/src/poseidon2_constants.rs`, the constants
behind Noir's permutation. They are stored in
`circom/scripts/lib/poseidon2_constants.json` (with their provenance) and
generated into `circom/circuits/poseidon2_constants.circom`
(docs/architecture.md). The cross-backend KAT checks the Circom permutation
against Noir's and against independent reference vectors
(`testdata/kat/poseidon2_permutation_reference.json`).

**Input encoding.** Every hash input is a canonical element of the BN254
scalar field, i.e. an integer in `[0, p)`. Dates (`YYYYMMDD`), `threshold`
and `slot_index` are 64-bit unsigned integers (Section 14) embedded as field
elements; identifiers, keys and digests are field elements as given. The
sponge has no padding: the input length `n` enters through the initial
capacity value (Section 4.1), so inputs of different lengths do not collide
by construction.

### 4.1 Sponge construction

The project-level sponge `Hraw(x_0, ..., x_{n-1})` hashes a sequence of `n`
field elements using a four-element state `[s0, s1, s2, s3]`, where `s0..s2`
form the rate portion and `s3` is the capacity element.

The initial state is:

```text
[0, 0, 0, n * 2^64]
```

where `n` is the total number of field elements absorbed by the sponge
(the input length), not the domain identifier.

Inputs are absorbed at a rate of three field elements per block.

For each complete three-field block:

1. add the block element-wise into the rate portion (`s0`, `s1`, `s2`);
2. apply the Poseidon2 permutation.

After all complete blocks are absorbed:

1. add any remaining elements (fewer than three) into `s0`, `s1`, ... in order;
2. apply a final Poseidon2 permutation;
3. return `state[0]`.

If `n` is a multiple of three, the final permutation is applied to the state
obtained after the last complete block, with no further absorption.

### 4.2 Domain-tagged hashes

The domain-separated protocol hashes `H1`-`H5` (Section 5) are defined by
prepending the domain identifier as the first absorbed element:

```text
Hd(x_1, ..., x_k) = Hraw(d, x_1, ..., x_k)
```

so that a domain-tagged hash over `k` protocol inputs absorbs `n = k + 1`
elements and uses the initial capacity value `(k + 1) * 2^64`.

`Hraw` without a domain tag is used only where this specification says so
explicitly (the signature challenge, Section 13).

The Noir implementation uses the canonical
`std::hash::poseidon2_permutation` primitive.

Circom MUST implement an equivalent Poseidon2 construction for all protocol
hashes for which cross-backend equality is required.

---

## 5. Domain Separation

The protocol uses the following domain identifiers:

| Construction | Domain |
|---|---:|
| Commitment `H1` | `1` |
| Identity `H2` | `2` |
| Nullifier `H3` | `3` |
| Registry leaf `H4` | `4` |
| Merkle node `H5` | `5` |
| *(retired)* | `6` |
| Medication-list digest `H7` (off-circuit) | `7` |

Domain `6` was used by the protocol-v1 patient binding `PB = H6(I, C)`. It is
retired in v2 and MUST NOT be reused for another construction. Domain `7` is
new in v3 (Section 6.1); it is computed by the doctor's software and by the
pharmacy, not inside the redemption circuit.

Domain separation MUST be preserved.

A protocol hash MUST NOT silently reuse another construction's domain.

---

## 6. Prescription Commitment

The prescription commitment is:

```text
I = H2(patient_secret)

D = H7(medication list)                      (Section 6.1)

C = H1(
    prescription_id,
    doctor_id,
    D,
    expiry,
    threshold,
    I
)
```

The six values above are part of the authenticated prescription statement.
In the circuits the third input is named `medication_digest`.

In particular, `expiry`, `threshold` and the patient reference `I` MUST be
included in the commitment. Including `I` binds the prescription to the
patient's secret (Section 8).

The commitment therefore binds the prescription fields that are also relevant
to authorization and policy evaluation.

A valid doctor signature in the redemption protocol is over this commitment.

Consequently, changing any commitment input changes the authenticated
prescription statement and invalidates a signature generated for the original
commitment.

### 6.1 Medication list and its digest D (protocol v3)

A prescription carries a list of one or more medicines. Each item has exactly
four fields:

| Field | Content |
|---|---|
| `code` | medication code, 6-18 decimal digits (a SNOMED CT concept id) |
| `name` | display name, e.g. `Paracetamol 500 mg tablet` |
| `dosage` | dosage instructions as text, e.g. `1 tablet up to 4 times a day if needed` |
| `quantity` | quantity to dispense per redemption, integer 1-1000000 |

`name` and `dosage` are non-empty UTF-8 strings of at most 200 characters, in
Unicode NFC form, without control characters (U+0000-U+001F, U+007F). A list
has 1-32 items. The order is the doctor's and is significant.

**Canonical encoding.** For each item in order, the UTF-8 bytes of
`code`, `0x1F`, `name`, `0x1F`, `dosage`, `0x1F`, the decimal `quantity`,
`0x1E` (unit and record separators, which the field rules exclude from the
fields). The encoding is at most 4096 bytes.

**Digest.** With `L` the byte length of the encoding and `b_0 .. b_{k-1}`
the encoding split into 31-byte big-endian chunks (the last one shorter; each
is below the field modulus),

```text
D = H7(list) = Hraw(7, L, b_0, ..., b_{k-1})
```

Reference implementation: `scripts/lib/medication_list.js`.

**Use.** The doctor computes `D` and signs `C` over it (Section 6). Every
redemption dispenses the whole list (decision D6, Section 27). The redemption
circuit takes `D` as a private input, uses it in `C` and outputs it
(Section 15.2); it does not parse the list. The patient's app sends the list
in clear together with the proof. The pharmacy MUST recompute `D` from the
received list and MUST NOT show or dispense anything unless it equals the `D`
output by a valid proof (Section 26). Because `D` is inside the signed `C`, a
changed, added, removed or swapped item changes `D` and is rejected; a proof
claiming another `D` does not verify.

The pharmacy learns the medication list and `D`; it does not learn the
patient, the doctor, the prescription identifier, the expiry or the threshold.

---

## 7. Patient Reference

The protocol defines an internal patient reference:

```text
I = H2(patient_secret)
```

At issuance the patient gives `I` to the doctor, who includes it in the
commitment (Section 6). During redemption the circuit recomputes `I` from the
private `patient_secret`; `I` is a private intermediate value.

`I` MUST NOT be a public output of the Phase-4 redemption circuit: a stable
patient-derived value would be a correlation point across all of a patient's
prescriptions.

The redemption proof exposes only the public values required for the
redemption protocol, namely the commitment, the redemption nullifier and the
medication-list digest (Section 15.2).

The patient secret itself remains private.

---

## 8. Patient-Prescription Binding

The patient-prescription binding is established by the doctor's signature on
`C`, which contains `I = H2(patient_secret)`:

1. a different patient secret gives a different `I`;
2. a different `I` gives a different commitment `C'`;
3. the doctor's signature does not validate `C'` (assuming signature
   unforgeability and collision resistance of `H1` and `H2`);
4. hence, for a given signed `C`, only the secret behind `I` can produce a
   valid redemption proof, and the same secret, commitment and slot always give
   the same nullifier (Section 9).

The binding is created once, at issuance, and checked by every redemption
proof as part of the commitment relation; there is no separate identity check.

Qualifications:

- including `I` in `C` binds the prescription to a secret, not to a legal
  person. That `patient_secret` belongs to the authenticated patient is
  established by the external enrollment process (Section 3);
- the redemption proof does not constitute fresh national/health-ID
  authentication.

Protocol v1 defined an issuance-side value `PB = H6(I, C)` that the
redemption circuit did not verify. It is superseded by the construction above
and removed.

---

## 9. Redemption Nullifier

The redemption nullifier is:

```text
N = H3(
    patient_secret,
    C,
    slot_index
)
```

The nullifier is deterministic for the same patient secret, commitment, and
slot index. Because the commitment fixes the patient secret (Section 8) and
the policy fixes `slot_index < threshold` (Section 14.1), a prescription with
threshold `t` has exactly `t` valid nullifiers, one per slot `0..t-1`.

The patient secret is not revealed by the nullifier construction.

The circuit derives `N` and makes it available as a public redemption value.

### 9.1 Replay handling

Computing `N` does not by itself maintain a global database of redeemed
prescriptions.

If single-use redemption is required, the external verifier or redemption
service MUST record previously accepted nullifiers and reject a nullifier that
has already been redeemed according to the application's replay policy. The
check and the insertion MUST be atomic, so that two verifiers cannot accept
the same nullifier concurrently.

The guarantee is one redemption per slot: a prescription with threshold `t`
can be redeemed at most `t` times in total, not once overall. It holds only if
every verifier that can dispense the prescription uses the same nullifier
service and that service checks and inserts atomically; without such a
service, the same valid proof can be accepted more than once.

### 9.2 Redemption QR: a transferable bearer token

A redemption proof together with its public values `(C, N, D)` and the
medication list (the redemption QR, or the token the app submits) is a
transferable bearer token for one slot of one prescription, valid
for the calendar date bound into the proof as `current_date`. The patient may
generate it and give it to a relative or other representative, who can redeem
it without learning `patient_secret`.

The token is not bound to a pharmacy or a session (design decision D2,
Section 27). Consequently the protocol does NOT prevent theft or relay of a
redemption QR, or a first-use race between the intended holder and someone
who copied it, on the date it is valid.

Misuse is intended to be detected, not prevented: the patient's application
can derive the expected nullifiers `N_i = H3(patient_secret, C, i)` for
`i = 0..t-1` and learn which of them the redemption service has recorded, so
that unexpected redemptions can be reported. Reporting where and when a
redemption happened additionally requires the service to expose redemption
event information to the patient's application. The artifact's redemption
service records the pharmacy and time with each nullifier and answers such
queries (`scripts/lib/redemption_service.js query`); pushing a notification
to the patient is an application-level requirement that is not implemented.

Thus:

```text
ZK circuit:
    derives N

Redemption service:
    enforces uniqueness of N
```

---

## 10. Doctor Registry

Doctors are authorized through a Merkle-tree registry.

The canonical leaf is:

```text
L = H4(
    doctor_id,
    pubkey_x,
    pubkey_y
)
```

The leaf MUST be computed from the doctor identifier and the public-key
coordinates used by the protocol.

A prover MUST NOT be able to supply an independent unconstrained leaf that is
unrelated to the `doctor_id` and public key used elsewhere in the circuit.

This binds:

```text
doctor_id
    +
public-key coordinates
```

to the authorized registry entry.

---

## 11. Merkle Tree Construction

Internal Merkle nodes are computed as:

```text
M = H5(
    left,
    right
)
```

The left/right ordering MUST be preserved.

For a path element at level `i`:

- direction `0` means the current node is the left child;
- direction `1` means the current node is the right child.

Each direction MUST be constrained to a binary value.

The generic registry verifier may support an arbitrary depth `D`.

The protocol does not require a single fixed Merkle depth independent of registry
size.

### 11.1 Canonical experimental registry

The canonical cross-backend application fixture used for the research artifact
contains four registered doctors.

For this specific fixture:

```text
number of leaves = 4
Merkle depth      = 2
```

This is a property of the experimental fixture, not a limitation of the
protocol construction.

The same registry leaves, internal nodes, root, and authentication-path
semantics MUST be used by both backends for the canonical cross-backend test.

---

## 12. Registry and Signature Binding

The public key used in registry verification MUST be the same public key used
for signature verification.

The intended relation is:

```text
(doctor_id, PKx, PKy)
        |
        +--> H4 --> Merkle membership
        |
        +--> Schnorr verification
```

A valid redemption proof therefore cannot combine the registry membership of
one public key with a signature under another public key.

---

## 13. Doctor Signature

The protocol uses a Schnorr-style signature relation over BabyJubJub.

The signature consists of:

```text
R = (Rx, Ry)
s
```

The public key is:

```text
PK = (PKx, PKy)
```

The challenge is:

```text
c = Hraw(
    Rx,
    Ry,
    PKx,
    PKy,
    C
)
```

where `Hraw` denotes the canonical raw Poseidon2 construction used for the
signature challenge.

The verification equation is:

```text
sG = R + 8 * PK * c
```

where:

- `G` is the protocol's BabyJubJub generator;
- `PK` is the registered public key;
- `8` is the protocol's cofactor-related multiplier.

Clarification of `G` and of the validity conditions: `G` is the BabyJubJub
base point `B8` (circomlib `Base8`, equal to `8 * Generator`), which generates
the prime-order subgroup of order `l`, where

```text
l = 2736030358979909402780800718157159386076813972158567259200215660948447373041
```

A public key `PK` is not required to lie in the prime-order subgroup; the
multiplication by `8` maps it into that subgroup. The verifier MUST check that:

- `PK` lies on the BabyJubJub curve;
- `8 * PK` is not the identity point;
- `R` lies on the BabyJubJub curve;
- `s < l`.

The challenge `c` is the full BN254 field element output of `Hraw` and MUST be
used in full (no truncation of its bit representation).

The implementation MUST validate the public key and signature nonce as
appropriate BabyJubJub points and enforce the protocol's scalar bound.

The same signature relation MUST be implemented by both backends.

---

## 14. Policy Enforcement

A redemption proof MUST satisfy the policy constraints defined by the
application.

The protocol includes:

### 14.1 Slot/threshold policy

The redemption slot must satisfy the configured prescription threshold.

### 14.2 Expiry policy

The protocol requires:

```text
current_date <= expiry_date
```

`current_date` is a public verifier-supplied input to the redemption circuit.

The prover MUST NOT be able to privately choose an arbitrary current date for
the expiry check.

Implementations MUST preserve equivalent integer semantics for the date values.

For Circom, if field-valued signals are used, the implementation MUST include
the necessary range constraints to enforce the intended 64-bit semantics.

---

## 15. Public and Private Data

The exact proof interface is backend-specific in syntax, but the logical
semantics are shared.

### 15.1 Private values

Examples include:

```text
patient_secret
```

and other witness values that are not required to be disclosed to the
verifier.

### 15.2 Public redemption values

The Phase-4 public outputs are (protocol v3):

```text
C
N
D
```

That is:

```text
[commitment, nullifier, medication_digest]
```

together with the public inputs `registry_root` and `current_date`. In v2 the
outputs were `[C, N]`.

The redemption circuit MUST NOT expose:

```text
I = H2(patient_secret)
```

as a public identity reference (Section 7).

---

## 16. Phase-4 Redemption Statement

A successful Phase-4 proof establishes, subject to the stated cryptographic
assumptions and implementation correctness, that the prover knows a witness
satisfying all required relations:

1. the prescription commitment is correctly computed from the prescription
   fields, the medication-list digest `D` and `I = H2(patient_secret)` for
   the prover's secret, and the public `D` is the digest inside the signed
   commitment;
2. the prescription satisfies the policy constraints;
3. the specified doctor identifier and public key are members of the authorized
   registry;
4. the same public key validates the doctor signature;
5. the signature authenticates the prescription commitment;
6. the prover knows the patient secret bound into the signed commitment, and
   the same secret derives the redemption nullifier;
7. the public nullifier is correctly derived from the patient secret,
   commitment, and slot index.

The proof does not reveal the patient secret.

The proof does not constitute fresh national/health-ID authentication.

The proof does not by itself maintain global replay state.

---

## 17. Cross-Backend Equivalence

Circom/Groth16 and Noir/UltraHonk may have different:

- circuit representations;
- constraint systems;
- proof formats;
- proving keys;
- verification keys;
- proof sizes;
- performance characteristics.

These backend-specific properties do not change the logical protocol.

Where the same canonical construction is specified, the two implementations MUST
produce equal protocol-level values for identical inputs.

The required equality targets include:

1. raw Poseidon2 permutation vectors;
2. sponge test vectors;
3. commitment `C` (including `I` and `D`);
4. patient reference `I`;
5. nullifier `N`;
6. registry leaf `L`;
7. Merkle node `M`;
8. complete registry root.

The final integrated canonical fixture SHOULD additionally demonstrate:

- identical commitment;
- identical nullifier;
- identical medication-list digest `D`;
- identical registry root;
- identical doctor identifier;
- identical public key;
- valid policy in both implementations;
- valid registry membership in both implementations;
- successful signature verification in both implementations;
- successful end-to-end proof verification in both implementations.

---

## 18. Negative and Robustness Tests

The research artifact SHOULD test failure when an authenticated input or
required condition is modified.

Relevant cases include:

- modified prescription identifier;
- modified doctor identifier;
- the digest of another medication list (one quantity changed);
- modified expiry;
- modified threshold;
- modified public key;
- modified registry root;
- modified Merkle path element;
- modified Merkle direction;
- expired prescription;
- invalid signature;
- invalid signature scalar;
- invalid/off-curve public key;
- invalid/off-curve signature nonce;
- a valid issuance record redeemed under a different patient secret
  (patient binding, v2);
- a different patient secret used to obtain a fresh nullifier for a slot;
- a valid protocol-v1 signature (over the commitment without `I`) used for
  the v2 commitment;
- a slot outside the u64 range;
- a valid protocol-v2 signature (single medicine code instead of `D`) used
  for the v3 commitment.

The public values of every valid redemption SHOULD be checked to be exactly
`registry_root`, `current_date`, `C`, `N` and `D`, with neither `I` nor
`patient_secret` among them.

The pharmacy-side check of Section 6.1 SHOULD be tested on real proofs of
both backends: the signed list is shown; a changed quantity, a swapped,
added or removed medicine, an altered list together with its own digest
substituted in the public values, and a root or date that is not the
pharmacy's own are rejected.

The redemption-service behaviour SHOULD also be tested on the outputs of both
backends: each slot is accepted once, and a second redemption of the same slot
(on any date, at any verifier) is rejected.

A modification to any value authenticated by the commitment or signature MUST
NOT silently continue to satisfy the corresponding verification relation.

---

## 19. Canonical Application Fixture

The canonical application scenario uses:

```text
prescription_id   = 1001
doctor_id         = 5001
medication list   = testdata/kat/medication_list.json (2 items; illustrative
                    placeholder codes, not checked against SNOMED CT)
medication_digest = D of that list (Section 6.1)
patient_secret    = 12345
expiry            = 20261231
threshold         = 3
```

Protocol v1 and v2 used `medicine_code = 123` in place of `D`.

A single coherent `current_date` value MUST be selected and used consistently
for the final cross-backend fixture.

The canonical registry public key for doctor `5001` MUST be the same valid
BabyJubJub public key used for the corresponding Schnorr signature.

Temporary or dummy public-key coordinates MUST NOT be used in the final
integrated fixture unless they have been explicitly generated and verified as
valid test keys.

---

## 20. Cryptographic Test-Vector Policy

Canonical test vectors MUST be generated from the implementation of the
specified construction rather than copied from undocumented or unrelated
fixtures.

A test vector SHOULD record:

- input fields;
- construction/domain;
- expected field output;
- backend result;
- cross-backend equality result.

Historical development vectors MAY be retained for regression purposes, but
they MUST be clearly distinguished from the canonical aligned protocol
fixture when their construction or inputs differ from this specification.

---

## 21. Replay and Linkability Considerations

The nullifier provides a deterministic public identifier derived from:

```text
patient_secret
commitment
slot_index
```

The system's privacy properties depend on what values are publicly disclosed
and what state is retained by the verifier.

The Phase-4 circuit therefore does not claim universal anonymity or unlinkability
merely from zero-knowledge proving.

What each party sees differs:

- **Verifiers and the redemption service** see `C` and `N` (and the root and
  date), never `I`. Verifiers additionally see the medication list and its
  digest `D` (Section 6.1); the redemption service needs only `N`. The
  list is what the pharmacist must know to dispense; an unusual combination
  of medicines can itself link prescriptions or hint at a condition, which
  the protocol cannot hide from the dispensing pharmacy. `D` depends only on
  the list, so identical lists of different patients have the same `D`.
  Different prescriptions of one patient have different `C`,
  and `C` and `N` are pseudorandom to anyone without `patient_secret` under the
  hash assumptions, so these parties cannot link a patient's different
  prescriptions. They can link all redemptions of the same prescription
  through `C`.
- **Issuing doctors** know `I` and the `C` they signed. They are outside the
  verifier-privacy property: one doctor can link the redemptions of its own
  prescriptions to the patient, and colluding issuers can correlate a
  patient's prescriptions through the stable `I` (decision D3, Section 27).

The scoping differs from application-scoped nullifiers such as Nova
Aadhaar's: here the linkable unit is one prescription (`C`), not one
application.

In particular:

- public commitments are linkable when reused;
- nullifier reuse is intentionally detectable for replay handling;
- external identity systems may possess information unavailable to the ZK
  verifier;
- application-level logging or metadata may introduce additional linkability.

Privacy claims in research evaluation MUST distinguish cryptographic witness
hiding from application-level metadata privacy.

---

## 22. Security Properties and Assumptions

The protocol is intended to provide the following implementation-level
properties when the underlying cryptographic primitives and proving systems are
sound:

### Prescription integrity

The signed commitment binds the prescription fields defined in Section 6.

### Doctor authorization

The doctor identifier and public key must belong to the authorized Merkle
registry.

### Registry/signature binding

The registered public key is the same key used for signature verification.

### Signature authenticity

Without the appropriate signing secret and under the security assumptions of
the signature construction, an adversary should not be able to produce a valid
signature for an unauthorized commitment.

### Patient-prescription binding

A redemption proof for a signed commitment `C` requires the secret behind the
`I` contained in `C`; a different secret does not yield a valid proof
(Section 8), subject to authenticated enrollment of the secret.

### Patient-secret privacy

The patient secret and the patient reference `I` are retained as private
witness values rather than revealed as public circuit values.

### Policy enforcement

The proof cannot verify unless the implemented policy constraints are
satisfied.

### Nullifier derivation

The public nullifier is correctly derived from the private patient secret,
commitment, and redemption slot.

### Replay detection and refill limit

The nullifier provides the value that an external redemption service uses to
detect repeated redemption attempts. With atomic nullifier storage, each slot
is redeemed at most once, and a prescription with threshold `t` at most `t`
times.

These statements are protocol goals/implementation properties, not a formal
security proof.

Claims about anonymity, universal unlinkability, collusion resistance,
accountability, or other stronger system-level properties require additional
analysis and MUST NOT be inferred solely from the presence of zero-knowledge
proofs.

---

## 23. Research Evaluation Boundary

The evaluation compares:

```text
Circom + Groth16
```

against:

```text
Noir + UltraHonk
```

using the same logical protocol and canonical test vectors.

Backend-specific measurements such as:

- R1CS constraints;
- ACIR representation;
- Barretenberg gates;
- witness-generation time;
- proving time;
- verification time;
- proof size;
- verification-key size;
- memory usage

MUST be reported using their native meanings.

R1CS constraints, ACIR opcodes, and Barretenberg gates MUST NOT be presented as
though they were identical complexity units.

Performance measurements MUST identify the platform, software/toolchain
version, and circuit revision used for the measurement.

---

## 24. Reproducibility Requirements

The repository SHOULD provide enough information for an independent researcher
to:

1. build the stated toolchain;
2. compile both circuit implementations;
3. generate the canonical witness;
4. generate proofs;
5. verify proofs;
6. reproduce the cryptographic test vectors;
7. reproduce the cross-backend equality checks;
8. reproduce reported benchmark measurements.

Docker is the preferred reproducibility path when host environments do not
contain all required proving toolchains.

---

## 25. Specification Change Policy

Any change to the following is a protocol-level change and MUST be explicitly
documented:

- H1-H5 input sets (and the retired domain 6);
- Poseidon2 parameters;
- domain identifiers;
- commitment semantics;
- nullifier semantics;
- registry leaf semantics;
- Merkle-node semantics;
- signature relation;
- public/private protocol values;
- identity boundary.

Changing the concrete Merkle depth of a particular registry fixture does not,
by itself, change the protocol, provided the generic Merkle construction and
leaf/node semantics remain unchanged.

---

## 26. Verifier Requirements (environmental assumptions)

The circuit proves the redemption relation for whatever public inputs it is
given. The following are requirements on the verifier (pharmacy) and the
redemption service; they are assumptions of the security analysis. Items 1-3
and 5 are implemented by `scripts/pharmacy_verify.js` (with the root, date and
key given to it by the pharmacy's configuration); item 4 is implemented by
`scripts/lib/redemption_service.js` (one file per accepted `N`, created
atomically with exclusive create on a shared local file system) and tested
with concurrent submissions (`scripts/lib/nullifier_concurrency.js`):

1. **Registry root.** The verifier sets `registry_root` itself, from an
   authenticated publication of the registry authority; never from the
   redemption QR. It accepts the current root and any root published within
   the last `Delta` (decision D4, Section 27).
2. **Date.** The verifier sets `current_date` from its own trusted clock;
   never from the redemption QR.
3. **Verification key.** The verification key and circuit version are pinned
   in the verifier software (by hash); a proof is never verified against a key
   it supplies.
4. **Nullifier service.** Acceptance is decided on `N`, never on proof bytes
   (Groth16 proofs can be re-randomised). Check-and-insert of `N` is one atomic
   operation in a service shared by every verifier that can dispense the
   prescription; the medicine is dispensed only after the insert succeeded.
5. **Medication list.** The verifier recomputes `D` from the medication list
   it receives (Section 6.1) and shows the list to the pharmacist, and
   dispenses, only if it equals the `D` output by the verified proof.

## 27. Design Decisions (protocols v2 and v3)

| Decision | Status | Choice |
|---|---|---|
| D1 Redemption model | settled | Credential-bound issuance (`I` inside the signed `C`), transferable bearer redemption QR (Section 9.2) |
| D2 Pharmacy/session binding of proofs | settled | Not used; relay and first-use races are an accepted risk of the bearer design, mitigated by notification (detection only) |
| D3 Patient reference | settled | Stable `I = H2(patient_secret)` per patient. Verifiers never receive `I`; issuing doctors do, and colluding issuers can correlate a patient's prescriptions (acknowledged limitation) |
| D4 Registry-root acceptance | settled | A verifier accepts a proof against the current root or any root the registry authority published within the last `Delta` (a deployment parameter, e.g. 24 hours). A doctor removed from the registry therefore stops being accepted at most `Delta` after the new root is published; the patient's app fetches a fresh Merkle path when the root changes. `Delta = 0` (latest root only) is the strict setting. The artifact's verifier takes a single configured root |
| D5 Patient binding `PB = H6(I, C)` | settled | Removed; superseded by `I` inside `C`; domain 6 retired |
| D6 What the pharmacy learns (v3) | settled | The full medication list (code, name, dosage, quantity per redemption), bound to the signed `C` through `D` and shown after verification; every redemption dispenses the whole list, so `threshold` counts redemptions of the whole prescription. Drugs that need a different refill limit go on a separate prescription |

## 28. Summary of Normative Relations

For reference, the core constructions are:

```text
I  = H2(patient_secret)

D  = H7(medication list) = Hraw(7, L, b_0, ..., b_{k-1})   (off-circuit, Section 6.1)

C  = H1(prescription_id, doctor_id, D, expiry, threshold, I)

N  = H3(patient_secret, C, slot_index)

L  = H4(doctor_id, pubkey_x, pubkey_y)

M  = H5(left, right)

Hd(x_1..x_k) = Hraw(d, x_1, ..., x_k)      (IV = (k+1) * 2^64)
```

Signature:

```text
c = Hraw(Rx, Ry, PKx, PKy, C)              (IV = 5 * 2^64, no domain tag)

sG = R + 8 * PK * c                         (G = Base8, s < l)
```

Policy:

```text
current_date <= expiry
slot_index   <  threshold
```

Public Phase-4 redemption outputs:

```text
[C, N, D]
```

The canonical application fixture uses four registry leaves and therefore a
depth-2 Merkle tree, while the underlying registry construction remains
parameterized by depth.
