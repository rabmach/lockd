# PACKAGING.md — for distro makers who love their users

You ship a Linux distro. Your users deserve whip-it-out encryption — one
word, password, done — without ever reading about cryptography. lockd is
that. This file is for YOU: the person who wants lockd riding along in the
ISO, out of the box, zero fuss. Copy, paste, done — and nothing about it
will ever call you in a panic.

_Shortest honest pitch you can relay to your users_: age underneath, MIT,
one word to lock a file or a whole directory, byte-verification **before**
any original is ever wiped, and the failure mode is always "your original
survives". Nothing to configure, nothing to babysit.


## The two ways in

1. **Per-user, at install time in your postinst / first-boot script:**
   copy this repo anywhere and run `./install.sh` as the user. Idempotent,
   self-guarding, backs up everything it touches. This is the whole
   product for a single user.

2. **System-wide at image build (this document):** the artifacts go to the
   system locations, templates to `/etc/skel`, and every user who ever
   logs in (existing or new) gets the whole experience. Build once, forget.

Both leave the executing user in charge of their own config — lockd never
overwrites a user setting silently. Merger rules below.


### Dependencies (the whole list)

Hard requirements: `age`, `age-keygen` (same package), `shred`, `cmp`,
`script` — coreutils/util-linux: present in EVERY distro. The only extra
Debian packages are `age` and, for desktops, `yad`, `xclip`,
`libnotify-bin`.

- Debian-family: `sudo apt-get install age yad xclip libnotify-bin`
- Whenever you prefer: Arch `age yad xclip libnotify` · Fedora
  `age xclip libnotify` (yad via COPR on some spins) · openSUSE similar.

Grace notes, not requirements: `zenity`/`kdialog` (dialog fallbacks),
`wl-clipboard` (Wayland clipboard), `python3` + `xmllint` only if your
users rely on Thunar/uca.xml editing. `LOCKD_DIALOG=tty` runs everything
headless (SSH, TTY) with zero GUI deps.


## System-wide placement (option 1: fork-and-ships)

    git clone github.com:rabmach/lockd && cd lockd

| Artifact | System path | What it does |
|---|---|---|
| `lockd` (the script, 755) | `/usr/bin/lockd` | the whole thing |
| `lockd.svg` (inline in install.sh:174) | `/usr/share/icons/hicolor/scalable/apps/lockd.svg` | theme-independent menu icon |
| `lockd.desktop`, `lockd-decrypt.desktop` | `/usr/share/applications/` | menu item + `*.age` double-click handler (`Exec=/usr/bin/lockd ...`) |
| `x-lockd.xml` (inline in install.sh:153) | `/usr/share/mime/packages/` | registers `application/x-age` → `update-mime-database` after |

**`/etc/skel` (reached by every NEW user the moment they first log in):**

| skel file | Purpose |
|---|---|
| `.config/Thunar/uca.xml` | right-click actions (see merge rules below) |
| `.bash_aliases` | guarded `lock` / `unlock` / `erase` alias block |
| `.config/openbox/rc.xml` | your WM config, with the Ctrl+Alt+E keybind present |

**Merge rules — the part that protects you:**
- **NEVER overwrite** an existing user's `uca.xml`, `rc.xml`, or
  `.bash_aliases`. System defaults only reach NEW accounts via skel
  (already-existing users keep theirs — a per-user `install.sh` run picks
  them up on first use or whenever they run it).
- `_skel`-placed alias block is the same guarded
  `# >>> lockd aliases >>> / <<<` block `install.sh` writes — safe to lift
  verbatim; if a user already defined `lock`/`unlock`/`erase` aliases
  themselves, lockd's installer leaves theirs standing (yours wins is the
  rule — we do not negotiate with the user's own muscle memory).
- Thunar's `uca.xml`: the `install.sh` thunar action blocks are what you
  lift. They expect the user to have a "Scripts/Encryption" submenu or,
  ideally, an `<name>Encrypt with keys</name>` anchor to slot next to — your
  skel uca.xml should include both. Absent the anchor, install.sh skips
  politely instead of mangling the file.
- Openbox rc.xml: `<keybind key="C-A-e">` + `<action name="Execute">` with
  `<execute>/usr/bin/lockd</execute>` before `</keyboard>`. Distros that
  already ship rc.xml edits probably have a merge/tooling line already —
  keep using it; do not clobber.

**One-time at key birth (fully automatic, protects your neighbor):**
On first `lockd` run, the user gets asked to make a passphrase-wrapped key,
which lands at `~/.config/lockd/identity.txt` (600, dir 700). A backup
tarball drops on their Desktop once, with one instruction to safeguard it.
Nothing else is written — no daemons, no autostart, no cron.


## Distro knobs

- `LOCKD_DIALOG=yad|zenity|kdialog|tty` — force the dialog backend at
  distro level. Your WM ecosystem decides; the CLI/tty path works with no
  GUI at all.
- Mailer: lockd offers "email the encrypted file(s)" via the system
  default mail handler (`xdg-email`), falling back to claws-mail — no
  config needed; whatever your distro ships as the mail client gets used.
- Clipboard: `wl-copy` → `xclip` → `xsel`, picked automatically.
- Places/bookmarks: read from the standard GTK bookmark file — your file
  manager's sidebar feeds it directly.


## Smoke test before you ship (5 minutes)

    lockd --selftest     # crypto roundtrips + plumbing, headless, silent
    touch /tmp/x && lockd /tmp/x   # first-run key birth; password, done
    lockd -d /tmp/x.age --open     # unlock; file opens
    erase /tmp/x     # if you kept the original: one line, "and just like
                     # that...gone", 3s, done (no other dialogs - shred is
                     # issued to make a thing gone)
    # right-click: Thunar → Scripts/Encryption → lockd: encrypt / decrypt
    # double-click any *.age anywhere → passphrase → opened


## Support posture

- Users: questions land fine on the GitHub Discussions tab.
- Bugs: `lockd --selftest` output attached → triage is fast.
- Anything wipe-adjacent or comet-level private: direct contact in
  SUPPORT.md.

Your keys are your users' keys: live in `~/.config/lockd/` and are NEVER
touched by packaging, updates, or uninstall unless the user explicitly
asks `uninstall.sh --purge` (which big-warns first). If a distro update
wipes `$HOME/.config/lockd` by accident, you have a bigger bug than us.

That's the whole load. cp, paste, seed, ship: your users get the good
sled, and the only thing you will ever do again is watch them smile at
"and just like that...gone".
