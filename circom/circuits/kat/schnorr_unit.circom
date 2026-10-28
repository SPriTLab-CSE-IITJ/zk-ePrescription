pragma circom 2.1.6;

// Isolated Schnorr verifier harness (not a protocol circuit). Used by
// circom/scripts/test_e2e.sh with circom/inputs/unit/schnorr_canonical/*.json
// so that signature rejections are attributable to SchnorrBJJ alone.

include "../06_schnorr_bjj.circom";

component main = SchnorrBJJ();
