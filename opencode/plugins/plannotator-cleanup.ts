import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DEFAULT_TIMEOUT_MS = 1000;
const SHUTDOWN_TIMEOUT_MS = 3000;
const PORT_RELEASE_TIMEOUT_MS = 3000;
const POLL_INTERVAL_MS = 150;
const DEFAULT_PORT_BASE = 19432;
const DEFAULT_PORT_COUNT = 64;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getEnvInt(name: string, fallback: number) {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;
  const value = Number.parseInt(raw, 10);
  return Number.isInteger(value) ? value : fallback;
}

function getPortBase() {
  const base = getEnvInt("PLANNOTATOR_PORT_BASE", DEFAULT_PORT_BASE);
  return base > 0 && base <= 65535 ? base : DEFAULT_PORT_BASE;
}

function getPortCount(base: number) {
  const count = getEnvInt("PLANNOTATOR_PORT_COUNT", DEFAULT_PORT_COUNT);
  return count > 0 && base + count <= 65536 ? count : DEFAULT_PORT_COUNT;
}

function getPortLockDir() {
  return process.env.PLANNOTATOR_PORT_LOCK_DIR?.trim() || join(homedir(), ".plannotator", "session-ports");
}

function fnv1a(input: string) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function sessionFileName(sessionID: string) {
  return `${fnv1a(sessionID).toString(16)}.session`;
}

function getSessionPortMapPath(dir: string) {
  return join(dir, "session-port-map.json");
}

type SessionPortMap = Record<string, number>;

function readTrimmed(path: string) {
  try {
    return readFileSync(path, "utf8").trim();
  } catch {
    return undefined;
  }
}

function readSessionPortMap(dir: string): SessionPortMap {
  const path = getSessionPortMapPath(dir);
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};

    const result: SessionPortMap = {};
    for (const [sessionID, port] of Object.entries(parsed)) {
      if (typeof sessionID === "string" && Number.isInteger(port)) result[sessionID] = port;
    }
    return result;
  } catch {
    return {};
  }
}

function writeSessionPortMap(dir: string, map: SessionPortMap) {
  const path = getSessionPortMapPath(dir);
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(map, Object.keys(map).sort(), 2)}\n`);
  renameSync(tmp, path);
}

function removeMappingFiles(dir: string, sessionID: string, port: number) {
  rmSync(join(dir, sessionFileName(sessionID)), { force: true });
  if (readTrimmed(join(dir, `${port}.lock`)) === sessionID) {
    rmSync(join(dir, `${port}.lock`), { force: true });
  }
}

function writeMapping(dir: string, sessionID: string, port: number) {
  mkdirSync(dir, { recursive: true });
  const map = readSessionPortMap(dir);
  map[sessionID] = port;
  writeSessionPortMap(dir, map);

  // Keep the older per-session files as human-friendly breadcrumbs and for
  // compatibility with any shells/tools that already inspected this directory.
  writeFileSync(join(dir, sessionFileName(sessionID)), `${port}\n`);
  writeFileSync(join(dir, `${port}.lock`), `${sessionID}\n`);
}

async function fetchWithTimeout(url: string, init: RequestInit = {}, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function isPlannotatorServer(baseUrl: string) {
  try {
    const response = await fetchWithTimeout(`${baseUrl}/api/plan`);
    return response.ok;
  } catch {
    return false;
  }
}

async function pruneInactiveMappings(dir: string, map: SessionPortMap, base: number, count: number) {
  const next: SessionPortMap = {};
  let removed = 0;

  for (const [sessionID, port] of Object.entries(map)) {
    if (!isValidPort(port, base, count)) {
      removeMappingFiles(dir, sessionID, port);
      removed += 1;
      continue;
    }

    if (await isPlannotatorServer(`http://localhost:${port}`)) {
      next[sessionID] = port;
      continue;
    }

    removeMappingFiles(dir, sessionID, port);
    removed += 1;
  }

  if (removed > 0) writeSessionPortMap(dir, next);
  return next;
}

function isValidPort(port: number, base: number, count: number) {
  return Number.isInteger(port) && port >= base && port < base + count && port > 0 && port <= 65535;
}

async function getSessionPort(sessionID: string) {
  const base = getPortBase();
  const count = getPortCount(base);
  const dir = getPortLockDir();
  mkdirSync(dir, { recursive: true });

  const map = readSessionPortMap(dir);
  const mapped = map[sessionID];
  if (isValidPort(mapped, base, count)) {
    writeMapping(dir, sessionID, mapped);
    return mapped;
  }

  const legacy = Number.parseInt(readTrimmed(join(dir, sessionFileName(sessionID))) || "", 10);
  if (isValidPort(legacy, base, count)) {
    writeMapping(dir, sessionID, legacy);
    return legacy;
  }

  let activeMap = map;
  let usedPorts = new Set(Object.values(activeMap).filter((port) => isValidPort(port, base, count)));
  const start = fnv1a(sessionID) % count;
  for (let offset = 0; offset < count; offset += 1) {
    const port = base + ((start + offset) % count);
    if (!usedPorts.has(port)) {
      writeMapping(dir, sessionID, port);
      return port;
    }
  }

  activeMap = await pruneInactiveMappings(dir, map, base, count);
  usedPorts = new Set(Object.values(activeMap).filter((port) => isValidPort(port, base, count)));
  for (let offset = 0; offset < count; offset += 1) {
    const port = base + ((start + offset) % count);
    if (!usedPorts.has(port)) {
      writeMapping(dir, sessionID, port);
      return port;
    }
  }

  throw new Error(`No free Plannotator ports in ${base}..${base + count - 1}. Run ~/.config/opencode/scripts/plannotator-port-cleaner.js or increase PLANNOTATOR_PORT_COUNT. Map: ${getSessionPortMapPath(dir)}`);
}

function setPlannotatorPort(port: number) {
  process.env.PLANNOTATOR_PORT = String(port);
  process.env.PLANNOTATOR_REMOTE ??= "1";
}

async function waitForServerToStop(baseUrl: string) {
  const deadline = Date.now() + PORT_RELEASE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (!(await isPlannotatorServer(baseUrl))) return true;
    await sleep(POLL_INTERVAL_MS);
  }
  return false;
}

export default (async ({ client }) => {
  async function log(level: "info" | "warn", message: string) {
    try {
      await client.app.log({ level, message });
    } catch {
      // Logging should never block tool execution.
    }
  }

  return {
    "tool.execute.before": async (input) => {
      if (input.tool !== "submit_plan") return;

      let port: number;
      try {
        port = await getSessionPort(input.sessionID);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Could not allocate session port.";
        await log("warn", `[Plannotator] ${message}`);
        delete process.env.PLANNOTATOR_PORT;
        throw new Error(`[Plannotator] ${message}`);
      }

      setPlannotatorPort(port);

      const baseUrl = `http://localhost:${port}`;
      if (!(await isPlannotatorServer(baseUrl))) return;

      await log("info", `[Plannotator] Closing previous plan on port ${port} before opening a new one.`);

      try {
        await fetchWithTimeout(
          `${baseUrl}/api/deny`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              feedback: "Previous plan superseded by a new submission.",
              planSave: { enabled: false },
            }),
          },
          SHUTDOWN_TIMEOUT_MS,
        );
      } catch {
        await log("warn", `[Plannotator] Previous plan on port ${port} did not respond to cleanup.`);
        return;
      }

      if (!(await waitForServerToStop(baseUrl))) {
        await log("warn", `[Plannotator] Previous plan on port ${port} is still running after cleanup.`);
      }

      setPlannotatorPort(port);
    },
  };
}) satisfies Plugin;
