const circomlib = require("circomlibjs");
const MerkleTree = require("./merkle_tree");

async function main() {
    const poseidon = await circomlib.buildPoseidon();

    const values = [];
    for (let i = 5001; i <= 5016; i++) values.push(i);

    const tree = new MerkleTree(poseidon, values);

    console.log("Root:");
    console.log(tree.getRoot());

    for (let i = 0; i < values.length; i++) {
        const proof = tree.getProof(i);
        const filename = `inputs/merkle/merkle_depth4_leaf${i}.json`;
        require("fs").writeFileSync(filename, JSON.stringify(proof, null, 2));
        console.log(`Wrote ${filename}`);
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
