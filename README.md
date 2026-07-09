# skills-marketplace

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) for distributing personal plugins and skills.

## Structure

```
.claude-plugin/
  marketplace.json    # marketplace catalog (name, owner, plugin list)
plugins/
  <plugin-name>/      # one directory per plugin
    .claude-plugin/
      plugin.json     # plugin manifest
    skills/           # skills, agents, commands, hooks, mcp, ...
```

The marketplace uses `metadata.pluginRoot: "./plugins"`, so plugin `source`
entries in `marketplace.json` are written relative to `plugins/` (e.g.
`"source": "my-plugin"` resolves to `./plugins/my-plugin`).

## Add a plugin

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json`:

   ```json
   {
     "name": "<plugin-name>",
     "description": "What the plugin does",
     "version": "0.1.0"
   }
   ```

2. Add the plugin's components (a `skills/<name>/SKILL.md`, agents, commands, hooks, etc.).

3. Register it in `.claude-plugin/marketplace.json` under `plugins`:

   ```json
   {
     "name": "<plugin-name>",
     "source": "<plugin-name>",
     "description": "What the plugin does"
   }
   ```

## Use it

```shell
# Validate the catalog
claude plugin validate .

# Add the marketplace (locally, by path, or from the repo)
/plugin marketplace add vitalybe/skills-marketplace

# Install a plugin
/plugin install <plugin-name>@vitalybe-skills
```
