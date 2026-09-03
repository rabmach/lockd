#!/usr/bin/env bash
# install.sh — the whole lockd adoption experience, user-level, idempotent.
# No sudo for anything lockd needs except the apt packages, which the
# installer checks first and offers to install.

set -euo pipefail

BINDIR=""; TARGET="lockd"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UCA="${HOME}/.config/Thunar/uca.xml"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

deps_check() {
    step "dependencies"
    local missing=()
    local d
    for d in age yad xclip notify-send shred script; do
        command -v "$d" >/dev/null || missing+=("$d")
    done
    if (( ${#missing[@]} == 0 )); then
        say "all present: age, yad, xclip, notify-send, shred, script"
        return 0
    fi
    say "missing: ${missing[*]}"
    if command -v apt-get >/dev/null; then
        local pkgs=""
        [[ " ${missing[*]} " == *" age "* ]] && pkgs+=" age"
        [[ " ${missing[*]} " == *" yad "* ]] && pkgs+=" yad"
        [[ " ${missing[*]} " == *" xclip "* ]] && pkgs+=" xclip"
        [[ " ${missing[*]} " == *" notify-send "* ]] && pkgs+=" libnotify-bin"
        say "install with:  sudo apt-get install -- $pkgs"
        if command -v yad >/dev/null || [[ -t 0 ]]; then
            if [[ -t 0 ]]; then
                read -r -p "run that now? [y/N] " a || a=n
                [[ "$a" == y* ]] && sudo apt-get install -y $pkgs
            fi
        fi
    else
        say "install the missing tools with your distro's package manager"
    fi
    # hard requirements for the core flow
    for d in age shred script; do
        command -v "$d" >/dev/null || { say "FATAL: $d still missing - cannot continue"; exit 1; }
    done
}

install_bin() {
    step "lockd script"
    # prefer an existing, PATH-visible ~/bin; else the XDG user bin
    if [[ -d "$HOME/bin" ]] && [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
        BINDIR="$HOME/bin"
    else
        BINDIR="$HOME/.local/bin"
        mkdir -p "$BINDIR"
        if [[ ":$PATH:" != *":$BINDIR:"* ]]; then
            local rc="${HOME}/.bashrc"
            if ! grep -qs "HOME/.local/bin" "$rc"; then
                printf '\n# lockd: user binaries\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
                say "PATH line appended to ~/.bashrc (new terminals pick it up)"
            fi
        fi
    fi
    cp -f "$SRC_DIR/lockd" "$BINDIR/lockd"
    chmod +x "$BINDIR/lockd"
    say "installed: $BINDIR/lockd"
}

install_mime() {
    step "mime type (application/x-age)"
    local d="${HOME}/.local/share/mime/packages"
    mkdir -p "$d" "${HOME}/.local/share/applications"
    cat > "$d/x-lockd.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-age">
    <comment>age-encrypted file (lockd)</comment>
    <glob pattern="*.age"/>
  </mime-type>
</mime-info>
EOF
    update-mime-database "${HOME}/.local/share/mime" 2>/dev/null || true
    say "registered *.age"
}

install_desktop() {
    step "desktop entries (menu item + double-click handler)"
    local apps="${HOME}/.local/share/applications"
    local bin="$BINDIR/lockd"      # absolute: menus do not read bashrc PATHs
    cat > "$apps/lockd.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=lockd
Comment=Encrypt files and directories - one word, password, done
Exec=$bin
Icon=channel-secure
Terminal=false
Categories=Utility;Security;FileManager;
EOF
    cat > "$apps/lockd-decrypt.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=lockd: unlock
Comment=Decrypt an age-encrypted file with your default key
Exec=$bin -d --open %f
Icon=channel-secure
Terminal=false
MimeType=application/x-age;
EOF
    xdg-mime default lockd-decrypt.desktop application/x-age 2>/dev/null || true
    say "launcher: lockd.desktop (shows in app menus via obamenu/xdg)"
    say "handler:  double-click on *.age unlocks with your passphrase"
}

uca_action() {
    # insert one <action> block after the Encryption anchor, idempotent
    local name="$1" block="$2"
    grep -q "<name>$name</name>" "$UCA" && { say "  already present: $name"; return 0; }
    local i j
    i=$(grep -n "<name>Encrypt with keys</name>" "$UCA" | head -1 | cut -d: -f1)
    [[ -n "$i" ]] || { say "  no Encryption anchor found in uca.xml - skipped"; return 0; }
    # back up once per invocation
    [[ -f "$UCA.bak-lockd" ]] || cp -f "$UCA" "$UCA.bak-lockd"
    # find the end of the action block CONTAINING the anchor (search upwards)
    j=$(awk -v n="$i" 'NR<=n && /<\/action>/ {last=NR} END{print last}' "$UCA")
    python3 - "$UCA" "$j" "$block" <<'PYEOF'
import sys
p, line_no, block = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lines = open(p).read().split("\n")
lines[line_no:line_no] = block.split("\n")
open(p, "w").write("\n".join(lines))
PYEOF
    say "  added: $name"
}

install_thunar() {
    step "thunar custom actions"
    [[ -f "$UCA" ]] || { say "no Thunar config - skipped"; return 0; }
    local sid
    sid=$(date +%s%N)
    local A1 A2 A3
    A1=$(cat <<BLOCK
<action>
	<icon>channel-secure</icon>
	<name>lockd: encrypt (age)</name>
	<submenu>Scripts/Encryption</submenu>
	<unique-id>${sid}-1</unique-id>
	<command>$BINDIR/lockd %F</command>
	<description>one-word encryption: password, pick, verify, wipe (or --keep)</description>
	<range></range>
	<patterns>*</patterns>
	<directories/>
	<audio-files/>
	<image-files/>
	<other-files/>
	<text-files/>
	<video-files/>
</action>
BLOCK
)
    A2=$(cat <<BLOCK
<action>
	<icon>channel-secure</icon>
	<name>lockd: decrypt</name>
	<submenu>Scripts/Encryption</submenu>
	<unique-id>${sid}-2</unique-id>
	<command>$BINDIR/lockd -d --open %F</command>
	<description>unlock .age files with the default key</description>
	<range></range>
	<patterns>*.age</patterns>
	<other-files/>
	<text-files/>
	<video-files/>
</action>
BLOCK
)
    A3=$(cat <<BLOCK
<action>
	<icon>edit-delete-shred</icon>
	<name>lockd: shred (secure wipe)</name>
	<unique-id>${sid}-3</unique-id>
	<command>$BINDIR/lockd --shred %F</command>
	<description>secure-wipe files - gone means gone</description>
	<range></range>
	<patterns>*</patterns>
	<directories/>
	<audio-files/>
	<image-files/>
	<other-files/>
	<text-files/>
	<video-files/>
</action>
BLOCK
)
    uca_action "lockd: encrypt (age)" "$A1"
    uca_action "lockd: decrypt" "$A2"
    uca_action "lockd: shred (secure wipe)" "$A3"
    xmllint --noout "$UCA" 2>/dev/null && say "uca.xml valid" || { say "uca.xml BROKEN - restoring backup"; cp -f "$UCA.bak-lockd" "$UCA"; }
}

install_keybind() {
    step "keybind (Ctrl+Alt+E -> quick-lock)"
    local rc="${HOME}/.config/openbox/rc.xml"
    [[ -f "$rc" ]] || { say "no openbox config - skipped (bind $BINDIR/lockd in your DE settings)"; return 0; }
    if grep -q 'key="C-A-e"' "$rc"; then
        say "  already bound (or user has their own C-A-e) - untouched"
        return 0
    fi
    cp -f "$rc" "$rc.bak-lockd"
    python3 - "$rc" "$BINDIR" <<'PYINNER'
import sys
p, bindir = sys.argv[1], sys.argv[2]
s = open(p).read()
block = (f'    <keybind key="C-A-e">\n'
         f'      <action name="Execute">\n'
         f'        <execute>{bindir}/lockd</execute>\n'
         f'      </action>\n'
         f'    </keybind>\n')
marker = "  </keyboard>"
assert marker in s, "no </keyboard> in rc.xml"
s = s.replace(marker, block + marker, 1)
open(p, "w").write(s)
print("  keybind inserted before </keyboard>")
PYINNER
    xmllint --noout "$rc" 2>/dev/null || { say "rc.xml BROKE - restoring backup"; cp -f "$rc.bak-lockd" "$rc"; }
    command -v openbox >/dev/null && openbox --reconfigure 2>/dev/null && say "  openbox reconfigured"
}

summary() {
    step "done"
    say "lockd is installed for $(whoami)."
    say "  command:   lockd            (encrypt flow)"
    say "  menu:      Apps → lockd     (via your app menu)"
    say "  right-click: Scripts/Encryption → lockd: ... (+ a top-level shred)"
    say "  double-click *.age          → passphrase → opened"
    say "  keybind:   Ctrl+Alt+E        → quick-lock (openbox)"
    say "  keys:      ~/.config/lockd/  (created on first run)"
    say "The original is wiped after verification - see the README, --keep opts out."
}

deps_check
install_bin
install_mime
install_desktop
install_thunar
install_keybind
summary
