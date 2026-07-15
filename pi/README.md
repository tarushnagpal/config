# Pi configuration

This directory is linked to `~/.pi/agent` by the host bootstrap. Keep authentication and sessions in the runtime directory; do not link or commit `auth.json` or `sessions/`.

## Frontier subagents

The shared Pi configuration uses pinned `@tintinweb/pi-subagents` `0.13.0` with a quality-first, coding-focused fleet. Main-session models are routed per mode: fresh build/ask sessions (`pi` startup or `/new`) start on `openai/gpt-5.6-sol`, while `/plan` and `pi --plan` switch to `anthropic/claude-fable-5` for Plannotator planning. Each default falls back visibly to the other frontier model when unavailable. Plannotator captures the pre-plan model on plan entry and restores it on approval or plan exit, so approved-plan execution runs on the model you were using before planning (Sol by default). Pi natively persists the last used model as its settings default, so without the fresh-session reset a new session would silently inherit whatever model the previous session ended on. Explicit selections still win: a CLI `--model`/`--models`/`--provider` flag disables default routing for that launch, and a mid-session manual selection sticks across mode switches until the session ends. Resumed and forked sessions keep their own model. Every Sol role — main build/ask/execution, investigator, implementer, and adversarial reviewer — runs at `xhigh`; the Opus implementer and Fable primary reviewer run at `high`. Fable is reserved for planning and the primary review, and the Sol adversarial auditor gives the review sequence cross-provider independence.

All main-session modes — ask, build, Plannotator planning, and approved-plan execution — default to `xhigh`. Any manual thinking change (`Shift+Tab`, settings, or the `\v` variant cycle across `medium`/`high`/`xhigh`) sticks until the next explicit mode switch, which is the lever for faster interactive turns when needed. The build orchestration prompt includes a proportionality rule: small, scoped, low-risk changes are implemented directly with targeted validation; delegation, worktrees, and the two-stage review gates apply to approved-plan or similarly large/risky work.

| Agent type | Model | Access | Use |
| --- | --- | --- | --- |
| `code-investigator` | GPT-5.6 Sol (`xhigh`) | Read-only | Root cause, architecture, dependency tracing, implementation reconnaissance |
| `sol-implementer` | GPT-5.6 Sol (`xhigh`) | Full built-in coding tools | Default terminal-heavy and test-driven implementation |
| `opus-implementer` | Claude Opus 4.8 (`high`) | Full built-in coding tools | Sustained multi-file work or a provider-diverse implementation path |
| `full-reviewer` | Fable 5 (`high`) | Read-only, foreground | Exhaustive primary review against plan, diff, code, and tests |
| `adversarial-reviewer` | GPT-5.6 Sol (`xhigh`) | Read-only, foreground | Cross-provider audit of the primary review and search for omissions/overclaims |

The built-in `general-purpose`, `Explore`, and `Plan` agents are disabled to avoid ambiguous or cheap-model routing. Plannotator owns planning; the custom agents own investigation, implementation, and review. Child agents load no extensions, which prevents the main-session mode extension from replacing their pinned models. They retain normal built-in tools and skills available through standard discovery roots, but not extension-contributed tools or `resources_discover` skill paths. In particular, the model prompt-authoring skills used as source material for these definitions are intentionally not preloaded into coding workers. Pi-subagents also removes its own delegation tools from children, so delegation is one level deep.

### Model-prompting skills

`agent-modes.ts` exposes the shared `opencode/skills` directory to the main orchestrator through `resources_discover`. Four independent prompt-authoring skills are available there:

- `claude-fable-5-prompting` — Fable orchestrator, investigator, and reviewer briefings.
- `claude-opus-4-8-prompting` — Opus implementer briefings.
- `gpt-5-6-prompting` — GPT-5.6 Sol implementer briefings.
- `gpt-5-5-prompting` — retained separately for personal GPT-5.5 prompt work; never use it as a substitute for the Sol skill.

