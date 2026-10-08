# mdv

A clean, native markdown viewer for the Mac. One window per file, tabs, live reload, no dependencies to install.

## Open a file

- Finder: right-click a `.md` → Open With → mdv (or drop it on the Dock icon).
- Terminal: `open -a mdv notes.md`, or the wrapper in this folder: `mdv notes.md`.
- Claude: writes you a `.md` and opens it here for you.

## What you get

- **Live reload** — the green dot in the toolbar means it's watching. Save the file, the view updates, your scroll position stays.
- **Outline** — every heading in the sidebar, highlighted as you scroll. Toggle with the toolbar button or ⌃⌘S.
- **Recent** — your last files in the sidebar and in File → Open Recent.
- **Tabs** — a second file opens as a tab in the same window.
- **Find** — ⌘F, Enter for next, Shift-Enter for previous.
- **Light / dark** — follows the system; override from the toolbar or View → Appearance.
- **Print** — ⌘P, sidebar drops out. Zoom with ⌘= / ⌘- / ⌘0.
- Relative images render, and links to other `.md` files open in a new tab.

## Rendering check

> A blockquote. Keep the bold colors, change nothing else.

| Column | Type | Notes |
| --- | --- | --- |
| `order_id` | text | primary key |
| `status` | enum | `open`, `held`, `shipped` |
| `updated_at` | timestamptz | set by trigger |

```js
export async function ping(ms = 400) {
  const r = await fetch(`${BASE}/api/ping`, { signal: AbortSignal.timeout(ms) });
  return r.ok ? r.json() : null;
}
```

- [x] app builds
- [x] file renders
- [ ] Noah says it looks clean

Inline `code`, **bold**, *italic*, ~~struck~~, and a [link](https://example.com).

### Smaller heading

Press <kbd>⌘</kbd> <kbd>F</kbd> to find, <kbd>⌘</kbd> <kbd>P</kbd> to print.

---

## Share it with a friend

1. `./build.sh --dist` makes `build/mdv.zip`. Send that.
2. They unzip it and drag mdv.app to Applications. First time only: **right-click → Open**, since it isn't notarized and macOS warns once.
3. On first launch, if they have Claude Code, mdv offers to install the Claude skill. Later: **mdv → Install Claude Code Skill…**, or `mdv.app/Contents/MacOS/mdv --install-skill`.

After that their Claude opens markdown in mdv the same way yours does. The skill lives inside the app, so updating the app updates the skill.

### Skip the right-click warning (notarize, one-time setup)

The build signs with the Developer ID cert in your keychain. To also notarize, store an
app-specific password once (password goes straight to your keychain, nothing is written to disk here):

```bash
xcrun notarytool store-credentials mdv --apple-id "YOUR_APPLE_ID" --team-id BS57FWH4AR
```

Make the app-specific password at account.apple.com → Sign-In and Security → App-Specific Passwords.
From then on `./build.sh --dist` notarizes and staples automatically, and friends just double-click.

## Updates

Installed copies check the release feed once a day and from **mdv → Check for Updates…**. An update downloads the notarized zip, verifies the new app is signed by the same Team ID, swaps it into place and relaunches with your documents open. Nothing is replaced if the signature doesn't match.

To ship one:

```bash
./release.sh 1.1 "What changed"
```

That builds, signs, notarizes, bumps the build number, tags, pushes, and publishes a GitHub release carrying `mdv.zip` and `latest.json`. Repos are set in `release.conf`; the releases repo must be public.

## Rebuild

```bash
./build.sh
```

Compiles `Sources/*.swift` with the Xcode toolchain, bundles `Resources/viewer.html`, draws the icon, and installs to `/Applications/mdv.app`. The markdown parser and code highlighter are bundled, so it works offline.

`mdv.mjs` is the older browser-pane version (`mdv --pane file.md`); it still works but the app is the main path.
