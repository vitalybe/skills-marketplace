---
name: skill-marketplace-update
description: Create a new skill or edit an existing one inside the personal skills-marketplace repo, with the placement, versioning, registration, and commit handled correctly. Use whenever the user wants to "make a new skill", "add a skill", "create a skill for X", "edit/update/improve the <name> skill", "tweak the git-commit skill", "add a skill to workbench/devflow", or similar - anything that ends with a skill living in this marketplace. New skills default to the workbench plugin unless the user names another plugin, and edits to an existing skill stay in whatever plugin already owns it. Delegates the actual authoring and eval loop to skill-creator, then bumps the plugin version, registers new plugins in marketplace.json, and commits - so the change actually ships on /plugin update.
---

# skill-marketplace-update - author skills that ship

Create or edit a skill in the personal skills-marketplace repo and make sure it
actually reaches installed users. The hard part of a marketplace skill is not
the writing (skill-creator handles that) - it is getting the mechanics right:
putting the skill in the correct plugin, bumping that plugin's `version` so the
plugin cache invalidates, registering any new plugin in `marketplace.json`, and
committing it all together. This skill owns those mechanics and delegates the
authoring to `skill-creator`.

This skill runs **inline** - it edits repo files the user reviews and it
coordinates with `skill-creator`. Do not run it in a fork.

## 1. Locate the marketplace repo

The marketplace lives at `~/hq/skills-marketplace`. Verify it exists:

```bash
test -f ~/hq/skills-marketplace/.claude-plugin/marketplace.json && echo found
```

If it does not exist, **stop** and tell the user the marketplace repo isn't at
`~/hq/skills-marketplace` - do not continue or look elsewhere.

Read `.claude-plugin/marketplace.json` and list `plugins/*/` so you know which
plugins exist and their `source` paths.

## 2. Decide: new skill or edit, and which plugin

**Editing an existing skill.** Search every plugin for a matching skill
directory:

```bash
fd -t d -d 3 . plugins/*/skills | rg '/skills/[^/]+$'
```

The skill stays in whatever plugin already owns it - never move it. If the name
matches skills in more than one plugin, ask which one. Its directory name and
`name:` frontmatter field are fixed; keep them unchanged.

**Creating a new skill.** Route it by this rule, in order:

1. The user explicitly names a plugin ("add it to devflow", "in system-tools")
   -> that plugin.
2. Otherwise -> **workbench** (the default home for everyday skills).

If the chosen plugin does not exist yet, that is a **new plugin** - confirm with
the user, then in step 4 you'll create its `.claude-plugin/plugin.json` and add
it to `marketplace.json`.

The skill's directory is `plugins/<plugin>/skills/<skill-name>/` and the model
will invoke it as `<plugin>:<skill-name>`.

## 3. Delegate the authoring to skill-creator

Invoke the `skill-creator` skill (Skill tool: `skill-creator`) to do the actual
drafting, test cases, eval loop, and description optimization. Give it two hard
constraints so its output lands in the right place and doesn't pollute the repo:

- **Write the skill into** `plugins/<plugin>/skills/<skill-name>/` (the path you
  resolved in step 2). For an edit, that directory already exists.
- **Put the eval workspace OUTSIDE the repo** - use `$CLAUDE_JOB_DIR/tmp` if set,
  else `/tmp` - not as a sibling of the skill dir. The marketplace repo should
  only ever contain the finished skill, never `*-workspace/`, `iteration-*/`, or
  `evals/` scratch. If skill-creator created any such dirs inside `plugins/`,
  delete them before committing.

Follow skill-creator through to a version the user is happy with. Do not proceed
to the mechanics below until the user has approved the skill content.

## 4. After approval - version bump and registration

Only once the user approves the skill:

**Always** bump the owning plugin's version - this is what makes `/plugin update`
deliver the change. Claude Code keys its plugin cache on the `version` string;
an unchanged version means installed users get nothing.

- Edit `plugins/<plugin>/.claude-plugin/plugin.json`: bump `version` (semver -
  patch for a fix or small edit, minor for a new skill or feature).
- If the plugin's `description` no longer reflects the skills it contains
  (e.g. you added a meaningfully new capability), update it too - and mirror
  that into the plugin's `marketplace.json` entry.

**New plugin only** - if step 2 determined the plugin didn't exist:

1. Create `plugins/<plugin>/.claude-plugin/plugin.json`:
   ```json
   {
     "name": "<plugin>",
     "description": "What the plugin does",
     "version": "0.1.0",
     "author": { "name": "Vitaly Belman", "email": "vbelman@drivenets.com" }
   }
   ```
2. Add an entry to `.claude-plugin/marketplace.json` under `plugins`:
   ```json
   { "name": "<plugin>", "source": "./plugins/<plugin>", "description": "..." }
   ```

## 5. Commit

Commit the skill change and the version bump **together** so the two never drift
apart. Delegate to the repo's commit skill for message style and conventions:

Invoke `/workbench:git-commit` (or follow its conventions inline). The commit
should include the SKILL.md and any bundled resources, the `plugin.json` version
bump, and any `marketplace.json` change. Do not push - leave that to the user.

Follow the global rule for multiline commit messages: write the message to
`/tmp/claude-<epoch-ms>.md` with the Write tool and pass it with
`git commit -F`, never heredocs / `echo` / `$()`. End the message with the
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

## 6. Report

Tell the user plainly:

- Which plugin the skill lives in and whether it was created or edited.
- The version bump (`old -> new`) and any `marketplace.json` change.
- The commit created (hash + subject), and that nothing was pushed.
- How installed users pick it up:
  `/plugin marketplace update` then `/plugin update <plugin>`, then restart.

## Notes

- One skill = one plugin. Don't spread a skill's files across plugins.
- Never edit a skill in the read-only installed cache
  (`~/.claude/plugins/cache/...`); always work in the marketplace source repo.
- If the user is only tweaking wording in a skill that's never been installed
  anywhere, the version bump still applies - it's cheap and keeps the rule simple.
