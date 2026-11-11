// Pharmacy-side verification of a redemption (protocol v3,
// docs/protocol_specification.md Sections 6.1 and 26).
//
// The pharmacy shows the medication list to the pharmacist only if
//   1. the registry root and the date in the proof's public values are the
//      pharmacy's OWN values (never taken from the patient),
//   2. the proof verifies under the pinned verification key, and
//   3. the medication list sent by the patient's app hashes to the digest D
//      that the proof outputs (D is part of the doctor-signed commitment C).
// It then prints the list and the nullifier N that the shared redemption
// service must accept exactly once. With --store, it submits N to the shared
// redemption service (scripts/lib/redemption_service.js, atomic
// check-and-insert) and dispenses only if N was not redeemed before.
//
//   node scripts/pharmacy_verify.js --backend circom|noir \
//        --vk <vk> --proof <proof> --public <public values> \
//        --list <medication_list.json> --root <0x..> --date <YYYYMMDD> \
//        [--store <redemption store dir> --pharmacy <HFR id>]
//
//   circom: --vk verification_key.json --proof proof.json --public public.json
//   noir:   --vk target/vk --proof target/proof --public target/public_inputs
//           (bb on PATH; target from BB_TARGET, default noir-recursive)
//
// Exit 0 = ACCEPT (list shown), 1 = REJECT, 2 = usage error.
"use strict";
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const meds = require("./lib/medication_list");
const service = require("./lib/redemption_service");

const hex = (x) => "0x" + BigInt(x).toString(16).padStart(64, "0");

// Public values in protocol order, per backend.
//   Circom public.json : [C, N, D, current_date, root]   (decimal strings)
//   Noir public_inputs : [root, current_date, C, N, D]   (32-byte big-endian)
function readPublic(backend, file) {
    if (backend === "circom") {
        const p = JSON.parse(fs.readFileSync(file, "utf8"));
        if (!Array.isArray(p) || p.length !== 5) throw new Error(`expected 5 public signals, got ${Array.isArray(p) ? p.length : "none"}`);
        const [C, N, D, date, root] = p.map(BigInt);
        return { C, N, D, date, root };
    }
    const b = fs.readFileSync(file);
    if (b.length !== 5 * 32) throw new Error(`expected 5 public inputs (160 bytes), got ${b.length} bytes`);
    const x = [];
    for (let i = 0; i < 5; i++) x.push(BigInt("0x" + b.subarray(32 * i, 32 * i + 32).toString("hex")));
    const [root, date, C, N, D] = x;
    return { C, N, D, date, root };
}

async function verifyProof(backend, vk, proof, pub) {
    if (backend === "circom") {
        const snarkjs = require("snarkjs");
        return snarkjs.groth16.verify(JSON.parse(fs.readFileSync(vk, "utf8")), JSON.parse(fs.readFileSync(pub, "utf8")),
            JSON.parse(fs.readFileSync(proof, "utf8")));
    }
    try {
        execFileSync("bb", ["verify", "-t", process.env.BB_TARGET || "noir-recursive", "-k", vk, "-p", proof, "-i", pub], { stdio: "pipe" });
        return true;
    } catch (_) {
        return false;
    }
}

// Returns { accept, reason, pub, list }.
async function check({ backend, vk, proof, public: pubFile, list: listFile, root, date }) {
    let pub;
    try { pub = readPublic(backend, pubFile); } catch (e) { return { accept: false, reason: `malformed public values: ${e.message}` }; }
    if (pub.root !== BigInt(root)) return { accept: false, reason: "registry root in the proof is not the pharmacy's current root", pub };
    if (pub.date !== BigInt(date)) return { accept: false, reason: "date in the proof is not the pharmacy's date", pub };
    if (!(await verifyProof(backend, vk, proof, pubFile))) return { accept: false, reason: "proof does not verify", pub };
    let list;
    try { list = JSON.parse(fs.readFileSync(listFile, "utf8")); } catch (e) { return { accept: false, reason: `medication list unreadable: ${e.message}`, pub }; }
    let d;
    try { d = meds.digest(list); } catch (e) { return { accept: false, reason: e.message, pub }; }
    if (d !== pub.D) return { accept: false, reason: "medication list does not match the prescription (digest differs from D)", pub };
    return { accept: true, pub, list };
}

function report(r) {
    if (!r.accept) return `REJECT: ${r.reason}`;
    return [
        "ACCEPT: valid prescription; dispense the following medicines",
        meds.render(r.list),
        "",
        `record nullifier N = ${hex(r.pub.N)} with the redemption service (accept once)`,
    ].join("\n");
}

module.exports = { check, report, readPublic };

if (require.main === module) {
    const args = {};
    const a = process.argv.slice(2);
    for (let i = 0; i < a.length; i += 2) args[a[i].replace(/^--/, "")] = a[i + 1];
    const need = ["backend", "vk", "proof", "public", "list", "root", "date"];   // optional: store, pharmacy
    if (need.some((k) => !args[k]) || !["circom", "noir"].includes(args.backend)) {
        console.error(`usage: node ${path.basename(__filename)} ${need.map((k) => `--${k} <..>`).join(" ")}`);
        process.exit(2);
    }
    check(args).then((r) => {
        if (r.accept && args.store) {
            const s = service.redeem(args.store, r.pub.N, args.pharmacy || "unknown");
            if (!s.accepted) r = { accept: false, reason: `this refill was already redeemed (${s.record && s.record.pharmacy}, ${s.record && s.record.redeemed_at})`, pub: r.pub };
        }
        console.log(report(r));
        process.exit(r.accept ? 0 : 1);
    })
        .catch((e) => { console.error(e); process.exit(2); });
}
