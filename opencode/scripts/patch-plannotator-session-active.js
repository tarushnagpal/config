#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const indexPath = process.env.PLANNOTATOR_OPENCODE_INDEX_JS
  || path.join(
    os.homedir(),
    ".cache/opencode/packages/@plannotator/opencode@latest/node_modules/@plannotator/opencode/dist/index.js",
  );

const beforeFunction = `function getPlanBackingPath(project) {
  return path.join(getPlannotatorDataDir(), "active", project, "_active-plan.md");
}`;

const afterFunction = `function getPlanBackingPath(project, sessionID) {
  const session = sessionID ? sanitizeTag(sessionID) : "_unknown-session";
  return path.join(getPlannotatorDataDir(), "active", project, session, "_active-plan.md");
}`;

const beforeCall = "const backingPath = getPlanBackingPath(project);";
const afterCall = "const backingPath = getPlanBackingPath(project, context.sessionID);";

function fail(message) {
  console.error(`[Plannotator patch] ${message}`);
  process.exitCode = 1;
}

if (!fs.existsSync(indexPath)) {
  fail(`plugin index not found: ${indexPath}`);
  process.exit();
}

let source = fs.readFileSync(indexPath, "utf8");
const alreadyPatched = source.includes(afterFunction) && source.includes(afterCall);

if (alreadyPatched) {
  console.error(`[Plannotator patch] already applied: ${indexPath}`);
  process.exit();
}

if (!source.includes(beforeFunction)) {
  fail("expected getPlanBackingPath implementation was not found; plugin may have changed upstream");
  process.exit();
}

if (!source.includes(beforeCall)) {
  fail("expected getPlanBackingPath call site was not found; plugin may have changed upstream");
  process.exit();
}

source = source.replace(beforeFunction, afterFunction).replace(beforeCall, afterCall);
fs.writeFileSync(indexPath, source, "utf8");
console.error(`[Plannotator patch] applied session-scoped active plan backing file: ${indexPath}`);
