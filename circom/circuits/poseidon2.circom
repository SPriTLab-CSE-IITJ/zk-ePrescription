pragma circom 2.1.6;

// Canonical protocol hash construction for the Circom backend
// (docs/protocol_specification.md, Sections 4-5).
//
//   * Poseidon2 permutation over the BN254 scalar field, t = 4,
//     x^5 S-box, 8 full + 56 partial rounds. Linear layers and round
//     constants are identical to Noir's std::hash::poseidon2_permutation
//     (ACVM bn254_blackbox_solver / Barretenberg).
//   * Sponge Hraw: state [0, 0, 0, n * 2^64], rate 3, permutation after each
//     complete block, remainder absorbed, final permutation, output state[0].
//   * Domain-tagged hashes Hd(x_1..x_k) = Hraw(d, x_1, ..., x_k).
//
// Equality with the Noir implementation is established by the cross-backend
// known-answer tests (scripts/kat/), not assumed.

include "poseidon2_constants.circom";

// x^5
template Poseidon2SBox() {
    signal input in;
    signal output out;
    signal x2;
    signal x4;
    x2 <== in * in;
    x4 <== x2 * x2;
    out <== x4 * in;
}

function poseidon2_ext_mds(s) {
    var t0 = s[0] + s[1];
    var t1 = s[2] + s[3];
    var t2 = 2 * s[1] + t1;
    var t3 = 2 * s[3] + t0;
    var t4 = 4 * t1 + t3;
    var t5 = 4 * t0 + t2;
    var t6 = t3 + t5;
    var t7 = t2 + t4;
    return [t6, t5, t7, t4];
}

template Poseidon2Permutation() {
    signal input in[4];
    signal output out[4];

    var RF = 8;
    var RP = 56;
    var RC[64][4] = POSEIDON2_RC();
    var DIAG[4] = POSEIDON2_INTERNAL_DIAG();

    // Number of S-box applications: RF * 4 + RP.
    component sb[RF * 4 + RP];
    var k = 0;

    var st[4];
    for (var i = 0; i < 4; i++) {
        st[i] = in[i];
    }

    // Initial external linear layer.
    st = poseidon2_ext_mds(st);

    // First half of full rounds.
    for (var r = 0; r < RF / 2; r++) {
        for (var i = 0; i < 4; i++) {
            sb[k] = Poseidon2SBox();
            sb[k].in <== st[i] + RC[r][i];
            st[i] = sb[k].out;
            k++;
        }
        st = poseidon2_ext_mds(st);
    }

    // Partial rounds.
    for (var r = RF / 2; r < RF / 2 + RP; r++) {
        sb[k] = Poseidon2SBox();
        sb[k].in <== st[0] + RC[r][0];
        st[0] = sb[k].out;
        k++;

        var sum = st[0] + st[1] + st[2] + st[3];
        for (var i = 0; i < 4; i++) {
            st[i] = st[i] * DIAG[i] + sum;
        }
    }

    // Second half of full rounds.
    for (var r = RF / 2 + RP; r < RF + RP; r++) {
        for (var i = 0; i < 4; i++) {
            sb[k] = Poseidon2SBox();
            sb[k].in <== st[i] + RC[r][i];
            st[i] = sb[k].out;
            k++;
        }
        st = poseidon2_ext_mds(st);
    }

    for (var i = 0; i < 4; i++) {
        out[i] <== st[i];
    }
}

// Hraw over N field elements (Section 4.1).
template Poseidon2Sponge(N) {
    signal input in[N];
    signal output out;

    var FULL = N \ 3;
    var REM = N - FULL * 3;
    var NUM_PERM = FULL + 1;

    component perm[NUM_PERM];

    var st[4] = [0, 0, 0, N * 18446744073709551616];

    for (var b = 0; b < FULL; b++) {
        perm[b] = Poseidon2Permutation();
        for (var j = 0; j < 3; j++) {
            perm[b].in[j] <== st[j] + in[3 * b + j];
        }
        perm[b].in[3] <== st[3];
        for (var j = 0; j < 4; j++) {
            st[j] = perm[b].out[j];
        }
    }

    for (var j = 0; j < REM; j++) {
        st[j] = st[j] + in[3 * FULL + j];
    }

    perm[FULL] = Poseidon2Permutation();
    for (var j = 0; j < 4; j++) {
        perm[FULL].in[j] <== st[j];
    }

    out <== perm[FULL].out[0];
}

// Hd(x_1..x_K) = Hraw(d, x_1, ..., x_K) (Section 4.2).
template Poseidon2Tagged(DOMAIN, K) {
    signal input in[K];
    signal output out;

    component h = Poseidon2Sponge(K + 1);
    h.in[0] <== DOMAIN;
    for (var i = 0; i < K; i++) {
        h.in[i + 1] <== in[i];
    }
    out <== h.out;
}

// Protocol hashes (Section 5).
template H1Commitment() {
    signal input prescription_id;
    signal input doctor_id;
    signal input medicine_code;
    signal input expiry;
    signal input threshold;
    signal output out;

    component h = Poseidon2Tagged(1, 5);
    h.in[0] <== prescription_id;
    h.in[1] <== doctor_id;
    h.in[2] <== medicine_code;
    h.in[3] <== expiry;
    h.in[4] <== threshold;
    out <== h.out;
}

template H2Identity() {
    signal input patient_secret;
    signal output out;

    component h = Poseidon2Tagged(2, 1);
    h.in[0] <== patient_secret;
    out <== h.out;
}

template H3Nullifier() {
    signal input patient_secret;
    signal input commitment;
    signal input slot_index;
    signal output out;

    component h = Poseidon2Tagged(3, 3);
    h.in[0] <== patient_secret;
    h.in[1] <== commitment;
    h.in[2] <== slot_index;
    out <== h.out;
}

template H4RegistryLeaf() {
    signal input doctor_id;
    signal input pubkey_x;
    signal input pubkey_y;
    signal output out;

    component h = Poseidon2Tagged(4, 3);
    h.in[0] <== doctor_id;
    h.in[1] <== pubkey_x;
    h.in[2] <== pubkey_y;
    out <== h.out;
}

template H5MerkleNode() {
    signal input left;
    signal input right;
    signal output out;

    component h = Poseidon2Tagged(5, 2);
    h.in[0] <== left;
    h.in[1] <== right;
    out <== h.out;
}

template H6PatientBinding() {
    signal input identity;
    signal input commitment;
    signal output out;

    component h = Poseidon2Tagged(6, 2);
    h.in[0] <== identity;
    h.in[1] <== commitment;
    out <== h.out;
}
