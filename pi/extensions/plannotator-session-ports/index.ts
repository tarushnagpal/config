import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { homedir } from "node:os";
import { join } from "node:path";
import { allocatePort, type PortAllocation } from "./allocator.js";

const DEFAULT_PORT_BASE = 19_600;
const DEFAULT_PORT_COUNT = 64;

type PortStatus =
  | { source: "pending" }
  | { source: "local-random" }
  | { source: "explicit"; port: string }
  | { source: "allocated"; allocation: PortAllocation }
  | { source: "error"; message: string };

function envInt(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value)) throw new Error(`${name} must be an integer, got ${JSON.stringify(raw)}`);
  return value;
}

function isRemoteSession(): boolean {
  const override = process.env.PLANNOTATOR_REMOTE?.trim().toLowerCase();
  if (override === "1" || override === "true") return true;
  if (override === "0" || override === "false") return false;
  return Boolean(process.env.SSH_TTY || process.env.SSH_CONNECTION);
}

export default function plannotatorSessionPorts(pi: ExtensionAPI) {
  const inheritedPort = process.env.PLANNOTATOR_PORT;
  const inheritedRemote = process.env.PLANNOTATOR_REMOTE;
  let status: PortStatus = { source: "pending" };
  let lifecycleGeneration = 0;

  function restoreEnvironment(): void {
    if (inheritedPort === undefined) delete process.env.PLANNOTATOR_PORT;
    else process.env.PLANNOTATOR_PORT = inheritedPort;

    if (inheritedRemote === undefined) delete process.env.PLANNOTATOR_REMOTE;
    else process.env.PLANNOTATOR_REMOTE = inheritedRemote;
  }

  function releaseAllocation(): void {
    if (status.source === "allocated") status.allocation.release();
    restoreEnvironment();
    status = { source: "pending" };
  }

  pi.on("session_start", async (_event, ctx) => {
    // Pi can overlap lifecycle notifications during session replacement. Make
    // startup idempotent and ensure an allocation that loses the race is freed.
    const generation = ++lifecycleGeneration;
    releaseAllocation();

    if (!isRemoteSession()) {
      status = { source: "local-random" };
      return;
    }

    if (inheritedPort !== undefined) {
      status = { source: "explicit", port: inheritedPort };
      return;
    }

    try {
      const base = envInt("PI_PLANNOTATOR_PORT_BASE", DEFAULT_PORT_BASE);
      const count = envInt("PI_PLANNOTATOR_PORT_COUNT", DEFAULT_PORT_COUNT);
      const stateDir = process.env.PI_PLANNOTATOR_PORT_LOCK_DIR?.trim() ||
        join(homedir(), ".plannotator", "pi-session-ports");
      const allocation = await allocatePort({
        sessionId: ctx.sessionManager.getSessionId(),
        base,
        count,
        stateDir,
      });

      if (generation !== lifecycleGeneration) {
        allocation.release();
        return;
      }
      process.env.PLANNOTATOR_PORT = String(allocation.port);
      process.env.PLANNOTATOR_REMOTE ??= "1";
      status = { source: "allocated", allocation };
    } catch (error) {
      if (generation !== lifecycleGeneration) return;
      const message = error instanceof Error ? error.message : String(error);
      restoreEnvironment();
      status = { source: "error", message };
      ctx.ui.notify(`Plannotator port allocation failed: ${message}`, "error");
    }
  });

  pi.on("session_shutdown", async () => {
    lifecycleGeneration += 1;
    releaseAllocation();
  });

  pi.registerCommand("plannotator-port", {
    description: "Show this Pi session's Plannotator port allocation",
    handler: async (_args, ctx) => {
      const sessionId = ctx.sessionManager.getSessionId();
      if (status.source === "allocated") {
        ctx.ui.notify(
          `Plannotator: port ${status.allocation.port} (Pi allocation) · session ${sessionId} · ${status.allocation.lockPath}`,
          "info",
        );
      } else if (status.source === "explicit") {
        ctx.ui.notify(`Plannotator: port ${status.port} (explicit PLANNOTATOR_PORT) · session ${sessionId}`, "info");
      } else if (status.source === "local-random") {
        ctx.ui.notify(`Plannotator: native random port (local session) · session ${sessionId}`, "info");
      } else if (status.source === "error") {
        ctx.ui.notify(`Plannotator port allocation failed: ${status.message}`, "error");
      } else {
        ctx.ui.notify("Plannotator port allocation is not initialized", "warning");
      }
    },
  });
}
