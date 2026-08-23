---
name: skill-marketplace-update
description: Create a new skill or edit an existing one inside the personal skills-marketplace repo, with the placement, versioning, registration, and commit handled correctly. Use whenever the user wants to "make a new skill", "add a skill", "create a skill for X", "edit/update/improve the <name> skill", "tweak the git-commit skill", "add a skill to workbench/devflow", or similar - anything that ends with a skill living in this marketplace. New skills default to the workbench plugin unless the user names another plugin, and edits to an existing skill stay in whatever plugin already owns it. Delegates the actual authoring and eval loop to skill-creator, then bumps the plugin version, registers new plugins in marketplace.json, and commits - so the change actually ships on /plugin update. devflow is the exception: it is generated here, so its skills are authored in the ai-enablement-skills department repo instead, where CI owns the version and the change lands through a PR.
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

## 0. Is it a devflow skill? Different repo, different mechanics

`plugins/devflow` here is **generated**. Its source of truth is the DriveNets
department repo `~/git/ai-enablement-skills`, bundle `plugins/aie-devflow`, and a
`post-commit` / `post-merge` hook there republishes it into this marketplace.
Anything you write into `~/hq/skills-marketplace/plugins/devflow` is silently
overwritten on that repo's next commit.

So if the skill being created or edited is a devflow skill - any of the flow
steps, `code-review`, `pr-review`, `claude-design`, `docs-update`,
`config-project`, `_internal-*`, or a new skill the user wants in devflow - skip
steps 1, 2, 4, 5 and 6 and follow **§7 The devflow route** instead. Step 3
(delegating to `skill-creator`) applies unchanged.

Everything else - workbench and any other plugin - continues below.

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

1. The user explicitly names a plugin ("add it to devflow", "in workbench")
   -> that plugin.
2. Otherwise -> **workbench** (the default home for everyday skills).

If the routing lands on **devflow**, stop here and go to §7 (see §0).

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

## 7. The devflow route

The department repo is a DriveNets Intelligence Marketplace bundle, so almost
every mechanic above is different there. Read its `AGENTS.md` and
`CONTRIBUTING.md` first - they are short and authoritative.

```bash
test -d ~/git/ai-enablement-skills/plugins/aie-devflow && echo found
```

If it isn't there, **stop** and tell the user - do not fall back to editing the
generated copy.

1. **Branch first.** `main` is protected and CI-gated; never commit on it.
2. **Write the skill** to `plugins/aie-devflow/skills/<skill-name>/` - step 3's
   `skill-creator` delegation is unchanged, including keeping the eval workspace
   outside the repo. Leave cross-references in whatever form the neighbouring
   files already use; the sync rewrites `/aie-devflow:` -> `/devflow:` on the way
   out and touches nothing else.
3. **Do not touch the version.** That repo has two manifests
   (`.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json`, identical
   `name`/`description`/`version`) and **CI owns both**:
   `.github/workflows/cd-release.yml` calls the hub's `version-bump.yml@v1` on
   push to `main`, derives the semver from the conventional commits, and tags
   `aie-devflow/v<version>`. A hand bump only collides with it. Edit
   `description` in both manifests only if the bundle's scope genuinely changed.
4. **There is no `marketplace.json` there.** The hub
   (`drivenets/intelligence-marketplace`) holds the pointer in `sources/aie.yaml`
   and aggregates by git-subdir, so a new *skill* in this bundle needs no
   registration at all. Only a brand-new *bundle* needs a hub PR.
5. **Commit with a conventional-commit subject** - it is what picks the bump
   level: `fix(devflow): …` for a patch, `feat(devflow): …` for a minor. Same
   `/tmp/claude-<epoch-ms>.md` + `git commit -F` rule and the same
   `Co-Authored-By` trailer as step 5. Update the bundle `README.md` in the same
   commit when the change adds or removes a skill (`AGENTS.md` requires it).
6. **Land it through a PR:** push the branch, `gh pr create`, let the three
   `marketplace-ci` checks (validate, security, evaluate) go green, then merge.
   You **cannot** approve it - GitHub rejects approving your own PR - so don't
   offer to; merge once the checks pass, or leave it to the user if a review is
   required.
7. **Don't publish it back by hand.** On merge the repo's `post-merge` hook runs
   `scripts/sync-from-aie.sh`, which rsyncs the bundle over
   `~/hq/skills-marketplace/plugins/devflow` and regenerates that copy's
   manifest with its own patch bump. The resulting dirty tree here is expected -
   the git-sweep cron commits it. Leave both alone; the two versions are
   independent by design.

Report as in step 6, but with what actually happened: the PR (number + merge
state), that CI bumped `aie-devflow` (or will, on merge), and that the
marketplace copy republishes itself via the hook.

## Notes

- One skill = one plugin. Don't spread a skill's files across plugins.
- Never edit a skill in the read-only installed cache
  (`~/.claude/plugins/cache/...`); always work in the marketplace source repo.
- If the user is only tweaking wording in a skill that's never been installed
  anywhere, the version bump still applies - it's cheap and keeps the rule simple.
