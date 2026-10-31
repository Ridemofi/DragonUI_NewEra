#!/usr/bin/env python3
"""Append every key the source uses but enUS.lua does not yet declare, grouped by module.

Additive on purpose. enUS.lua's first two sections were written by hand and carry keys reachable
only through dynamic subscripts (`L[engKey]` for a profession, `L[stat.tooltip]` for a paper-doll
line); a regenerate-from-scratch would drop exactly those, because no scanner can see them.

    python tools/locale-lint/gen_enus.py
"""

import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_keys import ROOT, locale_keys, used_keys  # noqa: E402

ENUS = os.path.join(ROOT, "Locales", "enUS.lua")

# Source path prefix -> section heading, longest prefix wins.
SECTIONS = [
    ("modules/auctionhouse", "AUCTION HOUSE"),
    ("modules/bags", "BAGS"),
    ("modules/collections", "COLLECTIONS"),
    ("modules/cooldownviewer", "COOLDOWN MANAGER"),
    ("modules/detailsskin", "DAMAGE METER SKIN"),
    ("modules/encounterjournal", "ADVENTURE GUIDE"),
    ("modules/guild", "GUILD"),
    ("modules/levelup", "LEVEL UP DISPLAY"),
    ("modules/lfg", "GROUP FINDER"),
    ("modules/options", "OPTIONS WINDOW"),
    ("modules/professions", "PROFESSIONS"),
    ("modules/social", "SOCIAL"),
    ("modules/spellbook", "SPELLBOOK"),
    ("modules/talents", "TALENTS"),
    ("integration", "OPTIONS PANEL"),
    ("core", "SHARED UI"),
    ("", "MISCELLANEOUS"),
]


def section_for(files):
    for prefix, name in SECTIONS:
        if any(f.startswith(prefix) for f in files):
            return name
    return "MISCELLANEOUS"


def lua_key(key):
    # Keys arrive exactly as they appear between the quotes in the source, escapes intact, so they
    # go back out verbatim. Re-escaping here would turn a real newline escape into a literal
    # backslash-n and silently mint a key nothing looks up.
    return '"%s"' % key


def main():
    used, _ = used_keys()
    translated, passthrough = locale_keys("enUS")
    have = translated | passthrough
    missing = sorted(set(used) - have)
    if not missing:
        print("enUS.lua is already complete (%d keys)" % len(have))
        return 0

    grouped = {}
    for key in missing:
        grouped.setdefault(section_for(used[key]), []).append(key)

    out = []
    for _, name in SECTIONS:
        if name not in grouped:
            continue
        out.append("")
        out.append("-- " + "=" * 76)
        out.append("-- " + name)
        out.append("-- " + "=" * 76)
        out.append("")
        for key in sorted(grouped.pop(name)):
            out.append("L[%s] = true" % lua_key(key))

    raw = io.open(ENUS, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in raw else "\n"
    body = raw.replace("\r\n", "\n").rstrip("\n") + "\n" + "\n".join(out) + "\n"
    io.open(ENUS, "w", encoding="utf-8", newline="").write(body.replace("\n", nl))
    print("added %d keys to enUS.lua (%d total)" % (len(missing), len(have) + len(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
