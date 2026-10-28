mod commitment;
mod policy;
mod registry;
mod schnorr;
mod outputs;
mod bjj_core;
mod fixture_tests;

use commitment::compute_commitment;
use policy::evaluate_policy;
use registry::verify_registry;
use schnorr::verify_signature;
use outputs::finalize_outputs;

// Merkle depth of the canonical experimental registry fixture
// (4 doctors -> depth 2; docs/protocol_specification.md Section 11.1).
// The registry verifier itself is generic over DEPTH; this constant is a
// fixture parameter, not a protocol constant.
global REGISTRY_DEPTH: u32 = 2;

fn main(
    registry_root: pub Field,

    prescription_id: Field,

    doctor_id: Field,
    doctor_pubkey_x: Field,
    doctor_pubkey_y: Field,

    medicine_code: Field,

    quantity_threshold: u64,
    expiry_date: u64,
    current_date: pub u64,

    patient_secret: Field,
    slot_index: u64,

    path_elements: [Field; REGISTRY_DEPTH],
    path_indices: [Field; REGISTRY_DEPTH],

    signature_nonce_x: Field,
    signature_nonce_y: Field,
    signature_s: Field,
) -> pub [Field; 2] {
    // ==========================================================
    // Phase 4 – Milestone 1
    // Commitment computation
    // ==========================================================

    let commitment = compute_commitment(
        prescription_id,
        doctor_id,
        medicine_code,
        expiry_date,
        quantity_threshold,
    );

    // ==========================================================
    // Selective disclosure
    // ==========================================================

    // ==========================================================
    // Phase 4 – Milestone 2
    // Policy evaluation
    // ==========================================================

    let policy_result = evaluate_policy(
        quantity_threshold,
        slot_index,
        expiry_date,
        current_date,
    );

    // ==========================================================
    // Phase 4 – Milestone 3
    // Registry verification
    // ==========================================================

    let registry_valid = verify_registry::<REGISTRY_DEPTH>(
        registry_root,
        doctor_id,
        doctor_pubkey_x,
        doctor_pubkey_y,
        path_elements,
        path_indices,
    );

    // ==========================================================
    // Phase 4 – Milestone 4
    // Schnorr verification
    // ==========================================================

    let signature_valid = verify_signature(
        commitment,
        doctor_pubkey_x,
        doctor_pubkey_y,
        signature_nonce_x,
        signature_nonce_y,
        signature_s,
    );

    // ==========================================================
    // Phase 4 – Milestone 5
    // Output assembly
    // ==========================================================

    let outputs = finalize_outputs(
        commitment,
        patient_secret,
        slot_index,
    );

    // ==========================================================
    // Final enforced constraints
    // ==========================================================

    assert(policy_result[0]);
    assert(policy_result[1]);
    assert(registry_valid);
    assert(signature_valid);

    outputs
}
