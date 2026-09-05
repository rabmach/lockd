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

ICON="$HOME/.local/share/icons/hicolor/scalable/apps/lockd.svg"
if [[ -f "$ICON" ]]; then
    rm -fv "$ICON"
    say "removed: bundled icon"
fi

if [[ -f "$HOME/.local/share/mime/packages/x-lockd.xml" ]]; then
    rm -fv "$HOME/.local/share/mime/packages/x-lockd.xml"
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    say "removed: *.age mime type (double-click falls back to the open-with dialog)"
fi

remove_aliases() {
    local ba="${HOME}/.bash_aliases"
    [[ -f "$ba" ]] || return 0
    grep -q "# >>> lockd aliases >>>" "$ba" || return 0
    cp -f "$ba" "$ba.bak-lockd-uninstall"
    sed -i '/# >>> lockd aliases >>>/,/# <<< lockd aliases <<</d' "$ba"
    say "removed: alias block (backup: $ba.bak-lockd-uninstall)"
}
remove_aliases

remove_fm_ctx() {
    # the same three files in each manager's scripts dir; rm -f is quiet
    # about the ones that were never installed
    rm -fv "$HOME/.local/share/nautilus/scripts/lockd encrypt" \
           "$HOME/.local/share/nautilus/scripts/lockd decrypt" \
           "$HOME/.local/share/nautilus/scripts/lockd shred" \
           "$HOME/.config/caja/scripts/lockd encrypt" \
           "$HOME/.config/caja/scripts/lockd decrypt" \
           "$HOME/.config/caja/scripts/lockd shred" \
           "$HOME/.local/share/nemo/scripts/lockd encrypt" \
           "$HOME/.local/share/nemo/scripts/lockd decrypt" \
           "$HOME/.local/share/nemo/scripts/lockd shred" 2>/dev/null || true
    say "removed: nautilus/caja/nemo right-click scripts (if present)"
}
remove_fm_ctx

rm -fv "$HOME/.local/share/kio/servicemenus/lockd.desktop" \
       "$HOME/.local/share/kservices5/ServiceMenus/lockd.desktop" 2>/dev/null || true
say "removed: dolphin service menu (if present)"

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

remove_keybind_openbox() {
    local rc="${HOME}/.config/openbox/rc.xml"
    [[ -f "$rc" ]] || return 0
    grep -q 'key="C-A-e"' "$rc" || return 0
    local removed=0
    removed=$(python3 - "$rc" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
pat = re.compile(r'\n?[ \t]*<keybind key="C-A-e">(?:(?!</keybind>).)*?</keybind>\n?', re.S)
s2 = pat.sub(lambda m: "" if "lockd" in m.group(0) else m.group(0), s)
if s2 != s:
    open(p, "w").write(s2)
    print(1)
else:
    print(0)
PY
) || removed=0
    if [[ "$removed" == "1" ]]; then
        xmllint --noout "$rc" 2>/dev/null \
            && say "removed: openbox Ctrl+Alt+E (only the block that pointed at lockd)" \
            || say "WARN: openbox rc.xml failed validation - inspect by hand"
        command -v openbox >/dev/null && openbox --reconfigure 2>/dev/null || true
    else
        say "kept: openbox Ctrl+Alt+E (points somewhere else - not lockd's)"
    fi
}

remove_keybind_xfce() {
    command -v xfconf-query >/dev/null 2>&1 || return 0
    local prop="/xfwm4/custom/<Primary><Alt>e" cur
    cur=$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)
    [[ "$cur" == */lockd ]] || return 0
    xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r -n 2>/dev/null || true
    say "removed: xfwm4 Ctrl+Alt+E"
}

remove_keybind_gnome() {
    command -v gsettings >/dev/null 2>&1 || return 0
    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local list
    list=$(gsettings get $schema custom-keybindings 2>/dev/null) || return 0
    local paths
    paths=$(printf '%s' "$list" | sed -e 's/^@as \[\]//' -e 's/^\[//' -e 's/\]$//' -e "s/'//g" -e 's/ //g')
    [[ -n "$paths" ]] || return 0
    local -a arr=() keep=() found=0
    mapfile -t arr < <(printf '%s' "$paths" | tr ',' '\n')
    local p cmd
    for p in "${arr[@]}"; do
        cmd=$(gsettings get "$schema.custom-keybinding:$p" command 2>/dev/null || true)
        if [[ "$cmd" == "'$HOME/.local/bin/lockd'" || "$cmd" == "'$HOME/bin/lockd'" ]]; then
            gsettings reset-recursively "$schema.custom-keybinding:$p" 2>/dev/null || true
            found=1
        else
            keep+=("$p")
        fi
    done
    if [[ $found -eq 1 ]]; then
        local newlist="[" first=1
        for p in "${keep[@]}"; do
            [[ $first -eq 1 ]] || newlist+=", "
            newlist+="'$p'"; first=0
        done
        newlist+="]"
        gsettings set $schema custom-keybindings "$newlist" 2>/dev/null || true
        say "removed: gnome Ctrl+Alt+E"
    fi
}

remove_keybind_openbox
remove_keybind_xfce
remove_keybind_gnome

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
