# Configuration

These are the supported configuration values and their default settings:

```lua
opts = {
    -- Defines match groups. Groups can be used to group match definitions
    -- that are used in conjunction with each other. For example a match group
    -- may define how to match errors and warnings from a specific compiler.
    groups = {
        default = {
            -- The default group is active by default.
        },
        -- ...
    },

    -- Specifies how to open a split when navigating to the location mentioned
    -- in a matched error or warning message. Accepted values are: horizontal,
    -- vertical, h or v.
    split = "horizontal",

    -- Hook function that is called when attaching to a buffer.
    attach = function(buffer, tracker)
        vim.keymap.set("n", "<cr>", function()
            tracker:goto_below_cursor()
        end, { buffer = buffer })
    end,

    -- Hook function that is called when detaching from a buffer.
    detach = function(buffer)
        vim.keymap.del("n", "<cr>", { buffer = buffer })
    end,

    -- Hook function that can be used to customize the highlight extmark for
    -- a match. You can override this to change highlight colors / style etc.
    highlight = function(match)
        local type = match.data["type"] or "hint"

        local highlight = {
            error = "DiagnosticSignError",
            warning = "DiagnosticSignWarn",
            info = "DiagnosticSignInfo",
        }

        return {
            sign_text = string.upper(string.sub(type, 1, 1)),
            sign_hl_group = highlight[type] or "DiagnosticSignHint",
            line_hl_group = highlight[type] or "DiagnosticSignHint",
        }
    end,
}
```

Match groups can be defined as described in [match groups](03-match-groups.md).
