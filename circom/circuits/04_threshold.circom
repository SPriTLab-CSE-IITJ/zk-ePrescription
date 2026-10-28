pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/comparators.circom";

template ThresholdCheck() {

    signal input slot_index;
    signal input threshold;

    signal output valid;

    component lessThan = LessThan(32);

    lessThan.in[0] <== slot_index;
    lessThan.in[1] <== threshold;

    valid <== lessThan.out;
}

component main = ThresholdCheck();
