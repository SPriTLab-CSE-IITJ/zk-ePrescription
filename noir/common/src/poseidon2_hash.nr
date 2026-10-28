// poseidon2_hash.nr
//
// Shared Poseidon2 sponge implementation for the project.
// Milestone 1: sponge core
// Milestone 2: domain tags + generic tagged hash helper

global HASH_RATE: u32 = 3;

// -----------------------------------------------------------------------
// Shared Poseidon2 Sponge Core
// -----------------------------------------------------------------------

fn poseidon2_hash<let N: u32>(inputs: [Field; N]) -> Field {
    let iv: Field = (N as Field) * 18446744073709551616;
    let mut state: [Field; 4] = [0, 0, 0, iv];

    let full_chunks: u32 = N / HASH_RATE;

    for i in 0..full_chunks {
        state[0] += inputs[i * HASH_RATE];
        state[1] += inputs[i * HASH_RATE + 1];
        state[2] += inputs[i * HASH_RATE + 2];
        state = std::hash::poseidon2_permutation(state);
    }

    let absorbed: u32 = full_chunks * HASH_RATE;
    let remainder: u32 = N - absorbed;

    for i in 0..remainder {
        state[i] += inputs[absorbed + i];
    }

    std::hash::poseidon2_permutation(state)[0]
}

// -----------------------------------------------------------------------
// Domain separation
// -----------------------------------------------------------------------

global DOMAIN_COMMITMENT: Field = 1;
global DOMAIN_IDENTITY: Field = 2;
global DOMAIN_NULLIFIER: Field = 3;
global DOMAIN_REGISTRY_LEAF: Field = 4;
global DOMAIN_MERKLE_NODE: Field = 5;
global DOMAIN_PATIENT_BINDING: Field = 6;

fn domain_tagged_hash<let N: u32>(domain: Field, inputs: [Field; N]) -> Field {
    let mut tagged: [Field; N + 1] = [0; N + 1];
    tagged[0] = domain;

    for i in 0..N {
        tagged[i + 1] = inputs[i];
    }

    poseidon2_hash(tagged)
}

// -----------------------------------------------------------------------
// Public wrappers
// -----------------------------------------------------------------------

pub fn poseidon2_hash_raw<let N: u32>(inputs: [Field; N]) -> Field {
    poseidon2_hash(inputs)
}

pub fn commitment_hash<let N: u32>(inputs: [Field; N]) -> Field {
    domain_tagged_hash(DOMAIN_COMMITMENT, inputs)
}

pub fn identity_hash<let N: u32>(inputs: [Field; N]) -> Field {
    domain_tagged_hash(DOMAIN_IDENTITY, inputs)
}

pub fn nullifier_hash<let N: u32>(inputs: [Field; N]) -> Field {
    domain_tagged_hash(DOMAIN_NULLIFIER, inputs)
}

pub fn registry_leaf_hash(
    doctor_id: Field,
    pubkey_x: Field,
    pubkey_y: Field,
) -> Field {
    domain_tagged_hash(DOMAIN_REGISTRY_LEAF, [doctor_id, pubkey_x, pubkey_y])
}

pub fn merkle_node_hash(left: Field, right: Field) -> Field {
    domain_tagged_hash(DOMAIN_MERKLE_NODE, [left, right])
}

pub fn patient_binding_hash<let N: u32>(inputs: [Field; N]) -> Field {
    domain_tagged_hash(DOMAIN_PATIENT_BINDING, inputs)
}


// -----------------------------------------------------------------------
// Unit Tests
// -----------------------------------------------------------------------

mod tests {
    use super::{
        commitment_hash,
        identity_hash,
        merkle_node_hash,
        nullifier_hash,
        poseidon2_hash,
        registry_leaf_hash,
    };

    #[test]
    fn sponge_is_deterministic() {
        let inputs: [Field; 5] = [1, 2, 3, 4, 5];

        let a = poseidon2_hash(inputs);
        let b = poseidon2_hash(inputs);

        assert(a == b);
    }

    #[test]
    fn domain_separation_holds() {
        let inputs: [Field; 4] = [111, 222, 333, 444];

        let commitment = commitment_hash(inputs);
        let identity = identity_hash(inputs);
        let nullifier = nullifier_hash(inputs);

        assert(commitment != identity);
        assert(commitment != nullifier);
        assert(identity != nullifier);
    }

    #[test]
    fn registry_leaf_is_deterministic() {
        let a = registry_leaf_hash(1, 100, 200);
        let b = registry_leaf_hash(1, 100, 200);

        assert(a == b);

        let c = registry_leaf_hash(1, 100, 999);
        assert(a != c);

        let d = registry_leaf_hash(2, 100, 200);
        assert(a != d);
    }

    #[test]
    fn registry_leaf_and_node_are_different() {
        let leaf = registry_leaf_hash(10, 20, 30);
        let node = merkle_node_hash(10, 20);

        assert(leaf != node);
    }

    #[test]
    fn merkle_node_is_order_sensitive() {
        let left_right = merkle_node_hash(111, 222);
        let right_left = merkle_node_hash(222, 111);

        assert(left_right != right_left);
    }
}

#[test]
fn different_input_lengths_produce_different_hashes() {
    let a = commitment_hash([1, 2, 3]);
    let b = commitment_hash([1, 2, 3, 0]);

    assert(a != b);
}
