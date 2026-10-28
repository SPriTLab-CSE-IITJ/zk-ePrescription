# zk-ePrescription Threat Model

## 1. Scope

The zk-ePrescription protocol provides privacy-preserving verification of an
electronic prescription using zero-knowledge proofs.

The protocol is designed to establish prescription integrity, authorized doctor
issuance, patient-prescription binding, witness privacy and minimal disclosure,
prescription policy enforcement, and replay resistance while minimizing
unnecessary disclosure during pharmacy redemption.

The protocol is a research prototype and does not implement the external
national-health-identity infrastructure itself.

**Implementation status.** This document states intended properties and their
assumptions; it is not a formal security proof. Within this artifact the ZK
circuits enforce prescription integrity, registry membership, signature
validity, the policy checks and correct nullifier derivation
(`docs/protocol_specification.md`, Section 16). The nullifier store (replay
rejection), patient notification / redemption accountability and the
national-health-identity enrolment are external services that are **not**
implemented here. No claim of anonymity, universal unlinkability or collusion
resistance is made.

---

## 2. Participants

### Patient

The patient registers using a national or medical health identifier and obtains
a protocol-specific patient binding.

### Doctor

The doctor is registered in the trusted doctor registry and issues signed
electronic prescriptions.

### Pharmacy

The pharmacy verifies the prescription and its redemption conditions.

### ZK Prover

The prover constructs a zero-knowledge proof from the valid prescription
witness.

### ZK Verifier

The verifier checks the proof and the public statement associated with
redemption.

### Doctor Registry

The registry contains the authorized doctor public keys.

### Registration / Issuance Layer

This layer establishes the patient binding and associates a prescription with
the registered patient during prescription issuance.

### Redemption / Notification Layer

This layer records successful redemption events and notifies the patient.

---

## 3. Adversary Capabilities

The adversary may:

- modify or fabricate prescription information;
- attempt to forge a valid prescription proof;
- substitute an unauthorized doctor key;
- provide an invalid doctor registry membership path;
- submit expired prescriptions;
- exceed the permitted redemption threshold;
- reuse an already redeemed redemption slot; and
- observe public proof or redemption information and attempt to infer hidden
  patient or prescription information.

The adversary may also obtain a valid prescription artifact and attempt to
redeem it more than once, subject to the protocol's redemption rules.

---

## 4. Trust and Security Assumptions

The threat model assumes:

1. The cryptographic primitives used by the protocol are secure.
2. The proving and verification systems correctly implement their specified
   security properties.
3. The doctor registry is an authoritative source of authorized doctor
   public keys.
4. The external patient-registration system correctly authenticates the
   patient's national or medical health identity.
5. The issuance layer correctly establishes the patient-prescription
   association.
6. The redemption state used for nullifier checking is maintained correctly.
7. The notification mechanism reliably records and reports successful
   redemptions.

The ZK circuit does not itself authenticate the national health-identity
authority.

---

## 5. Patient Identity Binding

Patient identity binding is established before pharmacy redemption.

### Registration

The external identity layer authenticates the patient using:

    HealthID

and establishes a protocol-specific patient binding:

    HealthID -> B_P

The raw HealthID is not required as a public input to the ZK prescription
verification circuit.

### Prescription Issuance

The doctor issues prescription P for the registered patient binding.

The existing prescription commitment remains:

    C = Commit(P)

The patient-prescription binding is established separately:

    PB = Bind(B_P, C)

This does not modify the existing prescription commitment.

In the current prototype, PB is an issuance-side binding artifact. The
existing pharmacy-facing redemption circuit does not expose PB as a public
verification input.

### Redemption

Redemption is bearer-based.

The person presenting the prescription at the pharmacy does not have to be the
patient. For example, a family member or authorized representative may redeem
the prescription.

Therefore:

    Presenter != Patient

is not itself a protocol violation.

The pharmacy does not require a fresh national-health-ID authentication for
every redemption.

---

## 6. Doctor Authenticity

Prescription authenticity is based on two independent properties:

    PK_D in DoctorRegistry

and:

    VerifySig(PK_D, C, sigma_D) = 1

The registry membership establishes that the doctor public key is authorized.

The digital signature establishes that the holder of the corresponding signing
key signed the prescription commitment.

Together they establish:

    An authorized doctor signed the prescription commitment.

A valid signature under an unauthorized key is therefore insufficient.

---

## 7. Witness Privacy and Minimal Disclosure

The protocol keeps the detailed prescription and other sensitive witness
values inside the prover-side witness.

The verifier does not require disclosure of the complete private prescription
to establish the enforced cryptographic properties.

The privacy objective is therefore to minimize information revealed during
verification while allowing the verifier to establish:

    C = Commit(P)

    PK_D in DoctorRegistry

    VerifySig(PK_D, C, sigma_D) = 1

    currentDate <= expiry

    slotIndex < quantityThreshold

    N = Nullifier(s_P, C, slotIndex)

