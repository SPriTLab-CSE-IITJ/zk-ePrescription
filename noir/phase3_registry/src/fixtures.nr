#[test]
fn registry_fixture_depth2_smoke() {
    let leaf0 = crate::poseidon2_hash::registry_leaf_hash(5001, 1111, 2222);
    let leaf1 = crate::poseidon2_hash::registry_leaf_hash(5002, 3333, 4444);
    let leaf2 = crate::poseidon2_hash::registry_leaf_hash(5003, 5555, 6666);
    let leaf3 = crate::poseidon2_hash::registry_leaf_hash(5004, 7777, 8888);

    let node0 = crate::poseidon2_hash::merkle_node_hash(leaf0, leaf1);
    let node1 = crate::poseidon2_hash::merkle_node_hash(leaf2, leaf3);
    let root = crate::poseidon2_hash::merkle_node_hash(node0, node1);

    assert(root != leaf0);
    assert(root != leaf1);
    assert(root != leaf2);
    assert(root != leaf3);
}
