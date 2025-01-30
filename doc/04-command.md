# Command

The plugin provides a `:MatchList` command that provides the following functions:

| Command           | Description |
| ----------------- | ----------- |
| `select`          | Shows the list of matches using `vim.ui.select`. Enter navigates to a match. |
| `attach`          | Attaches the plugin to the current buffer (enables matching). |
| `attach [groups]` | Same as `attach`, but also sets the given match group(s) for the current buffer. |
| `detach`          | Detaches the plugin from the current buffer. |
| `goto`            | Navigates to the match item under the cursor. |
| `first`           | Navigates to the first match item. |
| `last`            | Navigates to the last match item. |
| `next`            | Navigates to the next match item. |
| `next [types]`    | Navigates to the next match item with any of the given types. |
| `prev`            | Navigates to the previous match item. |
| `prev [types]`    | Navigates to the previous match item with any of the given types. |
| `unselect`        | Resets the current item selection. |
| `group`           | Shows the match groups using `vim.ui.select`. Enter switches the global match group. |
| `lgroup`          | Shows the match groups using `vim.ui.select`. Enter switches the (buffer-)local match group. |
| `group [names]`   | Sets the global match group(s) to the given group(s). |
| `lgroup [names]`  | Sets the (buffer-)local match group(s) to the given group(s). |
| `quickfix`        | Sends the matched items to the quickfix list. |

You have more control over the behavior of those commands, by using the
corresponding functions in the [Lua API](05-lua-api.md).
