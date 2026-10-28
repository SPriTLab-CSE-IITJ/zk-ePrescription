const fs = require("fs");
const circomlib = require("circomlibjs");

async function main() {
    const poseidon = await circomlib.buildPoseidon();
    const F = poseidon.F;

    const values = [5001, 5002, 5003, 5004];

    const leaves = values.map(v =>
        F.toString(poseidon([v]))
    );

    const h01 = F.toString(
        poseidon([leaves[0], leaves[1]])
    );

    const h23 = F.toString(
        poseidon([leaves[2], leaves[3]])
    );

    const root = F.toString(
        poseidon([h01, h23])
    );

    const paths = [
        {
            leaf: leaves[0],
            pathElements: [leaves[1], h23],
            pathIndices: [0, 0]
        },
        {
            leaf: leaves[1],
            pathElements: [leaves[0], h23],
            pathIndices: [1, 0]
        },
        {
            leaf: leaves[2],
            pathElements: [leaves[3], h01],
            pathIndices: [0, 1]
        },
        {
            leaf: leaves[3],
            pathElements: [leaves[2], h01],
            pathIndices: [1, 1]
        }
    ];

    paths.forEach((path, i) => {
        const input = {
            leaf: path.leaf,
            pathElements: path.pathElements,
            pathIndices: path.pathIndices,
            root: root
        };

        const filename = `inputs/merkle/merkle_depth2_leaf${i}.json`;

        fs.writeFileSync(
            filename,
            JSON.stringify(input, null, 2)
        );

        console.log(`Created ${filename}`);
    });

    console.log("\nRoot:");
    console.log(root);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
