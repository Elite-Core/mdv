---
name: mdv
description: Open a markdown file in mdv, the native markdown viewer app installed on this Mac. Use it right after writing any .md file for the user (reports, handoffs, plans, notes, READMEs) and whenever they say "open it in mdv", "open it in the viewer", "show me the markdown", "render that", "pull that up", "let me read it". Also for reading an existing .md on disk.
---

# mdv — open markdown in the viewer app

mdv is a native macOS markdown viewer installed at `/Applications/mdv.app`. It renders a
`.md` file in a clean reader window, watches the file and re-renders on every save, shows
an outline and recent files in a sidebar, and opens additional files as tabs.

## Open a file

```bash
open -a mdv "/absolute/path/to/file.md"
```

Several paths in one command open as tabs in one window. No path opens a file picker.

## Rules

- Open the file once. The window live-reloads while you keep editing it; don't re-run `open`.
- After opening, tell the user it's open in mdv, in one line. Don't paste the file into chat.
- You cannot see the window. If the user reports a rendering problem, ask for a screenshot.
- Relative image paths and links to other `.md` files resolve inside the viewer.
- Supported: `.md`, `.markdown`, `.mdown`, `.mdx`, `.txt`.

## If mdv isn't installed

If `/Applications/mdv.app` does not exist, say so and fall back to the user's default
app (`open file.md`). Don't try to install mdv yourself.
