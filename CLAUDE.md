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
