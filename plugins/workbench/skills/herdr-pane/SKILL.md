---
name: herdr-pane
description: "Pull the current content of a herdr pane into context. Takes a pane id as the first argument, optionally followed by what to do with it (e.g. /workbench:herdr-pane w1P:pBY check the build) and injects the pane's recent output at invocation time. Use when the user says 'look at pane X', 'see what's in pane X', 'read pane X', or references a herdr pane and wants you to act on what it shows (errors, logs, agent output). One-shot snapshot; for ongoing monitoring use herdr-watch-pane. Requires HERDR_ENV=1."
argument-hint: "<pane-id> [what to do with it]"
allowed-tools: Bash(herdr pane read:*)
---

# herdr-pane

Content of herdr pane `$0` (last 200 lines, soft-wraps joined):

!`herdr pane read "$0" --source recent-unwrapped --lines 200 2>&1`

Full arguments (pane id first, then any instruction from the user): $ARGUMENTS

The output above is a snapshot taken when this skill was invoked. Use it to do what the user asked about this pane. If it shows an error such as a missing or unknown pane, run `herdr pane list` and ask which pane they meant.

Need more or fresher output, or a different view? Run `herdr pane read <pane> --source visible|recent|recent-unwrapped|detection --lines N` yourself. See the `herdr` skill for the rest of the CLI, and `herdr-watch-pane` to react to changes over time.
