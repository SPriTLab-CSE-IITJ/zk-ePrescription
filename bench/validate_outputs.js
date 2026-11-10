// zk-ePrescription — final benchmark, post-run validation (runs in the container).
//
//   node validate_outputs.js <OUT> <canonical_fixture.json>
//
// Confirms that the benchmarked proofs are proofs of the aligned TV-001
// statement: public signals / public inputs equal the canonical fixture, the
// structural counts are present, every verify run succeeded, no run failed.
// Writes <OUT>/validation.json and exits non-zero on any failure.
"use strict";
const fs = require("fs");
const path = require("path");
const OUT = path.resolve(process.argv[2]);
const fx = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const exp = fx.expected_public_outputs["TV-001"];
const hex = (x) => "0x" + BigInt(x).toString(16).padStart(64, "0");
const checks = [];
const ok = (name, cond, detail) => checks.push({ check: name, pass: !!cond, detail });

// Circom: public.json order = [commitment_out, nullifier_out, current_date, root]
for (const k of ["measured1", "measured2", "measured3", "measured4", "measured5"]) {
    const p = path.join(OUT, `artifacts/circom/public_${k}.json`);
    if (!fs.existsSync(p)) continue;
    const pub = JSON.parse(fs.readFileSync(p, "utf8"));
    // protocol v3: [C, N, D, current_date, root]
    const got = { commitment: hex(pub[0]), nullifier: hex(pub[1]), medication_digest: hex(pub[2]), current_date: BigInt(pub[3]).toString(), registry_root: hex(pub[4]) };
    ok(`circom public signals ${k} == fixture TV-001`, pub.length === 5 && got.commitment === exp.commitment && got.nullifier === exp.nullifier &&
        got.medication_digest === exp.medication_digest && got.current_date === exp.current_date && got.registry_root === exp.registry_root, got);
}

// Noir: public_inputs = 32-byte big-endian fields in ABI order:
//   registry_root, current_date, then return values [C, N, D]
const pi = path.join(OUT, "artifacts/noir/prove_measured1/public_inputs");
if (fs.existsSync(pi)) {
    const b = fs.readFileSync(pi);
    const f = [];
    for (let i = 0; i + 32 <= b.length; i += 32) f.push("0x" + b.subarray(i, i + 32).toString("hex"));
    const want = [exp.registry_root, hex(exp.current_date), exp.commitment, exp.nullifier, exp.medication_digest];
    ok("noir public inputs == fixture TV-001 [root, current_date, C, N, D]",
        f.length === 5 && f.every((x, i) => x === want[i]), { got: f, expected: want });
} else ok("noir public_inputs present", false, pi);

// Raw run integrity
const raw = fs.readFileSync(path.join(OUT, "raw_runs.csv"), "utf8").trim().split("\n").slice(1).map((l) => l.split(","));
const failed = raw.filter((r) => r[3] !== "prep" && r[10] !== "0");
ok("no failed measured/once runs", failed.length === 0, failed);
const logs = fs.readdirSync(path.join(OUT, "logs"));
const cv = logs.filter((f) => /^circom\.verify\..*\.out$/.test(f));
ok("all Groth16 verify runs printed OK!", cv.length > 0 && cv.every((f) => /OK!/.test(fs.readFileSync(path.join(OUT, "logs", f), "utf8"))), cv.length);
const nv = logs.filter((f) => /^noir\.verify\..*\.out$/.test(f));
ok("all UltraHonk verify runs succeeded", nv.length > 0 && nv.every((f) => /verified successfully/.test(fs.readFileSync(path.join(OUT, "logs", f), "utf8"))), nv.length);

// Structural counts present (taken from tool output, not hardcoded)
const c = JSON.parse(fs.readFileSync(path.join(OUT, "circom_results.json"), "utf8")).structural;
const n = JSON.parse(fs.readFileSync(path.join(OUT, "noir_results.json"), "utf8")).structural;
ok("circom r1cs constraint count parsed", Number.isInteger(c.r1cs_constraints), c.r1cs_constraints);
ok("noir ACIR opcode count parsed", Number.isInteger(n.acir_opcodes_nargo_info), n.acir_opcodes_nargo_info);
ok("noir bb gate count parsed", Number.isInteger(n.barretenberg_circuit_size_gates), n.barretenberg_circuit_size_gates);

// Same aligned circuit as the regression/provenance stage (informational
// comparison against the values recorded at freeze time; a difference is a FAIL).
// Protocol v3 (medication-list digest D as a public output).
// v2: 12648 / 16686 / 22259; v1: 12291 / 16681 / 22182.
const FROZEN = { r1cs_constraints: 12648, acir_opcodes: 16687, bb_gates: 22261 };
ok("circom constraints equal frozen v3 build (12648)", c.r1cs_constraints === FROZEN.r1cs_constraints, c.r1cs_constraints);
ok("noir ACIR opcodes equal frozen v3 build (16687)", n.acir_opcodes_nargo_info === FROZEN.acir_opcodes, n.acir_opcodes_nargo_info);
ok("noir bb gates equal frozen v3 build (22261)", n.barretenberg_circuit_size_gates === FROZEN.bb_gates, n.barretenberg_circuit_size_gates);

