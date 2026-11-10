# Patient Identity Binding

## Objective

The identity-binding layer associates an electronic prescription with a
patient identity established during registration using a national or medical
health identifier, and makes every redemption of that prescription depend on
the patient's protocol secret.

## Registration

The patient authenticates using the applicable national or medical health
identifier:

    HealthID

The registration (enrollment) layer provisions a protocol-specific secret:

    HealthID -> patient_secret

The raw HealthID is never a witness or public input of any circuit.

## Prescription Issuance

The patient's app sends the patient reference

    I = H2(patient_secret)

to the doctor, who includes it in the prescription commitment and signs it:

    C = H1(prescription_id, doctor_id, D, expiry, threshold, I)      (D: medication-list digest, v3)

(`docs/protocol_specification.md`, Sections 6-8.) The patient-prescription
association is therefore part of the signed prescription itself.

## Redemption

The redemption proof recomputes `I` from the private `patient_secret` and
checks the doctor's signature on the resulting `C`. A different secret gives
a different, unsigned commitment and no valid proof. `I` stays private; the
public outputs are `C`, `N` and the medication-list digest `D` (v3).

Only the holder of the patient's secret can produce a redemption proof, but
the resulting redemption QR is a transferable bearer token for one slot on one
date: the patient can generate it and send it to a relative who collects the
medicine, without sharing the secret. A copy of the issuance record alone is
not enough. A stolen or relayed redemption QR is not prevented from being used
first on its date; the patient is meant to notice it through notification
(below).

The pharmacy does not require fresh authentication against the national
health-identity system for every redemption.

The pharmacy verifies the issued prescription and its cryptographic validity,
including doctor authorization, patient binding, policy validity and replay
protection (nullifier).

## Accountability

After redemption, the system records the redemption event and notifies the
patient through the patient application. Because the patient's app can
compute the nullifiers of its own prescription slots, it can learn which slots
were redeemed without the redemption service knowing who the patient is;
reporting where and when also requires the service to expose the redemption
event to the app. This is detection, not prevention.

*Status:* redemption recording and patient notification are application-layer
services; they are not implemented in this research artifact.

## Security Boundary

Authentication of the HealthID occurs during registration. The ZK circuit
does not itself authenticate the national identity authority, and binding a
prescription to `patient_secret` binds it to a secret, not to a legal person:
that the secret belongs to the authenticated patient is the enrollment
system's responsibility.

## History

Protocol v1 kept the binding on the issuance side only (`PB = H6(I, C)`) and
the redemption circuit did not verify it. As a result a valid issuance record
could be redeemed under any other secret, each time with a fresh nullifier.
Protocol v2 replaces `PB` with `I` inside the signed commitment.
