# Lua API

```lua
local M = require("match-list")
```

## Attach or detach

```lua
-- Attaches to the given buffer, using the given match group or list of match
-- groups. If `buffer` is `nil`, the current buffer is used. If `group` is `nil`,
-- the default group is used.
M.attach(buffer, group)

-- Detaches from the given buffer. If `buffer` is `nil`, the current buffer is used.
M.detach(buffer)
```

## Match group selection

```lua
-- Returns the list of groups that are set up in the configuration.
M.get_available_groups()

-- Returns the list of currently active match groups for the given buffer or
-- globally (if `buffer` is `nil`).
M.get_groups(buffer)

-- Sets the match group or list of match groups to use in the specified buffer or
-- globally (if `buffer` is `nil`). Resets to the default group, if `group` is `nil`.
M.set_group(group, buffer)

-- Shows a UI window for selecting the match group for the specified buffer or
-- globally, if `buffer` is `nil`.
M.select_group(buffer)
```

## Querying matches

```lua
-- Returns the currently selected match item.
M.get_current()

-- Returns the index of the currently selected item.
M.get_current_index()

-- Returns the list of all known matches.
M.get_matches()

-- Returns the list of all matches visible on screen (fast).
M.get_visible_matches()
```

## Navigating matches

```lua
-- Directly navigates to the given match (taken from `get_matches`).
M.goto_match(match, goto_config)

M.first(goto_config) -- Navigates to the first item.
M.last(goto_config)  -- Navigates to the last item.
M.next(goto_config)  -- Navigates to the next item.
M.prev(goto_config)  -- Navigates to the previous item.

-- Resets the currently selected item.
M.unselect()
```

`goto_config` is either `nil` or a table:

```lua
local goto_config = {
    -- Filter function that can be used to select a subset of the match items
    -- (such as errors only). Return `true` for any match item that should be
    -- considered.
    filter = function(match)
        return match.data["type"] == "error"
    end,

    -- Can be used to override the information printed as a notification on
    -- navigation. If no more items are found, the function is called with
    -- `match` being `nil`. The default implementation calls `vim.notify`.
    notify = function(match, index, total)
        -- ...
    end,

    -- Controls where the focus ends up after navigation. "file" will focus
    -- on the file navigated to (if provided by the match item). "match" will
    -- focus on the match item itself (the error / warning message). `nil` will
    -- not change the focus at all.
    focus = "file",

    -- Specifies the window to open the target file in. If 0, a window will be
    -- automatically selected. If `nil`, the target file will not be opened.
    -- Any other integer directly specifies a window ID.
    file_window = 0,

    -- If automatic selection can not find a window, `file_open` is called to
    -- create a new window for showing the file.
    file_open = function(match)
        return vim.api.nvim_open_win(0, false, { split = "above" })
    end,

    -- Loads the file specified by the match into the current buffer. You can
    -- implement more complex logic to locate the file here.
    file_load = function(match)
        local file = match.data["file"]

        if vim.fn.filereadable(file) == 1 then
            vim.cmd("silent edit " .. file)
            return true
        end
    end,

    -- Specifies the window to open the match in. If 0, a window will be
    -- automatically selected. If `nil`, the match will not be opened. Any other
    -- integer directly specifies a window ID.
    match_window = 0,

    -- If automatic selection can not find a window, `match_open` is called to
    -- create a new window for showing the file.
    match_open = function()
        return vim.api.nvim_open_win(0, false, { split = "below" })
    end,
}
```

```lua
-- Opens a UI window for selecting a match to navigate to.
M.select(sel_config)
```

`sel_config` is either `nil` or a table:

```lua
local sel_config = {
    -- All the options from `goto_config` and also:

    -- Specifies how a match should be formatted in the selection list.
    format = function(match)
        return match.data["message"]
    end
}
```

## Utility functions

```lua
-- Opens the debug UI.
M.debug()

-- Runs some matching benchmarks.
M.bench()

-- Sends the match items to the quickfix list.
M.send_to_quickfix(qf_config)
```

`qf_config` in `send_to_quickfix` is either `nil` or a table:

```lua
local qf_config = {
    -- Converts the match item into a quickfix item. See `setqflist()` for
    -- the quickfix item parameters.
    convert = function(match)
        return { --[[ ... ]] }
    end,

    -- `true` to open the quickfix after it was populated.
    open = true,
}
```
