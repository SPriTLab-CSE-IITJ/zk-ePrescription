pragma circom 2.1.6;

// Issuance-side patient-prescription binding
// (docs/protocol_specification.md, Sections 7-8):
//
//   I  = H2(patient_secret)
//   PB = H6(I, C)
//
// Not part of the Phase-4 redemption statement.

include "lib_modules.circom";

template PatientBindingIssuance() {
    signal input patient_secret;
    signal input commitment;

    signal output patient_binding;
    signal output patient_prescription_binding;

    component identity = IdentityBinding();
    identity.patient_secret <== patient_secret;
    patient_binding <== identity.identity_ref;

    component pb = H6PatientBinding();
    pb.identity <== identity.identity_ref;
    pb.commitment <== commitment;
    patient_prescription_binding <== pb.out;
}

component main = PatientBindingIssuance();
