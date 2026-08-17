---
name: _internal-step-design
description: Design the UX/UI for a development task in Claude Design. Use when requirements are gathered and the task changes screens, components, or user flows, or when the user invokes /devflow:_internal-step-design. Also trigger on phrases like "design the UI", "mock up the screens", "do the UX design". Internal - invoked by the orchestrator between the requirements and plan phases.
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

Designs live in Claude Design (claude.ai/design), reached through the
`/devflow:claude-design` skill. Never `WebFetch` a `claude.ai/design` URL
and never open it in a browser.

The target is a claude.ai/design project or file link, taken from the
user's request or from the plan's `## Design` section.

If no link is known, **stop** and end the gate turn with one question, `Q1`:
ask the user for the Claude Design project or file link to create or update
the design in. Don't guess a project and don't proceed without a link.

**Resume:** `## Design` holding a link but no recorded decisions - continue
from that link.

## Step: Design

1. Invoke `/devflow:claude-design` and read the target - the existing
   design if there is one, plus the design tokens it references.
2. Create or update the design so it covers the requirements' UX/UI scope,
   writing it back with the same skill.

## Step: Record the Design in the Plan

In the plan file's `## Design` section (add the heading between
`## Requirements Brief` and `## Plan` if it isn't there), record:

- The design link.
- The key UX/UI decisions taken - short bullets, one per decision.

## Wrap Up

1. Commit the plan file.
2. Report completion: the design link, the key decisions, and the commit.
