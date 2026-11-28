#!/usr/bin/env python3
"""Writes release/workshop.txt into the 'description' field of mod/metadata.lua.

The Mod Editor uploads that field as the Steam Workshop description, and the in-game Mod Manager
shows it, so the Workshop text is plain text with no BBCode.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
text = (root / "release/workshop.txt").read_text(encoding="utf-8").strip()
if len(text) > 8000:
    sys.exit(f"release/workshop.txt has {len(text)} characters. Steam allows 8000.")

lua = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
meta = root / "mod/metadata.lua"
src = meta.read_text(encoding="utf-8")
new, n = re.subn(r"('description', )\"(?:[^\"\\]|\\.)*\"", lambda m: m.group(1) + '"' + lua + '"', src, count=1)
if n != 1:
    sys.exit("no 'description' field in mod/metadata.lua")
meta.write_text(new, encoding="utf-8")
print(f"description: {len(text)} characters")
