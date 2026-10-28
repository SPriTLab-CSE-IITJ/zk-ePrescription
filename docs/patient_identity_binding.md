# Patient Identity Binding

## Objective

The identity-binding layer associates an electronic prescription with a
patient identity established during registration using a national or medical
health identifier.

## Registration

The patient authenticates using the applicable national or medical health
identifier:

    HealthID

The registration layer establishes a protocol-specific patient binding:

    HealthID -> PatientBinding

The raw HealthID is not exposed as a public input to the ZK prescription
verification circuit.

## Prescription Issuance

The doctor issues prescription P for the registered patient binding.

The existing prescription commitment remains unchanged:

    C = Commit(P)

The patient-prescription association is established separately using the
patient binding and the existing prescription commitment.

## Redemption

Redemption is bearer-based. The presenter at the pharmacy does not need to
be the patient.

The pharmacy does not require fresh authentication against the national
health-identity system for every redemption.

The pharmacy verifies the issued prescription and its cryptographic validity,
including doctor authorization, policy validity, and replay protection.

## Accountability

After redemption, the system records the redemption event and notifies the
patient through the patient application.

The patient can therefore track prescription redemption events without
requiring the patient to be physically present at the pharmacy.

*Status:* redemption recording and patient notification are application-layer
services; they are not implemented in this research artifact.

## Security Boundary

Authentication of the HealthID occurs during registration. The ZK circuit
does not itself authenticate the national identity authority.

The ZK protocol uses the resulting private patient binding as part of the
prescription protocol.

## Design Principle

Patient identity binding and pharmacy-side prescription authentication are
separate security properties.

Patient identity binding establishes which registered patient the prescription
belongs to.

Pharmacy-side verification establishes that the prescription is authentic,
valid, authorized, and not already redeemed.
