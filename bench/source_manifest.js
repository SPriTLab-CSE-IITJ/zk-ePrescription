// Read-only source manifest generator (provenance evidence; used by bench/run_benchmark.sh).
//
//   node source_manifest.js <root> > manifest.sha256
//
// Output: one line per included regular file, sorted by byte order of path:
//   <relative_path>\t<size_bytes>\t<sha256>
// Excluded files (generated/build artifacts, logs, VCS data) are written to
// stderr as:  EXCLUDED\t<relative_path>\t<size>\t<sha256>\t<rule>
// The exclusion rules mirror the repository's .dockerignore / .gitignore plus
// transient files the test scripts create while running.
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const root = path.resolve(process.argv[2] || ".");

const DIR_RULES = [
    [/^(\.git|node_modules|target|build)$/, "build/VCS directory (.dockerignore/.gitignore)"],
    [/^results$/, "run output (.dockerignore/.gitignore)"],
];
const FILE_RULES = [
    [/\.log$/, "log file (.dockerignore *.log)"],
    [/\.(wtns|r1cs|sym|wasm|zkey|ptau)$/, "compiled/proving artifact (.gitignore/.dockerignore)"],
    [/^_vector\.toml$/, "transient Noir suite input"],
    [/^KAT_index_\d+\.toml$/, "transient registry-generator input"],
    [/^_(kat_index|demo|bench)\.toml$/, "transient Noir input written by the scripts"],
    [/^\.DS_Store$/, "OS metadata"],
];

const included = [];
const excluded = [];

function sha(file) {
    return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function walk(dir, rel, excludedBy) {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
        const abs = path.join(dir, ent.name);
        const r = rel ? rel + "/" + ent.name : ent.name;
        if (ent.isDirectory()) {
            let rule = excludedBy;
            if (!rule) for (const [re, why] of DIR_RULES) if (re.test(ent.name)) rule = why;
            walk(abs, r, rule);
        } else if (ent.isFile()) {
            let rule = excludedBy;
            if (!rule) for (const [re, why] of FILE_RULES) if (re.test(ent.name)) rule = why;
            const st = fs.statSync(abs);
            const rec = { r, size: st.size, h: sha(abs), rule };
            (rule ? excluded : included).push(rec);
        }
    }
}

walk(root, "", null);
const cmp = (a, b) => (Buffer.compare(Buffer.from(a.r), Buffer.from(b.r)));
included.sort(cmp);
excluded.sort(cmp);
for (const f of included) process.stdout.write(`${f.r}\t${f.size}\t${f.h}\n`);
// Excluded directories such as node_modules can be large; summarise them by rule
// and list individual excluded files outside those directories.
const byDir = {};
for (const f of excluded) {
    const m = f.r.match(/(^|\/)(node_modules|target|build|\.git)\//);
    if (m) {
        const key = f.r.slice(0, f.r.indexOf(m[2] + "/") + m[2].length);
        byDir[key] = byDir[key] || { n: 0, bytes: 0, rule: f.rule };
        byDir[key].n++; byDir[key].bytes += f.size;
    } else {
        process.stderr.write(`EXCLUDED\t${f.r}\t${f.size}\t${f.h}\t${f.rule}\n`);
    }
}
for (const [d, v] of Object.entries(byDir).sort()) {
    process.stderr.write(`EXCLUDED_DIR\t${d}/\t${v.n} files\t${v.bytes} bytes\t${v.rule}\n`);
}
