#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const SUPPORTED_VERSION = "0.23.1";
const packageRoot = process.env.PLANNOTATOR_PI_PACKAGE_DIR
  || path.join(os.homedir(), ".pi", "agent", "npm", "node_modules", "@plannotator", "pi-extension");
const indexPath = process.env.PLANNOTATOR_PI_INDEX_TS
  || path.join(packageRoot, "index.ts");
const packageJsonPath = path.join(packageRoot, "package.json");

const patches = [
  {
    name: "browser opener import",
    before: 'import { isRemoteSession } from "./server/network.js";',
    after: 'import { isRemoteSession, openBrowser } from "./server/network.js";',
  },
  {
    name: "single-review state",
    before: `\tlet justApprovedPlan = false;`,
    after: `\tlet justApprovedPlan = false;
\t// A Pi process owns one fixed remote port, so a second review server cannot
\t// bind while the first is alive. Reopen the active review and suppress
\t// concurrent startup instead of retrying the same port.
\tlet activeCodeReviewSession: Awaited<ReturnType<typeof startCodeReviewBrowserSession>> | undefined;
\tlet codeReviewStarting = false;
\tlet plannotatorRuntimeActive = true;`,
  },
  {
    name: "session cleanup",
    before: `\tpi.on("session_start", (_event, ctx) => {
\t\tcurrentPiSession.update(ctx);
\t});

\tpi.on("session_shutdown", () => {
\t\tcurrentPiSession.clear();
\t});`,
    after: `\tpi.on("session_start", (_event, ctx) => {
\t\tplannotatorRuntimeActive = true;
\t\tcurrentPiSession.update(ctx);
\t});

\tpi.on("session_shutdown", () => {
\t\tplannotatorRuntimeActive = false;
\t\tcodeReviewStarting = false;
\t\tactiveCodeReviewSession?.stop();
\t\tactiveCodeReviewSession = undefined;
\t\tcurrentPiSession.clear();
\t});`,
  },
  {
    name: "review reentry guard",
    before: `\t\t\tcurrentPiSession.update(ctx);
\t\t\tconst origin = getPiSessionIdentity(ctx);

\t\t\ttry {
\t\t\t\tconst reviewArgs = parseReviewArgs(args ?? "");`,
    after: `\t\t\tcurrentPiSession.update(ctx);
\t\t\tconst origin = getPiSessionIdentity(ctx);

\t\t\tif (activeCodeReviewSession) {
\t\t\t\tawait openBrowser(activeCodeReviewSession.url);
\t\t\t\tctx.ui.notify(
\t\t\t\t\tsessionOpenedMessage("Code review already open", activeCodeReviewSession.url),
\t\t\t\t\t"info",
\t\t\t\t);
\t\t\t\treturn;
\t\t\t}
\t\t\tif (codeReviewStarting) {
\t\t\t\tctx.ui.notify("Code review is already starting.", "info");
\t\t\t\treturn;
\t\t\t}
\n\t\t\tcodeReviewStarting = true;
\t\t\ttry {
\t\t\t\tconst reviewArgs = parseReviewArgs(args ?? "");`,
  },
  {
    name: "active review assignment",
    before: `\t\t\t\tconst session = await startCodeReviewBrowserSession(ctx, {
\t\t\t\t\tprUrl: reviewArgs.prUrl,
\t\t\t\t\tvcsType: reviewArgs.vcsType,
\t\t\t\t\tuseLocal: reviewArgs.useLocal,
\t\t\t\t});
\t\t\t\tctx.ui.notify(sessionOpenedMessage("Code review opened", session.url), "info");`,
    after: `\t\t\t\tconst session = await startCodeReviewBrowserSession(ctx, {
\t\t\t\t\tprUrl: reviewArgs.prUrl,
\t\t\t\t\tvcsType: reviewArgs.vcsType,
\t\t\t\t\tuseLocal: reviewArgs.useLocal,
\t\t\t\t});
\t\t\t\tif (!plannotatorRuntimeActive) {
\t\t\t\t\tsession.stop();
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t\tactiveCodeReviewSession = session;
\t\t\t\tctx.ui.notify(sessionOpenedMessage("Code review opened", session.url), "info");`,
  },
  {
    name: "review completion cleanup",
    before: `\t\t\t\t\t.catch((err) => {
\t\t\t\t\t\treportBackgroundError(ctx, "Plannotator code review session failed", err, origin);
\t\t\t\t\t});
\t\t\t} catch (err) {
\t\t\t\tctx.ui.notify(
\t\t\t\t\t\`Failed to start code review UI: \${getStartupErrorMessage(err)}\`,
\t\t\t\t\t"error",
\t\t\t\t);
\t\t\t}
\t\t},`,
    after: `\t\t\t\t\t.catch((err) => {
\t\t\t\t\t\tif (plannotatorRuntimeActive) {
\t\t\t\t\t\t\treportBackgroundError(ctx, "Plannotator code review session failed", err, origin);
\t\t\t\t\t\t}
\t\t\t\t\t})
\t\t\t\t\t.finally(() => {
\t\t\t\t\t\tif (activeCodeReviewSession === session) activeCodeReviewSession = undefined;
\t\t\t\t\t});
\t\t\t} catch (err) {
\t\t\t\tctx.ui.notify(
\t\t\t\t\t\`Failed to start code review UI: \${getStartupErrorMessage(err)}\`,
\t\t\t\t\t"error",
\t\t\t\t);
\t\t\t} finally {
\t\t\t\tcodeReviewStarting = false;
\t\t\t}
\t\t},`,
  },
];

function occurrenceCount(source, text) {
  return source.split(text).length - 1;
}

function patchSource(source) {
  const afterCount = patches.filter(({ after }) => source.includes(after)).length;
  if (afterCount === patches.length) return { source, changed: false };
  if (afterCount !== 0) {
    throw new Error("partial single-review patch detected; reinstall the pinned package before retrying");
  }

  let patched = source;
  for (const { name, before, after } of patches) {
    const count = occurrenceCount(patched, before);
    if (count !== 1) {
      throw new Error(`expected exactly one ${name} target, found ${count}; package may have changed upstream`);
    }
    patched = patched.replace(before, after);
  }
  return { source: patched, changed: true };
}

function readInstalledVersion() {
  if (!fs.existsSync(packageJsonPath)) {
    throw new Error(`package metadata not found: ${packageJsonPath}`);
  }
  return JSON.parse(fs.readFileSync(packageJsonPath, "utf8")).version;
}

function patchInstalledPackage() {
  const version = readInstalledVersion();
  if (version !== SUPPORTED_VERSION) {
    throw new Error(`expected @plannotator/pi-extension ${SUPPORTED_VERSION}, found ${version}`);
  }
  if (!fs.existsSync(indexPath)) throw new Error(`extension source not found: ${indexPath}`);

  const original = fs.readFileSync(indexPath, "utf8");
  const result = patchSource(original);
  if (!result.changed) {
    console.error(`[Plannotator Pi patch] already applied: ${indexPath}`);
    return false;
  }

  const tempPath = `${indexPath}.${process.pid}.tmp`;
  fs.writeFileSync(tempPath, result.source, { encoding: "utf8", mode: fs.statSync(indexPath).mode });
  fs.renameSync(tempPath, indexPath);
  console.error(`[Plannotator Pi patch] applied single-active-review guard: ${indexPath}`);
  return true;
}

if (require.main === module) {
  try {
    patchInstalledPackage();
  } catch (error) {
    console.error(`[Plannotator Pi patch] ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

module.exports = {
  SUPPORTED_VERSION,
  indexPath,
  patches,
  patchSource,
  patchInstalledPackage,
};
