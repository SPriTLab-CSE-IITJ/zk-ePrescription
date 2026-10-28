pragma circom 2.1.6;

// Cross-backend known-answer-test harness (not a protocol circuit).
// Exposes the raw permutation, the sponge for input lengths 1..7 and
// the domain-tagged protocol hashes H1..H6 as outputs so that they can be
// compared against the Noir backend and the JS reference implementation.

include "../poseidon2.circom";

template KatHashes() {
    signal input perm_in[4];
    signal input sponge_in[7];

    signal input prescription_id;
    signal input doctor_id;
    signal input medicine_code;
    signal input expiry;
    signal input threshold;
    signal input patient_secret;
    signal input slot_index;
    signal input pubkey_x;
    signal input pubkey_y;
    signal input left;
    signal input right;

    signal output perm_out[4];
    signal output sponge_out[7];
    signal output h1;
    signal output h2;
    signal output h3;
    signal output h4;
    signal output h5;
    signal output h6;

    component p = Poseidon2Permutation();
    for (var i = 0; i < 4; i++) { p.in[i] <== perm_in[i]; }
    for (var i = 0; i < 4; i++) { perm_out[i] <== p.out[i]; }

    component s1 = Poseidon2Sponge(1); s1.in[0] <== sponge_in[0]; sponge_out[0] <== s1.out;
    component s2 = Poseidon2Sponge(2); for (var i = 0; i < 2; i++) { s2.in[i] <== sponge_in[i]; } sponge_out[1] <== s2.out;
    component s3 = Poseidon2Sponge(3); for (var i = 0; i < 3; i++) { s3.in[i] <== sponge_in[i]; } sponge_out[2] <== s3.out;
    component s4 = Poseidon2Sponge(4); for (var i = 0; i < 4; i++) { s4.in[i] <== sponge_in[i]; } sponge_out[3] <== s4.out;
    component s5 = Poseidon2Sponge(5); for (var i = 0; i < 5; i++) { s5.in[i] <== sponge_in[i]; } sponge_out[4] <== s5.out;
    component s6 = Poseidon2Sponge(6); for (var i = 0; i < 6; i++) { s6.in[i] <== sponge_in[i]; } sponge_out[5] <== s6.out;
    component s7 = Poseidon2Sponge(7); for (var i = 0; i < 7; i++) { s7.in[i] <== sponge_in[i]; } sponge_out[6] <== s7.out;

    component c = H1Commitment();
    c.prescription_id <== prescription_id;
    c.doctor_id <== doctor_id;
    c.medicine_code <== medicine_code;
    c.expiry <== expiry;
    c.threshold <== threshold;
    h1 <== c.out;

    component id = H2Identity();
    id.patient_secret <== patient_secret;
    h2 <== id.out;

    component n = H3Nullifier();
    n.patient_secret <== patient_secret;
    n.commitment <== c.out;
    n.slot_index <== slot_index;
    h3 <== n.out;

    component l = H4RegistryLeaf();
    l.doctor_id <== doctor_id;
    l.pubkey_x <== pubkey_x;
    l.pubkey_y <== pubkey_y;
    h4 <== l.out;

    component m = H5MerkleNode();
    m.left <== left;
    m.right <== right;
    h5 <== m.out;

    component pb = H6PatientBinding();
    pb.identity <== id.out;
    pb.commitment <== c.out;
    h6 <== pb.out;
}

component main = KatHashes();
