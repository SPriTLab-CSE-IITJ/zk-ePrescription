use crate::bjj_core::{Curve, Point, SUBORDER};
use common::poseidon2_hash::poseidon2_hash_raw;


/// BabyJubJub EdDSA verification wrapper.
pub fn verify_signature(
    commitment: Field,
    doctor_pubkey_x: Field,
    doctor_pubkey_y: Field,
    signature_nonce_x: Field,
    signature_nonce_y: Field,
    signature_s: Field,
) -> bool {
    let curve = Curve::new();

    let pub_key = Point::new(doctor_pubkey_x, doctor_pubkey_y);
    let signature_r8 = Point::new(signature_nonce_x, signature_nonce_y);

    assert(curve.contains(pub_key));
    assert(curve.contains(signature_r8));
    assert(signature_s.lt(SUBORDER));

    let challenge = poseidon2_hash_raw([
        signature_nonce_x,
        signature_nonce_y,
        doctor_pubkey_x,
        doctor_pubkey_y,
        commitment,
    ]);

    let left = curve.scalar_mul(
        Curve::generator().into_group(),
        signature_s,
    );

    let pub_key_8 = curve.double(curve.double(curve.double(pub_key.into_group())));
    assert(!pub_key_8.is_zero());

    let right = curve.add(
        signature_r8.into_group(),
        curve.scalar_mul(pub_key_8, challenge),
    );

    left.into_affine().equals(right.into_affine())
}
