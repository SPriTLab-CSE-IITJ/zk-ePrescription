// zk-ePrescription — final benchmark, summarisation stage.
//
//   node summarize.js <OUT>
//
// Reads <OUT>/raw_runs.csv, the captured tool outputs in <OUT>/artifacts and
// <OUT>/benchmark_metadata.json, and writes:
//   summary.csv, circom_results.json, noir_results.json, benchmark_report.txt
// Only measured runs enter statistics (warm-up and prep rows are kept in the
// raw CSV but excluded). Median is the primary statistic. Nothing is
// estimated: a value that is not present in the raw data is reported as null.
"use strict";
const fs = require("fs");
const path = require("path");

const OUT = path.resolve(process.argv[2]);
const rd = (p) => fs.readFileSync(path.join(OUT, p), "utf8");
const exists = (p) => fs.existsSync(path.join(OUT, p));

const lines = rd("raw_runs.csv").trim().split("\n");
const hdr = lines[0].split(",");
const rows = lines.slice(1).map((l) => {
    const v = l.split(",");
    const o = {};
    hdr.forEach((h, i) => (o[h] = v[i]));
    return o;
});

const num = (x) => (x === undefined || x === "" ? null : Number(x));
function stats(xs) {
    xs = xs.filter((x) => x !== null && !Number.isNaN(x));
    if (!xs.length) return null;
    const s = [...xs].sort((a, b) => a - b);
    const n = s.length;
    const mean = s.reduce((a, b) => a + b, 0) / n;
    const median = n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
    const sd = n > 1 ? Math.sqrt(s.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1)) : 0;
    return { n, median, mean, min: s[0], max: s[n - 1], stdev_sample: sd };
}

const summary = [];
function stage(backend, st) {
    const r = rows.filter((x) => x.backend === backend && x.stage === st);
    const measured = r.filter((x) => x.kind === "measured");
    const once = r.filter((x) => x.kind === "once");
    const use = measured.length ? measured : once;
    const failed = r.filter((x) => x.exit_code !== "0" && x.kind !== "prep");
    const res = {
        stage: st,
        mode: measured.length ? `${r.filter((x) => x.kind === "warmup").length} warm-up + ${measured.length} measured` : "once",
        wall_s: stats(use.map((x) => num(x.wall_s))),
        max_rss_kb: stats(use.map((x) => num(x.max_rss_kb))),
        artifact: use.length ? use[0].artifact : null,
        artifact_bytes: stats(use.map((x) => num(x.artifact_bytes))),
        failed_runs: failed.length,
        raw: r,
    };
    for (const [metric, s] of [["wall_s", res.wall_s], ["max_rss_kb", res.max_rss_kb], ["artifact_bytes", res.artifact_bytes]]) {
        if (!s) continue;
        summary.push([rows[0].platform_label, backend, st, res.mode, metric, s.n, s.median, s.mean, s.min, s.max, s.stdev_sample].join(","));
    }
    return res;
}

