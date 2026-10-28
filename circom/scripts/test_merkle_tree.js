const circomlib = require("circomlibjs");
const MerkleTree = require("./merkle_tree");

async function main() {

    const poseidon = await circomlib.buildPoseidon();

    const values = [
        5001,
        5002,
        5003,
        5004
    ];

    const tree = new MerkleTree(
        poseidon,
        values
    );

    console.log("Root:");
    console.log(tree.getRoot());

    console.log("\nProofs:");

    for (let i = 0; i < values.length; i++) {
        console.log(`\nLeaf ${i}:`);
        console.log(JSON.stringify(
            tree.getProof(i),
            null,
            2
        ));
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
