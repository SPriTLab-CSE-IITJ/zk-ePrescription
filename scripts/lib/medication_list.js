// Medication list of a prescription and its digest D (protocol v3,
// docs/protocol_specification.md Section 6.1).
//
// The doctor signs C = H1(pid, did, D, expiry, threshold, I) with
//
//     D = Hraw(7, L, b_0, ..., b_{k-1})
//
// where the medication list is encoded canonically as UTF-8 bytes,
//
//     for each item, in the doctor's order:
//         code 0x1F name 0x1F dosage 0x1F quantity 0x1E
//
// (0x1F = unit separator, 0x1E = record separator; quantity in decimal),
// L is the byte length and b_0..b_{k-1} are the bytes split into 31-byte
// big-endian chunks (the last one shorter), each below the BN254 modulus.
// Domain tag 7 is new in v3 (tag 6 is retired, see Section 5).
//
// The redemption proof outputs D. The patient's app sends the list in clear;
// the pharmacy recomputes D from it and shows the list only if it matches.
//
//   validate(list) -> throws on a malformed list
//   encode(list)   -> Buffer (canonical bytes)
//   digest(list)   -> BigInt D
//   render(list)   -> text table for the pharmacist
"use strict";
const path = require("path");
const p2 = require(path.join(__dirname, "../../circom/scripts/lib/poseidon2"));

const DOMAIN_MEDICATION_LIST = p2.DOMAIN.MEDICATION_LIST;
const US = 0x1f;
const RS = 0x1e;
const MAX_ITEMS = 32;
const MAX_TEXT = 200;
const MAX_BYTES = 4096;
const CHUNK = 31;

function fail(msg) { throw new Error(`invalid medication list: ${msg}`); }

function checkText(value, field, i) {
    if (typeof value !== "string" || value.length === 0) fail(`item ${i}: ${field} must be a non-empty string`);
    if (value.length > MAX_TEXT) fail(`item ${i}: ${field} longer than ${MAX_TEXT} characters`);
    if (value !== value.normalize("NFC")) fail(`item ${i}: ${field} is not in Unicode NFC form`);
    if (/[\u0000-\u001f\u007f]/.test(value)) fail(`item ${i}: ${field} contains a control character`);
}

function validate(list) {
    if (!Array.isArray(list) || list.length === 0) fail("must be a non-empty array");
    if (list.length > MAX_ITEMS) fail(`more than ${MAX_ITEMS} items`);
    list.forEach((item, i) => {
        if (item === null || typeof item !== "object") fail(`item ${i}: not an object`);
        const keys = Object.keys(item).sort().join(",");
        if (keys !== "code,dosage,name,quantity") fail(`item ${i}: fields must be exactly code, name, dosage, quantity`);
        if (typeof item.code !== "string" || !/^[0-9]{6,18}$/.test(item.code)) fail(`item ${i}: code must be 6-18 digits (SNOMED CT concept id)`);
        checkText(item.name, "name", i);
        checkText(item.dosage, "dosage", i);
        if (!Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > 1000000) fail(`item ${i}: quantity must be an integer 1..1000000`);
    });
    if (encodeUnchecked(list).length > MAX_BYTES) fail(`encoding longer than ${MAX_BYTES} bytes`);
}

function encodeUnchecked(list) {
    const parts = [];
    for (const item of list) {
        for (const [k, v] of [["code", item.code], ["name", item.name], ["dosage", item.dosage], ["quantity", String(item.quantity)]]) {
            parts.push(Buffer.from(v, "utf8"));
            parts.push(Buffer.from([k === "quantity" ? RS : US]));
        }
    }
    return Buffer.concat(parts);
}

function encode(list) {
    validate(list);
    return encodeUnchecked(list);
}

function digest(list) {
    const bytes = encode(list);
    const chunks = [];
    for (let i = 0; i < bytes.length; i += CHUNK) {
        chunks.push(BigInt("0x" + bytes.subarray(i, i + CHUNK).toString("hex")));
    }
    return p2.hashRaw([DOMAIN_MEDICATION_LIST, BigInt(bytes.length), ...chunks]);
}

function render(list) {
    const rows = list.map((m, i) => [String(i + 1), m.name, m.dosage, String(m.quantity), m.code]);
    const head = ["#", "medicine", "dosage", "qty", "code"];
    const w = head.map((h, c) => Math.max(h.length, ...rows.map((r) => r[c].length)));
    const line = (r) => r.map((x, c) => x.padEnd(w[c])).join("  ").trimEnd();
    return [line(head), line(w.map((n) => "-".repeat(n))), ...rows.map(line)].join("\n");
}

module.exports = { DOMAIN_MEDICATION_LIST, validate, encode, digest, render };
