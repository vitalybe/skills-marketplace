---
name: _internal-step-design
description: Design the UX/UI for a development task on the Paper canvas, or Claude Design. Use when requirements are gathered and the task changes screens, components, or user flows, or when the user invokes /devflow:_internal-step-design. Also trigger on phrases like "design the UI", "mock up the screens", "do the UX design". Internal - invoked by the orchestrator between the requirements and plan phases.
---

# UX/UI Design

User input goes through gates - see **Gates** in the common instructions
below.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Step: Read the Requirements

Read the plan file at `<plan-path>` - `## Requirements Brief` plus the full
`## Requirements` - and pull out the UX/UI scope: the screens, components,
and user flows this task adds or changes.

## Step: Resolve the Design Target

**Paper when connected, Claude Design otherwise.** Never `WebFetch` a design
URL or open one in a browser - both sit behind an auth wall. If `## Design`
names a target already, continue in that one.

Probe: `ToolSearch` `+paper canvas artboard` - Paper is there if
`mcp__paper__*` returns.

**Paper.** One file per task, named after the worktree (basename of
`git rev-parse --show-toplevel`), so parallel tasks never collide.
`list_files` to reuse it - it sees only open and recent files, so a miss means
create - else `create_file`. Then `open_file` on the id, and pass `fileId`
explicitly after - "most recently opened" is not yours. No gate: derived name.

**Claude Design.** A claude.ai/design link from the request or the plan's
`## Design`, via `/devflow:claude-design`. No link: **stop**, end the gate turn
with one question, `Q1`, asking for it. Don't guess a project.

## Step: Design

1. Read what is there plus the design tokens it references, so you resolve
   them rather than guess. Paper: `get_guide({ topic:
   "paper-mcp-instructions" })` **first**, required before any other Paper
   tool, then `get_basic_info` and `get_tokens`. Claude Design: invoke
   `/devflow:claude-design`.
2. Create or update the design to cover the UX/UI scope, writing it back the
   same way. On Paper, one artboard per screen or state, then
   `finish_working_on_nodes`.

## Step: Record the Design in the Plan

In the plan file's `## Design` section (add the heading between
`## Requirements Brief` and `## Plan` if it isn't there), record:

- The target: the Paper file name (and its url), or the Claude Design link.
- The key UX/UI decisions taken - short bullets, one per decision.

## Wrap Up

1. Commit the plan file.
2. Report completion: the design target, the key decisions, and the commit.
