// Cross-backend known-answer-test harness (not a protocol circuit).
//
// Mirrors circom/circuits/kat/kat_hashes.circom: returns the raw Poseidon2
// permutation, the project sponge for input lengths 1..7 and the protocol
// hashes H1..H6 so that `nargo execute` output can be compared with the
// Circom witness and the JS reference (scripts/kat/compare_kat.js).
//
// Output layout (17 elements):
//   [0..4)   permutation(perm_in)
//   [4..11)  Hraw(sponge_in[0..n]) for n = 1..7
//   11 H1(prescription_id, doctor_id, medicine_code, expiry, threshold) = C
//   12 H2(patient_secret)                                           = I
//   13 H3(patient_secret, C, slot_index)                            = N
//   14 H4(doctor_id, pubkey_x, pubkey_y)                            = L
//   15 H5(left, right)                                              = M
//   16 H6(I, C)                                                     = PB

use common::poseidon2_hash::{
    commitment_hash, identity_hash, merkle_node_hash, nullifier_hash,
    patient_binding_hash, poseidon2_hash_raw, registry_leaf_hash,
};

fn main(
    perm_in: [Field; 4],
    sponge_in: [Field; 7],
    prescription_id: Field,
    doctor_id: Field,
    medicine_code: Field,
    expiry: Field,
    threshold: Field,
    patient_secret: Field,
    slot_index: Field,
    pubkey_x: Field,
    pubkey_y: Field,
    left: Field,
    right: Field,
) -> pub [Field; 17] {
    let mut out: [Field; 17] = [0; 17];

    let p = std::hash::poseidon2_permutation(perm_in);
    for i in 0..4 {
        out[i] = p[i];
    }

    out[4] = poseidon2_hash_raw([sponge_in[0]]);
    out[5] = poseidon2_hash_raw([sponge_in[0], sponge_in[1]]);
    out[6] = poseidon2_hash_raw([sponge_in[0], sponge_in[1], sponge_in[2]]);
    out[7] = poseidon2_hash_raw([sponge_in[0], sponge_in[1], sponge_in[2], sponge_in[3]]);
    out[8] = poseidon2_hash_raw([sponge_in[0], sponge_in[1], sponge_in[2], sponge_in[3], sponge_in[4]]);
    out[9] = poseidon2_hash_raw([
        sponge_in[0], sponge_in[1], sponge_in[2], sponge_in[3], sponge_in[4], sponge_in[5],
    ]);
    out[10] = poseidon2_hash_raw(sponge_in);

    let c = commitment_hash([prescription_id, doctor_id, medicine_code, expiry, threshold]);
    let id = identity_hash([patient_secret]);
    out[11] = c;
    out[12] = id;
    out[13] = nullifier_hash([patient_secret, c, slot_index]);
    out[14] = registry_leaf_hash(doctor_id, pubkey_x, pubkey_y);
    out[15] = merkle_node_hash(left, right);
    out[16] = patient_binding_hash([id, c]);

    out
}
