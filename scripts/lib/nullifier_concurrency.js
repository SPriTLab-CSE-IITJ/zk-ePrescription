// Concurrency and notification tests of the shared redemption service
// (scripts/lib/redemption_service.js; docs/protocol_specification.md,
// Sections 9.1, 9.2 and 26, item 4).
//
//   node scripts/lib/nullifier_concurrency.js <repo> <results>
//
//   A  ROUNDS rounds: WORKERS separate processes, released at the same instant,
//      all submit the same nullifier N (slot 0 of TV-001), as if the same
//      redemption token were presented at many pharmacies at once.
//      Exactly one must be accepted per round.
//   B  The three refill slots of TV-001 submitted concurrently: all accepted.
//   C  Notification: the patient redeemed slot 0; someone else redeemed slot 1
//      with a copied token. From its own secret the patient's app derives
//      N_0..N_{t-1}, asks the service which are used, and must report slot 1
//      as a redemption it did not make; slot 2 stays unused.
//
// Prints one line per test; exits non-zero on any deviation.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const [repo, results] = process.argv.slice(2);
const fx = require(path.resolve(repo, "testdata/kat/canonical_fixture.json"));
const p2 = require(path.resolve(repo, "circom/scripts/lib/poseidon2"));
const service = path.resolve(repo, "scripts/lib/redemption_service.js");

const ROUNDS = 5;
const WORKERS = 32;
const secret = BigInt(fx.scenario.patient_secret);
const C = BigInt(fx.derived.commitment_C);
const threshold = Number(fx.scenario.threshold);
const N = (slot) => p2.H3(secret, C, BigInt(slot));

// One worker: wait for the common start instant, then redeem.
const WORKER = `
const s = require(process.argv[1]);
const startAt = Number(process.argv[2]);
while (Date.now() < startAt) {}
const r = s.redeem(process.argv[3], process.argv[4], process.argv[5]);
process.stdout.write(JSON.stringify({ accepted: r.accepted, late: Date.now() - startAt }));
`;

function race(store, items) {
    const startAt = Date.now() + 4000;   // time for all workers to start, also on 4-core boards
    return Promise.all(items.map(({ n, pharmacy }) => new Promise((resolve, reject) => {
        const p = spawn(process.execPath, ["-e", WORKER, service, String(startAt), store, String(n), pharmacy]);
        let out = "";
        p.stdout.on("data", (d) => { out += d; });
        p.on("error", reject);
        p.on("close", (code) => {
            try { resolve({ pharmacy, ...JSON.parse(out) }); } catch (_) { reject(new Error(`worker ${pharmacy} failed (exit ${code})`)); }
        });
    })));
}

(async () => {
    const lines = [];
    let ok = true;
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zkep-store-"));

    // A: same N from many processes at once
    let rounds = 0;
    for (let r = 0; r < ROUNDS; r++) {
        const store = path.join(tmp, `A${r}`);
        const res = await race(store, Array.from({ length: WORKERS }, (_, i) => ({ n: N(0), pharmacy: `pharmacy-${i}` })));
        const accepted = res.filter((x) => x.accepted).length;
        const files = fs.readdirSync(store).length;
        if (accepted === 1 && files === 1) rounds++; else ok = false;
        lines.push(`A round ${r + 1}: ${WORKERS} concurrent submissions of the same N -> ${accepted} accepted, ${WORKERS - accepted} rejected`);
    }
    lines.push(`concurrent same-N submissions: ${rounds}/${ROUNDS} rounds with exactly one acceptance (${WORKERS} processes each)`);

    // B: distinct slots concurrently
    {
        const store = path.join(tmp, "B");
        const res = await race(store, Array.from({ length: threshold }, (_, i) => ({ n: N(i), pharmacy: `pharmacy-${i}` })));
        const accepted = res.filter((x) => x.accepted).length;
        if (accepted !== threshold) ok = false;
        lines.push(`distinct refill slots submitted concurrently: ${accepted}/${threshold} accepted`);
    }

    // C: notification of a redemption the patient did not make
    {
        const store = path.join(tmp, "C");
        const svc = require(service);
        svc.redeem(store, N(0), "pharmacy-A");       // the patient's own redemption
        svc.redeem(store, N(1), "pharmacy-X");       // someone with a copied token
        const mine = new Set([0]);                   // slots the patient's app redeemed itself
        const report = [];
        for (let i = 0; i < threshold; i++) {
            const q = svc.query(store, N(i));
            report.push(q.used ? (mine.has(i) ? "own" : `FOREIGN (${q.record.pharmacy})`) : "unused");
        }
        const expected = ["own", "FOREIGN (pharmacy-X)", "unused"];
        const right = report.filter((x, i) => x === expected[i]).length;
        if (right !== threshold) ok = false;
        lines.push(`patient notification: slots ${report.map((x, i) => `${i}=${x}`).join(", ")} (${right}/${threshold} as expected)`);
    }

    fs.rmSync(tmp, { recursive: true, force: true });
    fs.mkdirSync(path.join(results, "logs"), { recursive: true });
    fs.writeFileSync(path.join(results, "logs", "nullifier_concurrency.log"), lines.join("\n") + "\n");
    console.log(lines.join("\n"));
    process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
