pragma circom 2.1.6;

// BabyJubJub Schnorr verification for the protocol relation
// (docs/protocol_specification.md, Section 13):
//
//     c  = Hraw(Rx, Ry, PKx, PKy, C)      project Poseidon2 sponge, no domain tag
//     s * B8 == R + c * (8 * PK)
//
// with the validity conditions
//     PK on curve, 8 * PK != identity, R on curve, s < l,
// and the challenge c used as a full 254-bit field element.
//
// This matches noir/redemption/src/schnorr.nr exactly.
//
// History: the previous Circom version used circomlib Poseidon v1 for c,
// omitted the 8x cofactor term, had no s < l bound (malleable: s and s + l
// both verified), and decomposed c with Num2Bits(253), which rejects valid
// signatures whenever c >= 2^253 (a completeness bug).

include "../node_modules/circomlib/circuits/babyjub.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/compconstant.circom";
include "../node_modules/circomlib/circuits/escalarmulany.circom";
include "../node_modules/circomlib/circuits/escalarmulfix.circom";
include "poseidon2.circom";

template SchnorrBJJ() {
    signal input Rx;
    signal input Ry;
    signal input PKx;
    signal input PKy;
    signal input C;
    signal input s;

    signal output valid;

    // R and PK must be BabyJubJub points.
    component checkR = BabyCheck();
    checkR.x <== Rx;
    checkR.y <== Ry;

    component checkPK = BabyCheck();
    checkPK.x <== PKx;
    checkPK.y <== PKy;

    // Scalar bound: s < l  (l = BabyJubJub prime subgroup order).
    component sBits = Num2Bits(253);
    sBits.in <== s;

    component sBound = CompConstant(2736030358979909402780800718157159386076813972158567259200215660948447373040);
    for (var i = 0; i < 253; i++) {
        sBound.in[i] <== sBits.out[i];
    }
    sBound.in[253] <== 0;
    sBound.out === 0;

    // Challenge c = Hraw(Rx, Ry, PKx, PKy, C), full field element.
    component h = Poseidon2Sponge(5);
    h.in[0] <== Rx;
    h.in[1] <== Ry;
    h.in[2] <== PKx;
    h.in[3] <== PKy;
    h.in[4] <== C;

    component cBits = Num2Bits_strict();
    cBits.in <== h.out;

    // 8 * PK, which must not be the identity (x == 0 <=> identity for 8*PK).
    component dbl1 = BabyDbl();
    dbl1.x <== PKx;
    dbl1.y <== PKy;
    component dbl2 = BabyDbl();
    dbl2.x <== dbl1.xout;
    dbl2.y <== dbl1.yout;
    component dbl3 = BabyDbl();
    dbl3.x <== dbl2.xout;
    dbl3.y <== dbl2.yout;

    component pk8IsZero = IsZero();
    pk8IsZero.in <== dbl3.xout;
    pk8IsZero.out === 0;

    // c * (8 * PK)
    component cPK8 = EscalarMulAny(254);
    for (var i = 0; i < 254; i++) {
        cPK8.e[i] <== cBits.out[i];
    }
    cPK8.p[0] <== dbl3.xout;
    cPK8.p[1] <== dbl3.yout;

    // s * B8
    var BASE8[2] = [
        5299619240641551281634865583518297030282874472190772894086521144482721001553,
        16950150798460657717958625567821834550301663161624707787222815936182638968203
    ];
    component sG = EscalarMulFix(253, BASE8);
    for (var i = 0; i < 253; i++) {
        sG.e[i] <== sBits.out[i];
    }

    // R + c * (8 * PK)
    component rhs = BabyAdd();
    rhs.x1 <== Rx;
    rhs.y1 <== Ry;
    rhs.x2 <== cPK8.out[0];
    rhs.y2 <== cPK8.out[1];

    sG.out[0] === rhs.xout;
    sG.out[1] === rhs.yout;

    valid <== 1;
}
