import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { chmodSync, existsSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

interface SlotRecord {
  slot: string;
  sessionId: string;
  sessionFile: string | null;
  order: number;
  createdAt: string;
  updatedAt: string;
  pendingEditorText: string | null;
  worktreePath: string;
  sessionCwd: string;
}

interface WorktreeContextData {
  worktreePath: string;
}

interface ForkMessage {
  entryId: string;
  text: string;
  label: string;
}

const SLOT_PATTERN = /^[a-f0-9]{12}$/;
const WORKTREE_CONTEXT_TYPE = "zellij-worktree-context";
const ACTIVE_WORKTREE_ENV = "PI_ZELLIJ_ACTIVE_WORKTREE_PATH";
const SLOT_OWNER_PID_ENV = "PI_ZELLIJ_SLOT_OWNER_PID";
const PI_PANE_BACKGROUND = "#111827";
const extensionPath = realpathSync(fileURLToPath(import.meta.url));
const configRoot = resolve(dirname(extensionPath), "../../..");
const registryPath = resolve(configRoot, "zellij/pi-session-registry.py");
const launcherPath = resolve(configRoot, "zellij/open-worktree-pi.sh");

function registryArgs(args: string[]): string[] {
  const stateDir = process.env.PI_ZELLIJ_STATE_DIR?.trim();
  return stateDir ? [registryPath, "--state-dir", stateDir, ...args] : [registryPath, ...args];
}

function runRegistry<T>(args: string[], pendingEditorText?: string): T {
  let tempDir: string | undefined;
  try {
    const fullArgs = [...args];
    if (pendingEditorText !== undefined) {
      tempDir = mkdtempSync(resolve(tmpdir(), "pi-zellij-fork-"));
      chmodSync(tempDir, 0o700);
      const promptPath = resolve(tempDir, "prompt.txt");
      writeFileSync(promptPath, pendingEditorText, { encoding: "utf8", mode: 0o600 });
      fullArgs.push("--pending-editor-file", promptPath);
    }
    const result = spawnSync("python3", registryArgs(fullArgs), {
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) {
      throw new Error(result.stderr.trim() || `registry exited ${result.status}`);
    }
    return JSON.parse(result.stdout) as T;
  } finally {
    if (tempDir) rmSync(tempDir, { recursive: true, force: true });
  }
}

function reserveSlot(
  worktreePath: string,
  sessionCwd: string,
  sessionId: string,
  sessionFile: string | undefined,
  slot?: string,
  pendingEditorText?: string,
): SlotRecord {
  const args = [
    "reserve",
    "--worktree-path",
    worktreePath,
    "--session-cwd",
    sessionCwd,
    "--session-id",
    sessionId,
  ];
  if (slot) args.push("--slot", slot);
  if (sessionFile) args.push("--session-file", sessionFile);
  return runRegistry<SlotRecord>(args, pendingEditorText);
}

function consumePending(worktreePath: string, sessionCwd: string, slot: string): string | null {
  return runRegistry<{ text: string | null }>([
    "consume-pending",
    "--worktree-path",
    worktreePath,
    "--session-cwd",
    sessionCwd,
    "--slot",
    slot,
  ]).text;
}

function forgetSlot(worktreePath: string, sessionCwd: string, slot: string): boolean {
  return runRegistry<{ forgotten: boolean }>([
    "forget",
    "--worktree-path",
    worktreePath,
    "--session-cwd",
    sessionCwd,
    "--slot",
    slot,
  ]).forgotten;
}

function paneId(): string | undefined {
  const raw = process.env.ZELLIJ_PANE_ID?.trim();
  return raw ? (raw.startsWith("terminal_") ? raw : `terminal_${raw}`) : undefined;
}

function ownsCurrentPane(): boolean {
  const ownerPid = process.env[SLOT_OWNER_PID_ENV]?.trim();
  return !ownerPid || ownerPid === String(process.pid);
}

function renamePane(name: string): void {
  const id = paneId();
  if (!id) return;
  const result = spawnSync("zellij", ["action", "rename-pane", "--pane-id", id, name], {
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr.trim() || `zellij rename-pane exited ${result.status}`);
}

function setPaneBackground(background?: string): boolean {
  const id = paneId();
  if (!process.env.ZELLIJ || !id || !ownsCurrentPane()) return false;
  const colorArgs = background ? ["--bg", background] : ["--reset"];
  const result = spawnSync("zellij", ["action", "set-pane-color", "--pane-id", id, ...colorArgs], {
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr.trim() || `zellij set-pane-color exited ${result.status}`);
  return true;
}

function userMessageText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((part): part is { type: string; text?: string } => Boolean(part && typeof part === "object"))
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text ?? "")
    .join("\n");
}

function compactLabel(text: string, index: number): string {
  const oneLine = text.replace(/\s+/g, " ").trim();
  const preview = oneLine.length > 100 ? `${oneLine.slice(0, 97)}…` : oneLine;
  return `${String(index + 1).padStart(3, "0")} · ${preview || "(empty user message)"}`;
}

function forkMessages(ctx: ExtensionCommandContext): ForkMessage[] {
  const messages: ForkMessage[] = [];
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "message" || entry.message.role !== "user") continue;
    const text = userMessageText(entry.message.content);
    messages.push({ entryId: entry.id, text, label: "" });
  }
  return messages.map((message, index) => ({ ...message, label: compactLabel(message.text, index) }));
}

