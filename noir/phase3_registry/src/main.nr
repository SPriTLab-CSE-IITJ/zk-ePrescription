mod poseidon2_hash;
mod registry;
mod fixtures;

use poseidon2_hash::{
    commitment_hash,
    identity_hash,
    nullifier_hash,
};
use registry::verify_doctor_membership;

fn main(
    prescription_id: Field,
    doctor_id: Field,
    medicine_code: Field,
    quantity_threshold: u64,
    expiry_date: u64,
    current_date: u64,
    registry_root: pub Field,
    doctor_pubkey_x: Field,
    doctor_pubkey_y: Field,
    sibling0: Field,
    sibling1: Field,
    direction0: bool,
    direction1: bool,
    patient_secret: Field,
    slot_index: u64
) -> pub [Field; 2] {

    let commitment = commitment_hash([
        prescription_id,
        doctor_id,
        medicine_code,
        Field::from(quantity_threshold),
        Field::from(expiry_date)
    ]);

    let _identity_ref = identity_hash([
        patient_secret
    ]);

    verify_doctor_membership(
        registry_root,
        doctor_id,
        doctor_pubkey_x,
        doctor_pubkey_y,
        sibling0,
        sibling1,
        direction0,
        direction1
    );

    assert(slot_index < quantity_threshold);
    assert(current_date <= expiry_date);

    let nullifier = nullifier_hash([
        patient_secret,
        commitment,
        Field::from(slot_index)
    ]);

    [commitment, nullifier]
}
