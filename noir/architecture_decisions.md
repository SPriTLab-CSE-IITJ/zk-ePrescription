# Architecture decisions

## Hash construction (current, normative)

Both backends use the **same** canonical construction defined in
`docs/protocol_specification.md`, Sections 4–5:

* Poseidon2 over BN254, t = 4, rate 3, x⁵ S-box, 8 full + 56 partial rounds,
  constants of Noir's `std::hash::poseidon2_permutation`;
* sponge with initial capacity `n·2⁶⁴` (n = number of absorbed elements);
* domain-tagged hashes `H1`–`H6` (tags 1–6 prepended), untagged `Hraw` for the
  Schnorr challenge.

Rationale: the research question compares two proving stacks on **one**
logical protocol. Equal protocol values for equal inputs are a requirement and
are verified on every regression run by the cross-backend known-answer tests.

## Superseded decision (historical record)

An earlier decision used circomlib Poseidon v1 for the Circom/Groth16 backend
and Poseidon2 for the Noir/UltraHonk backend, with commitments intentionally
non-portable between the two. That decision is **superseded** by the protocol
alignment and no longer describes this repository.
