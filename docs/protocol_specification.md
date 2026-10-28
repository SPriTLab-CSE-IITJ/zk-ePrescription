# Protocol Specification

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

The domain-separated protocol hashes `H1`-`H6` (Section 5) are defined by
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
| Patient binding `H6` | `6` |

Domain separation MUST be preserved.

A protocol hash MUST NOT silently reuse another construction's domain.

---

## 6. Prescription Commitment

The prescription commitment is:

```text
C = H1(
    prescription_id,
    doctor_id,
    medicine_code,
    expiry,
    threshold
)
```

The five values above are part of the authenticated prescription statement.

In particular, `expiry` and `threshold` MUST be included in the commitment.

The commitment therefore binds the prescription fields that are also relevant
to authorization and policy evaluation.

A valid doctor signature in the redemption protocol is over this commitment.

Consequently, changing any commitment input changes the authenticated
prescription statement and invalidates a signature generated for the original
commitment.

---

## 7. Patient Identity Reference

The protocol defines an internal identity construction:

```text
I = H2(patient_secret)
```

This value is used by the issuance-side patient-prescription binding described
below.

`I` is not required to be a public output of the Phase-4 redemption circuit.

The redemption proof SHOULD expose only the public values required for the
redemption protocol, namely the commitment and redemption nullifier.

The patient secret itself remains private.

---

## 8. Patient-Prescription Binding

The issuance-side patient-prescription binding is:

```text
PB = H6(I, C)
```

where:

```text
I = H2(patient_secret)
```

This construction associates the patient credential with a prescription
commitment during issuance/enrollment.

The current Phase-4 redemption circuit does not consume or verify `PB`.

Therefore Phase-4 redemption MUST NOT be described as performing fresh
national/health-ID authentication or as independently re-establishing the
issuance-side patient binding.

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
slot index.

The patient secret is not revealed by the nullifier construction.

The circuit derives `N` and makes it available as a public redemption value.

### 9.1 Replay handling

Computing `N` does not by itself maintain a global database of redeemed
prescriptions.

If single-use redemption is required, the external verifier or redemption
service MUST record previously accepted nullifiers and reject a nullifier that
has already been redeemed according to the application's replay policy.

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

The intended Phase-4 public outputs are:

```text
C
N
```

That is:

```text
[commitment, nullifier]
```

The redemption circuit SHOULD NOT expose:

```text
H2(patient_secret)
```

as an unnecessary public identity reference.

---

## 16. Phase-4 Redemption Statement

A successful Phase-4 proof establishes, subject to the stated cryptographic
assumptions and implementation correctness, that the prover knows a witness
satisfying all required relations:

1. the prescription commitment is correctly computed;
2. the prescription satisfies the policy constraints;
3. the specified doctor identifier and public key are members of the authorized
   registry;
4. the same public key validates the doctor signature;
5. the signature authenticates the prescription commitment;
6. the prover knows the patient secret used to derive the redemption nullifier;
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
3. commitment `C`;
4. identity value `I`;
5. nullifier `N`;
6. registry leaf `L`;
7. Merkle node `M`;
8. complete registry root;
9. patient binding `PB`.

The final integrated canonical fixture SHOULD additionally demonstrate:

- identical commitment;
- identical nullifier;
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
- modified medicine code;
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
- invalid/off-curve signature nonce.

A modification to any value authenticated by the commitment or signature MUST
NOT silently continue to satisfy the corresponding verification relation.

---

## 19. Canonical Application Fixture

The canonical application scenario uses:

```text
prescription_id = 1001
doctor_id       = 5001
medicine_code   = 123
patient_secret  = 12345
expiry          = 20261231
threshold       = 3
```

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

In particular:

- public commitments may be linkable when reused;
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

### Patient-secret privacy

The patient secret is retained as a private witness rather than revealed as a
public circuit value.

### Policy enforcement

The proof cannot verify unless the implemented policy constraints are
satisfied.

### Nullifier derivation

The public nullifier is correctly derived from the private patient secret,
commitment, and redemption slot.

### Replay detection

The nullifier provides the value that an external redemption service can use
to detect repeated redemption attempts.

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

- H1-H6 input sets;
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

## 26. Summary of Normative Relations

For reference, the core constructions are:

```text
C  = H1(prescription_id, doctor_id, medicine_code, expiry, threshold)

I  = H2(patient_secret)

PB = H6(I, C)

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
```

Public Phase-4 redemption outputs:

```text
[C, N]
```

The canonical application fixture uses four registry leaves and therefore a
depth-2 Merkle tree, while the underlying registry construction remains
parameterized by depth.
