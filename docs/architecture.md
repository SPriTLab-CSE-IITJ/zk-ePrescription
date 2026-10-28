# Noir Implementation Architecture

The Noir implementation of zk-ePrescription is organized as independent
packages together with an integrated Phase 4 orchestrator.

## Components

### Common

`common/` contains shared cryptographic primitives used by the Noir
implementation, including the Poseidon2 hashing layer.

### Phase 1

`components/commitment_nullifier/phase1_core/` contains the commitment and
nullifier-oriented primitive implementation.

### Phase 2

`phase2_policy/` contains prescription policy checks.

### Phase 3

`phase3_registry/` implements doctor registry membership verification.

It also contains:

```text
tools/registry_generator/
