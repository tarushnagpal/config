import type { AssistantMessage } from "@earendil-works/pi-ai";
import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { realpathSync } from "node:fs";
import { isAbsolute, dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

type Mode = "build" | "ask";
type DisplayMode = Mode | "plan";
type PlannotatorPhase = "idle" | "planning" | "executing";

type PlanModeResponse = {
  status: "handled" | "unavailable" | "error";
  result?: { phase: PlannotatorPhase };
  error?: string;
};

type ModelRef = { provider: string; id: string };

const SOL_MODEL: ModelRef = { provider: "openai", id: "gpt-5.6-sol" };
const FABLE_MODEL: ModelRef = { provider: "anthropic", id: "claude-fable-5" };
// Interactive build/ask default to Sol (fast, terminal-strong); Plannotator
// planning defaults to Fable (long-horizon plan synthesis). Each chain falls
// back to the other frontier model when the first is unavailable.
const BUILD_CHAIN: readonly ModelRef[] = [SOL_MODEL, FABLE_MODEL];
const PLAN_CHAIN: readonly ModelRef[] = [FABLE_MODEL, SOL_MODEL];
const DEEP_THINKING = "xhigh" as const; // Plannotator planning/executing phases
const INTERACTIVE_THINKING = "xhigh" as const; // plain build/ask turns (Sol default)
const THINKING_VARIANTS = ["medium", "high", "xhigh"] as const;
const READ_ONLY_TOOLS = ["read", "grep", "find", "ls", "bash"];
const PLAN_TOOLS = [...READ_ONLY_TOOLS, "write", "edit", "plannotator_submit_plan"];
function formatTokens(count: number): string {
  if (count < 1_000) return `${count}`;
  if (count < 10_000) return `${(count / 1_000).toFixed(1)}k`;
  if (count < 1_000_000) return `${Math.round(count / 1_000)}k`;
  return count < 10_000_000 ? `${(count / 1_000_000).toFixed(1)}M` : `${Math.round(count / 1_000_000)}M`;
}

function compactCwd(cwd: string): string {
  const home = process.env.HOME || process.env.USERPROFILE;
  if (!home) return cwd;
  const relativeToHome = relative(resolve(home), resolve(cwd));
  const insideHome = relativeToHome === "" ||
    (relativeToHome !== ".." && !relativeToHome.startsWith(`..${sep}`) && !isAbsolute(relativeToHome));
  return insideHome ? (relativeToHome ? `~${sep}${relativeToHome}` : "~") : cwd;
}

function align(left: string, right: string, width: number): string {
  const rightWidth = visibleWidth(right);
  if (rightWidth >= width) return truncateToWidth(right, width, "");
  const leftWidth = Math.max(0, width - rightWidth - 1);
  const fittedLeft = truncateToWidth(left, leftWidth, "…");
  return fittedLeft + " ".repeat(Math.max(1, width - visibleWidth(fittedLeft) - rightWidth)) + right;
}

type LeaderAction = Parameters<CustomEditor["onAction"]>[0];

type LeaderCallbacks = {
  cycleMode: () => void;
  cycleVariant: () => void;
  showHelp: () => void;
  protectDraft: (action: string) => void;
};

const LEADER_ACTIONS: Record<string, LeaderAction> = {
  l: "app.session.resume",
  m: "app.model.select",
  e: "app.editor.external",
  g: "app.tools.expand",
  t: "app.thinking.toggle",
  y: "app.session.tree",
  n: "app.session.new",
  f: "app.session.fork",
  q: "app.exit",
};

class LeaderEditor extends CustomEditor {
  private leaderActive = false;

  constructor(
    private readonly tuiRef: ConstructorParameters<typeof CustomEditor>[0],
    theme: ConstructorParameters<typeof CustomEditor>[1],
    keybindings: ConstructorParameters<typeof CustomEditor>[2],
    private readonly callbacks: LeaderCallbacks,
  ) {
    super(tuiRef, theme, keybindings);
  }

  override handleInput(data: string): void {
    if (!this.leaderActive) {
      if (data === "\\") {
        this.leaderActive = true;
        this.tuiRef.requestRender();
        return;
      }
      super.handleInput(data);
      return;
    }

    this.leaderActive = false;
    if (data === "\\") {
      this.callbacks.cycleMode();
    } else if (data === "v") {
      this.callbacks.cycleVariant();
    } else if (data === " ") {
      super.handleInput("\\");
    } else if (data === "?") {
      this.callbacks.showHelp();
    } else if (data === "\u001b") {
      // Escape only cancels leader mode.
    } else if (data === "q" && this.getText().length > 0) {
      // Do not discard a draft through the leader quit binding.
    } else if (data === "F") {
      // Keep lowercase \f on Pi's built-in current-pane fork. Uppercase \F
      // submits the extension command only when it cannot overwrite a draft.
      if (this.getText().length === 0) {
        this.setText("/fork-pane");
        super.handleInput("\r");
      } else {
        this.callbacks.protectDraft("fork into a pane");
      }
    } else {
      const action = LEADER_ACTIONS[data];
      if (action) this.actionHandlers.get(action)?.();
    }
    this.tuiRef.requestRender();
  }

  override render(width: number): string[] {
    const lines = super.render(width);
    if (!this.leaderActive || lines.length === 0) return lines;
    const hint = " \\  \\:mode f:fork F:fork-pane v:variant l:sessions m:models ?:help ";
    const last = lines.length - 1;
    lines[last] = truncateToWidth(lines[last]!, Math.max(0, width - visibleWidth(hint)), "") + hint;
    return lines;
  }
}

const ASK_PROMPT = `You are in answer-only Q&A mode.

Answer the user's questions directly. Do not create plans, open Plannotator, create todo lists, delegate work, or modify files.

You may inspect the workspace with read-only tools and run bash commands only for read-only diagnostics and information gathering. Do not run commands that modify files, install dependencies, start build steps, apply fixes, or otherwise change the workspace.

Use as much detail as the question needs and include file references when answering questions about code. If the request requires implementation, say that ask mode is read-only and tell the user to switch with /build or /plan.`;

const PLAN_ORCHESTRATION_PROMPT = `# Required implementation closure

Every implementation plan must end with these two separate, sequential checklist steps:

1. **Full review and remediation** — after all implementation and integrated-tree validation, invoke the fresh-context \`full-reviewer\` in the foreground. Give it the approved plan path, pre-task baseline or exact task diff scope, complete integrated diff, worker branches, and exact validation evidence. Adjudicate every R-xxx finding, fix confirmed issues, and rerun relevant checks.
2. **Adversarial review of the primary review and final closure** — invoke a separate fresh-context \`adversarial-reviewer\` in the foreground. Give it the complete primary report plus the same plan, diff, code, and test evidence. Adjudicate every primary disposition and A-xxx omission. If remediation materially changes code, repeat both review stages on the new final state.

Do not combine these gates, run them before implementation is complete, or mark either done while a confirmed finding remains unresolved. The adversarial reviewer audits both the implementation and the quality of the primary review.`;

const BUILD_ORCHESTRATION_PROMPT = `# Plan-first subagent orchestration

You are the main orchestrator and final integrator. Keep ownership of understanding, scope decisions, worker steering, diff inspection, integration, validation, and final conclusions.

## Proportionality

Match process weight to task weight. For a small, scoped, low-risk change — a focused edit, config tweak, straightforward bug fix, or question you can resolve directly — implement it yourself, run the most relevant targeted validation, and finish. Do not spawn investigators, implementation workers, or review agents for work of this size, and do not write a plan file nobody asked for.

Use the full machinery below — delegation, worktree isolation, and the mandatory review sequence — for approved-plan execution and for large, multi-file, or high-risk work. When in doubt, ask whether a reviewer would call the overhead proportionate; if not, do the work directly.

## Delegation

- Use \`code-investigator\` for deep read-only root-cause or architecture reconnaissance.
- Use \`sol-implementer\` as the default terminal-heavy implementation worker and \`opus-implementer\` for sustained multi-file work or an independent provider-diverse path.
- Brief every worker like a fresh colleague: include the approved plan step, relevant evidence and paths, exact scope, acceptance criteria, non-goals, and required validation. Prefer fresh context over \`inherit_context\`.
- Parallelize only genuinely independent, non-overlapping work. Put every concurrent writer in \`isolation: "worktree"\` and set \`run_in_background: true\` in the same turn. Never let concurrent agents edit the main tree or the same files.
- Before write delegation, inspect \`git status\`. A worktree starts from committed HEAD and cannot see parent uncommitted changes. If the task depends on those changes, use one deliberate foreground/in-place worker or pause for a checkpoint decision.
- Use FleetView and \`steer_subagent\` when new evidence invalidates a worker's assumptions or it leaves scope. Do not poll background agents.

## Model-aware briefings

Prompt-authoring skills are available to you through shared resource discovery, not to extension-isolated children. Before the first delegation to a model family in a session, read only its relevant skill and use it to shape the briefing:

- \`claude-fable-5-prompting\` for \`full-reviewer\`.
- \`gpt-5-6-prompting\` for \`sol-implementer\`, \`code-investigator\`, and \`adversarial-reviewer\`. Do not substitute the retained personal-use GPT-5.5 skill.
- \`claude-opus-4-8-prompting\` for \`opus-implementer\`.

Load on demand rather than reading every model skill on every turn. Apply the guidance to a concise, self-contained task prompt; do not paste the skill, its meta-instructions, or its prompt-generation output contract into the child briefing. State the intended outcome, why it matters, exact scope, evidence and paths, acceptance criteria, autonomy boundaries, non-goals, validation, and stop conditions. The child must be able to act correctly without access to the skill.

## Integration

- Treat a worker summary as untrusted. Inspect the complete returned branch diff, scope, tests, and artifacts before accepting it.
- Reject or steer out-of-scope/overlapping patches. Apply an accepted net patch to the main working tree without committing it, preserving user control of commits. Keep generated worker branches until all validation and review gates pass.
- Run relevant tests, type checks, lint, builds, and smoke checks on the integrated working tree; report exact failures rather than hiding them.

## Mandatory review sequence

This sequence is mandatory for approved-plan execution and for any similarly large or risky change; it does not apply to small direct edits covered by the proportionality rule.

1. After implementation and integrated validation, invoke \`full-reviewer\` in the foreground with the approved plan path, baseline/task diff, full code diff, worker branches, and exact test evidence. Adjudicate every R-xxx finding and remediate confirmed issues.
2. Then invoke a separate \`adversarial-reviewer\` in the foreground. Include the complete primary review verbatim plus the same source evidence. It must independently inspect code, challenge every finding, and search for omissions, false positives, severity errors, plan drift, and test gaps.
3. Adjudicate both reports yourself. Fix confirmed issues and rerun validation. If fixes materially change code, repeat both fresh review stages.

Do not claim completion or mark the final Plannotator checklist steps done until both sequential review gates close with no unresolved confirmed findings.`;

export default function agentModes(pi: ExtensionAPI) {
  let mode: Mode = "build";
  let displayMode: DisplayMode = "build";
  let thinkingOverride = false;
  let expectedThinking: string | undefined;
  let fallbackNoticeShown = false;
  const extensionPath = realpathSync(fileURLToPath(import.meta.url));
  const sharedSkillsPath = resolve(dirname(extensionPath), "../../opencode/skills");

  pi.on("resources_discover", () => ({ skillPaths: [sharedSkillsPath] }));

  function applyThinking(level: "medium" | "high" | "xhigh"): void {
    expectedThinking = level;
    pi.setThinkingLevel(level);
  }

  // Any thinking change this extension did not initiate (Shift+Tab cycle,
  // settings, \v variant) is a manual override and must stick between turns.
  pi.on("thinking_level_select", (event) => {
    if (event.level === expectedThinking) return;
    thinkingOverride = true;
  });

  async function getPlanPhase(requestedMode: "enter" | "exit" | "status"): Promise<PlannotatorPhase | undefined> {
    return await new Promise((resolve) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) resolve(undefined);
      }, 1000);

      pi.events.emit("plannotator:request", {
        requestId: crypto.randomUUID(),
        action: "plan-mode",
        payload: { mode: requestedMode },
        respond: (response: PlanModeResponse) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve(response.status === "handled" ? response.result?.phase : undefined);
        },
      });
    });
  }

  function cliModelRequested(): boolean {
    return process.argv.some((arg) =>
      arg === "--model" || arg.startsWith("--model=")
      || arg === "--models" || arg.startsWith("--models=")
      || arg === "--provider" || arg.startsWith("--provider="),
    );
  }

  async function selectMainModel(ctx: ExtensionContext, chain: readonly ModelRef[], opts: { force?: boolean } = {}): Promise<void> {
    // Pi persists the last used model as its settings default, so a fresh
    // session would otherwise inherit whatever model the previous session
    // ended on. Force the mode default on genuinely new sessions and on
    // explicit mode switches; otherwise only fill in a missing model.
    // Explicit CLI/TUI selections win.
    if (ctx.model && !opts.force) return;

    const activate = async (ref: ModelRef): Promise<boolean> => {
      if (ctx.model?.provider === ref.provider && ctx.model.id === ref.id) return true;
      const model = ctx.modelRegistry.find(ref.provider, ref.id);
      return model ? await pi.setModel(model) : false;
    };

    const [primary, fallback] = [chain[0]!, chain[1]];
    if (await activate(primary)) {
      fallbackNoticeShown = false;
      return;
    }

    if (fallback && await activate(fallback)) {
      if (!fallbackNoticeShown) {
        ctx.ui.notify(
          `Model ${primary.provider}/${primary.id} is unavailable or unauthenticated; using ${fallback.provider}/${fallback.id}`,
          "warning",
        );
        fallbackNoticeShown = true;
      }
      return;
    }

    ctx.ui.notify(
      `No usable main model: tried ${chain.map((ref) => `${ref.provider}/${ref.id}`).join(" and ")}`,
      "error",
    );
  }

  function buildTools(): string[] {
    return pi.getAllTools()
      .map((tool) => tool.name)
      .filter((name) => name !== "plannotator_submit_plan");
  }

  async function applyMode(nextMode: Mode, ctx: ExtensionContext, persist = true): Promise<void> {
    mode = nextMode;
    displayMode = nextMode;
    thinkingOverride = false;
    applyThinking(INTERACTIVE_THINKING);
    pi.setActiveTools(nextMode === "ask" ? READ_ONLY_TOOLS : buildTools());
    if (persist) pi.appendEntry("agent-mode", { mode: nextMode });
  }

  async function enterPlan(ctx: ExtensionContext): Promise<void> {
    // Keep build as the post-approval mode and as Plannotator's saved tool state.
    // If Plannotator cannot enter, restore the user's prior mode and tool policy.
    const previousMode = mode;
    await applyMode("build", ctx);
    const phase = await getPlanPhase("enter");
    if (!phase) {
      await applyMode(previousMode, ctx);
      ctx.ui.notify("Plannotator plan mode is unavailable; restored the previous mode", "error");
      return;
    }
    // Plannotator captured the pre-plan model in its saved state during
    // "enter", so plan approval and plan exit both restore it automatically.
    await selectMainModel(ctx, PLAN_CHAIN, { force: true });
    thinkingOverride = false;
    applyThinking(DEEP_THINKING);
    pi.setActiveTools(PLAN_TOOLS);
    displayMode = "plan";
  }

  async function enterBuild(ctx: ExtensionContext): Promise<void> {
    await getPlanPhase("exit");
    await applyMode("build", ctx);
    ctx.ui.notify(`Build mode enabled: ${ctx.model?.id ?? "main fallback"}, xhigh thinking`, "info");
  }

  async function enterAsk(ctx: ExtensionContext): Promise<void> {
    await getPlanPhase("exit");
    await applyMode("ask", ctx);
    ctx.ui.notify(`Ask mode enabled: ${ctx.model?.id ?? "main fallback"}, xhigh thinking, read-only tools`, "info");
  }

  async function cycleMode(ctx: ExtensionContext): Promise<void> {
    if (displayMode === "ask") {
      await enterPlan(ctx);
    } else if (displayMode === "plan") {
      await enterBuild(ctx);
    } else {
      await enterAsk(ctx);
    }
  }

  function cycleVariant(ctx: ExtensionContext): void {
    const current = pi.getThinkingLevel();
    const currentIndex = THINKING_VARIANTS.indexOf(current as (typeof THINKING_VARIANTS)[number]);
    const next = THINKING_VARIANTS[(currentIndex + 1) % THINKING_VARIANTS.length]!;
    thinkingOverride = true;
    pi.setThinkingLevel(next);
    ctx.ui.notify(`Thinking variant: ${next}`, "info");
  }

  function installCompactFooter(ctx: ExtensionContext): void {
    if (ctx.mode !== "tui") return;

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsubscribe = footerData.onBranchChange(() => tui.requestRender());
      return {
        dispose: unsubscribe,
        invalidate() {},
        render(width: number): string[] {
          let input = 0;
          let output = 0;
          let cacheRead = 0;
          let cacheWrite = 0;
          let cost = 0;
          for (const entry of ctx.sessionManager.getEntries()) {
            if (entry.type !== "message" || entry.message.role !== "assistant") continue;
            const message = entry.message as AssistantMessage;
            input += message.usage.input;
            output += message.usage.output;
            cacheRead += message.usage.cacheRead;
            cacheWrite += message.usage.cacheWrite;
            cost += message.usage.cost.total;
          }

          let location = compactCwd(ctx.sessionManager.getCwd());
          const branch = footerData.getGitBranch();
          if (branch) location += ` (${branch})`;
          const sessionName = ctx.sessionManager.getSessionName();
          if (sessionName) location += ` • ${sessionName}`;

          const locationLine = align(
            theme.fg("dim", location),
            theme.bold(theme.fg("accent", displayMode)),
            width,
          );

          const usage = ctx.getContextUsage();
          const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
          const contextUsage = usage?.percent == null
            ? `?/${formatTokens(contextWindow)}`
            : `${usage.percent.toFixed(1)}%/${formatTokens(contextWindow)}`;
          const stats = [] as string[];
          if (input) stats.push(`↑${formatTokens(input)}`);
          if (output) stats.push(`↓${formatTokens(output)}`);
          if (cacheRead) stats.push(`R${formatTokens(cacheRead)}`);
          if (cacheWrite) stats.push(`W${formatTokens(cacheWrite)}`);
          if (cost) stats.push(`$${cost.toFixed(3)}`);
          stats.push(`${contextUsage} (auto)`);

          const model = ctx.model;
          let modelText = model?.id ?? "no-model";
          if (model?.reasoning) modelText += ` • ${pi.getThinkingLevel()}`;
          if (footerData.getAvailableProviderCount() > 1 && model) {
            modelText = `(${model.provider}) ${modelText}`;
          }

          const statsLine = align(
            theme.fg("dim", stats.join(" ")),
            theme.fg("dim", modelText),
            width,
          );
          return [locationLine, statsLine];
        },
      };
    });
  }

  pi.registerCommand("plan", {
    description: "Enter Plannotator plan mode with Fable 5 at xhigh thinking",
    handler: async (_args, ctx) => enterPlan(ctx),
  });

  pi.registerCommand("build", {
    description: "Build mode: GPT-5.6 Sol default at xhigh thinking with full orchestration tools",
    handler: async (_args, ctx) => enterBuild(ctx),
  });

  pi.registerCommand("ask", {
    description: "Ask mode: GPT-5.6 Sol default at xhigh thinking, read-only tools",
    handler: async (_args, ctx) => enterAsk(ctx),
  });

  pi.on("session_start", async (event, ctx) => {
    thinkingOverride = false;
    installCompactFooter(ctx);
    if (ctx.mode === "tui") {
      ctx.ui.setEditorComponent((tui, theme, keybindings) => new LeaderEditor(tui, theme, keybindings, {
        cycleMode: () => { void cycleMode(ctx); },
        cycleVariant: () => cycleVariant(ctx),
        showHelp: () => ctx.ui.notify(
          "Leader: \\\\ mode · \\v variant · \\l sessions · \\m models · \\e editor · \\g tools · \\t thinking · \\y tree · \\n new · \\f fork here · \\F fork pane · \\q quit · \\Space literal backslash",
          "info",
        ),
        protectDraft: (action) => ctx.ui.notify(`Clear or submit the current draft before using ${action}`, "warning"),
      }));
    }
    const saved = ctx.sessionManager
      .getBranch()
      .filter((entry) => entry.type === "custom" && entry.customType === "agent-mode")
      .at(-1) as { data?: { mode?: Mode } } | undefined;
    mode = saved?.data?.mode === "ask" ? "ask" : "build";

    // Package session handlers run concurrently. Wait until Plannotator has
    // restored its phase and applied its own model/thinking profile.
    await new Promise((resolve) => setTimeout(resolve, 150));
    const phase = await getPlanPhase("status");
    await new Promise((resolve) => setTimeout(resolve, 50));
    // New sessions return to the mode default instead of the last-used
    // model that Pi persisted into settings. Resume/fork/reload keep the
    // session's own model, and CLI model flags always win.
    const freshSession = event.reason === "startup" || event.reason === "new";
    // Plannotator may still be entering planning when this runs, so honor the
    // --plan CLI flag directly in addition to the reported phase.
    const planning = phase === "planning" || process.argv.includes("--plan");
    await selectMainModel(
      ctx,
      planning ? PLAN_CHAIN : BUILD_CHAIN,
      { force: freshSession && !cliModelRequested() },
    );
    if (phase === "planning") {
      displayMode = "plan";
      applyThinking(DEEP_THINKING);
      pi.setActiveTools(PLAN_TOOLS);
    } else if (phase === "executing") {
      displayMode = "build";
      applyThinking(DEEP_THINKING);
      pi.setActiveTools(buildTools());
    } else {
      await applyMode(mode, ctx, false);
    }
  });

  pi.on("before_agent_start", async (event, ctx) => {
    const phase = await getPlanPhase("status");

    if (phase === "planning") {
      displayMode = "plan";
      if (!thinkingOverride) applyThinking(DEEP_THINKING);
      pi.setActiveTools(PLAN_TOOLS);
      return { systemPrompt: `${event.systemPrompt}\n\n${PLAN_ORCHESTRATION_PROMPT}` };
    }

    if (phase === "executing") {
      displayMode = "build";
      if (!thinkingOverride) applyThinking(DEEP_THINKING);
      pi.setActiveTools(buildTools());
      return { systemPrompt: `${event.systemPrompt}\n\n${BUILD_ORCHESTRATION_PROMPT}` };
    }

    displayMode = mode;
    if (!thinkingOverride) applyThinking(INTERACTIVE_THINKING);
    pi.setActiveTools(mode === "ask" ? READ_ONLY_TOOLS : buildTools());
    if (mode === "ask") {
      return { systemPrompt: `${event.systemPrompt}\n\n${ASK_PROMPT}` };
    }
    return { systemPrompt: `${event.systemPrompt}\n\n${BUILD_ORCHESTRATION_PROMPT}` };
  });
}