Before its first delegation to a model family in a session, the orchestrator reads only the corresponding skill, then writes a concise, self-contained briefing. It does not preload every skill, paste skill text or prompt-generation output contracts into child prompts, or assume the child can access the skill. Model-specific behavior needed by a specialist is distilled into that agent's fixed prompt.

The prompt-authoring skills are intentionally orchestrator-only: child agents use `extensions: false`, so they do not inherit this extension-contributed path. `skills: true` still allows normal project and standard-root skills. This separation preserves child model pins and prevents prompt-authoring meta-instructions from displacing the coding task.

Each synchronized skill (Fable 5, Opus 4.8, and GPT-5.6) cites its canonical vendor guide and synchronization date. When vendor guidance changes, update that one distilled skill and the affected fixed agent prompt together; do not replace it with a full documentation dump. Keep the separately retained GPT-5.5 skill and the new GPT-5.6 skill independently named and discoverable.

### Required lifecycle

1. Use `/plan` and iterate in Plannotator until the implementation plan is approved.
2. Every generated plan ends with separate **full review/remediation** and **adversarial review-of-review/final closure** checklist steps.
3. During execution, the main orchestrator may delegate independent implementation slices to Sol or Opus.
4. The main agent inspects each complete worker branch diff and validation evidence before applying an accepted net patch to the main working tree. It does not commit the integrated patch, preserving user control of commits.
5. After integrated-tree tests, `full-reviewer` performs the primary review and emits stable `R-xxx` findings plus a plan-coverage matrix.
6. `adversarial-reviewer` receives that complete report and the same source evidence. It independently inspects the code, dispositions every `R-xxx`, and emits missed `A-xxx` findings.
7. The main agent adjudicates both reports, fixes confirmed issues, reruns checks, and repeats both fresh review stages after material remediation. Completion is blocked while a confirmed finding remains unresolved.

### Worktrees, integration, and steering

Concurrent writers must use `run_in_background: true` with `isolation: "worktree"`, and their file scopes must not overlap. A worktree starts from committed `HEAD`; it cannot see uncommitted parent changes. If a task depends on a dirty working tree, use one deliberate foreground/in-place worker or create a user-approved checkpoint instead of silently delegating stale state.

A completed isolated worker returns a local `pi-agent-*` branch. Inspect the full diff and test evidence before applying its net patch without committing. Keep the generated branch until integrated tests and both review gates pass. The shared `AGENTS.md` git policy applies to the main agent and all append-mode children: no commits, pushes, or remote/branch/tag changes unless the user explicitly asks, and user-requested commits follow the Conventional Commits (`feat:`, `fix:`, ...) format. Worktree isolation protects repository files from concurrent edits; it is **not** an OS sandbox, so full-capability workers can still execute commands with the current user's permissions.

Use FleetView or `/agents` to inspect active conversations. The global widget mode is `all`, so foreground and background runs both remain visible. A running agent can be redirected from its conversation viewer or with `steer_subagent`; use steering when new evidence invalidates assumptions or the worker leaves scope. Background results use smart joining and should not be polled.

Pi's tool and completed-agent output expansion is rebound to `Ctrl+X` in the shared `keybindings.json`. Zellij keeps its more widely used `Ctrl+O` session-mode binding unchanged.

### Shared-host setup and upgrades

The host bootstrap must expose all of these shared assets beneath `$PI_CODING_AGENT_DIR` (normally `~/.pi/agent`):

- `settings.json`
- `keybindings.json`
- `plannotator.json`
- `subagents.json`
- `extensions/`
- `agents/`
- `themes/`

Authentication stays local in `$PI_CODING_AGENT_DIR/auth.json` on each host. Configure OpenAI and Anthropic independently; never copy `auth.json` into this repository. Sessions, npm runtime files, subagent transcripts, and worktrees also remain host-local.

`settings.json` contains Pi's managed `lastChangelogVersion`. A Pi upgrade can update that value and dirty the shared checkout, especially while hosts temporarily run different Pi versions. Treat this as expected metadata churn, keep host versions aligned, and review the diff rather than copying settings into a host-local file.

