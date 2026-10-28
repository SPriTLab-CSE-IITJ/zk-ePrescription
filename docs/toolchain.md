# Toolchain

All versions are pinned in the repository `Dockerfile`; the Docker image is the
reference environment for every regression run.

| Tool | Version |
|---|---|
| Circom | 2.2.3 (built from source, tag `v2.2.3`) |
| snarkjs | 0.7.6 |
| circomlib / circomlibjs | as locked in `package-lock.json` / `circom/package-lock.json` |
| Node.js | 18.20 (base image `node:18.20-bookworm`) |
| Noir / Nargo | 1.0.0-beta.24 |
| Barretenberg (`bb`) | 5.0.0-nightly.20260522 |

## Proving stacks

* Circom → R1CS → Groth16 (snarkjs), BN254.
* Noir → ACIR → UltraHonk (Barretenberg), BN254.

## Regression entry point

```bash
docker build -t zkep:aligned .
docker run --rm zkep:aligned        # npm test -> scripts/test_all.sh
```

Barretenberg downloads its CRS on first use; the Docker run therefore needs
network access to the Aztec CRS host.
