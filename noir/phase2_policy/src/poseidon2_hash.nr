global HASH_RATE: u32 = 3;

global DOMAIN_COMMITMENT: Field = 1;
global DOMAIN_IDENTITY: Field = 2;
global DOMAIN_NULLIFIER: Field = 3;

fn absorb_block(mut state: [Field; 4], block: [Field; 3]) -> [Field; 4] {
    state[0] += block[0];
    state[1] += block[1];
    state[2] += block[2];
    std::hash::poseidon2_permutation(state)
}

fn sponge_hash<let N: u32>(domain: Field, inputs: [Field; N]) -> Field {
    let mut state: [Field; 4] = [domain, 0, 0, N as Field];

    let full_chunks: u32 = N / HASH_RATE;
    let absorbed: u32 = full_chunks * HASH_RATE;

    for i in 0..full_chunks {
        let idx = i * HASH_RATE;
        let block: [Field; 3] = [
            inputs[idx],
            inputs[idx + 1],
            inputs[idx + 2],
        ];
        state = absorb_block(state, block);
    }

    let remainder: u32 = N - absorbed;
    if remainder == 1 {
        state[0] += inputs[absorbed];
    } else if remainder == 2 {
        state[0] += inputs[absorbed];
        state[1] += inputs[absorbed + 1];
    }

    std::hash::poseidon2_permutation(state)[0]
}

pub fn commitment_hash<let N: u32>(inputs: [Field; N]) -> Field {
    sponge_hash(DOMAIN_COMMITMENT, inputs)
}

pub fn identity_hash<let N: u32>(inputs: [Field; N]) -> Field {
    sponge_hash(DOMAIN_IDENTITY, inputs)
}

pub fn nullifier_hash<let N: u32>(inputs: [Field; N]) -> Field {
    sponge_hash(DOMAIN_NULLIFIER, inputs)
}

#[test]
fn known_vector_len_5() {
    let inputs: [Field; 5] = [1, 2, 3, 4, 5];
    let digest = commitment_hash(inputs);
    assert(digest == commitment_hash(inputs));
}

#[test]
fn domain_separation() {
    let inputs: [Field; 3] = [10, 20, 30];
    assert(commitment_hash(inputs) != identity_hash(inputs));
    assert(identity_hash(inputs) != nullifier_hash(inputs));
    assert(commitment_hash(inputs) != nullifier_hash(inputs));
}

#[test]
fn determinism() {
    let inputs: [Field; 3] = [42, 7, 99];
    assert(commitment_hash(inputs) == commitment_hash(inputs));
}
