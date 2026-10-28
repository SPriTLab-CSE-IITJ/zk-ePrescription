pragma circom 2.1.6;

// Integrated Phase-4 redemption circuit (Circom / Groth16).
// Implements the Phase-4 redemption statement of
// docs/protocol_specification.md (Section 16), identical in logic to
// noir/redemption.
//
// Public signals (snarkjs order): [commitment_out, nullifier_out, current_date, root]

include "lib_modules.circom";

template EPrescriptionMain(DEPTH) {
    // Prescription
    signal input prescription_id;
    signal input doctor_id;
    signal input medicine_code;
    signal input expiry;
    signal input threshold;

    // Verifier-supplied policy input (public)
    signal input current_date;

    // Patient (private)
    signal input patient_secret;
    signal input slot_index;

    // Registry (root public)
    signal input pathElements[DEPTH];
    signal input pathIndices[DEPTH];
    signal input root;

    // Doctor public key and signature
    signal input PKx;
    signal input PKy;
    signal input Rx;
    signal input Ry;
    signal input s;

    signal output commitment_out;
    signal output nullifier_out;

    // 1. Commitment C = H1(pid, did, med, expiry, threshold)
    component commitment = Commitment();
    commitment.prescription_id <== prescription_id;
    commitment.doctor_id <== doctor_id;
    commitment.medicine_code <== medicine_code;
    commitment.expiry <== expiry;
    commitment.threshold <== threshold;
    commitment_out <== commitment.commitment;

    // 2. Policy
    component threshold_check = ThresholdCheck();
    threshold_check.slot_index <== slot_index;
    threshold_check.threshold <== threshold;
    threshold_check.valid === 1;

    component expiry_check = ExpiryCheck();
    expiry_check.current_date <== current_date;
    expiry_check.expiry <== expiry;
    expiry_check.valid === 1;

    // 3. Registry membership of L = H4(doctor_id, PKx, PKy)
    component registry = DoctorRegistry(DEPTH);
    registry.doctor_id <== doctor_id;
    registry.pubkey_x <== PKx;
    registry.pubkey_y <== PKy;
    registry.root <== root;
    for (var i = 0; i < DEPTH; i++) {
        registry.pathElements[i] <== pathElements[i];
        registry.pathIndices[i] <== pathIndices[i];
    }
    registry.valid === 1;

    // 4-5. Schnorr signature over C under the SAME (PKx, PKy)
    component sig = SchnorrBJJ();
    sig.Rx <== Rx;
    sig.Ry <== Ry;
    sig.PKx <== PKx;
    sig.PKy <== PKy;
    sig.C <== commitment.commitment;
    sig.s <== s;
    sig.valid === 1;

    // 6-7. Nullifier N = H3(patient_secret, C, slot_index)
    component nullifier = Nullifier();
    nullifier.patient_secret <== patient_secret;
    nullifier.commitment <== commitment.commitment;
    nullifier.slot_index <== slot_index;
    nullifier_out <== nullifier.nullifier;
}

// Canonical experimental fixture: 4 doctors -> DEPTH = 2
// (fixture parameter, not a protocol constant; spec Section 11.1).
component main {public [current_date, root]} = EPrescriptionMain(2);
