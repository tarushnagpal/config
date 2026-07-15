import { closeSync, mkdirSync, openSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { hostname } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

const MALFORMED_LOCK_GRACE_MS = 10_000;

export interface LockOwner {
  sessionId: string;
  pid: number;
  processStart: string | null;
  token: string;
  host: string;
  createdAt: string;
}

export interface PortAllocation {
  port: number;
  lockPath: string;
  owner: LockOwner;
  release: () => void;
}

export interface AllocatorOptions {
  sessionId: string;
  base: number;
  count: number;
  stateDir: string;
  owner?: LockOwner;
  isOwnerAlive?: (owner: LockOwner) => boolean;
  isPortAvailable?: (port: number) => Promise<boolean>;
  now?: () => number;
  malformedLockGraceMs?: number;
}

export function fnv1a(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function readLinuxProcessStart(pid: number): string | null {
  if (process.platform !== "linux") return null;
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    const closingParen = stat.lastIndexOf(")");
    if (closingParen < 0) return null;
    const fieldsFromState = stat.slice(closingParen + 2).trim().split(/\s+/);
    const startTicks = fieldsFromState[19]; // /proc stat field 22; this array starts at field 3.
    return startTicks ? `${pid}:${startTicks}` : null;
  } catch {
    return null;
  }
}

export function currentLockOwner(sessionId: string): LockOwner {
  return {
    sessionId,
    pid: process.pid,
    processStart: readLinuxProcessStart(process.pid),
    token: randomUUID(),
    host: hostname(),
    createdAt: new Date().toISOString(),
  };
}

export function isLockOwnerAlive(owner: LockOwner): boolean {
  if (!Number.isInteger(owner.pid) || owner.pid <= 0) return false;
  if (owner.host !== hostname()) return true;
  try {
    process.kill(owner.pid, 0);
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }

  if (!owner.processStart) return true;
  return readLinuxProcessStart(owner.pid) === owner.processStart;
}

export function probePort(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = createServer();
    server.unref();
    server.once("error", () => resolve(false));
    server.listen({ port, host: "0.0.0.0", exclusive: true }, () => {
      server.close(() => resolve(true));
    });
  });
}

function isLockOwner(value: unknown): value is LockOwner {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const owner = value as Partial<LockOwner>;
  return typeof owner.sessionId === "string" &&
    Number.isInteger(owner.pid) &&
    (typeof owner.processStart === "string" || owner.processStart === null) &&
    typeof owner.token === "string" &&
    typeof owner.host === "string" &&
    typeof owner.createdAt === "string";
}

function readOwner(lockPath: string): LockOwner | null {
  try {
    const parsed: unknown = JSON.parse(readFileSync(lockPath, "utf8"));
    return isLockOwner(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function lockAgeMs(lockPath: string, now: number): number {
  try {
    return Math.max(0, now - statSync(lockPath).mtimeMs);
  } catch {
    return 0;
  }
}

function unlinkIfOwned(lockPath: string, token: string): void {
  const current = readOwner(lockPath);
  if (current?.token !== token) return;
  try {
    unlinkSync(lockPath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

function tryCreateLock(lockPath: string, owner: LockOwner): boolean {
  let fd: number;
  try {
    fd = openSync(lockPath, "wx", 0o600);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") return false;
    throw error;
  }

  try {
    writeFileSync(fd, `${JSON.stringify(owner, null, 2)}\n`, "utf8");
  } catch (error) {
    closeSync(fd);
    try {
      unlinkSync(lockPath);
    } catch {
      // Preserve the original write failure.
    }
    throw error;
  }
  closeSync(fd);
  return true;
}

function reclaimStaleLock(
  lockPath: string,
  isOwnerAlive: (owner: LockOwner) => boolean,
  now: number,
  malformedLockGraceMs: number,
): boolean {
  const existing = readOwner(lockPath);
  if (existing ? isOwnerAlive(existing) : lockAgeMs(lockPath, now) < malformedLockGraceMs) return false;
  try {
    unlinkSync(lockPath);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return true;
    return false;
  }
}

function validateRange(base: number, count: number): void {
  if (!Number.isInteger(base) || base < 1 || base > 65_535) {
    throw new Error(`Invalid Pi Plannotator port base: ${base}`);
  }
  if (!Number.isInteger(count) || count < 1 || base + count - 1 > 65_535) {
    throw new Error(`Invalid Pi Plannotator port count: ${count}`);
  }
}

export async function allocatePort(options: AllocatorOptions): Promise<PortAllocation> {
  validateRange(options.base, options.count);
  mkdirSync(options.stateDir, { recursive: true, mode: 0o700 });

  const owner = options.owner ?? currentLockOwner(options.sessionId);
  const isOwnerAlive = options.isOwnerAlive ?? isLockOwnerAlive;
  const isPortAvailable = options.isPortAvailable ?? probePort;
  const now = options.now?.() ?? Date.now();
  const malformedLockGraceMs = options.malformedLockGraceMs ?? MALFORMED_LOCK_GRACE_MS;
  const start = fnv1a(options.sessionId) % options.count;

  for (let offset = 0; offset < options.count; offset += 1) {
    const port = options.base + ((start + offset) % options.count);
    const lockPath = join(options.stateDir, `${port}.lock`);

    let acquired = tryCreateLock(lockPath, owner);
    if (!acquired && reclaimStaleLock(lockPath, isOwnerAlive, now, malformedLockGraceMs)) {
      acquired = tryCreateLock(lockPath, owner);
    }
    if (!acquired) continue;

    if (!(await isPortAvailable(port))) {
      unlinkIfOwned(lockPath, owner.token);
      continue;
    }

    let released = false;
    return {
      port,
      lockPath,
      owner,
      release: () => {
        if (released) return;
        released = true;
        unlinkIfOwned(lockPath, owner.token);
      },
    };
  }

  throw new Error(
    `No free Pi Plannotator ports in ${options.base}..${options.base + options.count - 1}. ` +
      `Inspect ${options.stateDir} or increase PI_PLANNOTATOR_PORT_COUNT.`,
  );
}
