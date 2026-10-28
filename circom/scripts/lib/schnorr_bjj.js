// Off-circuit BabyJubJub Schnorr signer / verifier for the protocol relation
// (docs/protocol_specification.md, Section 13):
//
//     c  = Hraw(Rx, Ry, PKx, PKy, C)          (project Poseidon2 sponge, no tag)
//     sG = R + 8 * c * PK                      (G = Base8, s < l)
//
// Curve arithmetic is circomlibjs' BabyJubJub implementation (existing
// repository dependency). Keys follow the repository's development-key
// convention PK = sk * Generator (circomlib full generator, order 8l), so that
// 8 * PK = sk * Base8. Signing therefore uses s = r + c * sk (mod l).
//
// TEST KEYS ONLY. The nonce r is derived deterministically from (sk, C) with
// the project sponge so that fixtures are reproducible; this is NOT a
// production nonce-derivation scheme.

"use strict";

const { buildBabyjub } = require("circomlibjs");
const p2 = require("./poseidon2");

const NONCE_DOMAIN = 0x6e6f6e6365n; // ASCII "nonce"; fixture-only derivation tag

async function babyjub() {
    const bj = await buildBabyjub();
    const F = bj.F;
    const toBig = (pt) => [F.toObject(pt[0]), F.toObject(pt[1])];
    const fromBig = (pt) => [F.e(pt[0]), F.e(pt[1])];
    const l = bj.subOrder;

    function publicKey(sk) {
        return toBig(bj.mulPointEscalar(bj.Generator, BigInt(sk)));
    }

    function isValidPublicKey(pk) {
        const P = fromBig(pk);
        if (!bj.inCurve(P)) return false;
        const P8 = bj.mulPointEscalar(P, 8n);
        return !(F.isZero(P8[0]) && F.eq(P8[1], F.one));
    }

    function sign(sk, C) {
        sk = BigInt(sk);
        const pk = publicKey(sk);
        const r = p2.hashRaw([NONCE_DOMAIN, sk, BigInt(C)]) % l;
        const R = toBig(bj.mulPointEscalar(bj.Base8, r));
        const c = p2.challenge(R[0], R[1], pk[0], pk[1], BigInt(C));
        const s = (r + (c % l) * sk) % l;
        return { R, s, c, pk };
    }

    function verify(pk, C, R, s) {
        s = BigInt(s);
        if (s >= l) return false;
        if (!isValidPublicKey(pk)) return false;
        const Rp = fromBig(R);
        if (!bj.inCurve(Rp)) return false;
        const c = p2.challenge(R[0], R[1], pk[0], pk[1], BigInt(C));
        const lhs = bj.mulPointEscalar(bj.Base8, s);
        const pk8 = bj.mulPointEscalar(fromBig(pk), 8n);
        const rhs = bj.addPoint(Rp, bj.mulPointEscalar(pk8, c));
        return F.eq(lhs[0], rhs[0]) && F.eq(lhs[1], rhs[1]);
    }

    return { bj, F, l, publicKey, isValidPublicKey, sign, verify, inCurve: (pt) => bj.inCurve(fromBig(pt)) };
}

module.exports = { babyjub };
