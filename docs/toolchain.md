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
docker build -t zkep .
docker run --rm zkep test           # scripts/run.sh test -> scripts/test.sh
```

Barretenberg's CRS is downloaded once during `docker build`
(`scripts/prime_crs.sh`, with retries) and cached in the image, so
`docker run` needs no network access.

## Pinned build inputs

| Input | Pin |
|---|---|
| Base image (Circom build stage) | `rust:1.96-bookworm@sha256:a339861a…77902663` |
| Base image (runtime) | `node:18.20-bookworm@sha256:c6ae79e3…16d3783` |
| `nargo` binary (x86-64) | sha256 `247b1d71…9600c1a`, checked during the build |
| `bb` binary (x86-64) | sha256 `031556ee…151b4942`, checked during the build |
| Circom | built from tag `v2.2.3`; version checked, binary hash printed |
| GNU `time` | installed in the image for the benchmark harness |

On ARM64 (Raspberry Pi, Jetson) the build prints the tool hashes instead of
checking them. If a base-image digest does not resolve on your architecture,
override it with `--build-arg NODE_IMAGE=…` / `--build-arg RUST_IMAGE=…` and
record the digest used.

Node.js 18 is past its upstream end of life and `npm audit` reports known
issues in the pinned dependency tree (snarkjs, circomlib). They are kept
unchanged so that the measured environment stays identical to the one that
produced the published results.
