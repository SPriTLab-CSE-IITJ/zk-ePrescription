pub fn verify_doctor_membership(
    registry_root: Field,
    doctor_id: Field,
    pubkey_x: Field,
    pubkey_y: Field,
    sibling0: Field,
    sibling1: Field,
    direction0: bool,
    direction1: bool,
) {
    let leaf = crate::poseidon2_hash::registry_leaf_hash(doctor_id, pubkey_x, pubkey_y);

    let level0 = if direction0 {
        crate::poseidon2_hash::merkle_node_hash(sibling0, leaf)
    } else {
        crate::poseidon2_hash::merkle_node_hash(leaf, sibling0)
    };

    let computed_root = if direction1 {
        crate::poseidon2_hash::merkle_node_hash(sibling1, level0)
    } else {
        crate::poseidon2_hash::merkle_node_hash(level0, sibling1)
    };

    assert(computed_root == registry_root);
}
