pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";

template IdentityBinding() {

    signal input patient_secret;

    signal output identity_ref;

    component poseidon = Poseidon(1);

    poseidon.inputs[0] <== patient_secret;

    identity_ref <== poseidon.out;
}

component main = IdentityBinding();