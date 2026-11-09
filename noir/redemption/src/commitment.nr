use common::poseidon2_hash::{commitment_hash, identity_hash};

/// Computes the patient reference I = H2(patient_secret)
/// (docs/protocol_specification.md, Section 7). It stays private: it is an
/// input of the commitment, never a public output.
pub fn compute_patient_reference(patient_secret: Field) -> Field {
    identity_hash([patient_secret])
}

/// Computes the prescription commitment (protocol v2)
///
///     C = H1(prescription_id, doctor_id, medicine_code, expiry, threshold, I)
///
/// (docs/protocol_specification.md, Section 6). Because the doctor signs C,
/// including I binds the prescription to the patient's secret: a different
/// secret yields a different, unsigned commitment. Thin wrapper around the
/// shared domain-tagged Poseidon2 construction (domain 1).
pub fn compute_commitment(
    prescription_id: Field,
    doctor_id: Field,
    medicine_code: Field,
    expiry_date: u64,
    quantity_threshold: u64,
    patient_reference: Field,
) -> Field {

    commitment_hash([
        prescription_id,
        doctor_id,
        medicine_code,
        expiry_date as Field,
        quantity_threshold as Field,
        patient_reference,
    ])
}
