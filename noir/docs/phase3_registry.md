# Phase 3: Doctor Registry

## Purpose

Phase 3 implements authorized-doctor membership verification using a
Poseidon2-based Merkle registry.

The phase contains two related components:

- `phase3_registry` — constrained membership verification
- `tools/registry_generator` — tree and authentication-path generation

## Registry Tree

The current generator constructs a depth-2 tree with four doctor leaves.

The tree layout is:

```text
leaf0   leaf1   leaf2   leaf3
   \     /         \     /
    node0           node1
          \         /
             root
