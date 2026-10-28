pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";

template MerkleProof(DEPTH) {

    signal input leaf;
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

    component hash[DEPTH];

    currentHash[0] <== leaf;

    for (var i = 0; i < DEPTH; i++) {

        // Direction must be 0 or 1
        pathIndices[i] * (pathIndices[i] - 1) === 0;

        // left = currentHash when direction = 0
        // left = sibling when direction = 1
        leftA[i] <== currentHash[i] * (1 - pathIndices[i]);
        leftB[i] <== pathElements[i] * pathIndices[i];

        left[i] <== leftA[i] + leftB[i];

        // right = sibling when direction = 0
        // right = currentHash when direction = 1
        rightA[i] <== currentHash[i] * pathIndices[i];
        rightB[i] <== pathElements[i] * (1 - pathIndices[i]);

        right[i] <== rightA[i] + rightB[i];

        // Hash left || right
        hash[i] = Poseidon(2);

        hash[i].inputs[0] <== left[i];
        hash[i].inputs[1] <== right[i];

        currentHash[i + 1] <== hash[i].out;
    }

    // Calculated root must equal supplied root
    currentHash[DEPTH] === root;

    valid <== 1;
}

component main {public [root]} = MerkleProof(2);
