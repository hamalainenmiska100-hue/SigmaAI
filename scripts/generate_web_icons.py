#!/usr/bin/env python3
"""Generate web PWA icon assets from web/favicon.ico."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FAVICON_PATH = ROOT / "web" / "favicon.ico"
ICONS_DIR = ROOT / "web" / "icons"

ICON_OUTPUTS = [
    ("Icon-192.png", 192),
    ("Icon-512.png", 512),
    ("Icon-maskable-192.png", 192),
    ("Icon-maskable-512.png", 512),
    ("apple-touch-icon.png", 180),
]


def main() -> None:
    if not FAVICON_PATH.exists():
        raise FileNotFoundError(f"Missing favicon source file: {FAVICON_PATH}")

    ICONS_DIR.mkdir(parents=True, exist_ok=True)

    source = Image.open(FAVICON_PATH).convert("RGBA")
    for filename, size in ICON_OUTPUTS:
        output = source.resize((size, size), Image.Resampling.LANCZOS)
        output_path = ICONS_DIR / filename
        output.save(output_path, format="PNG")
        print(f"Generated {output_path.relative_to(ROOT)} ({size}x{size})")


if __name__ == "__main__":
    main()
