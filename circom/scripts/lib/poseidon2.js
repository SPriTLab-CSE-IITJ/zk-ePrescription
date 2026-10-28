// Reference (off-circuit) implementation of the canonical protocol hash
// construction defined in docs/protocol_specification.md, Sections 4-5.
//
// - BN254 scalar field, Poseidon2 permutation, t = 4, x^5 S-box,
//   8 full + 56 partial rounds, constants from poseidon2_constants.json
//   (extracted verbatim from Noir's std::hash::poseidon2_permutation solver).
// - Sponge: state [0,0,0, n*2^64], rate 3, permute after each full block,
//   absorb remainder, final permutation, output state[0].
// - Domain-tagged hashes H1..H6 prepend the domain identifier.
//
// This file mirrors noir/common/src/poseidon2_hash.nr and
// circom/circuits/poseidon2.circom. It is used by fixture generators and by
// the cross-backend known-answer tests; it is NOT trusted on its own: its
// outputs are checked against Noir execution and Circom witnesses.

"use strict";

const C = require("./poseidon2_constants.json");

const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

const mod = (a) => ((a % P) + P) % P;
const RC = C.round_constants.map((r) => r.map(BigInt));
const DIAG = C.internal_matrix_diagonal.map(BigInt);
const RF = C.rounds_f;
const RP = C.rounds_p;

function sbox(x) {
    const s = (x * x) % P;
    return (((s * s) % P) * x) % P;
}

// External 4x4 MDS layer exactly as in Barretenberg / ACVM.
function matMul4(st) {
    const [a, b, c, d] = st;
    const t0 = a + b;
    const t1 = c + d;
    const t2 = b + b + t1;
    const t3 = d + d + t0;
    const t4 = 4n * t1 + t3;
    const t5 = 4n * t0 + t2;
    const t6 = t3 + t5;
    const t7 = t2 + t4;
    return [mod(t6), mod(t5), mod(t7), mod(t4)];
}

function internalMul(st) {
    const sum = st.reduce((x, y) => x + y, 0n);
    return st.map((x, i) => mod(x * DIAG[i] + sum));
}

function permutation(input) {
    if (input.length !== 4) throw new Error("permutation expects 4 elements");
    let st = matMul4(input.map((x) => mod(BigInt(x))));
    const half = RF / 2;
    for (let r = 0; r < half; r++) {
        st = matMul4(st.map((x, i) => sbox(mod(x + RC[r][i]))));
    }
    for (let r = half; r < half + RP; r++) {
        st[0] = sbox(mod(st[0] + RC[r][0]));
        st = internalMul(st);
    }
    for (let r = half + RP; r < RF + RP; r++) {
        st = matMul4(st.map((x, i) => sbox(mod(x + RC[r][i]))));
    }
    return st;
}

const TWO64 = 1n << 64n;

// Hraw: project sponge (docs/protocol_specification.md Section 4.1).
function hashRaw(inputs) {
    const xs = inputs.map((x) => mod(BigInt(x)));
    const n = BigInt(xs.length);
    let st = [0n, 0n, 0n, mod(n * TWO64)];
    const full = Math.floor(xs.length / 3);
    for (let i = 0; i < full; i++) {
        for (let j = 0; j < 3; j++) st[j] = mod(st[j] + xs[3 * i + j]);
        st = permutation(st);
    }
    const absorbed = full * 3;
    for (let j = 0; j < xs.length - absorbed; j++) st[j] = mod(st[j] + xs[absorbed + j]);
    return permutation(st)[0];
}

const DOMAIN = {
    COMMITMENT: 1n,
    IDENTITY: 2n,
    NULLIFIER: 3n,
    REGISTRY_LEAF: 4n,
    MERKLE_NODE: 5n,
    PATIENT_BINDING: 6n,
};

const tagged = (d, xs) => hashRaw([d, ...xs]);

module.exports = {
    P,
    permutation,
    hashRaw,
    DOMAIN,
    H1: (pid, did, med, expiry, threshold) => tagged(DOMAIN.COMMITMENT, [pid, did, med, expiry, threshold]),
    H2: (secret) => tagged(DOMAIN.IDENTITY, [secret]),
    H3: (secret, c, slot) => tagged(DOMAIN.NULLIFIER, [secret, c, slot]),
    H4: (did, pkx, pky) => tagged(DOMAIN.REGISTRY_LEAF, [did, pkx, pky]),
    H5: (left, right) => tagged(DOMAIN.MERKLE_NODE, [left, right]),
    H6: (i, c) => tagged(DOMAIN.PATIENT_BINDING, [i, c]),
    challenge: (rx, ry, pkx, pky, c) => hashRaw([rx, ry, pkx, pky, c]),
};
