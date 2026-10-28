pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";

template Commitment() {

    signal input prescription_id;
    signal input doctor_id;
    signal input medicine_code;
    signal input expiry;
    signal input threshold;

    signal output commitment;

    component poseidon = Poseidon(5);

    poseidon.inputs[0] <== prescription_id;
    poseidon.inputs[1] <== doctor_id;
    poseidon.inputs[2] <== medicine_code;
    poseidon.inputs[3] <== expiry;
    poseidon.inputs[4] <== threshold;

    commitment <== poseidon.out;
}

component main = Commitment();
