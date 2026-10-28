use common::poseidon2_hash::nullifier_hash;

/// Assembles the final public outputs of the orchestrator.
/// Computes the replay-protection nullifier and returns
/// the public outputs expected by the verifier.

pub fn finalize_outputs(
    commitment: Field,
    patient_secret: Field,
    slot_index: u64,
) -> [Field; 2] {

    let nullifier = nullifier_hash([
        patient_secret,
        commitment,
        slot_index as Field,
    ]);

    [
        commitment,
        nullifier,
    ]
}
