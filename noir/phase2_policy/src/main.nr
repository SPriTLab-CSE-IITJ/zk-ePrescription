mod poseidon2_hash;

use poseidon2_hash::{
    commitment_hash,
    identity_hash,
    nullifier_hash,
};

fn main(
    prescription_id: Field,
    doctor_id: Field,
    medicine_code: Field,
    quantity_threshold: u64,
    expiry_date: u64,
    current_date: u64,
    patient_secret: Field,
    slot_index: u64
) -> pub [Field; 2] {

    // Full commitment binds prescription + policy
    let commitment = commitment_hash([
        prescription_id,
        doctor_id,
        medicine_code,
        Field::from(quantity_threshold),
        Field::from(expiry_date)
    ]);

    // Internal identity binding, not public
    let _identity_ref = identity_hash([
        patient_secret
    ]);

    // Policy checks
    assert(slot_index < quantity_threshold);
    assert(current_date <= expiry_date);

    // Replay protection
    let nullifier = nullifier_hash([
        patient_secret,
        commitment,
        Field::from(slot_index)
    ]);

    [commitment, nullifier]
}
