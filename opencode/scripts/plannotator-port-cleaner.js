#!/usr/bin/env node
const { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } = require("node:fs");
const { homedir } = require("node:os");
const { join } = require("node:path");

const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run") || args.has("-n");

function loadEnvFile(path) {
  if (!existsSync(path)) return;
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  for (const line of lines) {
    if (!line || line.trimStart().startsWith("#")) continue;
    const index = line.indexOf("=");
    if (index <= 0) continue;
    const key = line.slice(0, index).trim();
    const value = line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "");
    process.env[key] ??= value;
  }
}

function envInt(name, fallback) {
  const value = Number.parseInt(process.env[name] || "", 10);
  return Number.isInteger(value) ? value : fallback;
}

function fnv1a(input) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function sessionFileName(sessionID) {
  return `${fnv1a(sessionID).toString(16)}.session`;
}

async function isPlannotatorServer(port) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 700);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/api/plan`, { signal: controller.signal });
    return response.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

function readMap(path) {
  if (!existsSync(path)) return {};
  const parsed = JSON.parse(readFileSync(path, "utf8"));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  return parsed;
}

function writeMap(path, map) {
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(map, Object.keys(map).sort(), 2)}\n`);
  renameSync(tmp, path);
}

async function main() {
  loadEnvFile(process.env.OPENCODE_WEB_ENV_FILE || join(homedir(), ".local/state/opencode-web.env"));

  const base = envInt("PLANNOTATOR_PORT_BASE", 19432);
  const count = envInt("PLANNOTATOR_PORT_COUNT", 64);
  const dir = process.env.PLANNOTATOR_PORT_LOCK_DIR || join(homedir(), ".plannotator/session-ports");
  const mapPath = join(dir, "session-port-map.json");
  mkdirSync(dir, { recursive: true });

  const map = readMap(mapPath);
  const next = {};
  const removed = [];
  const kept = [];

  for (const [sessionID, rawPort] of Object.entries(map)) {
    const port = Number(rawPort);
    const valid = Number.isInteger(port) && port >= base && port < base + count;
    const active = valid ? await isPlannotatorServer(port) : false;

    if (active) {
      next[sessionID] = port;
      kept.push([sessionID, port]);
      continue;
    }

    removed.push([sessionID, port, valid ? "inactive" : "out-of-range"]);
    if (!dryRun) {
      rmSync(join(dir, sessionFileName(sessionID)), { force: true });
      rmSync(join(dir, `${port}.lock`), { force: true });
    }
  }

  if (!dryRun) writeMap(mapPath, next);

  console.log(`Plannotator port cleaner (${dryRun ? "dry run" : "applied"})`);
  console.log(`Range: ${base}..${base + count - 1}`);
  console.log(`Kept active: ${kept.length}`);
  for (const [sessionID, port] of kept) console.log(`  keep ${port} ${sessionID}`);
  console.log(`Removed stale: ${removed.length}`);
  for (const [sessionID, port, reason] of removed) console.log(`  remove ${port} ${sessionID} (${reason})`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