The external application may expose the information required for prescription
dispensing, but such application-level disclosure is distinct from the
private ZK witness.

The prototype does not require the bearer to manually enumerate medicine
codes as ZK proof inputs.

---

## 8. Policy Enforcement

The protocol enforces prescription validity conditions including:

    currentDate <= expiry

and:

    slotIndex < quantityThreshold

A proof corresponding to an expired prescription or an invalid redemption slot
must not be accepted.

---

## 9. Nullifier and Replay Protection

The redemption nullifier is derived from the private patient secret, the
prescription commitment, and the redemption slot:

    N = H_N(patientSecret, C, slotIndex)

Before accepting a redemption, the redemption state must establish:

    N not in S

After successful acceptance, the state is updated:

    S' = S union {N}

The same redemption instance must therefore not be accepted twice.

Replay protection depends on correct maintenance and atomic update of the
redemption state.

---

## 10. Redemption Accountability

After a successful redemption, the system records the redemption event and
notifies the patient through the patient application.

A redemption event may include the pharmacy and time information defined by the
application.

This provides application-level detection and accountability for
prescription use.

The current cryptographic prototype does not implement the notification
service itself, and it does not cryptographically establish the physical
identity of the person standing at the pharmacy counter.

---

# 11. Security Games

## Game 1 -- Fresh Prescription Forgery

The adversary wins if it produces a proof for a fresh statement x such that:

    Verify(vk, x, pi) = 1

while no valid witness w exists for:

    R(x, w) = 1

Security requires that an adversary cannot construct an accepted proof for a
statement that does not correspond to a valid witness.

---

## Game 2 -- Replay

The adversary wins if the same redemption instance is accepted more than once.

For nullifier N, two accepted redemptions of the same redemption slot would
constitute a win:

    Accept(N, t1) = 1
    Accept(N, t2) = 1

where both correspond to the same redemption instance.

The intended invariant is:

    N not in S

before acceptance, followed by:

    S' = S union {N}

after successful redemption.

---

## Game 3 -- Witness Privacy

The adversary is given two valid witnesses:

    w0, w1

that produce the same permitted public statement x.

A challenge proof is generated using one of the witnesses selected by a random
bit b.

The adversary outputs b'.

Its distinguishing advantage is:

    Adv_priv =
        | Pr[b' = b] - 1/2 |

The intended security goal is negligible distinguishing advantage.

---

## Game 4 -- Doctor Impersonation

The adversary attempts to produce an accepted prescription using a signing key
that is not authorized by the doctor registry.

Let:

    PK_A not in DoctorRegistry

The adversary wins if the resulting prescription is nevertheless accepted.

Acceptance requires both:

    PK_D in DoctorRegistry

and:

    VerifySig(PK_D, C, sigma_D) = 1

Therefore possession of an arbitrary signing key is insufficient.

---

## Game 5 -- Policy Bypass

The adversary attempts to produce an accepted proof while violating an
enforced prescription condition.

Examples include:

    currentDate > expiry

    slotIndex >= quantityThreshold

The adversary wins if a proof corresponding to such an invalid state is
accepted.

The corresponding circuit constraints must reject the proof.

---

## Game 6 -- Linkage / Inference

The adversary observes valid public outputs, proofs, and redemption-related
information and attempts to infer hidden patient or prescription information
beyond the information deliberately exposed by the protocol.

The adversary wins if it can distinguish or infer a hidden patient or
prescription relationship with non-negligible advantage using information
that should remain private.

The game includes unintended linkage between observations.

The bearer-redemption model is explicit:

    Presenter != Patient

is permitted.

The protocol therefore does not claim to identify the physical person who
presents a prescription at the pharmacy.

The privacy objective is to minimize unnecessary disclosure and unintended
linkage while preserving prescription verification and redemption
accountability.

---

## 12. Security Property Summary

The protocol separates the following properties:

1. Prescription integrity:

       C = Commit(P)

2. Doctor authorization:

       PK_D in DoctorRegistry

3. Doctor authenticity:

       VerifySig(PK_D, C, sigma_D) = 1

4. Patient-prescription binding:

       HealthID -> B_P
       PB = Bind(B_P, C)

5. Witness privacy / minimal disclosure:

       Full prescription remains in the private witness.

       Only information deliberately exposed by the protocol/application
       is revealed to the verifier.

6. Policy enforcement:

       currentDate <= expiry
       slotIndex < quantityThreshold

7. Replay resistance:

       N not in S

8. Bearer-compatible redemption:

       Presenter may differ from Patient

9. Redemption accountability:

       Redemption -> PatientNotification

The protocol does not require pharmacy-side re-authentication of the patient's
national health identity for every redemption.
