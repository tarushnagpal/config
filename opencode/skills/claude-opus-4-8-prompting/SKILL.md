---
name: claude-opus-4-8-prompting
description: Claude Opus 4.8 prompt creation, prompt rewriting, prompt migration, and prompt review. Use when the user asks to create or improve prompts for Claude Opus 4.8 agents, tools, coding, design, or review workflows.
---

# Claude Opus 4.8 Prompting

Use this skill to turn a user's requirements into a finished Claude Opus 4.8 prompt that follows Anthropic's Claude Opus 4.8 prompting guidance.

## Core Behavior

- Produce a ready-to-use prompt, not generic prompting advice.
- Ask a narrow clarifying question only when missing information would materially change the prompt or create meaningful risk.
- If the request is clear enough, proceed with reasonable assumptions and label them briefly.
- Preserve the user's intended audience, product surface, tools, data sources, tone, policy boundaries, and output format.
- Avoid asking Claude to reveal hidden chain-of-thought or internal reasoning.
- Include parameter or scaffolding notes when they affect Opus 4.8 behavior.

## Opus 4.8 Prompting Principles

Claude Opus 4.8 is strong at long-horizon agentic work, knowledge work, vision, and memory tasks. It follows prompts literally, especially at lower effort settings.

- Calibrate response length explicitly when the product needs a predictable level of detail.
- Prefer positive examples of desired concision or tone over long lists of things not to do. The default prose style is direct and opinionated; if the product voice is warmer or more conversational, state that explicitly.
- State instruction scope explicitly. If a rule applies to every section, every item, every tool call, or the whole conversation, say so.
- Add tool-use guidance when tools are important, because Opus 4.8 can favor reasoning over tool calls.
- Avoid rigid progress-update scaffolding by default; define update length and content only when the user experience requires it.
- Add subagent guidance when work should fan out across independent files, sources, tasks, or investigations.
- For code review, use coverage-first finding instructions when recall matters.
- For frontend and design prompts, specify a concrete visual direction or ask for distinct options before building to avoid the model's default warm cream/editorial style.
- For interactive multi-turn coding products, specify the task, intent, and constraints upfront in the first turn and reduce required user interactions; the model reasons more after user turns, so ambiguous prompts spread over many turns cost tokens and performance.

## Effort Guidance

Include these notes when the prompt will be used in an API or harness that exposes effort controls:

- Use `xhigh` for most coding and agentic use cases.
- Use at least `high` for intelligence-sensitive work.
- Use `medium` for cost-sensitive work that can trade off intelligence.
- Use `low` only for short, scoped, latency-sensitive tasks.
- Test `max` only for intelligence-demanding tasks; it can show diminishing returns and overthinking.
- If shallow reasoning appears on complex work, raise effort before adding prompt clutter.
- If using `xhigh` or `max`, provide a large max output token budget (start at 64k) so the model has room for tool calls and subagents.
- Thinking is off unless `thinking: {type: "adaptive"}` is set. Adaptive thinking triggering is steerable: prompt to think less if it triggers too often with large system prompts, or to think more for hard workloads at lower effort.

## Useful Blocks

### Concision

```text
Provide concise, focused responses. Skip non-essential context, and keep examples minimal. Do not shorten the response so much that required evidence, decisions, or checks are omitted.
```

### Tool Use

```text
Use tools when they materially improve correctness: to inspect current state, verify claims, retrieve required evidence, run checks, or perform requested actions. Do not rely on reasoning alone when the answer depends on data that tools can confirm.
```

### Subagents

```text
Do not spawn a subagent for work you can complete directly in a single response. Spawn multiple subagents in the same turn when fanning out across independent files, sources, tasks, or investigations.
```

### Review Coverage

```text
Report every issue you find, including issues you are uncertain about or consider low-severity. Do not filter for importance or confidence at the finding stage. Include confidence and estimated severity so a downstream step can rank findings.
```

### Frontend Variety

```text
Before building, propose 4 distinct visual directions tailored to the brief. For each, include background color, accent color, typeface, and a one-line rationale. Ask the user to pick one, then implement only that direction.
```

### Frontend Aesthetics

```text
NEVER use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white or dark backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character. Use unique fonts, cohesive colors and themes, and animations for effects and micro-interactions.
```

## Output Contract For This Skill

When using this skill, respond with:

```markdown
**Prompt**
[The finished Claude Opus 4.8 prompt]

**Assumptions**
[Only if assumptions were needed]

**Questions**
[Only if the prompt cannot be responsibly completed]

**Notes**
[Optional effort, tool, subagent, design, or harness notes]
```