Install the pinned package on each host and verify discovery:

```sh
pi install npm:@tintinweb/pi-subagents@0.13.0
pi list
pi --list-models anthropic
pi --list-models openai
```

Do not silently float the package version. To upgrade, review the upstream changelog for frontmatter/tool-loading changes, update the version in shared `settings.json`, run `pi install npm:@tintinweb/pi-subagents@<version>` on both hosts, then repeat agent discovery, worktree, steering, and two-stage review smoke tests.

## Plannotator ports

`extensions/plannotator-session-ports/` prevents concurrent Pi sessions on a remote host from all trying to bind Plannotator's default port `19432`.

For SSH/remote sessions without an explicit `PLANNOTATOR_PORT`, each active Pi process reserves one port from a Pi-only range:

- Default range: `19600–19663`
- Lock directory: `~/.plannotator/pi-session-ports/`
- Diagnostic command: `/plannotator-port`

OpenCode continues to use its separate default range `19432–19495`, avoiding races between the two agent harnesses. The existing `opencode/scripts/plannotator-browser.sh` supports every port in either range by rewriting the URL to the devbox Tailnet hostname before asking the laptop opener to open it.

Optional overrides:

```sh
export PI_PLANNOTATOR_PORT_BASE=19600
export PI_PLANNOTATOR_PORT_COUNT=64
export PI_PLANNOTATOR_PORT_LOCK_DIR="$HOME/.plannotator/pi-session-ports"
```

An explicitly configured `PLANNOTATOR_PORT` always wins and disables allocation. Local sessions, including Pi running directly on macOS, retain Plannotator's native random-port behavior unless `PLANNOTATOR_REMOTE=1` is explicitly set.

Locks contain no credentials. Normal session shutdown, reload, resume, new-session, and fork flows release the owned lock. After an unclean exit, the next allocator verifies the recorded PID and Linux process-start identity and reclaims a dead owner's lock automatically. A recent malformed lock is retained briefly to avoid racing a writer, then becomes reclaimable.

If the range is exhausted:

1. Run `/plannotator-port` in active Pi sessions to identify their allocations.
2. Inspect `~/.plannotator/pi-session-ports/` and the configured range's listeners.
3. Exit unused Pi processes, or increase `PI_PLANNOTATOR_PORT_COUNT`.
4. Do not manually remove a lock belonging to a live Pi process.

The devbox browser path also requires the existing `PLANNOTATOR_BROWSER`, `PLANNOTATOR_LAPTOP_HOST`, and Tailnet host settings used by `plannotator-browser.sh`. No additional SSH forwarding is required when the laptop can reach the devbox over Tailscale.

### Single active code review patch

Pi uses one fixed remote port for the lifetime of each session. Upstream
`@plannotator/pi-extension` 0.23.1 starts a new HTTP server every time
`/plannotator-review` runs, so invoking the command again while its first review
is open retries the same occupied port. This configuration pins 0.23.1 and
applies an idempotent source patch that:

- reopens the existing review URL instead of starting another server;
- suppresses concurrent review startup;
- releases the active review server during Pi session shutdown; and
- fails closed if the installed package version or expected upstream source has
  changed.

Apply the patch on each host after installing the pinned package:

```sh
pi install npm:@plannotator/pi-extension@0.23.1
node pi/scripts/patch-plannotator-pi-single-review.js
```

Run the patch again after deliberately reinstalling the package. Finish or exit
an already-open review before restarting Pi so processes that loaded the old
extension code do not retain their listener. An upstream version bump requires
reviewing and updating the patch targets before changing the pin.

## Zellij pane slots and worktree restoration

