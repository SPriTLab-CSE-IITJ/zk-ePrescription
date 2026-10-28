use common::poseidon2_hash::{
    registry_leaf_hash,
    merkle_node_hash,
};

fn dual_mux(input: [Field; 2], s: Field) -> [Field; 2] {
    assert(s * (1 - s) == 0);
    let out0 = (input[1] - input[0]) * s + input[0];
    let out1 = (input[0] - input[1]) * s + input[1];
    [out0, out1]
}

/// Verifies that the doctor's public key is a member of the
/// authorized registry root using an array-based Merkle path.
///
/// `path_indices[i]` must be 0 or 1, where:
/// - 0 means current_hash is on the left
/// - 1 means current_hash is on the right
pub fn verify_registry<let DEPTH: u32>(
    registry_root: Field,
    doctor_id: Field,
    doctor_pubkey_x: Field,
    doctor_pubkey_y: Field,
    path_elements: [Field; DEPTH],
    path_indices: [Field; DEPTH],
) -> bool {
    let mut current_hash = registry_leaf_hash(
        doctor_id,
        doctor_pubkey_x,
        doctor_pubkey_y,
    );

    for i in 0..DEPTH {
        let muxed = dual_mux([current_hash, path_elements[i]], path_indices[i]);
        current_hash = merkle_node_hash(muxed[0], muxed[1]);
    }

    current_hash == registry_root
}
