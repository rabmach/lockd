#!/usr/bin/env bash
# uninstall.sh — reversibility is a tenet. Removes lockd's installed pieces.
# Your keys and config survive unless you pass --purge.

set -euo pipefail
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

say() { printf '%s\n' "$*"; }

say "== lockd uninstall"

rm -fv "$HOME/.local/bin/lockd" "$HOME/bin/lockd"
say "removed: the lockd command"

rm -fv "$HOME/.local/share/applications/lockd.desktop" \
       "$HOME/.local/share/applications/lockd-decrypt.desktop"
say "removed: desktop entries"

if [[ -f "$HOME/.local/share/mime/packages/x-lockd.xml" ]]; then
    rm -fv "$HOME/.local/share/mime/packages/x-lockd.xml"
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    say "removed: *.age mime type (double-click falls back to the open-with dialog)"
fi

UCA="$HOME/.config/Thunar/uca.xml"
if [[ -f "$UCA" ]] && grep -q "<name>lockd:" "$UCA"; then
    cp -f "$UCA" "$UCA.bak-lockd-uninstall"
    python3 - "$UCA" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
# remove complete <action> blocks whose name starts with "lockd:"
s = re.sub(r"<action>(?:(?!</action>).)*?<name>lockd:[^<]*</name>(?:(?!</action>).)*?</action>\n?",
           "", s, flags=re.S)
open(p, "w").write(s)
PYEOF
    xmllint --noout "$UCA" 2>/dev/null && say "removed: thunar actions (uca.xml valid; backup at uca.xml.bak-lockd-uninstall)" \
        || { say "uca.xml broke - restoring backup"; cp -f "$UCA.bak-lockd-uninstall" "$UCA"; }
fi

if [[ $PURGE -eq 1 ]]; then
    if [[ -d "$HOME/.config/lockd" ]]; then
        shred -uzn1 "$HOME/.config/lockd/identity.txt" 2>/dev/null || true
        rm -rf "$HOME/.config/lockd"
        say "PURGED: keys and config are gone. Encrypted files anywhere are now unreadable - forever."
    else
        say "no config to purge"
    fi
else
    say "kept: ~/.config/lockd/ (your key). Remove it with: $0 --purge"
fi

say "done. encrypted *.age files elsewhere are untouched (they are just files)."
