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
- Away messages: MyAIM → Away Message → New Message… opens AIM's editor, with
  working bold, italic, underline, size, color, link, picture and smiley buttons.
  Tick "Save for later use" to keep the message in the Away Message menu and the
  label dropdown. While you're away your buddies keep working and nothing is sent
  to Claude. The away window counts the replies that arrive and lists each buddy,
  how many messages it sent and when it last sent one, sortable by any of those
  columns. You can also hide chat windows or mute sounds until you click I'm Back.
- Buddy list, chats, screen name and saved away messages persist across launches.

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

The app icon is an original running figure drawn in code by
`scripts/make-icon.swift`. Run `swift scripts/make-icon.swift` to regenerate
`Resources/AppIcon.icns` after changing it.

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

This repo includes no AOL artwork or sounds. If you have your own copies, name them
to match the tables below and lay them out like this:

```
aim_assets/
  icons/   <name>.png or .gif
  sounds/  <name>.wav, .mp3, .aiff or .m4a
  fonts/   any .woff2, .woff, .ttf or .otf
```

Then install them:

```sh
scripts/install-skin.py ~/path/to/aim_assets
```

The script copies the three folders unchanged into
`~/Library/Application Support/AIMClaude/skin`, replacing the previous skin, and lists
any names below that it couldn't find. A missing icon falls back to an SF Symbol or
plain text, and a missing sound simply doesn't play.

Any button icon can also have two optional variants:
- `<name>-hover`: shown while the pointer is over the button, as AIM did.
- `<name>-disabled`: shown while the button can't be used. Without it, the normal image
  is drawn faded.

### Icons (`icons/`)

| File | Where it appears |
|---|---|
| `logo` | The running-man logo: the Sign On window when there's no `signon-banner`, and the Buddy List when there's no `buddylist-banner` |
| `signon-banner` | The large banner at the top of the Sign On window |
| `screenname-label` | The "ScreenName" label above the screen-name field |
| `help` | Sign On window: Help button (opens About) |
| `setup` | Sign On window: Setup button (opens Preferences) |
| `signon` | Sign On window: Sign On button |
| `signon-disabled` | The Sign On button while the screen name is empty |
| `buddylist-banner` | The banner at the top of the Buddy List |
| `tree-open` | The open-group arrow in the Buddy List (turned sideways when the group is closed) |
| `buddylist-im` | Buddy List toolbar: send an IM to the selected buddy |
| `add-small` | Buddy List toolbar: Add Buddy |
| `buddylist-remove` | Buddy List toolbar: Remove Buddy (ends the selected buddy's Claude session and deletes its chat history) |
| `buddylist-info` | Buddy List toolbar: Get Info on the selected buddy |
| `buddy-robot` | The buddy icon on the left of a chat window |
| `fmt-color`, `fmt-background` | Chat formatting bar: text color, background color |
| `fmt-smaller`, `fmt-normal`, `fmt-bigger` | Chat formatting bar: text size |
| `fmt-bold`, `fmt-italic`, `fmt-underline` | Chat formatting bar: text style |
| `fmt-link`, `fmt-image`, `fmt-smiley` | Chat formatting bar: link, picture, smiley |
| `warn` | Chat window: Warn button |
| `block` | Chat window: Block button |
| `add-buddy` | Chat window: Add Buddy button |
| `get-info` | Chat window: Get Info button |
| `send` | Chat window: Send button |

In the IM window the formatting bar is decorative, because Claude reads plain text. In the
away message editor it works.

Smileys for the editor's smiley button come from `icons/smileys/<face>-19.png`, for
example `smile-19.png` or `wink-19.png`. Without them, the button offers emoji.

### Sounds (`sounds/`)

| File | Plays when |
|---|---|
| `buddy-in` | You sign on, or a buddy is added (the door opening) |
| `buddy-out` | You sign off (the door closing) |
| `received` | A buddy's reply arrives, or a buddy asks permission to use a tool |
| `sent` | You send a message |

### Fonts (`fonts/`)

Every font in this folder is loaded when the app starts. The app looks for the family
`MS Sans Serif` (PostScript name `MS-Sans-Serif`) and uses Verdana if that isn't
there.

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
