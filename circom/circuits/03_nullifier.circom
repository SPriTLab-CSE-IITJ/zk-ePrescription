pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";

template Nullifier() {
    signal input patient_secret;
    signal input commitment;
    signal input slot_index;

    signal output nullifier;

    component poseidon = Poseidon(3);

    poseidon.inputs[0] <== patient_secret;
    poseidon.inputs[1] <== commitment;
    poseidon.inputs[2] <== slot_index;

    nullifier <== poseidon.out;
}

component main = Nullifier();