// ---- structural counts parsed from the actual tool outputs -------------
function circomStruct() {
    const comp = exists("artifacts/circom/compile_output.txt") ? rd("artifacts/circom/compile_output.txt") : "";
    const info = exists("artifacts/circom/r1cs_info.txt") ? rd("artifacts/circom/r1cs_info.txt") : "";
    const g = (re, t) => { const m = t.match(re); return m ? Number(m[1]) : null; };
    return {
        nonlinear_constraints: g(/non-linear constraints:\s*(\d+)/, comp),
        linear_constraints: g(/(?<!non-)linear constraints:\s*(\d+)/, comp),
        wires_compiler: g(/wires:\s*(\d+)/, comp),
        public_inputs: g(/public inputs:\s*(\d+)/, comp),
        private_inputs: g(/private inputs:\s*(\d+)/, comp),
        public_outputs: g(/public outputs:\s*(\d+)/, comp),
        r1cs_constraints: g(/# of Constraints:\s*(\d+)/, info),
        r1cs_wires: g(/# of Wires:\s*(\d+)/, info),
        unit_note: "R1CS constraints (Groth16 / snarkjs). Not comparable to ACIR opcodes or Barretenberg gates.",
    };
}
function noirStruct() {
    const info = exists("artifacts/noir/nargo_info.txt") ? rd("artifacts/noir/nargo_info.txt") : "";
    const gates = exists("artifacts/noir/bb_gates.txt") ? rd("artifacts/noir/bb_gates.txt") : "";
    const m = info.match(/\|\s*redemption\s*\|\s*main\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|/);
    const a = gates.match(/"acir_opcodes":\s*(\d+)/);
    const c = gates.match(/"circuit_size":\s*(\d+)/);
    return {
        acir_opcodes_nargo_info: m ? Number(m[1]) : null,
        brillig_opcodes_main: m ? Number(m[2]) : null,
        acir_opcodes_bb_gates: a ? Number(a[1]) : null,
        barretenberg_circuit_size_gates: c ? Number(c[1]) : null,
        unit_note: "ACIR opcodes (Noir IR) and Barretenberg UltraHonk gates. Not comparable to R1CS constraints.",
    };
}

const circom = {
    backend: "Circom 2.2.3 + snarkjs Groth16 (BN254)",
    structural: circomStruct(),
    stages: {},
};
for (const s of ["compile", "r1cs_info", "witness", "ptau_new", "ptau_contribute", "ptau_prepare_phase2", "groth16_setup", "zkey_contribute", "vk_export", "prove", "verify"]) {
    circom.stages[s] = stage("circom", s);
}
const noir = {
    backend: "Noir (nargo) + Barretenberg UltraHonk (BN254)",
    structural: noirStruct(),
    stages: {},
};
for (const s of ["compile", "nargo_info", "bb_gates", "execute", "write_vk", "prove", "verify"]) {
    noir.stages[s] = stage("noir", s);
}

// Artifact provenance (path, bytes, SHA-256) from artifact_manifest.sha256,
// which the measurement stage writes from the actual generated files.
const am = {};
if (exists("artifact_manifest.sha256")) {
    for (const l of rd("artifact_manifest.sha256").split("\n")) {
        if (!l) continue;
        const [p, b, h] = l.split("\t");
        am[p] = { path: p, bytes: Number(b), sha256: h };
    }
}
const art = (p) => am[p] || { path: p, bytes: null, sha256: null, missing: true };
circom.final_artifacts = {
    proof_json: art("artifacts/circom/proof_measured1.json"),
    public_json: art("artifacts/circom/public_measured1.json"),
    verification_key_json: art("artifacts/circom/verification_key.json"),
    proving_key_zkey: art("artifacts/circom/circuit_final.zkey"),
    r1cs: art("artifacts/circom/redemption.r1cs"),
    wasm: art("artifacts/circom/redemption_js/redemption.wasm"),
    pot_final_ptau: art("artifacts/circom/pot_final.ptau"),
};
circom.all_proofs = Object.values(am).filter((a) => /^artifacts\/circom\/proof_.*\.json$/.test(a.path));
noir.final_artifacts = {
    proof: art("artifacts/noir/prove_measured1/proof"),
    public_inputs: art("artifacts/noir/prove_measured1/public_inputs"),
    vk: art("artifacts/noir/vk/vk"),
    acir_program_json: art("artifacts/noir/redemption.json"),
    witness_gz: art("artifacts/noir/witness.gz"),
};
noir.all_proofs = Object.values(am).filter((a) => /^artifacts\/noir\/prove_[^/]+\/proof$/.test(a.path));
circom.artifact_bytes = Object.fromEntries(Object.entries(circom.final_artifacts).map(([k, v]) => [k, v.bytes]));
noir.artifact_bytes = Object.fromEntries(Object.entries(noir.final_artifacts).map(([k, v]) => [k, v.bytes]));

const meta = exists("benchmark_metadata.json") ? JSON.parse(rd("benchmark_metadata.json")) : {};
circom.metadata_ref = noir.metadata_ref = "benchmark_metadata.json";

fs.writeFileSync(path.join(OUT, "circom_results.json"), JSON.stringify(circom, null, 2) + "\n");
fs.writeFileSync(path.join(OUT, "noir_results.json"), JSON.stringify(noir, null, 2) + "\n");
fs.writeFileSync(path.join(OUT, "summary.csv"),
    "platform_label,backend,stage,mode,metric,n,median,mean,min,max,stdev_sample\n" + summary.join("\n") + "\n");

// ---- human-readable report --------------------------------------------
const f3 = (x) => (x === null || x === undefined ? "n/a" : Number(x).toFixed(3));
const kb2mb = (x) => (x === null || x === undefined ? "n/a" : (x / 1024).toFixed(2));
function line(res) {
    const w = res.wall_s, m = res.max_rss_kb;
    return `${res.stage.padEnd(20)} ${res.mode.padEnd(22)} wall median ${f3(w && w.median)} s ` +
        `(mean ${f3(w && w.mean)}, min ${f3(w && w.min)}, max ${f3(w && w.max)}, sd ${f3(w && w.stdev_sample)}); ` +
        `peak RSS median ${kb2mb(m && m.median)} MiB (max ${kb2mb(m && m.max)} MiB)` +
        (res.failed_runs ? `  FAILED RUNS: ${res.failed_runs}` : "");
}
const r = [];
r.push("zk-ePrescription — final benchmark of the aligned implementation");
r.push(`Platform label : ${rows[0].platform_label}`);
r.push(`Image          : ${meta.docker && meta.docker.benchmark_image_id || "see benchmark_metadata.json"}`);
r.push(`Input          : TV-001 (canonical aligned fixture)`);
r.push("");
r.push("STRUCTURAL METRICS (backend-native units — NOT comparable across backends)");
r.push(`  Circom R1CS constraints : ${circom.structural.r1cs_constraints} (non-linear ${circom.structural.nonlinear_constraints} + linear ${circom.structural.linear_constraints}); wires ${circom.structural.r1cs_wires}`);
r.push(`  Noir ACIR opcodes       : ${noir.structural.acir_opcodes_nargo_info} (bb gates reports ${noir.structural.acir_opcodes_bb_gates})`);
r.push(`  Barretenberg gates      : ${noir.structural.barretenberg_circuit_size_gates}`);
r.push("");
r.push("CIRCOM + GROTH16");
r.push("  Development/setup infrastructure (once; NOT part of per-redemption latency):");
for (const s of ["ptau_new", "ptau_contribute", "ptau_prepare_phase2", "groth16_setup", "zkey_contribute", "vk_export"]) r.push("    " + line(circom.stages[s]));
r.push("  Build:");
r.push("    " + line(circom.stages.compile));
r.push("  Online (per redemption):");
for (const s of ["witness", "prove", "verify"]) r.push("    " + line(circom.stages[s]));
for (const k of ["proof_json", "verification_key_json", "proving_key_zkey", "pot_final_ptau"]) {
    const a = circom.final_artifacts[k];
    r.push(`  ${k.padEnd(22)} ${String(a.bytes).padStart(9)} B  sha256 ${a.sha256}  ${a.path}`);
}
r.push("");
r.push("NOIR + ULTRAHONK");
r.push("  Offline (once):");
r.push("    " + line(noir.stages.write_vk));
r.push("  Build:");
r.push("    " + line(noir.stages.compile));
r.push("  Online (per redemption):");
for (const s of ["execute", "prove", "verify"]) r.push("    " + line(noir.stages[s]));
for (const k of ["proof", "vk", "public_inputs"]) {
    const a = noir.final_artifacts[k];
    r.push(`  ${k.padEnd(22)} ${String(a.bytes).padStart(9)} B  sha256 ${a.sha256}  ${a.path}`);
}
r.push("");
r.push("PLATFORM (measured; see benchmark_metadata.json)");
const H = meta.host || {}, D = meta.docker || {}, T = meta.toolchain || {}, K = meta.container || {};
r.push(`  hostname ${meta.hostname || "n/a"}; ${H.os_release || "n/a"}; kernel ${H.kernel || "n/a"}; arch ${H.architecture || "n/a"}`);
r.push(`  CPU ${H.cpu_model || "n/a"}; logical CPUs ${H.logical_cpus ?? "n/a"}${H.device_model && H.device_model !== "unavailable" ? "; device " + H.device_model : ""}`);
r.push(`  host physical RAM (Windows) ${typeof H.windows_host_physical_ram_bytes === "number" ? (H.windows_host_physical_ram_bytes / 2 ** 30).toFixed(2) + " GiB" : H.windows_host_physical_ram_bytes || "n/a"}`);
if (typeof H.macos_host_physical_ram_bytes === "number") r.push(`  host physical RAM (macOS) ${(H.macos_host_physical_ram_bytes / 2 ** 30).toFixed(2)} GiB; ${H.macos_host_os}; ${H.macos_host_cores} cores; power ${H.macos_host_power}; low power mode ${H.macos_host_lowpowermode}`);
r.push(`  Linux/WSL-visible MemTotal ${H.linux_visible_memtotal_kb ? (H.linux_visible_memtotal_kb / 2 ** 20).toFixed(2) + " GiB" : "n/a"}; Docker-visible ${D.docker_visible_memtotal_bytes ? (D.docker_visible_memtotal_bytes / 2 ** 30).toFixed(2) + " GiB" : "n/a"}, ${D.docker_visible_ncpu ?? "n/a"} CPUs; container MemTotal ${K.memtotal_kb ? (K.memtotal_kb / 2 ** 20).toFixed(2) + " GiB" : "n/a"}`);
r.push(`  Docker ${D.server_version || "n/a"}; image ${D.base_image_id || "n/a"} (created ${D.base_image_created || "n/a"}); benchmark image ${D.benchmark_image_id || "n/a"}${D.derived_image_used ? " (derived: + GNU time only)" : ""}`);
r.push(`  ${T.circom || ""} | ${T.snarkjs || ""} | ${T.nargo || ""} | bb ${T.bb || ""} | node ${T.node || ""}`);
r.push("  Current machine configuration as-is; not a reproduction of any historical benchmark configuration.");
r.push("");
r.push("STATISTICAL METHODOLOGY");
r.push(`  compile: ${(meta.methodology || {}).warmup ?? 1} warm-up + ${(meta.methodology || {}).measured_runs_compile ?? 3} measured; witness/prove/verify: ${(meta.methodology || {}).warmup ?? 1} warm-up + ${(meta.methodology || {}).measured_runs_witness_prove_verify ?? 5} measured; setup stages once`);
r.push("  statistics over measured runs only: median (primary), mean, min, max, sample standard deviation; all raw runs in raw_runs.csv");
r.push("");
r.push("NOTES");
r.push("  * Median is the primary statistic; mean/min/max/sample-sd from the same measured runs.");
r.push("  * Peak RSS = GNU time 'Maximum resident set size' of the measured process.");
r.push("  * snarkjs/node timings include Node.js process start-up (CLI invocation as in the regression).");
r.push("  * Noir prove uses the precomputed VK (bb prove -k); VK generation is reported separately (write_vk).");
r.push("  * The CRS-priming bb call is excluded from all statistics (kind=prep).");
r.push("  * Powers of Tau is circuit-independent setup infrastructure, reported separately.");
fs.writeFileSync(path.join(OUT, "benchmark_report.txt"), r.join("\n") + "\n");
console.log(r.join("\n"));
