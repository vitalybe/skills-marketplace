---
name: _devflow-shared
description: Not an invocable skill. Carrier directory holding the aie-devflow bundle's shared tooling (bin/) and reference docs (docs/) so they ship with the bundle wherever it is installed. Never invoke this; nothing here responds to a request. Other aie-devflow skills reference its files by path.
---

# Not a skill

This directory is not an invocable skill. It exists so the `aie-devflow`
bundle's shared files travel with the bundle in every environment:

- `bin/` - the bundle's tooling (`mdexec`, `tasks`, `doctor`, `project-config`,
  `worktree-kind`, `worktree-remove`, `git-merge-me-local`).
- `docs/` - the shared reference docs the devflow skills embed.

It lives under `skills/` rather than beside it because the marketplace
provisioner only fetches `<bundle>/skills` and only installs directories that
contain a `SKILL.md`. Anything a `SKILL.md` references must therefore live in a
`skills/<name>/` directory, or it will not exist at runtime.

## How other skills reference these files

Two forms, because two different things do the resolving.

**Shell commands** - anything a skill injects as a `!`...`` block, or hands the
agent to run - name both roots, joined by `||`:

```
${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/doctor || /home/agent/.cursor/skills/_devflow-shared/bin/doctor
```

Claude Code replaces the bare `${CLAUDE_PLUGIN_ROOT}` token with a real path
before it parses the command, and it refuses any injected command whose text
still holds an unresolved shell expansion - so a single `${VAR:-default}` cannot
carry both roots. In an agent pod nothing is substituted, the first path does
not exist, the shell moves on, and the second arm runs. Whichever arm runs, a
non-zero exit from the surviving one aborts the whole skill load, which is why
the wrappers in `bin/` print their errors and exit 0.

**Reference docs** the agent reads rather than executes are written relative to
the skills root - `_devflow-shared/docs/plan-format.md` - since no shell is
involved and the skills sit as siblings in both environments.
