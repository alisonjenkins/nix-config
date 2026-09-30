"use strict";
// Usage: merge-jsonc.js <target> <patch.json>
// Deep-merges the patch into a JSONC file, editing only the touched values so
// comments, key order and formatting elsewhere survive.
const fs = require("fs");
const path = require("path");
const { isDeepStrictEqual } = require("util");
const jsonc = require("@jsoncParser@/lib/umd/main.js");

const [target, patchFile] = process.argv.slice(2);

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const skip = (why) => {
  console.error("copilot-cli: not updating " + target + ": " + why);
  process.exit(0);
};
process.on("uncaughtException", (err) => skip(err.message));

let text = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : "";
const bom = text.startsWith("\uFEFF") ? "\uFEFF" : "";
text = text.slice(bom.length);
if (jsonc.stripComments(text).trim() === "") text = text.trimEnd() + "\n{}\n";

const errors = [];
const existing = jsonc.parse(text, errors, { allowTrailingComma: true });
if (errors.length > 0) skip("it is not valid JSONC");
if (!isObject(existing)) skip("its top level is not an object");

const patch = JSON.parse(fs.readFileSync(patchFile, "utf8"));
const formattingOptions = { insertSpaces: true, tabSize: 2 };

// Same semantics as the jq merge used for the other files: objects merge
// recursively, anything else (arrays, scalars) is replaced by the patch;
// a null existing value counts as absent.
const apply = (keyPath, patchValue, existingValue) => {
  if (isObject(patchValue) && isObject(existingValue)) {
    for (const key of Object.keys(patchValue)) {
      apply(keyPath.concat(key), patchValue[key], existingValue[key]);
    }
    return;
  }
  if (isDeepStrictEqual(patchValue, existingValue)) return;
  text = jsonc.applyEdits(text, jsonc.modify(text, keyPath, patchValue, { formattingOptions }));
};

for (const key of Object.keys(patch)) apply([key], patch[key], existing[key]);

const after = [];
jsonc.parse(text, after, { allowTrailingComma: true });
if (after.length > 0) skip("the merged result did not parse; refusing to write it");

text = bom + text;
const original = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : null;
if (original === text) process.exit(0);

fs.mkdirSync(path.dirname(target), { recursive: true });
const tmp = target + "." + process.pid + ".tmp";
try {
  fs.writeFileSync(tmp, text, { mode: original === null ? 0o600 : fs.statSync(target).mode });
  fs.renameSync(tmp, target);
} finally {
  fs.rmSync(tmp, { force: true });
}
