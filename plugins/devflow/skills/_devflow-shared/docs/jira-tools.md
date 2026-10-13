Reads and status changes go through MCP tools, not a CLI.

| Operation         | Tool                              |
| ----------------- | --------------------------------- |
| Read an issue     | `atlassian_jira_get_issue`        |
| List transitions  | `atlassian_jira_get_transitions`  |
| Change status     | `atlassian_jira_transition_issue` |

The harness may namespace these - `mcp__dn-mcp-server__atlassian_jira_get_issue`
if the server was added by hand, `mcp__plugin_aie-devflow_dn-mcp-server__...`
when it comes from this plugin, bare in Cursor. Use whichever form this session
exposes.

**Changing status:** call `get_transitions` for the issue, pick the transition
whose target matches, then `transition_issue`. JIRA names "In Review" as
**Review**; the other states match their canonical name. If nothing matches,
warn and carry on - a status write never blocks the flow.
