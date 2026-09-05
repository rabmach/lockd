#!/usr/bin/env bash
# install.sh — the whole lockd adoption experience, user-level, idempotent.
# No sudo for anything lockd needs except optional packages, which the
# installer checks first and offers to install. Every DE integration is
# guarded (skips politely when the file manager / desktop isn't there),
# idempotent (re-runs change nothing), and backed up before touching.

set -euo pipefail

BINDIR=""; TARGET="lockd"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UCA="${HOME}/.config/Thunar/uca.xml"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

# ---------- dependency mapping ----------
# binary -> package name, per distro family. Names drift between releases;
# anything unknown is skipped from the suggestion rather than guessed.
pkg_for() {
    case "$1:$2" in
        apt:age)            echo "age" ;;
        apt:yad)            echo "yad" ;;
        apt:zenity)         echo "zenity" ;;
        apt:xclip)          echo "xclip" ;;
        apt:wl-copy)        echo "wl-clipboard" ;;
        apt:notify-send)    echo "libnotify-bin" ;;
        pacman:age)         echo "age" ;;
        pacman:yad)         echo "yad" ;;
        pacman:zenity)      echo "zenity" ;;
        pacman:xclip)       echo "xclip" ;;
        pacman:wl-copy)     echo "wl-clipboard" ;;
        pacman:notify-send) echo "libnotify" ;;
        dnf:age)            echo "age" ;;
        dnf:yad)            echo "yad" ;;
        dnf:zenity)         echo "zenity" ;;
        dnf:xclip)          echo "xclip" ;;
        dnf:wl-copy)        echo "wl-clipboard" ;;
        dnf:notify-send)    echo "libnotify" ;;
        zypper:age)         echo "age" ;;
        zypper:yad)         echo "yad" ;;
        zypper:zenity)      echo "zenity" ;;
        zypper:xclip)       echo "xclip" ;;
        zypper:wl-copy)     echo "wl-clipboard" ;;
        zypper:notify-send) echo "libnotify-tools" ;;
        apk:age)            echo "age" ;;
        apk:yad)            echo "yad" ;;
        apk:zenity)         echo "zenity" ;;
        apk:xclip)          echo "xclip" ;;
        apk:wl-copy)        echo "wl-clipboard" ;;
        apk:notify-send)    echo "libnotify" ;;
    esac
}

fam_detect() {
    if command -v apt-get >/dev/null; then echo apt
    elif command -v pacman >/dev/null; then echo pacman
    elif command -v dnf >/dev/null; then echo dnf
    elif command -v zypper >/dev/null; then echo zypper
    elif command -v apk >/dev/null; then echo apk
    else echo ""; fi
}

