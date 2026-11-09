// Nullifier-store simulation on the outputs each backend actually produced.
//
//   node scripts/lib/nullifier_store.js <repo> <results>
//
// Reads results/circom_outputs.tsv and results/noir_outputs.tsv (vector, C, N;
// written by the two suites) and replays the sequence in
// testdata/kat/canonical_fixture.json -> nullifier_store_scenario against an
// in-memory redemption service that accepts a nullifier only once
// (docs/protocol_specification.md, Section 9). Checks, per backend, that every
// step is accepted or rejected as expected, and that both backends produced
// the same nullifier for every vector. Exits non-zero on any deviation.
"use strict";
const fs = require("fs");
const path = require("path");

const [repo, results] = process.argv.slice(2);
const fixture = require(path.resolve(repo, "testdata/kat/canonical_fixture.json"));
const scenario = fixture.nullifier_store_scenario;

const read = (f) => Object.fromEntries(fs.readFileSync(path.join(results, f), "utf8").trim().split("\n")
    .filter(Boolean).map((l) => { const [id, c, n] = l.split("\t"); return [id, { c, n }]; }));
const outputs = { circom: read("circom_outputs.tsv"), noir: read("noir_outputs.tsv") };

let ok = true;
const lines = [];
for (const [backend, out] of Object.entries(outputs)) {
    const S = new Set();
    let right = 0;
    for (const step of scenario) {
        const o = out[step.vector];
        if (!o) { ok = false; lines.push(`${backend}: no output for ${step.vector}`); continue; }
        const got = S.has(o.n) ? "reject" : "accept";
        if (got === "accept") S.add(o.n);
        if (got === step.expect) right++; else ok = false;
        lines.push(`${backend.padEnd(7)} ${step.vector}  N=${o.n.slice(0, 14)}...  ${got.padEnd(7)} ${got === step.expect ? "as expected" : "UNEXPECTED"}  (${step.note})`);
    }
    lines.push(`${backend}: ${right}/${scenario.length} steps as expected`);
}
const ids = Object.keys(outputs.circom);
const same = ids.filter((id) => outputs.noir[id] && outputs.noir[id].n === outputs.circom[id].n && outputs.noir[id].c === outputs.circom[id].c).length;
if (same !== ids.length) ok = false;
lines.push(`same C and N in both backends: ${same}/${ids.length} vectors`);
fs.writeFileSync(path.join(results, "nullifier_store.txt"), lines.join("\n") + "\n");
console.log(lines.join("\n"));
process.exit(ok ? 0 : 1);
