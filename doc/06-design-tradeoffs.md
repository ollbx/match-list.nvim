# Design Tradeoffs

Unfortunately keeping track of a list of matches is tricky for the terminal buffer,
as soon as the scrollback buffer runs out. In that case, the line numbers of the
match items will change every time there is a new output line, making it hard to
locate the match item during navigation.

Tracking changes to the buffer and updating match item positions is hard to do.
I tried using extmarks, because they usually "move around" with the text that they
are marking, but that also does not work for the terminal buffer.

So in the end I decided to implement a tradeoff for this:

- The plugin will only search and highlight matches in the part of the buffer that
  is currently visible. Everything else is ignored.
- This allows for a fast scan and update that can run on content updates / scroll
  changes etc.
- When a navigation action (go to next etc.) is triggered for the first time, the
  whole buffer content is scanned and a comprehensive list of matches is built for
  the navigation. This may take a bit more time, but I felt that the scan is fast
  enough for this not to be an issue.
- The results of the full scan are cached, so that follow-up navigation will not
  need to rebuild the match list. However any change to the buffer will reset that
  cache.
- This works well for the normal build use case:
  - During the build the buffer will change frequently, but the user won't navigate.
  - After the build the user navigates, but the buffer contents are mostly static.
