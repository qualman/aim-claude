#!/usr/bin/env python3 -I
"""Copy AIM art, sounds and fonts from a local assets folder into the app's skin folder.

Nothing here is bundled with the app: you supply the assets folder yourself, laid out as

    <assets>/icons/<name>.png|gif    e.g. send.png, send-hover.png, signon-disabled.png
    <assets>/sounds/BuddyIn.wav, BuddyOut.wav, received.mp3, sent.mp3
    <assets>/fonts/*.woff2|woff|ttf|otf

    scripts/install-skin.py ~/Downloads/aim_assets

Icon names are what the app asks for; a "-hover" twin is shown while the pointer is over the
button. GIFs are converted to PNG. Anything missing falls back to an SF Symbol or text.
"""
import os, shutil, subprocess, sys

SKIN = os.path.expanduser("~/Library/Application Support/AIMClaude/skin")

# Icons the app uses. Each may also have <name>-hover (and the app asks for signon-disabled).
ICONS = ["signon-banner", "buddylist-banner", "screenname-label", "help", "setup", "signon",
         "signon-disabled", "buddylist-im", "add-small", "runner-small", "tree-open", "buddy-robot",
         "fmt-color", "fmt-background", "fmt-smaller", "fmt-normal", "fmt-bigger", "fmt-bold",
         "fmt-italic", "fmt-underline", "fmt-link", "fmt-image", "fmt-smiley",
         "warn", "block", "add-buddy", "get-info", "send"]

# <assets>/sounds/<file> -> skin name. These are the only sounds the app plays.
SOUNDS = {"BuddyIn.wav": "door-open.wav", "BuddyOut.wav": "door-close.wav",
          "received.mp3": "received.mp3", "sent.mp3": "sent.mp3"}
# Files earlier versions installed; removed so nothing stale is used.
RETIRED = ["im.wav", "welcome.wav", "goodbye.wav", "icons/im.png"]
FONT_EXTS = (".woff2", ".woff", ".ttf", ".otf")


def install_icon(src, dest):
    if src.lower().endswith(".png"):
        shutil.copy(src, dest)
    else:
        subprocess.run(["sips", "-s", "format", "png", src, "--out", dest], check=True, capture_output=True)


def main(root):
    icons_src = os.path.join(root, "icons")
    if not os.path.isdir(icons_src):
        sys.exit(f"no icons folder at {icons_src}")
    os.makedirs(os.path.join(SKIN, "icons"), exist_ok=True)
    os.makedirs(os.path.join(SKIN, "fonts"), exist_ok=True)

    available = {}
    for f in os.listdir(icons_src):
        stem, ext = os.path.splitext(f)
        if ext.lower() in (".png", ".gif") and os.path.isfile(os.path.join(icons_src, f)):
            if stem not in available or ext.lower() == ".png":
                available[stem] = os.path.join(icons_src, f)
    wanted = ICONS + [n + "-hover" for n in ICONS]
    installed = [n for n in wanted if n in available]
    for n in installed:
        install_icon(available[n], os.path.join(SKIN, "icons", n + ".png"))

    fonts_src = os.path.join(root, "fonts")
    fonts = sorted(f for f in os.listdir(fonts_src) if f.lower().endswith(FONT_EXTS)) if os.path.isdir(fonts_src) else []
    for f in fonts:
        shutil.copy(os.path.join(fonts_src, f), os.path.join(SKIN, "fonts", f))

    for name in RETIRED:
        if os.path.exists(os.path.join(SKIN, name)):
            os.remove(os.path.join(SKIN, name))
    sounds = os.path.join(root, "sounds")
    copied = []
    for src, dst in SOUNDS.items():
        path = os.path.join(sounds, src)
        if os.path.exists(path):
            shutil.copy(path, os.path.join(SKIN, dst))
            copied.append(dst + ("  (warning: only %d bytes, probably not playable)" % os.path.getsize(path)
                                 if os.path.getsize(path) < 100 else ""))

    hovers = sum(n.endswith("-hover") for n in installed)
    missing = [n for n in ICONS if n not in available]
    print(f"icons: {len(installed) - hovers}/{len(ICONS)} (+{hovers} hover)  fonts: {len(fonts)}  skin: {SKIN}")
    print("sounds:", *copied, sep="\n  ")
    if missing:
        print("missing (app will use fallbacks):", ", ".join(missing))


if __name__ == "__main__":
    main(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/aim_assets"))
