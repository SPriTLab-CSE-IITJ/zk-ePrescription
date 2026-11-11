// Shared redemption (nullifier) service with atomic check-and-insert
// (docs/protocol_specification.md, Sections 9.1 and 26, item 4).
//
// One file per accepted nullifier N in a store directory shared by every
// pharmacy. Acceptance is a single exclusive create (O_CREAT | O_EXCL, Node
// flag "wx"): the operating system lets exactly one of any number of
// concurrent creators of the same file succeed, so the same N can never be
// accepted twice, even by processes racing on different pharmacies. No
// database or extra package is needed, and it behaves the same on x86-64 and
// ARM64. The store must be a local POSIX file system (not a network file
// system without exclusive-create semantics).
//
// The file records when and by which pharmacy N was redeemed, so the patient's
// application can ask whether one of its own nullifiers was used (detection of
// a stolen or relayed redemption token, Section 9.2).
//
//   node scripts/lib/redemption_service.js redeem <store> <N> [pharmacy]
//        -> prints ACCEPT (exit 0) or REJECT already redeemed (exit 1)
//   node scripts/lib/redemption_service.js query  <store> <N>
//        -> prints UNUSED (exit 0) or the stored record (exit 3)
"use strict";
const fs = require("fs");
const path = require("path");

// Canonical 32-byte hex form of a field element, used as the file name.
function key(n) {
    const v = BigInt(n);
    if (v < 0n || v >= 1n << 256n) throw new Error("nullifier out of range");
    return "0x" + v.toString(16).padStart(64, "0");
}

function redeem(store, n, pharmacy = "unknown") {
    fs.mkdirSync(store, { recursive: true });
    const k = key(n);
    const file = path.join(store, k);
    let fd;
    try {
        fd = fs.openSync(file, "wx");            // atomic: fails with EEXIST if N is known
    } catch (e) {
        if (e.code === "EEXIST") return { accepted: false, nullifier: k, record: query(store, n).record };
        throw e;
    }
    const record = { nullifier: k, pharmacy: String(pharmacy), redeemed_at: new Date().toISOString(), pid: process.pid };
    fs.writeSync(fd, JSON.stringify(record) + "\n");
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    return { accepted: true, nullifier: k, record };
}

function query(store, n) {
    const file = path.join(store, key(n));
    if (!fs.existsSync(file)) return { used: false };
    let record = null;
    // The winner may still be writing its record; the file's existence alone
    // already means "redeemed".
    try { record = JSON.parse(fs.readFileSync(file, "utf8")); } catch (_) { record = { nullifier: key(n) }; }
    return { used: true, record };
}

module.exports = { redeem, query, key };

if (require.main === module) {
    const [cmd, store, n, pharmacy] = process.argv.slice(2);
    if (!store || !n || !["redeem", "query"].includes(cmd)) {
        console.error("usage: redemption_service.js redeem <store> <N> [pharmacy] | query <store> <N>");
        process.exit(2);
    }
    if (cmd === "redeem") {
        const r = redeem(store, n, pharmacy);
        console.log(r.accepted ? `ACCEPT ${r.nullifier}` : `REJECT already redeemed ${r.nullifier}`);
        process.exit(r.accepted ? 0 : 1);
    }
    const q = query(store, n);
    console.log(q.used ? `USED ${JSON.stringify(q.record)}` : "UNUSED");
    process.exit(q.used ? 3 : 0);
}
