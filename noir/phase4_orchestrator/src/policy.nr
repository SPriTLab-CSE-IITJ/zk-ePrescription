pub fn evaluate_policy(
    quantity_threshold: u64,
    slot_index: u64,
    expiry_date: u64,
    current_date: u64,
) -> [bool; 2] {

    let quantity_valid = slot_index < quantity_threshold;

    let expiry_valid = current_date <= expiry_date;

    [
        quantity_valid,
        expiry_valid,
    ]
}
