---
name: gpt-5-5-prompting
description: GPT-5.5 prompt creation, prompt rewriting, prompt migration, and prompt review. Use when the user asks to create or improve prompts for GPT-5.5, OpenAI Responses, or GPT-5.5 agents.
---

# GPT-5.5 Prompting

Use this skill to turn a user's requirements into a finished GPT-5.5 prompt that follows OpenAI's GPT-5.5 prompt guidance.

## Core Behavior

- Produce a ready-to-use prompt, not generic prompting advice.
- Ask a narrow clarifying question only when missing information would materially change the prompt or create meaningful risk.
- If the request is clear enough, proceed with reasonable assumptions and label them briefly.
- Preserve the user's intended audience, product surface, tool environment, data sources, tone, policy boundaries, and output format.
- Avoid asking the model to reveal hidden chain-of-thought or internal reasoning.
- Include a short note on why the prompt fits GPT-5.5 only when it helps the user apply or evaluate the prompt.

## GPT-5.5 Prompting Principles

GPT-5.5 works best with concise, outcome-first prompts. Define what good looks like and give the model room to choose an efficient path.

- Prefer target outcome, success criteria, constraints, available evidence, final answer shape, and stop rules over step-by-step process stacks.
- Remove legacy over-specification unless a step is truly required.
- Use `always`, `never`, `must`, and `only` for true invariants such as safety rules, required fields, output schemas, and irreversible side-effect limits.
- For judgment calls, write decision rules instead of absolute rules.
- Add personality and collaboration style only when tone or user experience matters.
- For multi-step, tool-heavy, or long-running workflows, include a brief preamble rule so the model gives a short visible first-step update before tool calls.
- For factual or research workflows, define grounding rules, citation expectations, retrieval budgets, and missing-evidence behavior.
- For creative or generative drafting such as slides, outbound copy, summaries for sharing, or narrative framing, distinguish source-backed facts from creative wording and forbid invented specifics.
- For coding, visual, planning, or other verifiable work, include validation instructions and stopping conditions.
- Default formatting to plain paragraphs; use headers, bullets, and tables only when they improve comprehension. Add explicit audience and length guidance when the product needs it.
- For editing, rewriting, summarizing, or polishing prompts, instruct the model to preserve the artifact, length, structure, and genre first, then quietly improve clarity.
- For frontend prompts, include product and user context, design-system alignment, expected states, and defaults to avoid such as generic heroes, decorative gradients, nested cards, and visible instructional text.

## Recommended Prompt Shape

Use this structure for complex prompts. Omit sections that do not affect behavior.

```text
Role: [1-2 sentences defining the model's function, context, and job]

# Personality
[Tone, demeanor, and collaboration style]

# Goal
[User-visible outcome]

# Success Criteria
[What must be true before the final answer]

# Constraints
[Policy, safety, business, evidence, side-effect, and tool limits]

# Output
[Sections, length, tone, and format]

# Stop Rules
[When to retry, fallback, ask, abstain, or stop]
```

## Useful Blocks

### Preamble For Multi-Step Work

```text
Before any tool calls for a multi-step task, send a short user-visible update that states the first step. Keep it to one or two sentences.
```

### Retrieval Budget

```text
Use the minimum evidence sufficient to answer correctly, cite it precisely, then stop.

Start with one broad search using short, discriminative keywords. Search again only when the top results do not answer the core question, a required fact is missing, the user asked for exhaustive coverage, a specific artifact must be read, or an important factual claim would otherwise be unsupported.
```

### Creative Drafting

```text
Use retrieved or provided facts for concrete product, customer, metric, roadmap, date, capability, and competitive claims, and cite those claims. Do not invent specific names, first-party data claims, metrics, roadmap status, customer outcomes, or product capabilities to make the draft sound stronger. If there is little or no citable support, write a useful generic draft with placeholders or clearly labeled assumptions rather than unsupported specifics.
```

### Preserve-First Editing

```text
Preserve the requested artifact, length, structure, and genre first. Quietly improve clarity, flow, and correctness. Do not add new claims, extra sections, or a more promotional tone unless explicitly requested.
```

### Validation

```text
After completing the work, run the most relevant validation available. Prefer targeted tests, type checks, lint checks, build checks, rendered inspection, or a minimal smoke test. If validation cannot be run, explain why and describe the next best check.
```

## Parameter And Integration Notes

Surface these in the **Notes** section when relevant to the user's harness:

- Set `text.verbosity` to match the product; the API default is `medium`, and `low` suits shorter, more concise responses.
- Re-evaluate `low` and `medium` reasoning effort before escalating; GPT-5.5 reasons more efficiently than prior models.
- If the harness manually replays assistant output items into the next request, preserve each `phase` value exactly: `commentary` for intermediate user-visible updates, `final_answer` for the completed answer, and no `phase` on user messages. With `previous_response_id`, the API handles this automatically.

## Output Contract For This Skill

When using this skill, respond with:

```markdown
**Prompt**
[The finished GPT-5.5 prompt]

**Assumptions**
[Only if assumptions were needed]

**Questions**
[Only if the prompt cannot be responsibly completed]

**Notes**
[Optional model-specific implementation or parameter notes]
```
