# devflow

A structured development-task workflow as a Claude Code plugin: **requirements → plan → code → close**, with sub-agent reviews and JIRA task-tracker integration. It bundles its own supporting tooling so the skills resolve everything from inside the installed plugin.

## Skills

Invoked as `/devflow:<name>`.

| Skill | Role |
|---|---|
| `start-flow` | Orchestrator entry point. Runs a dependency preflight, reads the current phase, and launches the next step. **Start here.** |
| `_internal-step-requirements` | Phase 1 - gather requirements, write the plan file. |
| `_internal-step-plan` | Phase 2 - draft and review the implementation plan. |
| `_internal-step-code` | Phase 3 - implement, test, code review. |
| `_internal-step-close` | Phase 4 - validate and merge/PR. |
| `code-review` | Standalone review of the working diff vs main (ad-hoc, outside the flow). |
| `pr-review` | Review a GitHub PR (`review PR #N`) against its plan, inside a worktree. |
| `config-project` | Configure per-project settings (`project-config.toml`). |
| `docs-update` | Create or update project documentation. |
| `_internal-review-aggregator` | Shared review engine - convenes the reviewer roster, fans out in parallel, dedups/triages. Used by the plan/code phases and the code-review/pr-review skills. |

Skills prefixed with `_internal-` are driven by the orchestrator and its phases, not meant for direct invocation.

## Layout

```
devflow/
├── skills/    # the skills above
├── docs/      # shared reference docs injected into the skills at runtime
│              #   (review-roster.md defines the reviewers; review-report-format.md the output)
└── bin/       # bundled tooling, referenced via ${CLAUDE_PLUGIN_ROOT}/bin
    ├── tasks                       # JIRA task dispatcher (Python, run via uv)
    ├── mdexec                      # markdown command-injector (Node)
    ├── worktree                    # git-worktree manager (bash, needs argc/jq)
    ├── git-merge-me-local          # local no-ff merge helper (bash)
    ├── integration-worktree-merge  # merge + worktree teardown (bash)
    ├── doctor                      # dependency checker
    └── _shared/script-utils.sh     # shared bash helpers
```

## Prerequisites

This plugin drives real tools; the **files** ship with the plugin, but their **runtimes and credentials** must exist in the environment where you run it. Run the checker any time:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/doctor
```

| Dependency | Needed by | Install |
|---|---|---|
| `uv` | `tasks` | https://docs.astral.sh/uv/ |
| `node` | `mdexec` | Node.js |
| `git` | merge/worktree helpers | git |
| `argc` | `worktree` | `brew install argc` (or `cargo install argc`) |
| `jq` | `worktree` | `brew install jq` |
| `jira` (jira-cli) | `tasks` (JIRA backend) | `brew install ankitpokhrel/jira-cli/jira-cli` |
| JIRA token | `tasks` | `JIRA_API_TOKEN` env var, or a macOS keychain item with service `jira-api-token` |

Each bundled script also validates its own dependencies at runtime and prints a helpful message if one is missing.

The target project also needs a `project-config.toml` (create it with `/devflow:config-project`).

## Install

```shell
/plugin marketplace add vitalybe/skills-marketplace
/plugin install devflow@vitalybe-skills
/devflow:start-flow
```
