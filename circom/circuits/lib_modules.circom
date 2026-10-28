pragma circom 2.1.6;

// Shared protocol modules for the integrated Phase-4 circuit.
// All protocol hashes use the canonical Poseidon2 construction
// (poseidon2.circom; docs/protocol_specification.md Sections 4-9).

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "poseidon2.circom";
include "06_schnorr_bjj.circom";
include "05_doctor_registry_merkle_lib.circom";

// C = H1(prescription_id, doctor_id, medicine_code, expiry, threshold)
template Commitment() {
    signal input prescription_id;
    signal input doctor_id;
    signal input medicine_code;
    signal input expiry;
    signal input threshold;

    signal output commitment;

    component h = H1Commitment();
    h.prescription_id <== prescription_id;
    h.doctor_id <== doctor_id;
    h.medicine_code <== medicine_code;
    h.expiry <== expiry;
    h.threshold <== threshold;

    commitment <== h.out;
}

// I = H2(patient_secret). Issuance-side only; not a Phase-4 public output.
template IdentityBinding() {
    signal input patient_secret;
    signal output identity_ref;

    component h = H2Identity();
    h.patient_secret <== patient_secret;
    identity_ref <== h.out;
}

// N = H3(patient_secret, C, slot_index)
template Nullifier() {
    signal input patient_secret;
    signal input commitment;
    signal input slot_index;

    signal output nullifier;

    component h = H3Nullifier();
    h.patient_secret <== patient_secret;
    h.commitment <== commitment;
    h.slot_index <== slot_index;

    nullifier <== h.out;
}

// Constrains `in` to the u64 range, matching Noir's u64 typing.
template RangeU64() {
    signal input in;
    component bits = Num2Bits(64);
    bits.in <== in;
}

// slot_index < threshold, both u64.
template ThresholdCheck() {
    signal input slot_index;
    signal input threshold;

    signal output valid;

    component rs = RangeU64();
    rs.in <== slot_index;
    component rt = RangeU64();
    rt.in <== threshold;

    component lessThan = LessThan(64);
    lessThan.in[0] <== slot_index;
    lessThan.in[1] <== threshold;

    valid <== lessThan.out;
}

// current_date <= expiry, both u64.
template ExpiryCheck() {
    signal input current_date;
    signal input expiry;

    signal output valid;

    component rc = RangeU64();
    rc.in <== current_date;
    component re = RangeU64();
    re.in <== expiry;

    component le = LessEqThan(64);
    le.in[0] <== current_date;
    le.in[1] <== expiry;

    valid <== le.out;
}
