---
name: claude-fable-5-prompting
description: Claude Fable 5 prompt creation, prompt rewriting, prompt migration, and prompt review. Use when the user asks to create or improve prompts for Claude Fable 5 long-horizon agents, autonomous work, subagents, memory, or verification workflows.
---

# Claude Fable 5 Prompting

Use this skill to turn a user's requirements into a finished Claude Fable 5 prompt that follows Anthropic's Claude Fable 5 prompting guidance.

## Core Behavior

- Produce a ready-to-use prompt, not generic prompting advice.
- Ask a narrow clarifying question only when missing information would materially change the prompt or create meaningful risk.
- If the request is clear enough, proceed with reasonable assumptions and label them briefly.
- Preserve the user's intended audience, product surface, tools, data sources, tone, policy boundaries, output format, and autonomy level.
- Do not ask Claude to reproduce hidden chain-of-thought, internal reasoning, or private thinking. This can trigger reasoning-extraction refusals.
- Include parameter, fallback, or scaffolding notes when they affect Fable 5 behavior.

## Fable 5 Prompting Principles

Claude Fable 5 is built for hard, ambiguous, long-horizon work. It can sustain end-to-end execution, use parallel subagents well, and navigate multi-threaded tasks, but prompts should define boundaries clearly.

- Give the reason for the request, not only the task, especially for long-running agents drawing on multiple workstreams.
- Use concise steering for instruction following; avoid old prompt stacks that enumerate every minor behavior.
- Define when to act, when to pause, and what side effects are out of scope.
- Prevent unrequested expansion: no extra features, broad refactors, defensive backups, abstractions, or compatibility shims unless the user asked or the requirement demands it.
- For long runs, require progress claims to be grounded in actual tool results.
- Prefer parallel subagents for independent subtasks and fresh-context verifier subagents for long-running checks.
- Add memory-system instructions only when the user's harness provides a safe place to write and retrieve persistent notes.
- For autonomous pipelines, add an end-of-turn check so the model never ends a turn on a plan, promise, or permission question it could resolve itself.
- Avoid surfacing context-budget anxiety. Do not prompt the model to stop, summarize, or hand off merely because a run is long.
- Include domain caution for offensive cybersecurity, biology and life-sciences, and other workflows where Fable 5 refusals or fallback routing may matter.

## Effort Guidance

Include these notes when the prompt will be used in an API or harness that exposes effort controls:

- Use `high` as the default for most tasks.
- Use `xhigh` for the most capability-sensitive workloads.
- Use `medium` or `low` for routine, short, or interactive work where latency matters.
- Reduce effort if the task completes correctly but takes longer than necessary.
- For lower effort on complex tasks, add a short instruction that the task requires careful multi-step reasoning.

## Useful Blocks

### Act Without Overplanning

```text
When you have enough information to act, act. Do not re-derive facts already established in the conversation, re-litigate decisions the user has already made, or narrate options you will not pursue. If you are weighing a choice, give a recommendation, not an exhaustive survey.
```

### Scope Boundaries

```text
Do not add features, refactor, introduce abstractions, or create compatibility shims beyond what the task requires. Do the simplest thing that works well. Validate only at system boundaries such as user input and external APIs unless the task requires deeper checks.

When the user is describing a problem, asking a question, or thinking out loud rather than requesting a change, the deliverable is your assessment. Report your findings and stop; do not apply a fix until they ask for one. Before running a command that changes system state, check that the evidence actually supports that specific action.
```

### Pause Rules

```text
Pause for the user only when the work genuinely requires them: a destructive or irreversible action, a real scope change, missing input only they can provide, or a choice that materially changes the outcome. If you hit one of these, ask a narrow question and end the turn. Otherwise continue until the task is complete.
```

### Grounded Progress

```text
Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for. If tests fail, say so with the output. If a step was skipped, say that. When something is done and verified, state it plainly without hedging.
```

### Autonomous Operation

```text
You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task, so asking "Want me to…?" or "Shall I…?" will block the work. For reversible actions that follow from the original request, proceed without asking. Before ending your turn, check your last paragraph. If it is a plan, an analysis, a question, a list of next steps, or a promise about work you have not done, do that work now with tool calls. End your turn only when the task is complete or you are blocked on input only the user can provide.
```

### Memory Notes

```text
Store one lesson per file with a one-line summary at the top. Record corrections and confirmed approaches alike, including why they mattered. Do not save what the repo or chat history already records. Update an existing note rather than creating a duplicate, and delete notes that turn out to be wrong.
```

### Context Reassurance

```text
You have ample context remaining. Do not stop, summarize, or suggest a new session on account of context limits. Continue the work.
```

### Parallel Subagents

```text
Delegate independent subtasks to subagents and keep working while they run. Intervene if a subagent goes off track or is missing relevant context. For long-running work, establish a verification method and use fresh-context verifier subagents at defined checkpoints.
```

### Final Communication

```text
Lead with the outcome. Write complete sentences for the final summary. Do not use dense shorthand, arrow chains, or labels introduced only in the working context. If you have been working for a while, re-ground the user: outcome first, then the most important supporting detail, then any action needed from them.
```

## Scaffolding And Harness Notes

Surface these in the **Notes** section when relevant to the user's harness:

- Individual turns can run for many minutes and autonomous runs for hours. Adjust client timeouts, streaming, and user-facing progress indicators before migrating, and prefer checking on runs asynchronously over blocking.
- For long asynchronous agents, recommend a client-side `send_to_user` tool whose input is rendered verbatim in the UI. Tool inputs are never summarized, so deliverables, progress updates with specific numbers, and mid-loop replies arrive intact without ending the turn.
- Use the Context Reassurance block only when the harness must show a remaining-token countdown; otherwise avoid surfacing context-budget counts at all.
- Configure server-side or client-side fallback to Claude Opus 4.8 for refusal stop reasons in cybersecurity, life-sciences, or reasoning-extraction-adjacent workloads.

## Output Contract For This Skill

When using this skill, respond with:

```markdown
**Prompt**
[The finished Claude Fable 5 prompt]

**Assumptions**
[Only if assumptions were needed]

**Questions**
[Only if the prompt cannot be responsibly completed]

**Notes**
[Optional effort, autonomy, subagent, memory, fallback, or domain-risk notes]
```