deps_check() {
    step "dependencies"
    local hard_missing=() d
    for d in age shred script; do
        command -v "$d" >/dev/null || hard_missing+=("$d")
    done
    local dlg="" clip="" note=""
    for d in yad zenity kdialog; do command -v "$d" >/dev/null && { dlg="$d"; break; }; done
    for d in wl-copy xclip xsel; do command -v "$d" >/dev/null && { clip="$d"; break; }; done
    command -v notify-send >/dev/null || note="notify-send"

    say "crypto/wipe core: age shred script"
    say "dialog backend:   ${dlg:-NONE (terminal mode only)}"
    say "clipboard:        ${clip:-NONE (key-copy offer disabled)}"
    say "notifications:    ${note:-notify-send}"

    # soft deps: only mentioned, never fatal
    local soft_missing=()
    [[ -n "$dlg" ]] || soft_missing+=("yad")
    [[ -n "$clip" ]] || soft_missing+=("xclip")
    [[ -z "$note" ]] || soft_missing+=("notify-send")

    if [[ -n "$dlg" && -n "$clip" && -z "$note" && ${#hard_missing[@]} -eq 0 ]]; then
        say "all present"
        return 0
    fi

    local fam; fam=$(fam_detect)
    local -a pkgs=() p
    for d in "${hard_missing[@]}" "${soft_missing[@]}"; do
        p=$(pkg_for "${fam:-none}" "$d") && [[ -n "$p" ]] && pkgs+=("$p") || true
    done

    if (( ${#hard_missing[@]} > 0 )); then
        if [[ "$fam" == "apt" && ${#pkgs[@]} -gt 0 ]]; then
            say "missing (required): ${hard_missing[*]}"
            say "install with:  sudo apt-get install -- ${pkgs[*]}"
            if [[ -t 0 ]]; then
                local a
                read -r -p "run that now? [y/N] " a || a=n
                if [[ "$a" == y* ]]; then sudo apt-get install -y "${pkgs[@]}"; fi
            fi
        elif [[ -n "$fam" && ${#pkgs[@]} -gt 0 ]]; then
            local pmi
            case "$fam" in
                pacman) pmi="sudo pacman -S" ;;
                dnf)    pmi="sudo dnf install" ;;
                zypper) pmi="sudo zypper install" ;;
                apk)    pmi="sudo apk add" ;;
            esac
            say "missing (required): ${hard_missing[*]}"
            say "install with:  $pmi ${pkgs[*]}"
        else
            say "missing (required): ${hard_missing[*]} - install them with your distro's package manager"
        fi
        for d in age shred script; do
            command -v "$d" >/dev/null || { say "FATAL: $d still missing - cannot continue"; exit 1; }
        done
    fi
    if [[ -z "$dlg" ]]; then
        say "no dialog tool: lockd will run in TERMINAL MODE (fully usable, also over ssh)."
        say "  install yad or zenity later for windows - lockd picks it up automatically."
    fi
    if [[ -z "$clip" ]]; then
        say "no clipboard helper: the 'copy public key' offer is skipped. xclip or wl-clipboard fix it."
    fi
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

install_icon() {
    step "icon (theme-independent)"
    local dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
    mkdir -p "$dir"
    cat > "$dir/lockd.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <path d="M21 30v-9a11 11 0 0 1 22 0v9" fill="none" stroke="#5b6770" stroke-width="6" stroke-linecap="round"/>
  <rect x="14" y="30" width="36" height="26" rx="5" fill="#5b6770"/>
  <circle cx="32" cy="41" r="4.5" fill="#fdf6e3"/>
  <rect x="29.8" y="42" width="4.4" height="9" rx="2.2" fill="#fdf6e3"/>
</svg>
EOF
    command -v gtk-update-icon-cache >/dev/null 2>&1 \
        && gtk-update-icon-cache -q -f "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    say "installed: $dir/lockd.svg"
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
Icon=lockd
Terminal=false
Categories=Utility;Security;FileManager;
Keywords=encrypt;decrypt;secure;wipe;age;password;privacy;lock;
EOF
    cat > "$apps/lockd-decrypt.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=lockd: unlock
Comment=Decrypt an age-encrypted file with your default key
Exec=$bin -d --open %f
Icon=lockd
Terminal=false
MimeType=application/x-age;
Keywords=decrypt;unlock;age;lock;
EOF
    xdg-mime default lockd-decrypt.desktop application/x-age 2>/dev/null || true
    if command -v desktop-file-validate >/dev/null 2>&1; then
        if desktop-file-validate "$apps/lockd.desktop" 2>/dev/null \
           && desktop-file-validate "$apps/lockd-decrypt.desktop" 2>/dev/null; then
            say "entries validate"
        else
            say "WARN: desktop-file-validate complained (entries still installed)"
        fi
    fi
    say "launcher: lockd.desktop (shows in app menus)"
    say "handler:  double-click on *.age unlocks with your passphrase"
}

install_aliases() {
    step "aliases (lock / unlock / erase)"
    local ba="${HOME}/.bash_aliases"
    local begin="# >>> lockd aliases >>>" end="# <<< lockd aliases <<<"
    if grep -q "$begin" "$ba" 2>/dev/null; then
        say "  already installed"
        return 0
    fi
    # an existing lock/unlock/erase alias outside our block wins - warn,
    # never touch (the user's own aliases are the user's own)
    if grep -Eq "^[[:space:]]*alias (lock|unlock|erase)=" "$ba" 2>/dev/null; then
        say "  you already define lock/unlock/erase aliases - left untouched"
        say "  (lockd's aliases, if you want them: alias lock='lockd' etc.)"
        return 0
    fi
    if [[ ! -f "$ba" ]]; then
        touch "$ba"
        local rc="${HOME}/.bashrc"
        if ! grep -qs "bash_aliases" "$rc"; then
            printf '\n# lockd: aliases live in ~/.bash_aliases\nif [ -f ~/.bash_aliases ]; then\n    . ~/.bash_aliases\nfi\n' >> "$rc"
            say "  ~/.bashrc now sources ~/.bash_aliases"
        fi
    fi
    cp -f "$ba" "$ba.bak-lockd"
    cat >> "$ba" <<EOF
$begin
alias lock='lockd'
alias unlock='lockd -d'
alias erase='lockd --shred'
$end
EOF
    say "  added: lock / unlock / erase (backup: $ba.bak-lockd)"
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
    if [[ -z "$j" ]]; then
        # anchor is the FIRST action - nothing above it; use its own
        # closing </action> (found downwards) instead
        j=$(awk -v n="$i" 'NR>=n && /<\/action>/ {print NR; exit}' "$UCA")
    fi
    [[ -n "$j" ]] || { say "  uca.xml malformed - skipped"; return 0; }
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
	<icon>lockd</icon>
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
	<icon>lockd</icon>
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

install_fm_ctx() {
    step "right-click: nautilus / caja / nemo"
    # all three speak the nautilus script protocol; lockd generates the
    # script bodies itself (lockd --ctx-script) so there is one source of
    # truth and the selftest exercises the exact bytes that get installed.
    local mgr dir kind
    for mgr in nautilus caja nemo; do
        command -v "$mgr" >/dev/null 2>&1 || { say "  $mgr: not installed - skipped"; continue; }
        case "$mgr" in
            nautilus) dir="${HOME}/.local/share/nautilus/scripts" ;;
            caja)     dir="${HOME}/.config/caja/scripts" ;;
            nemo)     dir="${HOME}/.local/share/nemo/scripts" ;;
        esac
        mkdir -p "$dir"
        for kind in encrypt decrypt shred; do
            "$BINDIR/lockd" --ctx-script "$kind" > "$dir/lockd $kind"
            chmod +x "$dir/lockd $kind"
        done
        say "  $mgr: Scripts -> lockd encrypt / decrypt / shred"
    done
}

install_dolphin() {
    step "right-click: dolphin service menu"
    command -v dolphin >/dev/null 2>&1 || { say "  dolphin: not installed - skipped"; return 0; }
    local bin="$BINDIR/lockd"
    local menu
    menu=$(cat <<EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=application/octet-stream;inode/directory;all/allfiles;
Actions=lockdEncrypt;lockdDecrypt;lockdShred;
X-KDE-Priority=TopLevel

[Desktop Action lockdEncrypt]
Name=lockd: encrypt
Icon=lockd
Exec=$bin %F

[Desktop Action lockdDecrypt]
Name=lockd: decrypt
Icon=lockd
Exec=$bin -d --open %F

[Desktop Action lockdShred]
Name=lockd: shred (secure wipe)
Icon=edit-delete-shred
Exec=$bin --shred %F
EOF
)
    # modern Plasma (5.90+) reads kio/servicemenus; older reads kservices5
    local d1="${HOME}/.local/share/kio/servicemenus"
    local d2="${HOME}/.local/share/kservices5/ServiceMenus"
    mkdir -p "$d1" "$d2"
    printf '%s\n' "$menu" > "$d1/lockd.desktop"
    printf '%s\n' "$menu" > "$d2/lockd.desktop"
    say "  dolphin: right-click -> lockd (encrypt / decrypt / shred)"
}

install_keybind() {
    step "keybind (Ctrl+Alt+E -> quick-lock)"
    install_keybind_openbox
    install_keybind_xfce
    install_keybind_gnome
    say "  i3/sway/KDE: snippets in the README"
}

install_keybind_openbox() {
    local rc="${HOME}/.config/openbox/rc.xml"
    [[ -f "$rc" ]] || { say "  openbox: no config - skipped"; return 0; }
    if grep -q 'key="C-A-e"' "$rc"; then
        say "  openbox: already bound (or user has their own C-A-e) - untouched"
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
print("  openbox: keybind inserted before </keyboard>")
PYINNER
    xmllint --noout "$rc" 2>/dev/null || { say "  openbox rc.xml BROKE - restoring backup"; cp -f "$rc.bak-lockd" "$rc"; }
    command -v openbox >/dev/null && openbox --reconfigure 2>/dev/null && say "  openbox reconfigured"
    return 0
}

install_keybind_xfce() {
    command -v xfconf-query >/dev/null 2>&1 || { say "  xfconf: not installed - skipped"; return 0; }
    case "${XDG_CURRENT_DESKTOP:-}" in
        *XFCE*) ;;
        *) say "  xfwm4: not an XFCE session - skipped"; return 0 ;;
    esac
    local prop="/xfwm4/custom/<Primary><Alt>e" cur
    cur=$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)
    if [[ -n "$cur" ]]; then
        if [[ "$cur" == "$BINDIR/lockd" ]]; then say "  xfwm4: already bound"
        else say "  xfwm4: Ctrl+Alt+E already used by '$cur' - untouched"; fi
        return 0
    fi
    if xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -n -t string -s "$BINDIR/lockd" >/dev/null 2>&1; then
        say "  xfwm4: Ctrl+Alt+E -> lockd"
    else
        say "  xfwm4: xfconf set failed - skipped"
    fi
}

install_keybind_gnome() {
    command -v gsettings >/dev/null 2>&1 || { say "  gnome: gsettings not installed - skipped"; return 0; }
    case "${XDG_CURRENT_DESKTOP:-}" in
        *GNOME*) ;;
        *) say "  gnome: not a GNOME session - skipped"; return 0 ;;
    esac
    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local list
    list=$(gsettings get $schema custom-keybindings 2>/dev/null) \
        || { say "  gnome: gsettings read failed - skipped"; return 0; }
    # strip the GVariant wrapper: "@as []" or "['/path0/', '/path1/']"
    local paths
    paths=$(printf '%s' "$list" | sed -e 's/^@as \[\]//' -e 's/^\[//' -e 's/\]$//' -e "s/'//g" -e 's/ //g')
    local -a arr=()
    [[ -n "$paths" ]] && mapfile -t arr < <(printf '%s' "$paths" | tr ',' '\n')
    local p cmd
    for p in "${arr[@]}"; do
        cmd=$(gsettings get "$schema.custom-keybinding:$p" command 2>/dev/null || true)
        if [[ "$cmd" == "'$BINDIR/lockd'" ]]; then
            say "  gnome: already bound"
            return 0
        fi
    done
    local n=${#arr[@]}
    local newp="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${n}/"
    local newlist="[" first=1
    for p in "${arr[@]}"; do
        [[ $first -eq 1 ]] || newlist+=", "
        newlist+="'$p'"; first=0
    done
    [[ $first -eq 1 ]] || newlist+=", "
    newlist+="'$newp']"
    if ! gsettings set $schema custom-keybindings "$newlist" 2>/dev/null; then
        say "  gnome: set failed - skipped"
        return 0
    fi
    gsettings set "$schema.custom-keybinding:$newp" name 'lockd' 2>/dev/null || true
    gsettings set "$schema.custom-keybinding:$newp" command "$BINDIR/lockd" 2>/dev/null || true
    gsettings set "$schema.custom-keybinding:$newp" binding '<Control><Alt>e' 2>/dev/null || true
    say "  gnome: Ctrl+Alt+E -> lockd"
}

summary() {
    step "done"
    say "lockd is installed for $(whoami)."
    say "  command:   lockd            (encrypt flow)"
    say "  aliases:   lock / unlock / erase (if installed)"
    say "  menu:      Apps -> lockd    (via your app menu)"
    say "  right-click: thunar/nautilus/caja/nemo scripts + dolphin service menu"
    say "             (whatever this desktop actually has)"
    say "  double-click *.age          -> passphrase -> opened"
    say "  keybind:   Ctrl+Alt+E        -> quick-lock (openbox/xfce/gnome; see README)"
    say "  keys:      ~/.config/lockd/  (created on first run)"
    say "The original is wiped after verification - see the README, --keep opts out."
}

deps_check
install_bin
install_mime
install_icon
install_desktop
install_aliases
install_thunar
install_fm_ctx
install_dolphin
install_keybind
summary
