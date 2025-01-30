# Installation

Setup example for lazy.nvim:

```lua
return {
    "ollbx/match-list.nvim",
    cmd = "MatchList",
    opts = {
        groups = {
            default = {
                { [[\(error\|warning\|warn\|info\|debug\):\s*\(.*\)]], { "type", "message" } }
            },
            rust = {
                {
                    { [[\(error\|warning\)[^:]*:\s*\(.*\)]], { "type", "message" } },
                    { [[-->\s*\(.*\):\(\d\+\):\(\d\+\)]], { "file", "lnum", "col" } }
                }
            }
        },
    },
    keys = {
        { "[m",         "<cmd>MatchList prev<cr>", desc = "Previous match" },
        { "]m",         "<cmd>MatchList next<cr>", desc = "Next match" },
        { "[w",         "<cmd>MatchList prev warning warn<cr>", desc = "Previous warning" },
        { "]w",         "<cmd>MatchList next warning warn<cr>", desc = "Next warning" },
        { "[e",         "<cmd>MatchList prev error fatal<cr>", desc = "Previous error" },
        { "]e",         "<cmd>MatchList next error fatal<cr>", desc = "Next error" },
        { "<leader>ma", "<cmd>MatchList attach<cr>", desc = "Attach to buffer" },
        { "<leader>md", "<cmd>MatchList detach<cr>", desc = "Detach from buffer" },
        { "<leader>mg", "<cmd>MatchList group<cr>", desc = "Select match group" },
    }
}
```

- You can find an overview of the configuration options under [setup](02-configuration.md).
- For the `:MatchList` command, please refer to [command](04-command.md).
- For the Lua API see [API](05-lua-api.md).