// Legacy benchmark never invoked
const cmds = fs.readFileSync(path.join(OUT, "benchmark_commands.txt"), "utf8");
ok("scripts/benchmark.js not invoked", !/benchmark\.js/.test(cmds), null);

// Independent sanity check (NOT the source of truth): values recorded at the
// protocol-v3 freeze (v2: C 0x1858ba4c..., N 0x0e51d203...; v1: C 0x2206c427..., N 0x13ffd498...).
const SANITY = {
    C: "0x0c0dcdd6a41f85ba95410e634862efec73514fc511bbe4ea9f0dcc8f655b65a7",
    N: "0x0fb1b94c01543fbbc96497ec32298beba60133c67029e31c2400e7fee001b8c6",
    D: "0x2f76e5f7c5bf5a9475f9ee4ced0ac7c295cd79bdbbe6fb2bb305846f6b202360",
};
ok("sanity: fixture TV-001 C equals value recorded at freeze", exp.commitment === SANITY.C, exp.commitment);
ok("sanity: fixture TV-001 N equals value recorded at freeze", exp.nullifier === SANITY.N, exp.nullifier);
ok("sanity: fixture TV-001 D equals value recorded at freeze", exp.medication_digest === SANITY.D, exp.medication_digest);

// Repetition counts as approved
const count = (b, st, kind) => raw.filter((r) => r[1] === b && r[2] === st && r[3] === kind).length;
const R = Number(process.env.REPS || 5), CR = Number(process.env.COMPILE_REPS || 3), WU = Number(process.env.WARMUP || 1);
for (const [b, st, n] of [["circom", "compile", CR], ["noir", "compile", CR], ["circom", "witness", R], ["noir", "execute", R],
    ["circom", "prove", R], ["noir", "prove", R], ["circom", "verify", R], ["noir", "verify", R]]) {
    ok(`${b}/${st}: ${WU} warm-up + ${n} measured`, count(b, st, "warmup") === WU && count(b, st, "measured") === n,
        { warmup: count(b, st, "warmup"), measured: count(b, st, "measured") });
}
for (const [b, st] of [["circom", "ptau_new"], ["circom", "ptau_contribute"], ["circom", "ptau_prepare_phase2"], ["circom", "groth16_setup"],
    ["circom", "zkey_contribute"], ["circom", "vk_export"], ["circom", "r1cs_info"], ["noir", "nargo_info"], ["noir", "bb_gates"], ["noir", "write_vk"]]) {
    ok(`${b}/${st}: exactly once`, count(b, st, "once") === 1, count(b, st, "once"));
}

// Every generated proof was verified exactly once (verify run i <- prove run i)
const cmdRows = cmds.trim().split("\n").slice(1).map((l) => l.split("\t"));
for (const [b, re] of [["circom", /proof_(warmup\d+|measured\d+)\.json/], ["noir", /prove_(warmup\d+|measured\d+)\/proof/]]) {
    const vr = cmdRows.filter((r) => r[0] === b && r[1] === "verify");
    const pairs = vr.map((r) => ({ want: r[2] + r[3], got: ((r[4] || "").match(re) || [])[1] }));
    ok(`${b}: each verify run checks the proof of the matching prove run (${vr.length} proofs)`,
        vr.length === WU + R && pairs.every((p) => p.want === p.got) && new Set(pairs.map((p) => p.got)).size === vr.length, pairs);
}

// Artifact provenance for final proofs/VKs (path, bytes, SHA-256)
const cr = JSON.parse(fs.readFileSync(path.join(OUT, "circom_results.json"), "utf8"));
const nr = JSON.parse(fs.readFileSync(path.join(OUT, "noir_results.json"), "utf8"));
for (const [name, a] of [["circom r1cs", cr.final_artifacts.r1cs], ["circom wasm", cr.final_artifacts.wasm],
    ["circom proof.json", cr.final_artifacts.proof_json], ["circom verification_key.json", cr.final_artifacts.verification_key_json],
    ["noir ACIR json", nr.final_artifacts.acir_program_json], ["noir witness", nr.final_artifacts.witness_gz],
    ["noir proof", nr.final_artifacts.proof], ["noir vk", nr.final_artifacts.vk]]) {
    ok(`artifact provenance recorded: ${name}`, a && a.bytes > 0 && /^[0-9a-f]{64}$/.test(a.sha256 || ""), a);
}

const allPass = checks.every((x) => x.pass);
fs.writeFileSync(path.join(OUT, "validation.json"), JSON.stringify({ all_pass: allPass, checks }, null, 2) + "\n");
for (const x of checks) console.log(`${x.pass ? "PASS" : "FAIL"}  ${x.check}`);
process.exit(allPass ? 0 : 1);
