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

    console.log("leaf0 =", leaf0);
    console.log("leaf1 =", leaf1);
    console.log("leaf2 =", leaf2);
    console.log("leaf3 =", leaf3);

    console.log("h01 =", h01);
    console.log("h23 =", h23);

    console.log("root =", root);
}

main();
