#!/usr/bin/env node
// zk-ePrescription — reviewer-friendly benchmark summary (read-only).
//
//   node print_summary.js <benchmark-result-dir>
//
// Prints boxed Groth16-vs-UltraHonk tables from an existing, validated result
// directory (circom_results.json, noir_results.json, benchmark_metadata.json,
// validation.json). It measures nothing and modifies nothing.
"use strict";
const fs = require("fs");
const path = require("path");

const dir = path.resolve(process.argv[2] || ".");
const rd = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
const c = rd("circom_results.json");
const n = rd("noir_results.json");
const meta = rd("benchmark_metadata.json");
const val = rd("validation.json");

const fmt = (x, d = 3) => (x === null || x === undefined ? "n/a" : Number(x).toFixed(d));
const sec = (r, s) => fmt(r.stages[s].wall_s.median) + " s";
const mib = (r, s) => fmt(r.stages[s].max_rss_kb.median / 1024, 2) + " MiB";
const B = (x) => (x === null || x === undefined ? "n/a" : Number(x).toLocaleString("en-US") + " B");
const num = (x) => Number(x).toLocaleString("en-US");

function box(title, header, rows, note) {
    const all = [header, ...rows.filter((r) => r !== "-")];
    const w = header.map((_, i) => Math.max(...all.map((r) => String(r[i]).length)));
    const line = (ch = "-") => "+" + w.map((x) => ch.repeat(x + 2)).join("+") + "+";
    const row = (r) => "| " + r.map((v, i) => (i === 0 ? String(v).padEnd(w[i]) : String(v).padStart(w[i]))).join(" | ") + " |";
    const out = [];
    out.push("");
    out.push(title);
    out.push(line("="));
    out.push(row(header));
    out.push(line("="));
    for (const r of rows) out.push(r === "-" ? line() : row(r));
    out.push(line());
    if (note) for (const l of note) out.push("  " + l);
    console.log(out.join("\n"));
}

const H = meta.host || {}, D = meta.docker || {}, T = meta.toolchain || {};
const MM = meta.methodology || {};
const REPS = MM.measured_runs_witness_prove_verify ?? "?", WU = MM.warmup ?? "?", CREPS = MM.measured_runs_compile ?? "?";
const gib = (kb) => (kb ? (kb / 2 ** 20).toFixed(2) + " GiB" : "n/a");

console.log("\n" + "=".repeat(78));
console.log(" zk-ePrescription — Benchmark Summary: Circom/Groth16 vs Noir/UltraHonk");
console.log("=".repeat(78));
console.log(` Result dir : ${path.basename(dir)}`);
console.log(` Validation : ${val.all_pass ? "ALL " + val.checks.length + " CHECKS PASSED" : "FAILED"}`);
console.log(` Input      : TV-001 (canonical fixture; same logical statement for both backends)`);
console.log(` Platform   : ${H.cpu_model} | ${H.logical_cpus} logical CPUs | ${H.architecture}`);
const hostRam = typeof H.windows_host_physical_ram_bytes === "number" ? H.windows_host_physical_ram_bytes
    : typeof H.macos_host_physical_ram_bytes === "number" ? H.macos_host_physical_ram_bytes : null;
const visible = H.linux_visible_memtotal_kb ? gib(H.linux_visible_memtotal_kb)
    : D.docker_visible_memtotal_bytes ? (D.docker_visible_memtotal_bytes / 2 ** 30).toFixed(2) + " GiB" : "n/a";
console.log(`              host RAM ${hostRam ? (hostRam / 2 ** 30).toFixed(2) + " GiB" : "n/a"}, ${H.linux_visible_memtotal_kb ? "WSL/Docker" : "Docker"}-visible ${visible} | ${H.os_release} | Docker ${D.server_version}`);
if (typeof H.macos_host_physical_ram_bytes === "number") console.log(`              ${H.device_model} | ${H.macos_host_cores} cores | Docker VM ${D.docker_visible_ncpu} CPUs | power ${H.macos_host_power} | low power mode ${H.macos_host_lowpowermode}`);
console.log(` Toolchain  : ${T.circom} | ${T.snarkjs} | ${(T.nargo || "").split(" noirc")[0]} | bb ${T.bb} | node ${T.node}`);

