# workbench

A personal grab-bag of everyday skills - the things invoked ad hoc at work and at home. One plugin instead of several single-skill ones, because there's no real install boundary between them: every machine gets all of it.

## Skills

Invoked as `/workbench:<name>`.

| Skill | Role |
|---|---|
| `git-commit` | Split uncommitted changes into logical, well-scoped commits via a forked subagent. |
| `git-commit-worktree` | Move the current work into a per-task worktree+branch (slugged to the task) and commit it there; no-ops to `git-commit` if already in a worktree. |
| `git-merge-local` | Merge the current branch into the default branch locally with `--no-ff`, including worktree cleanup. |
| `code-varlock` | Set up, extend, or debug a varlock env schema (validation, type generation, 1Password secrets). |
| `code-refactor-logging` | Refactor console/log output to structured logging standards (levels, colors, prefixes). |
| `skill-improve-session` | Review a session transcript to find and fix skill/doc/permission failures; bundles its own parser. |
| `browser-automation-explore-and-script` | Record a web flow with Playwright codegen, then translate it into a reliable replayable script. |
| `task-jira` | Read, create, edit, comment, transition, and search JIRA issues via the `tasks` CLI. |
| `task-obsidian` | List, open, and create personal to-dos in the Obsidian vault via `obsidian-tasks`. |
| `wiki` | Read from and write to the personal Obsidian knowledge vault (routes via the vault's own `CLAUDE.md`). |
| `schedule-work-meeting` | Schedule a meeting end-to-end: resolve attendees, find a free slot, open a prefilled Outlook invite. |
| `orchestrate-agents` | Manager-mode: spawn several subagents in their own worktrees, each taking one whole task end-to-end (via devflow), coordinating waves and serializing merges. |
| `task-herdr` | Delegate one task as a real `claude` agent in its own tracked herdr tab (visible, watchable) instead of an Agent-tool subagent. |
| `orchestrator-init` | Establish and keep current the session's live markdown status document, delegating monitoring to a subagent. |
| `orchestrator-drive` | Take over and drive a named orchestration task's in-pane gates to completion on the user's explicit request (marks it 🚗 in the tab and status doc). |
| `herdr-watch-pane` | Event-driven monitoring of a sibling herdr pane: a debounced background watcher re-invokes you only when the pane settles after a real change. |

## Prerequisites

The skill **files** ship with the plugin; their **runtimes, CLIs, and credentials** must exist in the environment where you run them. Each skill checks and reports what it needs.

| Skill | External dependency |
|---|---|
| `task-jira` | the `tasks` CLI (from the ai-enablement repo) on `PATH`; a JIRA API token in the macOS keychain (`jira-api-token`). |
| `task-obsidian` | the `obsidian-tasks` CLI (`~/hq/bin/obsidian-tasks`); `$OBSIDIAN_VAULT`. |
| `wiki` | an Obsidian vault at `$OBSIDIAN_VAULT` (default `~/obsidian`) with its own routing `CLAUDE.md`. |
| `schedule-work-meeting` | the Microsoft 365 + Slack MCP connectors; a browser logged into Outlook Web. |
| `skill-improve-session` | `node` + `pnpm` (installs the bundled parser deps on first run). |
| `browser-automation-explore-and-script` | `node`; Puppeteer/Playwright installed in the target project. |
| `code-varlock` | `pnpm`; `varlock` in the target project. |
| `task-herdr`, `orchestrator-init`, `herdr-watch-pane` | the `herdr` CLI, running inside herdr (`HERDR_ENV=1`); `python3` for `orchestrator-init`. These no-op outside herdr. |
| `orchestrate-agents` | `git`; the devflow plugin (`devflow@vitalybe-skills`) - each subagent runs its Code step. Works outside herdr. |

## Install

```shell
/plugin marketplace add vitalybe/skills-marketplace
/plugin install workbench@vitalybe-skills
```
