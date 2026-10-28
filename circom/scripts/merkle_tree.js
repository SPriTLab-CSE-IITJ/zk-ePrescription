const circomlib = require("circomlibjs");

class MerkleTree {
    constructor(poseidon, values) {
        this.poseidon = poseidon;
        this.F = poseidon.F;

        this.leaves = values.map((value) =>
            this.F.toString(this.poseidon([value]))
        );

        this.levels = [this.leaves];

        this.buildTree();
    }

    hash(left, right) {
        return this.F.toString(
            this.poseidon([left, right])
        );
    }

    buildTree() {
        let currentLevel = this.leaves;

        while (currentLevel.length > 1) {
            const nextLevel = [];

            for (let i = 0; i < currentLevel.length; i += 2) {
                const left = currentLevel[i];
                const right = currentLevel[i + 1];

                nextLevel.push(
                    this.hash(left, right)
                );
            }

            this.levels.push(nextLevel);
            currentLevel = nextLevel;
        }
    }

    getRoot() {
        return this.levels[this.levels.length - 1][0];
    }

    getProof(index) {
        const pathElements = [];
        const pathIndices = [];

        let currentIndex = index;

        for (let level = 0; level < this.levels.length - 1; level++) {

            const currentLevel = this.levels[level];

            const isRight = currentIndex % 2;

            pathIndices.push(isRight);

            const siblingIndex = isRight
                ? currentIndex - 1
                : currentIndex + 1;

            pathElements.push(
                currentLevel[siblingIndex]
            );

            currentIndex = Math.floor(currentIndex / 2);
        }

        return {
            leaf: this.leaves[index],
            pathElements,
            pathIndices,
            root: this.getRoot()
        };
    }
}

module.exports = MerkleTree;
