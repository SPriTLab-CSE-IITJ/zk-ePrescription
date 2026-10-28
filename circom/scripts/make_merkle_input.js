const fs = require("fs");
const circomlib = require("circomlibjs");

async function main() {
  const poseidon = await circomlib.buildPoseidon();
  const F = poseidon.F;

  const leaf0 = F.toString(poseidon([5001]));
  const leaf1 = F.toString(poseidon([5002]));
  const leaf2 = F.toString(poseidon([5003]));
  const leaf3 = F.toString(poseidon([5004]));

  const h01 = F.toString(poseidon([leaf0, leaf1]));
  const h23 = F.toString(poseidon([leaf2, leaf3]));
  const root = F.toString(poseidon([h01, h23]));

  const input = {
    leaf: leaf0,
    pathElements: [leaf1, h23],
    pathIndices: [0, 0],
    root: root
  };

  fs.writeFileSync("inputs/merkle/merkle_depth2_leaf0.json", JSON.stringify(input, null, 2));
  console.log("written inputs/merkle/merkle_depth2_leaf0.json");
  console.log(input);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
