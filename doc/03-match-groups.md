# Match groups

```lua
opts = {
    groups = {
        default = {
            { [[\(error\|warning\|warn\|info\|debug\):\s*\(.*\)]], { "type", "message" } }
        },
        rust = {
            {
                { [[\(error\|warning\)[^:]*:\s*\(.*\)]], { "type", "message" } },
                { [[-->\s*\(.*\):\(\d\+\):\(\d\+\)]], { "file", "lnum", "col" } }
            },
        }
    }
}
```

The `groups` setting defines a map of _match groups_ that can be used to match
the output of various commands / tools. They can then be enabled, disabled or
switched through the `:MatchList group` and `:MatchList lgroup` commands (see
[commands](04-commands.md)).

Each group defines a list of _scanners_ that can match different output messages.
If one of the _scanners_ finds a match, it will produce a _match item_, that will
then be highlighted and made available for navigation.

_Match items_ are used to capture information about a match, such as the line
number or filenames involved etc. The default (recognized) field names are:

| name      | description |
| --------- | ----------- |
| `type`    | The type of the match (`error`, `warning`, `info`, `debug`, `hint`, ...) |
| `message` | The message for the match. |
| `file`    | The name of the file that triggered the error / warning etc. |
| `lnum`    | The line number for the error. |
| `col`     | The column number for the error. |

You can define your own fields, if you want to capture other information.

*Note*: you should almost always provide `message` when defining your own _scanners_.
Furthermore if you provide `file` and `lnum`, you can navigate from the match to
the error location directly.

## Scanner definitions

*Note*: you can run `:MatchList debug`, to open a debugger view, that will allow
you to easily test and experiment with scanner definitions.

### Regular expressions

This is probably the most straight-forward type of scanner. It is defined like
this:

```lua
{ [[error: .*]] }

-- Or more explicitly
{ regex = [[error: .*]] }
```

However this will not capture any data and isn't terribly useful by itself. In
this example, you'd likely want to capture the error message, using a named group.

### Named groups

You can pass a table as the second parameter to the scanner, which will define
names for any of the capture groups in the regular expressions. Any group named
this way will be stored in the _match item_ under that name. For example:

```lua
{ [[error: \(.*\)]], { "message" } }

-- Or more explicitly
{ regex = [[error: \(.*\)]], groups = { "message" } }
```

This will capture the error message and store it in the _match item_ under the
`message` key. You can also use multiple groups:

```lua
{ [[\(error\|warning\): \(.*\)]], { "type", "message" } }
```

This will also match warnings and capture the type of the message as well. Since
`type` is a recognized field (see the table above), it will influence how the
match is highlighted in the buffer.

### Lua match expressions

You can also use a match expression compatible with the `string.match()` function
instead of using a regular expression. The usage is very similar:

```lua
{ match = [[error: (.*)]], { "message" } }
{ match = [[error: (.*)]], groups = { "message" } }
```

## Lua LPeg grammars

For more complicated cases, LPeg could also be used as an alternative:

```lua
{ lpeg = lpeg.P("error: ") * lpeg.C(lpeg.P(1)^0), { "message" } }
```

Please refer to the LPeg documentation on how to specifiy the grammar. Use
`lpeg.C()` to capture parts of the expression and assign it to a group name.
Note that you may need to load lpeg using `local lpeg = require("lpeg")` in the
configuration.

## Lua functions

You can also use a Lua function, to match lines. For example:

```lua
{ function(line) return line:sub(1, 6) == "error:" end }

-- Or more explicitly
{ eval = function(line) return line:sub(1, 6) == "error:" end }
```

will match all lines that start with `"error:"`. If you want the match to return
any data, the function can return a table:

```lua
{ function(line)
    if line:sub(1, 6) == "error:" then
        return { message = line:sub(7) }
    end
end }
```

*Note*: the table around the function is optional here. If you don't need to
specify additional options, you can just use the function definition directly.

## Direct property values

Let's say you are matching an error and want to specify the `"type"` property
for the _match item_, but the input string does not contain the string `"error"`.
You can directly specify the value for `type` like this:

```lua
{ [[err: \(.*\)]], { "message", type = "error" } }
```

This works for any property.

## Priorities

If you have multiple _scanners_ that can match the same line, you can set a
priority, to destinguish between them. For example:

```lua
{ [[error: \(.*\)]],       { "message" }, priority = 0 },
{ [[fatal error: \(.*\)]], { "message" }, priority = 1 },
```

The default priority is 0.

## Multi-line matches

If you need to match multiple lines at once, you can specify multiple _scanner_
for successive lines like this:

```lua
{
    { [[\(error\|warning\).*:\s*\(.*\)]], { "type", "message" } },
    { [[-->\s*\(.*\):\(\d\+\):\(\d\+\)]], { "file", "lnum", "col" } },
}
```

The results produced by all _scanners_ are combined into a single _match item_.

*Note*: if you need to match a single regular expression for a line, without it
producing any output, you can just pass a single string for that line, instead
of using a table.

### Previous line data in lua functions

When specifying a lua function, the function will get the item data from previous
lines passed in as the second parameter. It should then extend that data and
return the extended data table.

```lua
{ [[\(error\|warning\).*:\s*\(.*\)]], { "type", "message" } },
function(line, data)
    if line:sub(1, 5) == "note:" then
        data["note"] = line:sub(6)
        return data
    end
end
```

### Continuation lines

Sometimes you may want to collect multiple lines of input into a single output
value. For example you may want to match a two-line error output:

```lua
{
    { [[error: \(.*\)]], { "message" } },
    { [[error: \(.*\)]], { "message" } },
}
```

In this case, the second match on `"message"` will overwrite the first one,
leaving you with the output of the second line only. You can add _flags_ to
the group name, to customize this behavior:

```lua
{
    { [[error: \(.*\)]], { "message" } },
    { [[error: \(.*\)]], { "+:message" } },
}
```

Specifying `"+:message"`, will append the new value to the existing `message`,
so that no data is lost. Note that you can also specify a separator character.
For example `"+,:message"` will comma-separate the data from the two lines.

## Filter functions

Sometimes you may want to do some post-processing on the data produced by the
match or have some higher-level filtering logic to figure out if there should
actually be a match.

You can specify a filter function for this. It will receive the item data that
has been produced by the match as a table and it can then return a new table
with the item data that should actually be used. This allows for doing more
computation on the match data.

The filter function can also return `nil`, to omit a match from the results.
For example:

```lua
{
    regex = [[error: \(.*\)]],
    groups = { "message" },
    filter = function(data)
        if string.len(data["message"]) >= 5 then
            return data
        end
    end
}
```

This will filter out all errors with messages shorter than 5 characters.
