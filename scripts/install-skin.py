#!/usr/bin/env python3 -I
"""Copy AIM art, sounds and fonts from a local assets folder into the app's skin folder.

Nothing here is bundled with the app: you supply the assets folder yourself. Images are
picked out of saved AIM Rewind web archives by content hash, so names don't matter.

    scripts/install-skin.py ~/Downloads/aim_assets
"""
import hashlib, os, plistlib, shutil, subprocess, sys

SKIN = os.path.expanduser("~/Library/Application Support/AIMClaude/skin")

# sha1 prefix of the image bytes -> skin name
ICONS = {
    "c2221fe1": "signon-banner",
    "39374ee0": "buddylist-banner",
    "2e780599": "screenname-label",
    "26b86f56": "help",
    "f5d111f3": "setup",
    "d78a4f21": "signon",
    "3d89964c": "signon-disabled",
    "2103deef": "im",
    "78befa92": "add-small",
    "ec5fff09": "runner-small",
    "5183974b": "tree-open",
    "513f41bc": "buddy-robot",
    "bc7ffdab": "fmt-color",
    "da38fa69": "fmt-background",
    "66051ab2": "fmt-smaller",
    "e4bcd935": "fmt-normal",
    "16f00801": "fmt-bigger",
    "94b1985c": "fmt-bold",
    "ee53e8ca": "fmt-italic",
    "449720f8": "fmt-underline",
    "c13eddc9": "fmt-link",
    "71caed62": "fmt-image",
    "8405a6ef": "fmt-smiley",
    "7c0240f9": "warn",
    "aa6f7ade": "block",
    "651508f2": "add-buddy",
    "e74f0b35": "get-info",
    "e5ff2f81": "send",
}

# <assets>/sounds/<file> -> skin name. These are the only sounds the app plays.
SOUNDS = {"BuddyIn.wav": "door-open.wav", "BuddyOut.wav": "door-close.wav",
          "received.mp3": "received.mp3", "sent.mp3": "sent.mp3"}
# Sounds earlier versions installed; removed so nothing else can play.
RETIRED = ["im.wav", "welcome.wav", "goodbye.wav"]


def archives(root):
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith(".webarchive"):
                yield os.path.join(dirpath, f)


def to_png(data, mime, dest):
    if mime == "image/png":
        open(dest, "wb").write(data)
        return
    tmp = dest + ".src"
    open(tmp, "wb").write(data)
    subprocess.run(["sips", "-s", "format", "png", tmp, "--out", dest], check=True, capture_output=True)
    os.remove(tmp)


def main(root):
    os.makedirs(os.path.join(SKIN, "icons"), exist_ok=True)
    os.makedirs(os.path.join(SKIN, "fonts"), exist_ok=True)
    found, fonts = {}, []
    for path in archives(root):
        d = plistlib.load(open(path, "rb"))
        for r in d.get("WebSubresources", []):
            mime = r.get("WebResourceMIMEType") or ""
            data = r.get("WebResourceData", b"")
            if mime.startswith("image/"):
                name = ICONS.get(hashlib.sha1(data).hexdigest()[:8])
                if name and name not in found:
                    found[name] = True
                    to_png(data, mime, os.path.join(SKIN, "icons", name + ".png"))
            elif mime == "application/octet-stream" and data[:4] == b"wOF2" and len(fonts) < 2:
                fonts.append(data)
    for i, data in enumerate(fonts):
        open(os.path.join(SKIN, "fonts", f"ms-sans-serif-{i + 1}.woff2"), "wb").write(data)

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

    missing = sorted(set(ICONS.values()) - set(found))
    print(f"icons: {len(found)}/{len(ICONS)}  fonts: {len(fonts)}  skin: {SKIN}")
    print("sounds:", *copied, sep="\n  ")
    if missing:
        print("missing (app will use fallbacks):", ", ".join(missing))


if __name__ == "__main__":
    main(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/aim_assets"))
