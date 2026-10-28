// Input tree layout:
//
// tree[0] = leaf0
// tree[1] = leaf1
// tree[2] = leaf2
// tree[3] = leaf3
// tree[4] = node0
// tree[5] = node1
// tree[6] = root
//
// Returns:
//
// [ selected_leaf,
//   sibling0,
//   sibling1,
//   direction0,
//   direction1,
//   root ]
//
// direction:
// 0 = current node is LEFT
// 1 = current node is RIGHT

pub fn authentication_path(
    doctor_index: u32,
    tree: [Field; 7],
) -> [Field; 6] {

    if doctor_index == 0 {
        [
            tree[0],
            tree[1],
            tree[5],
            0,
            0,
            tree[6],
        ]
    } else if doctor_index == 1 {
        [
            tree[1],
            tree[0],
            tree[5],
            1,
            0,
            tree[6],
        ]
    } else if doctor_index == 2 {
        [
            tree[2],
            tree[3],
            tree[4],
            0,
            1,
            tree[6],
        ]
    } else {
        [
            tree[3],
            tree[2],
            tree[4],
            1,
            1,
            tree[6],
        ]
    }
}
