// Public-value privacy check (protocol v2, docs/protocol_specification.md
// Sections 7 and 15): the only public values of a redemption are
// registry_root, current_date, C and N. In particular the patient reference
// I = H2(patient_secret) and the secret itself must never be public.
//
//   node scripts/lib/public_values_check.js circom <r1cs_info.txt> <public.json>...
//   node scripts/lib/public_values_check.js noir   <target/redemption.json> <noir_outputs.tsv>
//
// Prints one summary line; exits non-zero on any violation.
"use strict";
const fs = require("fs");
const path = require("path");

const REPO = path.resolve(__dirname, "../..");
const fx = require(path.join(REPO, "testdata/kat/canonical_fixture.json"));
const big = (x) => BigInt(x);
const secret = big(fx.scenario.patient_secret);
const forbidden = [big(fx.derived.identity_I), secret];

const [backend, meta, ...rest] = process.argv.slice(2);
const problems = [];
let checked = 0;

if (backend === "circom") {
    const info = fs.readFileSync(meta, "utf8");
    const num = (label) => Number((info.match(new RegExp(`# of ${label}: *(\\d+)`)) || [])[1]);
    if (num("Public Inputs") !== 2) problems.push(`public inputs = ${num("Public Inputs")} (expected 2: current_date, root)`);
    if (num("Outputs") !== 2) problems.push(`outputs = ${num("Outputs")} (expected 2: C, N)`);
    for (const f of rest) {
        const pub = JSON.parse(fs.readFileSync(f, "utf8")).map(big);
        if (pub.length !== 4) problems.push(`${path.basename(f)}: ${pub.length} public signals (expected 4)`);
        if (pub.some((v) => forbidden.includes(v))) problems.push(`${path.basename(f)}: I or patient_secret is public`);
        checked++;
    }
} else if (backend === "noir") {
    const abi = JSON.parse(fs.readFileSync(meta, "utf8")).abi;
    const pubParams = abi.parameters.filter((p) => p.visibility === "public").map((p) => p.name).sort();
    if (JSON.stringify(pubParams) !== JSON.stringify(["current_date", "registry_root"])) problems.push(`public parameters ${pubParams}`);
    const rt = abi.return_type;
    if (!rt || rt.visibility !== "public" || rt.abi_type.kind !== "array" || rt.abi_type.length !== 2) problems.push("return value is not [C, N]");
    for (const line of fs.readFileSync(rest[0], "utf8").trim().split("\n").filter(Boolean)) {
        const [id, c, n] = line.split("\t");
        if ([c, n].map(big).some((v) => forbidden.includes(v))) problems.push(`${id}: I or patient_secret is public`);
        checked++;
    }
} else {
    console.error("usage: public_values_check.js circom|noir ...");
    process.exit(2);
}

if (problems.length) { console.log("FAIL " + problems.join("; ")); process.exit(1); }
console.log(`${checked} redemptions: public values are only root, date, C, N; I and the secret are not public`);
