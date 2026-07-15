import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

import zellijSessionSlots from "./index.ts";

type Handler = (...args: any[]) => any;

const ENV_KEYS = [
  "PI_ZELLIJ_STATE_DIR",
  "PI_ZELLIJ_WORKTREE_PATH",
  "PI_ZELLIJ_ACTIVE_WORKTREE_PATH",
  "PI_ZELLIJ_SLOT",
  "PI_ZELLIJ_SLOT_FORGOTTEN",
  "PI_ZELLIJ_SLOT_OWNER_PID",
  "ZELLIJ",
  "ZELLIJ_PANE_ID",
  "PATH",
] as const;

function sessionFile(root: string, id: string, cwd: string): string {
  const path = join(root, `${id}.jsonl`);
  writeFileSync(
    path,
    `${JSON.stringify({ type: "session", version: 3, id, timestamp: "2026-07-14T00:00:00.000Z", cwd })}\n`,
  );
  return path;
}

function sessionManager(id: string, file: string | undefined, branch: any[] = []) {
  return {
    getSessionId: () => id,
    getSessionFile: () => file,
    getBranch: () => branch,
  };
}

function context(cwd: string, manager: any, overrides: Record<string, any> = {}) {
  let editorText = "";
  const notifications: any[] = [];
  return {
    cwd,
    sessionManager: manager,
    ui: {
      getEditorText: () => editorText,
      setEditorText: (text: string) => {
        editorText = text;
      },
      notify: (...args: any[]) => notifications.push(args),
      select: async () => undefined,
      confirm: async () => false,
    },
    isIdle: () => true,
    notifications,
    get editorText() {
      return editorText;
    },
    ...overrides,
  };
}

function harness() {
  const events = new Map<string, Handler>();
  const commands = new Map<string, any>();
  const appended: Array<{ type: string; data: any }> = [];
  const pi = {
    on: (name: string, handler: Handler) => events.set(name, handler),
    registerCommand: (name: string, command: any) => commands.set(name, command),
    appendEntry: (type: string, data: any) => appended.push({ type, data }),
  };
  zellijSessionSlots(pi as any);
  return { events, commands, appended };
}

function manifests(state: string): any[] {
  try {
    return readdirSync(state)
      .filter((name) => name.endsWith(".json"))
      .map((name) => JSON.parse(readFileSync(join(state, name), "utf8")));
  } catch {
    return [];
  }
}

function slots(state: string): any[] {
  return manifests(state).flatMap((manifest) => manifest.slots ?? []);
}

function installFakeZellij(root: string): string {
  const bin = join(root, "bin");
  mkdirSync(bin);
  const log = join(root, "zellij.log");
  const script = join(bin, "zellij");
  writeFileSync(log, "");
  writeFileSync(
    script,
    `#!/bin/sh\nprintf '%s\\n' "$*" >>"${log}"\n`,
    { mode: 0o755 },
  );
  process.env.PATH = `${bin}:${process.env.PATH}`;
  return log;
}

async function withEnvironment(run: (root: string, state: string, mono: string, worktree: string, log: string) => Promise<void>) {
  const original = new Map(ENV_KEYS.map((key) => [key, process.env[key]]));
  const root = mkdtempSync(join(tmpdir(), "pi-zellij-extension-test-"));
  const state = join(root, "state");
  const mono = join(root, "mono");
  const worktree = join(root, "worktree");
  mkdirSync(state);
  mkdirSync(mono);
  mkdirSync(worktree);
  const log = installFakeZellij(root);
  process.env.PI_ZELLIJ_STATE_DIR = state;
  try {
    await run(root, state, mono, worktree, log);
  } finally {
    for (const [key, value] of original) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    rmSync(root, { recursive: true, force: true });
  }
}