Every worktree Pi process and every new Pi session runs from the stable mono
root, `${PROXIMAL_MONO_ROOT:-/home/ubuntu/workspace/proximal/mono}`. The Zellij
tab container is also mono-rooted so its final layout remains serializable after
the worktree is deleted; the rendered layout gives editor and shell command
panes explicit worktree cwd values. A custom `PROXIMAL_WORKTREE_LAYOUT` must
use the repository layout's inline `pane ... command="..."` form; an explicit
inline `cwd="..."` is preserved. Private manifests under
`$XDG_STATE_HOME/pi-zellij/worktrees/` (default:
`~/.local/state/pi-zellij/worktrees/`) keep the worktree path as durable
metadata separately from the Pi session cwd. The worktree path may be missing;
it is never recreated implicitly.

While Pi owns a Zellij pane, the session-slots extension sets that pane's default
background to midnight navy (`#111827`). Normal quit, reload, and session
replacement reset the pane to its terminal-default colors; the next Pi
`session_start` reapplies the navy background.

Each stable pane slot points to that pane's current mono-root Pi session ID and
optional JSONL path. The extension also stores a custom worktree-context entry
inside the session. On every agent turn it appends the active path and its
present/missing status to the existing system prompt, directing repository
edits, git commands, builds, tests, and worktree-local instruction discovery to
the worktree instead of Pi's cwd. That custom entry restores context when a
mono-root session is resumed manually, including after the worktree is deleted.

- The first Pi pane for a worktree with no registered slots starts a fresh
  session. It never uses shared-cwd `--continue`.
- A legacy slot whose JSONL header names the old worktree cwd is migrated once
  by `pi --fork` into a new mono-root session. The original JSONL is preserved;
  after `session_start` updates the slot, later restorations use the new file.
- `\\f` keeps Pi's built-in current-pane fork behavior.
- `\\F` opens the full user-message selector, forks before the selected
  message, restores that prompt in the child editor, and opens the child in a
  focused mono-root stacked Zellij pane. A non-empty editor draft is never
  overwritten.
- `/forget-pi-pane` removes the current slot from future tab restoration while
  retaining its Pi JSONL history.
- `piw` starts a new registered Pi pane for the current worktree, with Pi itself
  running at mono root.
- `owt` focuses an existing same-name tab; after an explicit tab close it
  restores every registered slot.
- `rmwt` clears only the removed worktree's pane registry. Mono-root Pi history
  remains available to Pi's normal resume selector.

`zellij/rewrite-resurrect-command.sh` is the primary command-discovery hook.
`zellij/sanitize-resurrection-layout.py` is a defensive fallback for Zellij
0.44.3: it keeps stack expansion valid and rewrites serialized, registered Pi
panes to `open-worktree-pi.sh` with mono-root pane cwd. A no-argument restored
launcher resolves the exact pane slot globally and fails rather than guessing
if registry metadata is ambiguous. Bare `z` remains an alias for `zellij`;
attaching to or resurrecting `mono` is intentionally explicit. OpenCode's
separate launcher behavior is unchanged by this Pi workflow.

Diagnostics:

```sh
piw --help
~/.config/zellij/pi-session-registry.py list --worktree-path "$PWD"
~/.config/zellij/pi-session-registry.py path --worktree-path "$PWD"
```

## Tests

From the configuration repository, with Node.js 24 or newer:

```sh
node --test \
  pi/extensions/plannotator-session-ports/allocator.test.ts \
  pi/extensions/zellij-session-slots/zellij-session-slots.test.ts \
  pi/scripts/patch-plannotator-pi-single-review.test.js
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v \
  zellij/test_pi_session_registry.py \
  zellij/test_open_worktree_pi.py \
  zellij/test_open_worktree_tab.py \
  zellij/test_sanitize_resurrection_layout.py
./zellij/test_no_singleton_pi_stack.sh
./zellij/test_pi_resurrection.sh
```

The Zellij integration tests use disposable named sessions and fake processes.
They exercise singleton and stacked layout serialization, two independent Pi
slots, pane restart, tab recreation, existing-tab focus, and full
kill/resurrection after deleting the worktree, without touching `mono`.
