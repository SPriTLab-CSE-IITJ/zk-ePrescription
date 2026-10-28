use crate::poseidon2_hash::{
    registry_leaf_hash,
    merkle_node_hash,
};

// Returns:
// [leaf0, leaf1, leaf2, leaf3, node0, node1, root]
pub fn build_tree(
    doctor1_id: Field,
    doctor1_pubkey_x: Field,
    doctor1_pubkey_y: Field,

    doctor2_id: Field,
    doctor2_pubkey_x: Field,
    doctor2_pubkey_y: Field,

    doctor3_id: Field,
    doctor3_pubkey_x: Field,
    doctor3_pubkey_y: Field,

    doctor4_id: Field,
    doctor4_pubkey_x: Field,
    doctor4_pubkey_y: Field,
) -> [Field; 7] {

    let leaf0 = registry_leaf_hash(
        doctor1_id,
        doctor1_pubkey_x,
        doctor1_pubkey_y,
    );

    let leaf1 = registry_leaf_hash(
        doctor2_id,
        doctor2_pubkey_x,
        doctor2_pubkey_y,
    );

    let leaf2 = registry_leaf_hash(
        doctor3_id,
        doctor3_pubkey_x,
        doctor3_pubkey_y,
    );

    let leaf3 = registry_leaf_hash(
        doctor4_id,
        doctor4_pubkey_x,
        doctor4_pubkey_y,
    );

    let node0 = merkle_node_hash(
        leaf0,
        leaf1,
    );

    let node1 = merkle_node_hash(
        leaf2,
        leaf3,
    );

    let root = merkle_node_hash(
        node0,
        node1,
    );

    [
        leaf0,
        leaf1,
        leaf2,
        leaf3,
        node0,
        node1,
        root,
    ]
}
