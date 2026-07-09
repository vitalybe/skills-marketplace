---
name: config-project
description: Configure per-project settings for the devflow workflow - task system and merge strategy. Writes to `project-config.toml` in the project root. Use when the user invokes `/devflow:config-project`, or when another devflow skill reports a missing required key.
---

# Project Config

Reads and updates `project-config.toml` in the project root. One key per question. Only prompt for keys that are missing, unless the user explicitly asks to reconfigure.

## Step: Load Current Config

<current-config>
!`cat project-config.toml 2>/dev/null || echo "[[No project-config.toml yet — will create one]]"`
</current-config>

If the user passed arguments naming specific keys to (re)configure, only touch those. Otherwise, prompt for every key below that is missing from the current config.

## Step: Prompt for Each Missing Key

For each missing key, use `AskUserQuestion` to ask the user. Header = key name. Questions below.

### `task-system` (string)

**Not prompted.** Always written as `task-system = "jira"`. The
dispatcher (`${CLAUDE_PLUGIN_ROOT}/bin/tasks`) and every devflow skill target JIRA;
no other backend is supported.

### `use-pull-requests` (bool)

**Question:** "How should this project merge completed tasks to main?"

- `true` — "Team — open a pull request, let someone review/merge on GitHub"
- `false` — "Solo — merge directly to main from the command line"

### (future keys go here — add new sections as needed)

## Step: Write the Config

Merge answers into `project-config.toml`. Preserve any existing keys the user didn't touch.

Write the final file using the Write tool (not heredoc). Format:

```toml
task-system = "jira"
use-pull-requests = true
# other keys...
```

## Wrap Up

Show the user the resulting `project-config.toml` contents. Done - no tracker comment, no next-phase call. This skill is a utility, not a flow phase.
