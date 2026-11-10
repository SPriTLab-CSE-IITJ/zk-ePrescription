use common::poseidon2_hash::nullifier_hash;

/// Assembles the final public outputs of the orchestrator.
/// Computes the replay-protection nullifier and returns the public outputs
/// expected by the verifier: [C, N, D] (protocol v3). D is the signed
/// medication-list digest, against which the pharmacy checks the list it is
/// shown (docs/protocol_specification.md, Sections 6.1 and 15.2).

pub fn finalize_outputs(
    commitment: Field,
    medication_digest: Field,
    patient_secret: Field,
    slot_index: u64,
) -> [Field; 3] {

    let nullifier = nullifier_hash([
        patient_secret,
        commitment,
        slot_index as Field,
    ]);

    [
        commitment,
        nullifier,
        medication_digest,
    ]
}
