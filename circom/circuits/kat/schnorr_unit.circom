pragma circom 2.1.6;

// Isolated Schnorr verifier harness (not a protocol circuit). Used by
// scripts/circom_suite.sh with circom/inputs/unit/schnorr_canonical/*.json
// so that signature rejections are attributable to SchnorrBJJ alone.

include "../schnorr_bjj.circom";

component main = SchnorrBJJ();
