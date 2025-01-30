# match-list.nvim

[![Tests](https://github.com/ollbx/match-list.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ollbx/match-list.nvim/actions/workflows/ci.yml)

This Neovim plugin is intended to automatically match, highlight and record
error and warning messages (or anything that can be matched) in any buffer
that you attach it to. It will also provide functions to navigate the list of
matches and also the locations that the matched errors and warnings refer to.

The main intended use case is for attaching to a terminal buffer and then
running a build command in that buffer. After the build has completed, the
plugin allows easy navigation of any build errors etc.

## Functionality

- Simple and straight-forward. Focus on one functionality.
- Provides different ways to match output, such as:
  - Regular expressions
  - Lua match expressions
  - Lua LPeg grammars
  - Arbitrary lua functions
- Allows multi-line matches
- Match expression debugger tool
- Highlighting of matches in real-time
- Match navigation
  - Go to first, last
  - Go to next, previous
  - Allows for filtering during navigation (errors only etc.)
- Provides hooks to customize a lot of functionality.

## Documentation

See [installation](doc/01-installation.md) to get started.

## TODO

- [ ] Allow for specifying a priority between matches.
- [ ] Allow matching a variable amount of input lines.
