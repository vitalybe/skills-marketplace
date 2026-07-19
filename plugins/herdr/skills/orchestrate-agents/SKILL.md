---
name: orchestrate-agents
description: Manager-mode orchestration - run a multi-task effort by spawning several autonomous subagents, each taking one whole task end-to-end (via the devflow skills) in its own git worktree, while you coordinate dependency waves, serialize merges back to the integration branch, and gate on decisions only the user can make. Use whenever the user asks to "manage subagents", "run agents in parallel", "spin up agents for each task", "have agents do the tasks in <plan/wiki/phase>", "juggle several agents", "you manage them", or a backlog/plan/phase naturally splits into several independent tasks that could be built concurrently. The one-line discriminator versus architect mode: reach for THIS skill when each task is big enough to deserve its own full dev lifecycle (own plan, own tests, own review) and you will NOT read the diffs; stay in architect mode - designing the interfaces yourself and reviewing every diff of implementers you keep on a short leash - when you will.
---

# Multi-Agent Orchestration

You are the **manager**, not the implementer and not the reviewer. Each subagent
takes one whole task and runs it end-to-end on its own - implement, test, update
docs, and review its own code (via the devflow Code step). Your job is
coordination: decompose the work into agent-sized tasks, sequence them into
dependency waves, keep the integration branch coherent by serializing merges,
and stop to ask the user when a real decision surfaces.

The reason this split works: your context stays at the level of the plan,
the dependency graph, and the integration state - never clogged with any single
task's file-by-file detail. That's what lets you keep many workstreams straight
at once. If you find yourself writing feature code, you've dropped out of the
manager role and the coordination will start to slip.

## When to reach for this

- The user hands you a plan / wiki phase / backlog with several tasks and says
  some variant of "you manage them" or "run agents in parallel".
- A task decomposes into independent pieces (separate screens, separate
  packages, separate providers) with near-zero shared-file overlap.
- The work is large enough that doing it in one context would blow the budget
  or lose coherence.

If it's a single feature, or a task that needs one precise design you'd review
diff-by-diff, drop into architect mode instead - you design the interfaces
yourself and review every diff of implementers kept on a short leash - not the
manager mode this skill describes. If it's just one task, don't orchestrate at
all; do it directly.

## The wave model

Never fan everything out at once. Work proceeds in **waves**, with a barrier
between waves so dependencies and decisions resolve before the next fan-out:

1. **Planning wave.** Spawn one agent per task to *plan only* (devflow
   Requirements + Plan, produce a `_plans/<slug>.md`), then STOP before coding.
   Frame the brief as producing a concrete deliverable, not as a mode: "write a
   design DOCUMENT (a markdown file) using investigation tools (Read/Grep/Glob/
   Bash), then Write it", and say explicitly "you are NOT in plan mode; there is
   no approval gate; investigate and write the file directly". A brief worded as
   "plan only, do not implement" sometimes trips a plan-mode refusal - the agent
   reads it as the harness plan mode and returns almost instantly having done
   nothing, echoing plan-mode reminder text. The only restriction is scope (touch
   just the plan file), not action.
   Have planners write into the integration checkout's `_plans/` (or commit the
   plan on their branch) so you can read them without chasing worktrees. Require
   each planner to declare what its tests will need to actually run - a live
   backend/service, realtime/websocket, seeded fixtures, a test DB - so the "can
   these tests even run in the harness?" question lands at the decision gate
   rather than three agents deep into implementation. Cheap,
   parallel, and it surfaces the cross-task decisions and interface overlaps
   before any code exists. Read the plans; they often dovetail (one agent's
   inputs are another's outputs) - that tells you the real ordering. Because
   SendMessage resumes an agent with its context intact, the natural move is to
   resume each planner as its own implementer in wave 4 - it already holds the
   plan. Weigh that against context budget: a long-running agent carries its
   whole history; a fresh agent with a tight brief is cheaper if the plan file
   already captures everything it needs.
2. **Decision gate.** Anything the plans surface that you cannot decide from the
   plan, the code, or a sensible default - a shared architecture choice, a
   product tradeoff, a monetization/security call, a test-layering call (stand up
   the live stack some tests declared they need vs. push those cases down to
   hermetic integration tests) - goes to the user now, before implementation.
   Batch these into one `AskUserQuestion` rather than trickling.
3. **Prep wave (only if needed).** Any cross-cutting change - a new field on a
   shared interface, a new manager hook, a shared migration - goes to a single
   sequential agent BEFORE the parallel fan-out, so the parallel agents build
   against a stable interface instead of colliding on it. When the planning wave
   reveals a shared artifact several tasks need - a test fixture, a shared helper,
   a set of data-testids - have this agent OWN it and publish its exact consumable
   signature (fixture call signature, testid names, helper API) so every
   downstream agent consumes it verbatim instead of reinventing it.
4. **Implementation wave.** Fan out the independent tasks. Each agent
   implements its own plan end-to-end using the devflow skills.
5. **Serialized merge + integration validation.** You (not the agents) merge the
   finished branches one at a time, in dependency order (a foundation branch
   others build on merges first), running the full validation on the integration
   branch after each merge (see below). Merge each branch as it finishes and
   passes rather than holding the whole wave - smaller, earlier merges keep the
   conflict surface small.
6. **Cleanup.** Tear down each merged worktree and its branch:
   ```bash
   git worktree remove <path> --force   # if it wasn't auto-removed
   git branch -d <task-branch>          # or keep it, per the user's preference
   ```

## Worktree setup

Every agent works in its own worktree branched off the **integration branch**
(the branch the user told you to base on - usually the one you're on), never off
`main`, and never sharing a checkout:

```bash
git worktree add -b <task-branch> <path> <integration-branch>
```

Put worktrees under a predictable location outside the repo's own tree (e.g. a
`.worktrees/<task>` dir that is gitignored, or a sibling directory) so agents'
`git status` stays clean. `git worktree add` does NOT change any agent's working
directory, and an agent's shell cwd resets between commands - so the brief must
tell the agent to treat the worktree path as absolute and prefix every command
and file path with it (`git -C <path> ...`, absolute file paths). Prefer this
manual approach over the Agent tool's `isolation: "worktree"` here because you
need to control the base branch (the integration branch, not `main`) and keep
predictable paths for the merges you'll drive.

Agent worktrees don't get dependencies. A single root symlink is NOT enough in a
pnpm/monorepo workspace (each package - `app/`, `backend/`, `@shared/` - has its
own `node_modules`). Tell the agent to either symlink every dependency dir the
project has (ABSOLUTE paths - a relative `../node_modules` breaks from a nested
worktree) or just run the project's install command in the worktree; don't
assume one root symlink covers a workspace.

## Spawning an agent

Spawn implementation agents in the **background** (default) and, for a parallel
wave, in a **single message** so they run concurrently. Each brief is
self-contained - the agent has none of your conversation:

```
You are taking ONE task end-to-end: <task>. You are in your own git worktree
at <path>, branched off <integration-branch>.

Do EVERY command and file operation under the absolute worktree path <path>
(use `git -C <path> ...` and absolute file paths - your cwd is not the worktree
and resets between commands).

Setup:
1. Provision dependencies: <exact per-project step - symlink each package's
   node_modules with absolute paths, or run <install command> in the worktree>.

Do the work using the project's dev-flow Code step - invoke the skill
`<exact skill name, e.g. devflow:_internal-step-code or g-flow-3-code>`: read
the plan at <_plans/...>, implement it, run the tests, update the docs, then
run its Code Review step (two parallel reviewers) and apply the clear fixes
(one commit each).

Constraints:
- Run in task-less mode: skip ALL task-tracker calls (no Linear, no `tasks`)
  in every dev-flow step, including Requirements/Plan.
- Match existing code style; add no dependencies without flagging.
- Stay inside this task's files. If you need to touch a shared file, touch
  ONLY the one registration line named here: <line>.
- Commit on your branch (multiline message via `git commit -F <file>`, ending
  with the repo's Co-Authored-By trailer).

If you hit a genuine decision that isn't yours to make (a product call, a
shared-contract change), STOP and report the blocker instead of guessing - I'll
get the answer and resume you.

Do NOT merge to <integration-branch> - I serialize merges. When done, report:
branch name, files changed, test/tsc results, any decision you had to make or
punt, and anything you deviated from the plan on.
```

Before you write the briefs, verify the exact dev-flow Code-step skill name
against the live skill registry - names drift and vary per environment
(`g-flow-3-code` vs `devflow:_internal-step-code`). A brief that names a skill
which doesn't exist in that environment makes the agent silently fall back to
whatever it can find - it may still work, but by luck, not design. Name the one
that actually exists; don't trust a skill name carried over from stale or
summarized session context.

Two briefing rules that pay off every time: tell the agent to **flag any
decision it had to make** (that's where your attention goes on merge), and tell
it to **validate what the merge target will actually run**, not just what's
green inside its worktree (see the integration-validation lesson).

## Serialize the merges yourself

Parallel agents finishing against one integration branch is a race - two
simultaneous merges corrupt the branch. So the agents do NOT merge; you do, one
at a time, from the integration worktree:

```bash
git merge <task-branch> --no-edit
```

Design the fan-out so parallel agents only ever touch shared files at trivially
mergeable spots (one entry in a registry, one `case` line) - everything else in
new files each agent owns. Resolve the small expected registry conflicts by
hand. If git rerere mangles a conflicted file ("could not parse conflict
hunks"), stop fiddling and rewrite that small shared file wholesale with Write.

**After every merge, re-run the full validation on the integration branch** -
tsc, the unit suite, the e2e/smoke suite, whatever the project uses. Merges
break even when both sides were independently green, and the failure often lives
in a seam neither agent could see from inside its worktree. (Real example from
this workflow: two branches each passed in isolation, but once the test harness
and a package merged together, the unit runner's default glob started collecting
the e2e specs and the suite exited non-zero - invisible until integration.)
Also expect a freshly-merged dependency to be declared but not installed in the
integration worktree; run the install step, don't just trust the lockfile.

## Managing agents in flight

- A background agent's completion fires a task-notification; pick up its report
  then, don't poll.
- To continue an agent with its context intact (a fix, a follow-up task, a
  clarification), use SendMessage with its id - a fresh Agent call starts cold
  and re-derives everything.
- If you discover a shared need while the foundation/prep agent is still running,
  extend its scope in-flight with SendMessage rather than letting each downstream
  task reinvent the artifact.
- When a review finds a substantive behavioral problem, prefer sending the
  findings back to an agent over patching behavior yourself - manager hands stay
  on coordination, not code.
- When an agent reports a blocker (a decision that isn't its to make, or a
  dependency on another task not yet merged), don't let it guess: get the answer
  - from the user if it's a real decision gate - and resume the agent with
  SendMessage. If an agent dies or stalls, its worktree and branch persist;
  inspect its last state, then either resume it or spawn a fresh agent pointed at
  the same worktree with a corrected brief.

## Decision gates - when to stop and ask

The user put you in charge precisely so you'd absorb the small decisions and
escalate only the ones that are theirs. Escalate when: two plans disagree on a
shared contract; a task is blocked on a product/business/monetization call; a
change is hard to reverse or outward-facing; or the "sensible default" would
lock in something the user clearly cares about. Otherwise decide, note the
decision in your next message, and keep the waves moving. Don't stall a whole
wave on a question you can answer.

## Anti-patterns

- **Fanning out before planning.** You discover the collisions and the ordering
  from the plans; skip the planning wave and you fan out into conflicts.
- **Letting agents self-merge in parallel.** Races the integration branch. If
  an agent must merge, gate it so only one merges at a time.
- **Trusting in-worktree green.** Validate on the integration branch after each
  merge - that's where cross-task breakage appears.
- **Doing the coding yourself.** The moment you're editing feature files you're
  no longer managing; hand it to an agent (new or resumed) instead.
- **Trickling questions.** Batch the decision gate into one ask; don't interrupt
  the user once per task.
