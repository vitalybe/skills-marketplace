# Environment details

<current-branch>
!`git branch --show-current`
</current-branch>

<project-config>
!`cat "$(git rev-parse --show-toplevel)/project-config.toml" 2>/dev/null || echo [[Error: No project config found in project root. Run: /devflow:config-project skill]]`
</project-config>

## Issue details

<issue-details>
!`${CLAUDE_PLUGIN_ROOT}/bin/tasks show || echo [[No issue key resolved from branch name]]`
</issue-details>

**Task mode** when the block above resolved an issue, or the user names a
key (`${CLAUDE_PLUGIN_ROOT}/bin/tasks show <KEY>`) or asks to create one
(create it, then use its key). In task mode, if the issue has a parent,
fetch that too: `${CLAUDE_PLUGIN_ROOT}/bin/tasks show <PARENT-KEY>`. In task
mode, unless the issue's state is Done or Cancelled, move it along:
`${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> "In Progress"`.

Otherwise **task-less**: skip every `${CLAUDE_PLUGIN_ROOT}/bin/tasks`
call, and don't ask about task tracking unless the user brings up Jira or
a task themselves.

## Plan file path

<plan-path>
!`${CLAUDE_PLUGIN_ROOT}/bin/tasks plan || echo [[No plan path resolved - task-less mode]]`
</plan-path>

That is the plan file for this task - existing if one is already in the
tree (or on the task's branch), else the canonical path to create. Use
this path directly; **do not** re-run `tasks plan` to recompute it.

**Task-less mode:** if the block holds an error instead of a path, derive
it once - `_plans/<slug>.md`, kebab-cased from the task summary (~50
chars) - and use that exactly as you would the injected path.

Plan file shape: `${CLAUDE_PLUGIN_ROOT}/docs/plan-format.md`.

**Angle brackets are HTML.** GitHub renders `<void>`, `<slug>`, `<Toolbar />`
as tags and silently swallows them, so anything carrying `<` or `>` goes in
backticks: `` `Promise<void>` ``, `` `temp/<slug>` ``, `` `Map<string, T>` ``.
Where it can't be code - a placeholder inside a bolded heading or a link
label - escape it as `\<slug\>`. `<details>`/`<summary>` are the only raw
HTML tags the plan uses. This applies to every section you write, findings
bodies included.

## Gates

A gate is any point where the phase needs user input or approval.

Before ending a gate turn, flush state to the plan file: findings, the
answers received so far, anything a fresh agent needs to continue from the
plan alone.

End the turn with a user-ready package: the exact report text to present,
worded so it needs no rewording, plus the questions enumerated with stable
ids (`Q1`, `Q2`, ...), each carrying closed options where a choice fits.
What the user is asked must be self-contained - the full body needed to
decide, since that is what the question tool shows. Review findings satisfy
that from the plan file: the package names the section and the ids, and
whoever asks reads the bodies from there. Answers come back keyed by those
ids; continue from them. Running inline rather than as a sub-agent, present
that same package yourself (`AskUserQuestion`, one question per finding).

Report phase completion explicitly. A turn that ends with neither a gate
package nor a completion report is an error.

A completion report is valid only when no gate is outstanding: if the plan
file holds any finding under `### Unhandled` in its review sections that the
user has not yet been asked about, end the turn with that gate package
instead. Writing findings to the plan is the flush before presenting them,
never a substitute for asking about them - the gate still names them by id and
asks for a decision on each. A user instruction
to stop after a step means stop at its gate, not past it.

## Talking to the task tracker

All tracker access goes through `${CLAUDE_PLUGIN_ROOT}/bin/tasks` - never
invoke the underlying CLI from a SKILL.md. The flow's only tracker writes are
`tasks set-state`: "In Progress" at flow start, then at close "Pending Pull
Request Review" on the PR path (fall back to "In Review" if the project's Jira
lacks that state) or "Done" on a direct merge. Never post plans, descriptions,
or progress comments to the tracker.