box("1. CIRCUIT SIZE  (backend-native units — NOT directly comparable)",
    ["Metric", "Circom / Groth16", "Noir / UltraHonk"],
    [
        ["R1CS constraints", num(c.structural.r1cs_constraints), "—"],
        ["  non-linear / linear", `${num(c.structural.nonlinear_constraints)} / ${num(c.structural.linear_constraints)}`, "—"],
        ["ACIR opcodes", "—", num(n.structural.acir_opcodes_nargo_info)],
        ["Barretenberg gates", "—", num(n.structural.barretenberg_circuit_size_gates)],
    ]);

box(`2. PER-REDEMPTION COST  (median of ${REPS} measured runs after ${WU} warm-up)`,
    ["Stage", "Circom / Groth16", "Noir / UltraHonk"],
    [
        ["Witness generation", sec(c, "witness"), sec(n, "execute")],
        ["Proof generation", sec(c, "prove"), sec(n, "prove")],
        ["Proof verification", sec(c, "verify"), sec(n, "verify")],
        "-",
        ["Peak RSS — witness", mib(c, "witness"), mib(n, "execute")],
        ["Peak RSS — proving", mib(c, "prove"), mib(n, "prove")],
        ["Peak RSS — verification", mib(c, "verify"), mib(n, "verify")],
        "-",
        ["Proof size", B(c.final_artifacts.proof_json.bytes), B(n.final_artifacts.proof.bytes)],
        ["Verification key size", B(c.final_artifacts.verification_key_json.bytes), B(n.final_artifacts.vk.bytes)],
    ],
    [
        "Witness: Circom generate_witness.js (WASM) vs Noir nargo execute.",
        "Noir proving uses the precomputed VK (bb prove -k). snarkjs/node timings include Node.js start-up.",
        "Every generated proof was verified; public outputs matched the canonical fixture.",
    ]);

const rng = (r, s) => `${fmt(r.stages[s].wall_s.min)}–${fmt(r.stages[s].wall_s.max)} s (sd ${fmt(r.stages[s].wall_s.stdev_sample)})`;
box("3. RUN-TO-RUN SPREAD  (min–max of measured runs; median above is primary)",
    ["Stage", "Circom / Groth16", "Noir / UltraHonk"],
    [
        ["Witness generation", rng(c, "witness"), rng(n, "execute")],
        ["Proof generation", rng(c, "prove"), rng(n, "prove")],
        ["Proof verification", rng(c, "verify"), rng(n, "verify")],
    ]);

box("4. BUILD AND ONE-TIME SETUP  (NOT per-redemption latency)",
    ["Stage", "Circom / Groth16", "Noir / UltraHonk"],
    [
        [`Compilation (median of ${CREPS})`, sec(c, "compile"), sec(n, "compile")],
        "-",
        ["Powers of Tau — new", sec(c, "ptau_new"), "— (universal CRS)"],
        ["Powers of Tau — contribution", sec(c, "ptau_contribute"), "—"],
        ["Powers of Tau — phase-2 prep", sec(c, "ptau_prepare_phase2"), "—"],
        ["Circuit-specific setup", sec(c, "groth16_setup"), "—"],
        ["zkey contribution", sec(c, "zkey_contribute"), "—"],
        ["Verification-key generation", sec(c, "vk_export"), sec(n, "write_vk")],
    ],
    [
        "Groth16 needs a circuit-specific setup (here: local single-contributor dev ceremony, not production).",
        "UltraHonk uses Barretenberg's universal CRS; its download/caching is excluded from all timings.",
    ]);

console.log(`
NOTES
  * Median is the primary statistic; all raw runs are in raw_runs.csv (summary.csv has mean/min/max/sd).
  * Peak RSS = GNU /usr/bin/time -v "Maximum resident set size" of the measured process.
  * Results are for this platform only; performance is hardware-dependent.
  * Artifact SHA-256 hashes: artifact_manifest.sha256. Validation details: validation.json.
`);
