#!/usr/bin/env python3
"""Builds Apps/tvOS/Assets.xcassets (app icon + Top Shelf images) from the PNGs `design-preview --icons` renders.

    swift run design-preview --icons /tmp/icons
    python3 scripts/make-icon-catalog.py /tmp/icons
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "icons")
root = Path(__file__).resolve().parent.parent / "Apps/tvOS/Assets.xcassets"
brand = root / "App Icon & Top Shelf Image.brandassets"
INFO = {"author": "xcode", "version": 1}


def write(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def copy(name: str, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src / name, dest)


def imagestack(folder: str, prefix: str, scales: list[str]):
    stack = brand / folder
    write(stack / "Contents.json", {
        "layers": [{"filename": f"{n}.imagestacklayer"} for n in ("Front", "Middle", "Back")],  # front-most first
        "info": INFO,
    })
    for layer in ("Front", "Middle", "Back"):
        base = stack / f"{layer}.imagestacklayer"
        write(base / "Contents.json", {"info": INFO})
        images = []
        for scale in scales:
            suffix = "" if scale == "1x" and len(scales) == 1 else f"@{scale}"
            file = f"{prefix}-{layer.lower()}{suffix}.png"
            copy(file, base / "Content.imageset" / file)
            images.append({"idiom": "tv", "filename": file, "scale": scale})
        write(base / "Content.imageset" / "Contents.json", {"images": images, "info": INFO})


def imageset(folder: str, prefix: str):
    """Top Shelf images are opaque, so they are stored as JPEG (about a tenth the size of PNG)."""
    base = brand / folder
    images = []
    for scale in ("1x", "2x"):
        png = f"{prefix}@{scale}.png"
        jpg = f"{prefix}@{scale}.jpg"
        base.mkdir(parents=True, exist_ok=True)
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "88", str(src / png), "--out", str(base / jpg)],
                       check=True, capture_output=True)
        images.append({"idiom": "tv", "filename": jpg, "scale": scale})
    write(base / "Contents.json", {"images": images, "info": INFO})


shutil.rmtree(root, ignore_errors=True)
write(root / "Contents.json", {"info": INFO})
imagestack("App Icon - App Store.imagestack", "appstore", ["1x"])
imagestack("App Icon.imagestack", "home", ["1x", "2x"])
imageset("Top Shelf Image.imageset", "topshelf")
imageset("Top Shelf Image Wide.imageset", "topshelfwide")
write(brand / "Contents.json", {
    "assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ],
    "info": INFO,
})
print("wrote", root)
