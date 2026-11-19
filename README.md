# AIM for Claude

A native macOS app that looks and feels like classic AOL Instant Messenger,
where every buddy is its own Claude conversation. Pick a screen name, hit
**Add Buddy**, and `xX_Claude_Xx` signs on.

- Each buddy is a separate, persistent Claude Code session, rooted in a
  folder you choose.
- Replies arrive whole. While Claude works, the chat window shows what it's
  doing ("Reading …", "Running: …").
- When Claude wants to run a tool that isn't already allowed, an Allow/Deny
  prompt pops up in that buddy's chat window. It goes through a small MCP
  server the app hosts on localhost.
- Buddy list, chats and screen name persist across launches.

No Electron and no webview: it's SwiftUI and AppKit built with Swift Package
Manager.

## Requirements

- macOS 26 or later, on Apple silicon
- Swift 6.2+ (Command Line Tools is enough; Xcode isn't required)
- The [`claude` CLI](https://docs.claude.com/en/docs/claude-code), installed
  and logged in. The app finds it through your login shell's `PATH`, or you
  can set the path in Preferences.

## Build and run

```sh
scripts/build-app.sh                                  # builds build/AIMClaude.app
ditto build/AIMClaude.app ~/Applications/AIMClaude.app
open ~/Applications/AIMClaude.app
```

A rebuild doesn't update the copy in `~/Applications`, so run `ditto` again
after each build.

## Tests

```sh
scripts/test.sh
```

The script points Swift Testing at its macro plugin, which Command Line Tools
doesn't put on the default search path. These tests are opt-in because they
call the real `claude` CLI and spend tokens:

```sh
AIM_LIVE=1 scripts/test.sh
```

## Skin (art, sounds, fonts)

This repo includes no AOL artwork or sounds. If you have your own copies,
install them into the app's skin folder:

```sh
scripts/install-skin.py ~/path/to/aim_assets
```

They're copied to `~/Library/Application Support/AIMClaude/skin`, where
images are matched by content hash. Anything missing falls back to an
SF Symbol or plain text, and a missing sound simply doesn't play.

## Where data lives

`~/Library/Application Support/AIMClaude/` holds `state.json` (screen name,
buddies, chat history) and the skin folder. Set `AIM_SUPPORT_DIR` to keep
`state.json` somewhere else, for example a throwaway profile. The skin folder
stays where it is.

## Layout

- `Sources/AIMCore`: the testable core, covering models, state storage,
  the `claude` process channel, the stream-json parser, the permission
  broker and the MCP server.
- `Sources/AIMClaude`: the app itself, with the SwiftUI views, the window
  manager, sounds and the AIM look.
- `Tests/AIMCoreTests`: Swift Testing suites and recorded CLI fixtures.
