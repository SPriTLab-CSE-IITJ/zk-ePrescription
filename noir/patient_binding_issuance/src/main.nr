use common::poseidon2_hash::{
    identity_hash,
    patient_binding_hash,
};

/// Derives a patient-prescription binding during prescription issuance.
///
/// The external registration layer is assumed to have authenticated the
/// patient's national/medical health identity and established the private
/// patient secret used here.
///
/// The existing prescription commitment is not modified.
fn main(
    patient_secret: Field,
    commitment: Field,
) -> pub Field {
    let patient_binding = identity_hash([
        patient_secret,
    ]);

    let patient_prescription_binding = patient_binding_hash([
        patient_binding,
        commitment,
    ]);

    patient_prescription_binding
}

#[test]
fn binding_is_deterministic() {
    let a = identity_hash([12345]);
    let b = identity_hash([12345]);

    let pb_a = patient_binding_hash([a, 777]);
    let pb_b = patient_binding_hash([b, 777]);

    assert(pb_a == pb_b);
}

#[test]
fn different_patients_produce_different_bindings() {
    let a = identity_hash([12345]);
    let b = identity_hash([54321]);

    let pb_a = patient_binding_hash([a, 777]);
    let pb_b = patient_binding_hash([b, 777]);

    assert(pb_a != pb_b);
}

#[test]
fn different_prescriptions_produce_different_bindings() {
    let binding = identity_hash([12345]);

    let pb_a = patient_binding_hash([binding, 777]);
    let pb_b = patient_binding_hash([binding, 778]);

    assert(pb_a != pb_b);
}

#[test]
fn identity_and_patient_binding_domains_are_distinct() {
    let binding = identity_hash([12345]);
    let pb = patient_binding_hash([binding, 777]);

    assert(binding != pb);
}
