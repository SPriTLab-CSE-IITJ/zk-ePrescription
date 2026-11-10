// Pharmacy-view checks on a real proof of TV-001 (protocol v3,
// docs/protocol_specification.md Section 6.1): the medication list is shown
// only when it is the doctor-signed list, the proof verifies and the root and
// date are the pharmacy's own.
//
//   node scripts/lib/pharmacy_cases.js circom|noir <vk> <proof> <public> <results_dir>
//
// Writes <results_dir>/pharmacy_view_<backend>.txt (what the pharmacist sees)
// and prints "<k>/<n> as expected"; exits non-zero on any deviation.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { check, report } = require("../pharmacy_verify");
const meds = require("./medication_list");

const REPO = path.resolve(__dirname, "../..");
const fx = require(path.join(REPO, "testdata/kat/canonical_fixture.json"));
const LIST = require(path.join(REPO, "testdata/kat/medication_list.json"));
const e = fx.expected_public_outputs["TV-001"];

const [backend, vk, proof, pub, results] = process.argv.slice(2);
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zkep-pharmacy-"));
const file = (name, content) => { const f = path.join(tmp, name); fs.writeFileSync(f, content); return f; };
const listFile = (name, list) => file(`${name}.json`, JSON.stringify(list));
const clone = () => JSON.parse(JSON.stringify(LIST));

// Public values with D replaced by the digest of another list (the attacker
// changes the list AND the digest the proof claims to output).
function forgedPublic(D) {
    if (backend === "circom") {
        const p = JSON.parse(fs.readFileSync(pub, "utf8"));
        p[2] = D.toString();
        return file("forged_public.json", JSON.stringify(p));
    }
    const b = Buffer.from(fs.readFileSync(pub));
    Buffer.from(D.toString(16).padStart(64, "0"), "hex").copy(b, 4 * 32);
    return file("forged_public_inputs", b);
}

const more = clone(); more[0].quantity += 20;
const swapped = clone(); swapped[1] = { code: "100000099", name: "Tramadol 50 mg capsule", dosage: "1 capsule 3 times a day", quantity: 15 };
const extra = clone().concat([{ code: "100000098", name: "Alprazolam 0.5 mg tablet", dosage: "1 tablet at night", quantity: 10 }]);
const fewer = clone().slice(0, 1);
const base = { backend, vk, proof, public: pub, list: listFile("signed", LIST), root: e.registry_root, date: e.current_date };

const CASES = [
    { name: "signed medication list", expect: true, args: base },
    { name: "quantity raised (20 -> 40)", expect: false, args: { ...base, list: listFile("more", more) } },
    { name: "one medicine swapped for another", expect: false, args: { ...base, list: listFile("swapped", swapped) } },
    { name: "extra medicine added", expect: false, args: { ...base, list: listFile("extra", extra) } },
    { name: "one medicine left out", expect: false, args: { ...base, list: listFile("fewer", fewer) } },
    { name: "altered list with its own digest put into the public values", expect: false,
        args: { ...base, list: listFile("more2", more), public: forgedPublic(meds.digest(more)) } },
    { name: "pharmacy date differs (next day)", expect: false, args: { ...base, date: String(BigInt(e.current_date) + 1n) } },
    { name: "pharmacy registry root differs", expect: false, args: { ...base, root: "0x" + (BigInt(e.registry_root) + 1n).toString(16) } },
];

(async () => {
    let right = 0;
    const lines = [];
    for (const c of CASES) {
        const r = await check(c.args);
        const ok = r.accept === c.expect;
        if (ok) right++;
        lines.push(`${backend.padEnd(7)} ${c.name.padEnd(62)} ${(r.accept ? "ACCEPT" : "REJECT").padEnd(7)} ${ok ? "as expected" : "UNEXPECTED"}${r.accept ? "" : `  (${r.reason})`}`);
        if (c.expect && r.accept) fs.writeFileSync(path.join(results, `pharmacy_view_${backend}.txt`), report(r) + "\n");
    }
    fs.rmSync(tmp, { recursive: true, force: true });
    fs.appendFileSync(path.join(results, "logs", `pharmacy_${backend}.log`), lines.join("\n") + "\n");
    console.log(`${right}/${CASES.length} as expected`);
    process.exit(right === CASES.length ? 0 : 1);
})().catch((err) => { console.error(err); process.exit(1); });
