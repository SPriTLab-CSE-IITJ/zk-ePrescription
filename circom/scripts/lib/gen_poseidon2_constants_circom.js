// Generates circuits/poseidon2_constants.circom from scripts/lib/poseidon2_constants.json.
// Usage: node scripts/lib/gen_poseidon2_constants_circom.js > circuits/poseidon2_constants.circom
"use strict";
const C = require("./poseidon2_constants.json");
const dec = (h) => BigInt(h).toString();
let out = "";
out += "pragma circom 2.1.6;\n\n";
out += "// GENERATED FILE - do not edit by hand.\n";
out += "// Generator: circom/scripts/lib/gen_poseidon2_constants_circom.js\n";
out += "// Source   : circom/scripts/lib/poseidon2_constants.json\n";
out += "// " + C._provenance + "\n";
out += `// BN254 Poseidon2, t=${C.t}, R_F=${C.rounds_f}, R_P=${C.rounds_p}, S-box ${C.sbox}\n\n`;
out += "function POSEIDON2_INTERNAL_DIAG() {\n    return [\n";
out += C.internal_matrix_diagonal.map((x) => "        " + dec(x)).join(",\n") + "\n    ];\n}\n\n";
out += "function POSEIDON2_RC() {\n    return [\n";
out += C.round_constants.map((r) => "        [" + r.map(dec).join(", ") + "]").join(",\n") + "\n    ];\n}\n";
process.stdout.write(out);
