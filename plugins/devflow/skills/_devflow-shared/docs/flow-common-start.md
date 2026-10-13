# Environment details

<current-branch>
!`git branch --show-current`
</current-branch>

<project-config>
!`cat "$(git rev-parse --show-toplevel)/project-config.toml" 2>/dev/null || echo [[Error: No project config found in project root. Run: /devflow:config-project skill]]`
</project-config>

## Issue details

<issue-key>
!`git branch --show-current | grep -oE '[A-Z]+-[0-9]+$' || echo [[No issue key in branch name]]`
</issue-key>

**Task mode** when the block above holds a key, the user names one, or the user
asks to create one (create it, then use its key). Your first step in task mode
is to read that issue with `atlassian_jira_get_issue`; if it has a parent, read
that too. Then, unless its state is Done or Cancelled, transition it to
"In Progress". Tool names and the transition procedure are in
`_devflow-shared/docs/jira-tools.md`, inlined under **Talking to the task
tracker** below.

Otherwise **task-less**: skip every JIRA call, and don't ask about task
tracking unless the user brings up Jira or a task themselves.

## Plan file path

<plan-path>
!`${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/tasks plan || echo [[No plan path resolved - task-less mode]]`
</plan-path>

When that block holds a path, it is the plan file for this task - one already
in the tree (or on the task's branch). Use it directly; **do not** re-run
`tasks plan` to recompute it. When it reports no existing plan, run `tasks plan
<KEY> "<issue title>"` once with the title you read from the issue, and use the
canonical path it prints - passing the title is what keeps that command free of
any tracker lookup.

**Task-less mode:** if the block holds an error instead of a path, derive
it once - `_plans/<slug>.md`, kebab-cased from the task summary (~50
chars) - and use that exactly as you would the injected path.

Plan file shape: `_devflow-shared/docs/plan-format.md`.

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

Tracker reads and writes go through the JIRA tools below;
`${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/tasks` resolves plan paths and
nothing else. The flow's only tracker writes are status changes: "In Progress"
at flow start, then at close "Pending Pull Request Review" on the PR path (fall
back to "In Review" if the project's Jira lacks that state) or "Done" on a
direct merge. Never post plans, descriptions, or progress comments to the
tracker.

!`${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/docs/jira-tools.md || /home/agent/.cursor/skills/_devflow-shared/bin/mdexec /home/agent/.cursor/skills/_devflow-shared/docs/jira-tools.md`
