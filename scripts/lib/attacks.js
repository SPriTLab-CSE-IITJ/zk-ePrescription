// Prints the attack-vector table: what each NT vector changes, and where each
// backend rejected it. Inputs are written by the two suites:
//   results/circom_negative.tsv   id <TAB> template <TAB> line
//   results/noir_negative.tsv     id <TAB> src/file.nr:line
// The description is the first line of noir/redemption/tests/negative/<id>.toml
// (written by circom/scripts/build_canonical_fixture.js).
"use strict";
const fs = require("fs");
const path = require("path");

const [repo, results, full] = process.argv.slice(2);
const read = (f) => (fs.existsSync(f) ? fs.readFileSync(f, "utf8").trim().split("\n").filter(Boolean) : []);
const tsv = (f) => Object.fromEntries(read(f).map((l) => { const [id, ...r] = l.split("\t"); return [id, r]; }));

// Circom: innermost failing template and line -> check (circuits are frozen,
// line numbers refer to circom/circuits/*.circom)
function circomSite([tpl, line]) {
    const n = Number(line);
    if (tpl === "SchnorrBJJ") return n <= 60 ? "s < l bound" : n <= 85 ? "8*PK != O" : "signature";
    if (tpl === "DoctorRegistry") return n <= 50 ? "binary direction" : "registry";
    if (tpl === "BabyCheck") return "point on curve";
    if (tpl === "EPrescriptionMain") return n <= 57 ? "slot < threshold" : n <= 62 ? "expiry" : n <= 75 ? "registry" : "signature";
    return tpl || "?";
}
// Noir: failing assertion -> check (noir/redemption/src)
const NOIR = {
    "src/main.nr:118": "slot < threshold", "src/main.nr:119": "expiry",
    "src/main.nr:120": "registry", "src/main.nr:121": "signature",
    "src/registry.nr:7": "binary direction", "src/schnorr.nr:19": "PK on curve",
    "src/schnorr.nr:20": "R on curve", "src/schnorr.nr:21": "s < l bound",
    "src/schnorr.nr:37": "8*PK != O",
};
const noirSite = ([loc]) => NOIR[loc] || loc || "?";

const circom = tsv(path.join(results, "circom_negative.tsv"));
const noir = tsv(path.join(results, "noir_negative.tsv"));
const dir = path.join(repo, "noir/redemption/tests/negative");
const ids = fs.readdirSync(dir).filter((f) => f.endsWith(".toml")).map((f) => f.slice(0, -5)).sort();

const rows = ids.map((id) => {
    const desc = fs.readFileSync(path.join(dir, `${id}.toml`), "utf8").split("\n")[0].replace(/^# [A-Z0-9-]+: /, "");
    return { id, desc, c: circom[id] ? circomSite(circom[id]) : "-", n: noir[id] ? noirSite(noir[id]) : "-" };
});

const lines = [];
lines.push(`      ${"vector".padEnd(8)}${"Groth16 rejects at".padEnd(20)}${"UltraHonk rejects at".padEnd(22)}what the attacker changed`);
for (const r of rows) lines.push(`      ${r.id.padEnd(8)}${r.c.padEnd(20)}${r.n.padEnd(22)}${r.desc}`);
fs.writeFileSync(path.join(results, "attacks.txt"), lines.join("\n") + "\n");
const show = full === "full" ? lines : lines.slice(0, 1).concat(lines.slice(1, 6), [`      ... ${rows.length - 5} more in results/attacks.txt`]);
console.log(show.join("\n"));