function normalizedWorktreePath(raw: string | undefined): string | undefined {
  const value = raw?.trim();
  if (!value) return undefined;
  return isAbsolute(value) ? resolve(value) : undefined;
}

function storedWorktreePath(ctx: ExtensionContext): string | undefined {
  const branch = ctx.sessionManager.getBranch();
  for (let index = branch.length - 1; index >= 0; index -= 1) {
    const entry = branch[index];
    if (entry?.type !== "custom" || entry.customType !== WORKTREE_CONTEXT_TYPE) continue;
    const data = entry.data as Partial<WorktreeContextData> | undefined;
    const worktreePath = normalizedWorktreePath(data?.worktreePath);
    if (worktreePath) return worktreePath;
  }
  return undefined;
}

function hasCurrentWorktreeEntry(ctx: ExtensionContext, worktreePath: string): boolean {
  const branch = ctx.sessionManager.getBranch();
  const latest = [...branch].reverse().find(
    (entry) => entry.type === "custom" && entry.customType === WORKTREE_CONTEXT_TYPE,
  );
  if (!latest || latest.type !== "custom") return false;
  const data = latest.data as Partial<WorktreeContextData> | undefined;
  return normalizedWorktreePath(data?.worktreePath) === worktreePath;
}

function openForkPane(sessionCwd: string, worktreePath: string, slot: string): void {
  const args = [
    "action",
    "new-pane",
    "--stacked",
    "--near-current-pane",
    "--cwd",
    sessionCwd,
    "--name",
    `pi-slot:${slot}`,
    "--",
    launcherPath,
    "--worktree-path",
    worktreePath,
    "--slot",
    slot,
  ];
  const result = spawnSync("zellij", args, { encoding: "utf8", maxBuffer: 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr.trim() || `zellij new-pane exited ${result.status}`);
}

export default function zellijSessionSlots(pi: ExtensionAPI) {
  // This value is present only when the launcher supplied pane metadata. Do
  // not synthesize it into process.env from a resumed session: a later manual
  // /resume must be able to recover that target session's own custom entry.
  const launcherWorktree = normalizedWorktreePath(process.env.PI_ZELLIJ_WORKTREE_PATH);
  let activeWorktree: string | undefined;
  let activeSlot: string | undefined;
  let registrationError: string | undefined;
  let paneBackgroundApplied = false;

  async function registerCurrentSession(ctx: ExtensionContext): Promise<void> {
    const storedWorktree = storedWorktreePath(ctx);
    const inheritedManualWorktree = normalizedWorktreePath(process.env[ACTIVE_WORKTREE_ENV]);
    activeWorktree = launcherWorktree ?? storedWorktree ?? inheritedManualWorktree;
    if (!activeWorktree) return;

    // A Pi process started manually at mono root has no launcher metadata.
    // Carry context through /new and context-free forks without masking a
    // later /resume target's own durable custom entry.
    if (!launcherWorktree) process.env[ACTIVE_WORKTREE_ENV] = activeWorktree;

    if (!hasCurrentWorktreeEntry(ctx, activeWorktree)) {
      pi.appendEntry(WORKTREE_CONTEXT_TYPE, { worktreePath: activeWorktree });
    }

    const requestedSlot = process.env.PI_ZELLIJ_SLOT?.trim();
    if (requestedSlot && !SLOT_PATTERN.test(requestedSlot)) {
      throw new Error(`invalid PI_ZELLIJ_SLOT: ${requestedSlot}`);
    }
    if (
      !process.env.ZELLIJ ||
      !process.env.ZELLIJ_PANE_ID ||
      process.env.PI_ZELLIJ_SLOT_FORGOTTEN === "1" ||
      !requestedSlot ||
      !ownsCurrentPane()
    ) {
      return;
    }
    const record = reserveSlot(
      activeWorktree,
      ctx.cwd,
      ctx.sessionManager.getSessionId(),
      ctx.sessionManager.getSessionFile(),
      requestedSlot,
    );
    activeSlot = record.slot;
    process.env.PI_ZELLIJ_SLOT = record.slot;
    renamePane(`pi-slot:${record.slot}`);

    if (!ctx.ui.getEditorText()) {
      const pending = consumePending(activeWorktree, ctx.cwd, record.slot);
      if (pending) ctx.ui.setEditorText(pending);
    }
  }

  pi.on("session_start", async (_event, ctx) => {
    try {
      paneBackgroundApplied = setPaneBackground(PI_PANE_BACKGROUND) || paneBackgroundApplied;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      ctx.ui.notify(`Pi pane background could not be applied: ${message}`, "warning");
    }
    try {
      registrationError = undefined;
      await registerCurrentSession(ctx);
    } catch (error) {
      registrationError = error instanceof Error ? error.message : String(error);
      ctx.ui.notify(`Pi pane registration failed: ${registrationError}`, "error");
    }
  });

  pi.on("session_shutdown", async () => {
    if (!paneBackgroundApplied) return;
    try {
      setPaneBackground();
    } catch {
      // Pane shutdown must continue even if the cosmetic reset fails.
    } finally {
      paneBackgroundApplied = false;
    }
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (!activeWorktree) return;
    const worktreeStatus = existsSync(activeWorktree) ? "present" : "missing (do not recreate it implicitly)";
    const contextBlock = [
      "[Zellij worktree context]",
      `Pi cwd: ${ctx.cwd}`,
      `Active worktree: ${activeWorktree}`,
      `Active worktree status: ${worktreeStatus}`,
      "Direct repository edits, git operations, tests, and builds to the active worktree, not Pi's cwd.",
      "Before modifying repository code, read the AGENTS.md files applicable within the active worktree.",
      "If the active worktree is missing, report that fact and do not recreate it implicitly.",
    ].join("\n");
    return { systemPrompt: `${event.systemPrompt}\n\n${contextBlock}` };
  });

  pi.registerCommand("fork-pane", {
    description: "Fork from a selected user message into a new stacked Zellij pane",
    handler: async (_args, ctx) => {
      if (!process.env.ZELLIJ || !process.env.ZELLIJ_PANE_ID) {
        ctx.ui.notify("/fork-pane requires Pi to be running inside Zellij", "error");
        return;
      }
      if (registrationError || !activeSlot || !activeWorktree) {
        ctx.ui.notify(`Current Pi pane is not registered${registrationError ? `: ${registrationError}` : ""}`, "error");
        return;
      }
      if (!ctx.isIdle()) {
        ctx.ui.notify("Wait for the current agent turn to finish before forking", "warning");
        return;
      }

      const originalSessionFile = ctx.sessionManager.getSessionFile();
      if (!originalSessionFile) {
        ctx.ui.notify("Send at least one message before forking this session", "warning");
        return;
      }
      const messages = forkMessages(ctx);
      if (messages.length === 0) {
        ctx.ui.notify("No user messages are available to fork from", "warning");
        return;
      }
      const labels = [...messages].reverse().map((message) => message.label);
      const selectedLabel = await ctx.ui.select("Fork into a stacked pane from which message?", labels);
      if (!selectedLabel) return;
      const selected = messages.find((message) => message.label === selectedLabel);
      if (!selected) {
        ctx.ui.notify("Could not resolve the selected fork point", "error");
        return;
      }

      const worktreePath = activeWorktree;
      const parentSlot = activeSlot;
      const previousSlotEnv = process.env.PI_ZELLIJ_SLOT;
      let forkSlot: string | undefined;
      let paneError: string | undefined;
      let result: Awaited<ReturnType<typeof ctx.fork>>;
      delete process.env.PI_ZELLIJ_SLOT;
      try {
        result = await ctx.fork(selected.entryId, {
          position: "before",
          withSession: async (forkCtx) => {
            const forkRecord = reserveSlot(
              worktreePath,
              forkCtx.cwd,
              forkCtx.sessionManager.getSessionId(),
              forkCtx.sessionManager.getSessionFile(),
              undefined,
              selected.text,
            );
            forkSlot = forkRecord.slot;

            // The fork's session_start ran without launcher provenance. Put
            // the parent provenance back before switching so the returning
            // parent's session_start can reclaim its own slot.
            process.env.PI_ZELLIJ_SLOT = parentSlot;
            const switched = await forkCtx.switchSession(originalSessionFile, {
              withSession: async (parentCtx) => {
                try {
                  openForkPane(parentCtx.cwd, worktreePath, forkRecord.slot);
                } catch (error) {
                  paneError = error instanceof Error ? error.message : String(error);
                  parentCtx.ui.notify(
                    `Fork ${forkRecord.sessionId} was saved in slot ${forkRecord.slot}, but its pane could not open: ${paneError}`,
                    "error",
                  );
                }
              },
            });
            if (switched.cancelled) {
              forkCtx.ui.notify(
                `Fork ${forkRecord.sessionId} was saved in slot ${forkRecord.slot}, but the parent session switch was cancelled`,
                "warning",
              );
            }
          },
        });
      } finally {
        if (previousSlotEnv === undefined) delete process.env.PI_ZELLIJ_SLOT;
        else process.env.PI_ZELLIJ_SLOT = previousSlotEnv;
      }

      if (result.cancelled) {
        ctx.ui.notify("Fork was cancelled", "warning");
      } else if (forkSlot && !paneError) {
        // The new pane is focused by Zellij. Its session_start restores the selected prompt.
      }
    },
  });

  pi.registerCommand("forget-pi-pane", {
    description: "Stop restoring this pane slot without deleting Pi session history",
    handler: async (_args, ctx) => {
      if (!activeSlot || !activeWorktree) {
        ctx.ui.notify("This Pi pane has no registered restoration slot", "warning");
        return;
      }
      const confirmed = await ctx.ui.confirm(
        "Forget Pi pane?",
        `Slot ${activeSlot} will not return when this worktree tab is recreated. Pi JSONL history is retained.`,
      );
      if (!confirmed) return;
      const forgotten = forgetSlot(activeWorktree, ctx.cwd, activeSlot);
      if (!forgotten) {
        ctx.ui.notify(`Pi pane slot ${activeSlot} was already absent`, "warning");
        return;
      }
      process.env.PI_ZELLIJ_SLOT_FORGOTTEN = "1";
      delete process.env.PI_ZELLIJ_SLOT;
      try {
        renamePane("pi-unregistered");
      } catch {
        // The registry is authoritative even if the cosmetic rename fails.
      }
      activeSlot = undefined;
      ctx.ui.notify("Pane forgotten. Pi session history was not deleted; close the pane when ready.", "info");
    },
  });
}
