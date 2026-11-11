// Nullifier-store scenario on the outputs each backend actually produced.
//
//   node scripts/lib/nullifier_store.js <repo> <results>
//
// Reads results/circom_outputs.tsv and results/noir_outputs.tsv (vector, C, N,
// D; written by the two suites) and replays the sequence in
// testdata/kat/canonical_fixture.json -> nullifier_store_scenario against the
// shared redemption service (scripts/lib/redemption_service.js: one store per
// backend, atomic check-and-insert; docs/protocol_specification.md,
// Section 9). Checks, per backend, that every step is accepted or rejected as
// expected, and that both backends produced the same C, N and D for every
// vector. Concurrent submissions are tested by nullifier_concurrency.js.
// Exits non-zero on any deviation.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const service = require("./redemption_service");

const [repo, results] = process.argv.slice(2);
const fixture = require(path.resolve(repo, "testdata/kat/canonical_fixture.json"));
const scenario = fixture.nullifier_store_scenario;

const read = (f) => Object.fromEntries(fs.readFileSync(path.join(results, f), "utf8").trim().split("\n")
    .filter(Boolean).map((l) => { const [id, c, n, d] = l.split("\t"); return [id, { c, n, d }]; }));
const outputs = { circom: read("circom_outputs.tsv"), noir: read("noir_outputs.tsv") };

let ok = true;
const lines = [];
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zkep-store-"));
for (const [backend, out] of Object.entries(outputs)) {
    const store = path.join(tmp, backend);
    let right = 0;
    for (const step of scenario) {
        const o = out[step.vector];
        if (!o) { ok = false; lines.push(`${backend}: no output for ${step.vector}`); continue; }
        const got = service.redeem(store, o.n, `test-${backend}`).accepted ? "accept" : "reject";
        if (got === step.expect) right++; else ok = false;
        lines.push(`${backend.padEnd(7)} ${step.vector}  N=${o.n.slice(0, 14)}...  ${got.padEnd(7)} ${got === step.expect ? "as expected" : "UNEXPECTED"}  (${step.note})`);
    }
    lines.push(`${backend}: ${right}/${scenario.length} steps as expected`);
}
fs.rmSync(tmp, { recursive: true, force: true });
const ids = Object.keys(outputs.circom);
const same = ids.filter((id) => outputs.noir[id] && ["c", "n", "d"].every((k) => outputs.noir[id][k] === outputs.circom[id][k])).length;
if (same !== ids.length) ok = false;
lines.push(`same C, N and D in both backends: ${same}/${ids.length} vectors`);
fs.writeFileSync(path.join(results, "nullifier_store.txt"), lines.join("\n") + "\n");
console.log(lines.join("\n"));
process.exit(ok ? 0 : 1);
