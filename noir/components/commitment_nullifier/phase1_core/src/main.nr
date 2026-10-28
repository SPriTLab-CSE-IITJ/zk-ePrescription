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
    patient_secret: Field,
    slot_index: Field
) -> pub [Field; 2] {

    // Commitment to prescription contents
    let commitment = commitment_hash([
        prescription_id,
        doctor_id,
        medicine_code
    ]);

    // Identity binding (kept internal, not public)
    let _identity_ref = identity_hash([
        patient_secret
    ]);

    // Replay protection nullifier
    let nullifier = nullifier_hash([
        patient_secret,
        commitment,
        slot_index
    ]);

    [
        commitment,
        nullifier
    ]
}
