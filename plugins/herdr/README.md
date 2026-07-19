# herdr

Multi-agent orchestration skills for the [herdr](https://github.com/) terminal environment - running a multi-task effort as tracked tabs and parallel subagents, keeping a live status document, and reacting to sibling panes event-driven.

## Skills

Invoked as `/herdr:<name>`.

| Skill | Role |
|---|---|
| `orchestrate-agents` | Manager-mode: spawn several subagents in their own worktrees, each taking one whole task end-to-end (via devflow), coordinate dependency waves, and serialize merges. |
| `task-herdr` | Delegate one task as a real `claude` agent in its own tracked herdr tab (visible, watchable) instead of an Agent-tool subagent. |
| `orchestrator-init` | Establish and keep current the session's live markdown **status document**, delegating monitoring to a subagent so noise stays out of your context. |
| `herdr-watch-pane` | Event-driven monitoring of a sibling herdr pane: a debounced background watcher re-invokes you only when the pane settles after a real change. |

## Prerequisites

| Dependency | Needed by | Notes |
|---|---|---|
| `herdr` CLI | `task-herdr`, `orchestrator-init`, `herdr-watch-pane` | These skills require running inside herdr (`HERDR_ENV=1`). |
| `git` | `orchestrate-agents`, `task-herdr` | Worktree-per-task model. |
| `python3` | `orchestrator-init` | The child-tracker script (`track-children.py`). |
| devflow plugin | `orchestrate-agents` | Each subagent runs the devflow Code step. Install `devflow@vitalybe-skills`. |

`orchestrate-agents` is the only skill here that also works **outside** herdr - it drives plain Agent-tool subagents. The other three control herdr panes/tabs directly and no-op without `HERDR_ENV=1`.

## Install

```shell
/plugin marketplace add vitalybe/skills-marketplace
/plugin install herdr@vitalybe-skills
```
