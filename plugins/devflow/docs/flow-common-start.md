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

## Gates

A gate is any point where the phase needs user input or approval.

Before ending a gate turn, flush state to the plan file: findings, the
answers received so far, anything a fresh agent needs to continue from the
plan alone.

End the turn with a user-ready package: the exact report text to present,
worded so it needs no rewording, plus the questions enumerated with stable
ids (`Q1`, `Q2`, ...), each carrying closed options where a choice fits.
Answers come back keyed by those ids; continue from them. Running inline
rather than as a sub-agent, present that same package yourself.

Report phase completion explicitly. A turn that ends with neither a gate
package nor a completion report is an error.

## Talking to the task tracker

All tracker access goes through `${CLAUDE_PLUGIN_ROOT}/bin/tasks` - never
invoke the underlying CLI from a SKILL.md. The flow's only tracker writes are
`tasks set-state`: "In Progress" at flow start, then at close "Pending Pull
Request Review" on the PR path (fall back to "In Review" if the project's Jira
lacks that state) or "Done" on a direct merge. Never post plans, descriptions,
or progress comments to the tracker.
