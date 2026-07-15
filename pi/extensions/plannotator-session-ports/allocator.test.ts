import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { allocatePort, fnv1a, type LockOwner } from "./allocator.ts";

function tempDir(): string {
  return mkdtempSync(join(tmpdir(), "pi-plannotator-ports-"));
}

function owner(sessionId: string, token: string, pid = 10_000): LockOwner {
  return {
    sessionId,
    pid,
    processStart: `${pid}:12345`,
    token,
    host: "test-host",
    createdAt: "2026-07-12T00:00:00.000Z",
  };
}

function remove(path: string): void {
  rmSync(path, { recursive: true, force: true });
}

test("FNV-1a and scan order are deterministic", async () => {
  assert.equal(fnv1a("session-a"), fnv1a("session-a"));
  const dir = tempDir();
  try {
    const probes: number[] = [];
    const allocation = await allocatePort({
      sessionId: "session-a",
      base: 20_000,
      count: 8,
      stateDir: dir,
      owner: owner("session-a", "a"),
      isPortAvailable: async (port) => {
        probes.push(port);
        return true;
      },
    });
    assert.equal(allocation.port, 20_000 + (fnv1a("session-a") % 8));
    assert.deepEqual(probes, [allocation.port]);
    allocation.release();
  } finally {
    remove(dir);
  }
});

test("concurrent allocators reserve distinct ports atomically", async () => {
  const dir = tempDir();
  try {
    const [first, second] = await Promise.all([
      allocatePort({
        sessionId: "same-offset",
        base: 20_100,
        count: 2,
        stateDir: dir,
        owner: owner("one", "one", 10_001),
        isOwnerAlive: () => true,
        isPortAvailable: async () => true,
      }),
      allocatePort({
        sessionId: "same-offset",
        base: 20_100,
        count: 2,
        stateDir: dir,
        owner: owner("two", "two", 10_002),
        isOwnerAlive: () => true,
        isPortAvailable: async () => true,
      }),
    ]);
    assert.notEqual(first.port, second.port);
    first.release();
    second.release();
  } finally {
    remove(dir);
  }
});

test("occupied external ports are skipped and their reservations are released", async () => {
  const dir = tempDir();
  try {
    const probes: number[] = [];
    const allocation = await allocatePort({
      sessionId: "occupied",
      base: 20_200,
      count: 2,
      stateDir: dir,
      owner: owner("occupied", "occupied"),
      isPortAvailable: async (port) => {
        probes.push(port);
        return probes.length > 1;
      },
    });
    assert.equal(probes.length, 2);
    assert.equal(allocation.port, probes[1]);
    assert.equal(readFileSync(allocation.lockPath, "utf8").includes("occupied"), true);
    allocation.release();
  } finally {
    remove(dir);
  }
});

test("a live owner is preserved", async () => {
  const dir = tempDir();
  try {
    await allocatePort({
      sessionId: "live",
      base: 20_300,
      count: 1,
      stateDir: dir,
      owner: owner("live", "live"),
      isPortAvailable: async () => true,
    });
    await assert.rejects(
      allocatePort({
        sessionId: "other",
        base: 20_300,
        count: 1,
        stateDir: dir,
        owner: owner("other", "other"),
        isOwnerAlive: () => true,
        isPortAvailable: async () => true,
      }),
      /No free Pi Plannotator ports/,
    );
    assert.equal(JSON.parse(readFileSync(join(dir, "20300.lock"), "utf8")).token, "live");
  } finally {
    remove(dir);
  }
});

test("a dead owner's lock is reclaimed", async () => {
  const dir = tempDir();
  try {
    await allocatePort({
      sessionId: "dead",
      base: 20_400,
      count: 1,
      stateDir: dir,
      owner: owner("dead", "dead"),
      isPortAvailable: async () => true,
    });
    const replacement = await allocatePort({
      sessionId: "replacement",
      base: 20_400,
      count: 1,
      stateDir: dir,
      owner: owner("replacement", "replacement"),
      isOwnerAlive: () => false,
      isPortAvailable: async () => true,
    });
    assert.equal(replacement.port, 20_400);
    assert.equal(JSON.parse(readFileSync(replacement.lockPath, "utf8")).token, "replacement");
    replacement.release();
  } finally {
    remove(dir);
  }
});

test("release never removes a lock now owned by another allocator", async () => {
  const dir = tempDir();
  try {
    const allocation = await allocatePort({
      sessionId: "old",
      base: 20_500,
      count: 1,
      stateDir: dir,
      owner: owner("old", "old"),
      isPortAvailable: async () => true,
    });
    unlinkSync(allocation.lockPath);
    writeFileSync(allocation.lockPath, `${JSON.stringify(owner("new", "new"))}\n`);
    allocation.release();
    assert.equal(JSON.parse(readFileSync(allocation.lockPath, "utf8")).token, "new");
  } finally {
    remove(dir);
  }
});

test("recent malformed locks are preserved, then reclaimed after the grace period", async () => {
  const dir = tempDir();
  try {
    const lockPath = join(dir, "20600.lock");
    writeFileSync(lockPath, "");
    await assert.rejects(
      allocatePort({
        sessionId: "malformed",
        base: 20_600,
        count: 1,
        stateDir: dir,
        owner: owner("malformed", "first"),
        isPortAvailable: async () => true,
        now: () => Date.now(),
      }),
      /No free Pi Plannotator ports/,
    );

    const replacement = await allocatePort({
      sessionId: "malformed",
      base: 20_600,
      count: 1,
      stateDir: dir,
      owner: owner("malformed", "second"),
      isPortAvailable: async () => true,
      now: () => Date.now() + 20_000,
    });
    assert.equal(replacement.port, 20_600);
    replacement.release();
  } finally {
    remove(dir);
  }
});

test("range exhaustion and invalid ranges fail with actionable errors", async () => {
  const dir = tempDir();
  try {
    await assert.rejects(
      allocatePort({
        sessionId: "exhausted",
        base: 20_700,
        count: 1,
        stateDir: dir,
        owner: owner("exhausted", "exhausted"),
        isPortAvailable: async () => false,
      }),
      /No free Pi Plannotator ports in 20700\.\.20700/,
    );
    await assert.rejects(
      allocatePort({ sessionId: "bad", base: 0, count: 1, stateDir: dir }),
      /Invalid Pi Plannotator port base/,
    );
  } finally {
    remove(dir);
  }
});
