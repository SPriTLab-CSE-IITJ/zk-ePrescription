pragma circom 2.1.6;

// Authorized-doctor registry membership
// (docs/protocol_specification.md, Sections 10-12).
//
//   L = H4(doctor_id, pubkey_x, pubkey_y)     computed inside the circuit
//   M = H5(left, right)
//
// The leaf is never supplied by the prover: it is derived from the same
// doctor_id and public-key signals that the caller passes to Schnorr
// verification. The verifier is generic over DEPTH.
//
// pathIndices[i] = 0: current node is the left child
// pathIndices[i] = 1: current node is the right child

include "poseidon2.circom";

template DoctorRegistry(DEPTH) {
    signal input doctor_id;
    signal input pubkey_x;
    signal input pubkey_y;
    signal input pathElements[DEPTH];
    signal input pathIndices[DEPTH];
    signal input root;

    signal output valid;

    signal currentHash[DEPTH + 1];
    signal left[DEPTH];
    signal right[DEPTH];
    signal leftA[DEPTH];
    signal leftB[DEPTH];
    signal rightA[DEPTH];
    signal rightB[DEPTH];

    component leaf = H4RegistryLeaf();
    leaf.doctor_id <== doctor_id;
    leaf.pubkey_x <== pubkey_x;
    leaf.pubkey_y <== pubkey_y;

    component hash[DEPTH];

    currentHash[0] <== leaf.out;

    for (var i = 0; i < DEPTH; i++) {
        pathIndices[i] * (pathIndices[i] - 1) === 0;

        leftA[i] <== currentHash[i] * (1 - pathIndices[i]);
        leftB[i] <== pathElements[i] * pathIndices[i];
        left[i] <== leftA[i] + leftB[i];

        rightA[i] <== currentHash[i] * pathIndices[i];
        rightB[i] <== pathElements[i] * (1 - pathIndices[i]);
        right[i] <== rightA[i] + rightB[i];

        hash[i] = H5MerkleNode();
        hash[i].left <== left[i];
        hash[i].right <== right[i];

        currentHash[i + 1] <== hash[i].out;
    }

    currentHash[DEPTH] === root;
    valid <== 1;
}
