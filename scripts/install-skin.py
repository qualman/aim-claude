#!/usr/bin/env python3 -I
"""Copy your AIM art, sounds and fonts into the app's skin folder.

Nothing here is bundled with the app. Name your files to match what the app looks for
(lists below) and lay them out as

    <assets>/icons/<name>.png|gif           e.g. send.png, send-hover.png, logo.png
    <assets>/sounds/<cue>.wav|mp3|aiff|m4a  buddy-in, buddy-out, received, sent
    <assets>/fonts/*.woff2|woff|ttf|otf

    scripts/install-skin.py ~/Downloads/aim_assets

The three folders are copied as they are, replacing the previous skin. A "<name>-hover"
image is shown while the pointer is over that button. Anything missing falls back to an
SF Symbol or text; a missing sound doesn't play.
"""
import os, shutil, sys

SKIN = os.path.expanduser("~/Library/Application Support/AIMClaude/skin")
FOLDERS = ["icons", "sounds", "fonts"]

# Names the app asks for (the README has a table of where each appears). Buttons may also
# have "-hover" and "-disabled" variants.
ICONS = ["logo", "signon-banner", "buddylist-banner", "screenname-label", "help", "setup", "signon",
         "signon-disabled", "buddylist-im", "add-small", "buddylist-remove", "buddylist-info", "tree-open", "buddy-robot",
         "fmt-color", "fmt-background", "fmt-smaller", "fmt-normal", "fmt-bigger", "fmt-bold",
         "fmt-italic", "fmt-underline", "fmt-link", "fmt-image", "fmt-smiley",
         "warn", "block", "add-buddy", "get-info", "send"]
SOUNDS = ["buddy-in", "buddy-out", "received", "sent"]
IMAGE_TYPES = (".png", ".gif")
SOUND_TYPES = (".wav", ".mp3", ".aiff", ".m4a")


def stems(folder, types):
    if not os.path.isdir(folder):
        return set()
    return {os.path.splitext(f)[0] for f in os.listdir(folder) if f.lower().endswith(types)}


def main(root):
    if not any(os.path.isdir(os.path.join(root, f)) for f in FOLDERS):
        sys.exit(f"no icons, sounds or fonts folder in {root}")
    # Replace the whole skin so files from older layouts or removed assets don't linger.
    if os.path.isdir(SKIN):
        shutil.rmtree(SKIN)
    os.makedirs(SKIN)
    ignore = shutil.ignore_patterns(".DS_Store")
    for f in FOLDERS:
        src = os.path.join(root, f)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(SKIN, f), ignore=ignore)

    icons = stems(os.path.join(SKIN, "icons"), IMAGE_TYPES)
    sounds = stems(os.path.join(SKIN, "sounds"), SOUND_TYPES)
    hovers = [n for n in ICONS if n + "-hover" in icons]
    fonts = os.listdir(os.path.join(SKIN, "fonts")) if os.path.isdir(os.path.join(SKIN, "fonts")) else []
    print(f"skin: {SKIN}")
    print(f"icons: {len([n for n in ICONS if n in icons])}/{len(ICONS)} (+{len(hovers)} hover)  "
          f"sounds: {len([s for s in SOUNDS if s in sounds])}/{len(SOUNDS)}  fonts: {len(fonts)}")
    missing = [n for n in ICONS if n not in icons] + [f"sounds/{s}" for s in SOUNDS if s not in sounds]
    if missing:
        print("missing (fallbacks used):", ", ".join(missing))


if __name__ == "__main__":
    main(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/aim_assets"))