test("launcher-owned session reserves its exact slot and appends worktree prompt context", async () => {
  await withEnvironment(async (root, state, mono, worktree, log) => {
    const id = "owned-session";
    const file = sessionFile(root, id, mono);
    const slot = "123456789abc";
    Object.assign(process.env, {
      PI_ZELLIJ_WORKTREE_PATH: worktree,
      PI_ZELLIJ_SLOT: slot,
      PI_ZELLIJ_SLOT_OWNER_PID: String(process.pid),
      ZELLIJ: "1",
      ZELLIJ_PANE_ID: "42",
    });
    const { events, appended } = harness();
    const ctx = context(mono, sessionManager(id, file));

    await events.get("session_start")!({}, ctx);

    const records = slots(state);
    assert.equal(records.length, 1);
    assert.equal(records[0].slot, slot);
    assert.equal(records[0].sessionId, id);
    assert.equal(manifests(state)[0].worktreePath, worktree);
    assert.equal(manifests(state)[0].sessionCwd, mono);
    assert.deepEqual(appended, [{ type: "zellij-worktree-context", data: { worktreePath: worktree } }]);
    assert.match(readFileSync(log, "utf8"), /set-pane-color --pane-id terminal_42 --bg #111827/);
    assert.match(readFileSync(log, "utf8"), /rename-pane --pane-id terminal_42 pi-slot:123456789abc/);

    rmSync(worktree, { recursive: true });
    const before = await events.get("before_agent_start")!({ systemPrompt: "base prompt" }, ctx);
    assert.match(before.systemPrompt, /^base prompt\n\n\[Zellij worktree context\]/);
    assert.match(before.systemPrompt, new RegExp(`Pi cwd: ${mono.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(before.systemPrompt, /Active worktree status: missing \(do not recreate it implicitly\)/);

    await events.get("session_shutdown")!({}, ctx);
    assert.match(readFileSync(log, "utf8"), /set-pane-color --pane-id terminal_42 --reset/);
  });
});

test("manual resumes and nested Pi retain durable context without mutating pane slots", async () => {
  await withEnvironment(async (root, state, mono, worktree, log) => {
    const id = "manual-session";
    const file = sessionFile(root, id, mono);
    const branch = [
      { type: "custom", customType: "zellij-worktree-context", data: { worktreePath: worktree } },
    ];
    process.env.PI_ZELLIJ_ACTIVE_WORKTREE_PATH = join(root, "wrong-inherited-worktree");
    delete process.env.PI_ZELLIJ_WORKTREE_PATH;
    delete process.env.PI_ZELLIJ_SLOT;
    delete process.env.ZELLIJ;
    delete process.env.ZELLIJ_PANE_ID;
    const manual = harness();
    const manualCtx = context(mono, sessionManager(id, file, branch));

    await manual.events.get("session_start")!({}, manualCtx);
    const before = await manual.events.get("before_agent_start")!({ systemPrompt: "prefix" }, manualCtx);
    assert.match(before.systemPrompt, new RegExp(`Active worktree: ${worktree.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.equal(manifests(state).length, 0);
    assert.equal(readFileSync(log, "utf8"), "");

    Object.assign(process.env, {
      PI_ZELLIJ_WORKTREE_PATH: worktree,
      PI_ZELLIJ_SLOT: "abcdef123456",
      PI_ZELLIJ_SLOT_OWNER_PID: String(process.pid + 1),
      ZELLIJ: "1",
      ZELLIJ_PANE_ID: "43",
    });
    const nested = harness();
    const nestedCtx = context(mono, sessionManager("nested-session", sessionFile(root, "nested-session", mono)));
    await nested.events.get("session_start")!({}, nestedCtx);
    const nestedBefore = await nested.events.get("before_agent_start")!({ systemPrompt: "nested" }, nestedCtx);
    assert.match(nestedBefore.systemPrompt, /\[Zellij worktree context\]/);
    assert.equal(manifests(state).length, 0);
    assert.equal(readFileSync(log, "utf8"), "");
  });
});

test("fork-pane removes parent provenance until the child has its dedicated slot", async () => {
  await withEnvironment(async (root, state, mono, worktree, log) => {
    const parentId = "parent-session";
    const childId = "child-session";
    const parentFile = sessionFile(root, parentId, mono);
    const childFile = sessionFile(root, childId, mono);
    const parentSlot = "111111111111";
    const branch = [
      { id: "u1", type: "message", message: { role: "user", content: "first prompt" } },
      { id: "u2", type: "message", message: { role: "user", content: "selected historical prompt" } },
    ];
    Object.assign(process.env, {
      PI_ZELLIJ_WORKTREE_PATH: worktree,
      PI_ZELLIJ_SLOT: parentSlot,
      PI_ZELLIJ_SLOT_OWNER_PID: String(process.pid),
      ZELLIJ: "1",
      ZELLIJ_PANE_ID: "44",
    });
    const app = harness();
    let childSlotDuringSwitch = "";
    const parentManager = sessionManager(parentId, parentFile, branch);
    const parentCtx: any = context(mono, parentManager, {
      ui: {
        getEditorText: () => "",
        setEditorText: () => {},
        notify: () => {},
        confirm: async () => false,
        select: async (_title: string, labels: string[]) => labels[0],
      },
      fork: async (entryId: string, options: any) => {
        assert.equal(entryId, "u2");
        assert.equal(options.position, "before");
        assert.equal(process.env.PI_ZELLIJ_SLOT, undefined);
        const childCtx: any = context(mono, sessionManager(childId, childFile, branch));
        await app.events.get("session_start")!({}, childCtx);
        assert.deepEqual(slots(state).map((slot) => slot.slot), [parentSlot]);
        childCtx.switchSession = async (file: string, switchOptions: any) => {
          assert.equal(file, parentFile);
          assert.equal(process.env.PI_ZELLIJ_SLOT, parentSlot);
          childSlotDuringSwitch = slots(state).find((slot) => slot.sessionId === childId)?.slot ?? "";
          assert.match(childSlotDuringSwitch, /^[a-f0-9]{12}$/);
          assert.notEqual(childSlotDuringSwitch, parentSlot);
          await app.events.get("session_start")!({}, parentCtx);
          await switchOptions.withSession(parentCtx);
          return { cancelled: false };
        };
        await options.withSession(childCtx);
        return { cancelled: false };
      },
    });

    await app.events.get("session_start")!({}, parentCtx);
    await app.commands.get("fork-pane").handler("", parentCtx);

    assert.equal(process.env.PI_ZELLIJ_SLOT, parentSlot);
    const records = slots(state);
    assert.equal(records.length, 2);
    assert.equal(records.find((slot) => slot.sessionId === childId)?.pendingEditorText, "selected historical prompt");
    const invocation = readFileSync(log, "utf8");
    assert.match(invocation, new RegExp(`new-pane --stacked --near-current-pane --cwd ${mono.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(invocation, new RegExp(`--worktree-path ${worktree.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")} --slot ${childSlotDuringSwitch}`));
  });
});
