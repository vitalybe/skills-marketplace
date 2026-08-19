# skills-marketplace

A Claude Code plugin marketplace. See `README.md` for structure and how to add a plugin.

## Always bump the version when changing a plugin

Claude Code keys the plugin cache by the `version` string in each plugin's
`.claude-plugin/plugin.json`. If you change a plugin's files but leave `version`
unchanged, installed users get nothing on `/plugin update` - Claude Code sees
the same version and keeps the cached copy.

So, on **every** change to a plugin (bug fix, skill edit, tooling tweak):

1. Bump the plugin's `version` in `plugins/<name>/.claude-plugin/plugin.json`
   (semver - patch for fixes, minor for features).
2. Commit the change together with the version bump.

Users then pick it up with `/plugin marketplace update` followed by
`/plugin update <name>` (restart to apply).

## `plugins/devflow` is generated - do not edit it here

The source of truth is `~/git/ai-enablement-skills/plugins/aie-devflow`
(the DriveNets department repo). A `post-commit` / `post-merge` hook there runs
`scripts/sync-from-aie.sh`, which rsyncs `skills/`, `bin/`, `docs/` over this
copy with `--delete` and regenerates `plugins/devflow/.claude-plugin/plugin.json`
(version bumped automatically). Anything edited here is silently overwritten on
the department repo's next commit - make devflow changes there instead.
