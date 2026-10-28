mod poseidon2_hash;
mod tree_builder;
mod auth_path;

use tree_builder::build_tree;
use auth_path::authentication_path;

fn main(

    doctor1_id: Field,
    doctor1_pubkey_x: Field,
    doctor1_pubkey_y: Field,

    doctor2_id: Field,
    doctor2_pubkey_x: Field,
    doctor2_pubkey_y: Field,

    doctor3_id: Field,
    doctor3_pubkey_x: Field,
    doctor3_pubkey_y: Field,

    doctor4_id: Field,
    doctor4_pubkey_x: Field,
    doctor4_pubkey_y: Field,

    doctor_index: u32,

) -> pub [Field; 6] {

    let tree = build_tree(

        doctor1_id,
        doctor1_pubkey_x,
        doctor1_pubkey_y,

        doctor2_id,
        doctor2_pubkey_x,
        doctor2_pubkey_y,

        doctor3_id,
        doctor3_pubkey_x,
        doctor3_pubkey_y,

        doctor4_id,
        doctor4_pubkey_x,
        doctor4_pubkey_y,
    );

    authentication_path(
        doctor_index,
        tree,
    )
}
