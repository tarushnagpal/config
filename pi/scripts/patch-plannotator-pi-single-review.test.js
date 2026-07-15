const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const {
  SUPPORTED_VERSION,
  indexPath,
  patches,
  patchSource,
} = require("./patch-plannotator-pi-single-review.js");

test("applies every single-review patch exactly once", () => {
  const fixture = patches.map(({ before }, index) => `// fixture ${index}\n${before}`).join("\n\n");
  const first = patchSource(fixture);

  assert.equal(first.changed, true);
  for (const { after } of patches) assert.ok(first.source.includes(after));

  const second = patchSource(first.source);
  assert.equal(second.changed, false);
  assert.equal(second.source, first.source);
});

test("rejects partial patches instead of producing mixed source", () => {
  const fixture = [patches[0].after, ...patches.slice(1).map(({ before }) => before)].join("\n\n");
  assert.throws(() => patchSource(fixture), /partial single-review patch detected/);
});

test("rejects changed upstream source", () => {
  const fixture = patches.slice(1).map(({ before }) => before).join("\n\n");
  assert.throws(() => patchSource(fixture), /browser opener import target, found 0/);
});

test("installed pinned package contains the complete patch", () => {
  const packageJsonPath = indexPath.replace(/index\.ts$/, "package.json");
  const version = JSON.parse(fs.readFileSync(packageJsonPath, "utf8")).version;
  const source = fs.readFileSync(indexPath, "utf8");

  assert.equal(version, SUPPORTED_VERSION);
  assert.equal(patchSource(source).changed, false);
});
