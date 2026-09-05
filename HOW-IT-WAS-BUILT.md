# how lockd was built

A build-and-integration notes document — for anyone curious how lockd
works the way it works, and especially for anyone who wants to fold it
(or its ideas) into a distro, a restore kit, or their own setup.

lockd itself: one word encrypts, one word unlocks. `age` does the
cryptography; lockd is everything around it — the dialogs, the
file-manager integration, and above all the *rules*: verify before
wiping, leave nothing behind, and prove it works before you trust it.

---

## The contract (release criteria, not slogans)

Everything lockd ships must survive four tests, in plain language:

1. **Stoopid easy** — three handy ways to invoke it: the command line,
   right-click in a file manager, and a keybind. A new user picks one
   and never thinks about it again.
2. **Reliably encrypted** — age underneath, passphrase-protected key,
   adopted or born on first run.
3. **WILL decrypt, every time** — the ciphertext is decrypted back and
   byte-compared against the original before anything is ever wiped.
   If verification fails for any reason, the original survives and
   lockd says so loudly.
4. **No residue, ever** — temp keys, verify workspaces, staging dirs:
   cleaned on every exit path, success, failure, or cancel.

None of that is taken on faith. Criteria 3 and 4 are **machine-checked
by `lockd --selftest`**: the selftest runs the *real* flow (key birth,
encrypt, verify-wipe, decrypt) in an isolated HOME and TMPDIR, then
asserts the payload comes back byte-perfect and the temp footprint is
empty. A residue leak fails the selftest instead of hiding.

---

## Design decisions, and why

### Any desktop, or none — the dialog backend chain

lockd started life on an openbox desktop, married to one dialog tool
(`yad`). That marriage locks out most of the Linux world: GNOME, KDE,
XFCE users don't have yad. So every window and menu now goes through a
resolved backend, chosen once per run:

```
$LOCKD_DIALOG (override) -> yad -> zenity -> kdialog -> plain terminal
```

- The override lets a user force a specific toolkit (or terminal mode)
  for testing or preference.
- The **terminal fallback is first-class, not a consolation prize**:
  the whole flow — key birth included — works over SSH with zero GUI
  installed, reading the passphrase right on the command line.
- The fast-path choice ("no other options going forward") is a checkbox
  in yad's form. zenity and kdialog have no checkbox widget, so there
  the choice becomes a follow-up question — **asked once per key
  lifetime**, then never again: one window, credentials, enter, done.
  A per-config marker remembers that the question was asked.
- Form fields are newline-separated, so passphrases containing `|` or
  `;` don't break parsing. (A passphrase containing a literal newline
  remains out of scope everywhere.)

### Clipboard, mailer, places — same chain philosophy

- **Clipboard**: `wl-copy` -> `xclip` -> `xsel`. Wayland first, X11
  next, xsel as the elder fallback. Each candidate is tried in order;
  a *present but failing* helper falls through to the next one.
- **Mailer**: `$LOCKD_MAILER` (override) -> `xdg-email` -> `claws-mail`.
  The freedesktop mailer first, because it respects the user's own
  default; the override for people with opinions.
- **Places**: the "copy to a Place" offer reads both GTK bookmarks
  (`~/.config/gtk-3.0/bookmarks`) and KDE's
  (`~/.local/share/user-places.xbel`), merged and deduplicated. The
  URL decode is deliberately rough (`%20` only) — spaces cover
  real-world bookmarks.

One practical trap worth passing on: a clipboard helper may **daemonize
while holding your stdout**. xclip forks a child that keeps the
selection alive — and if that child inherits your stdout, whatever is
waiting on your output pipe waits forever. All clipboard helpers run
with stdio redirected to /dev/null.

### Right-click: one source of truth

The nautilus-family file managers (Nautilus, Caja, Nemo) all speak the
same "scripts" protocol: drop executable scripts in the manager's
scripts directory, and the selection arrives in a newline-separated
environment variable. lockd generates those script bodies itself:

```
lockd --ctx-script encrypt|decrypt|shred
```

The installer calls that and writes the output to
`~/.local/share/nautilus/scripts/`, `~/.config/caja/scripts/`, and
`~/.local/share/nemo/scripts/` — guarded by whether each file manager
is actually installed, idempotent on re-run. The body reads whichever
selection variable the host manager sets (NEMO/CAJA/NAUTILUS_*).

Dolphin speaks a different protocol — KIO service menus. The installer
writes one `.desktop` with three actions into both
`~/.local/share/kio/servicemenus/` (Plasma 5.90+ and 6) and
`~/.local/share/kservices5/ServiceMenus/` (legacy), so one file serves
either Plasma generation.

Why generate instead of hand-copying? The **selftest tests the exact
bytes the installer will drop**, driving the script with a fake
selection (including paths with spaces) against a stub `lockd` — the
env-to-argv plumbing is proven, not assumed.

### Keybinds: guarded, never clobbering

Ctrl+Alt+E is offered on openbox (rc.xml), XFCE (xfconf-query), and
GNOME (gsettings custom keybindings). The rule everywhere: **if the
combo is already taken, lockd does not touch it** — it reports and
moves on. The GNOME case is the fiddly one: custom keybindings live in
an array of paths in `org.gnome.settings-daemon.plugins.media-keys`,
so the installer reads the array, looks for its own command, appends a
new path only when absent, and rebuilds the GVariant string. Uninstall
removes only the block whose command points at lockd — nothing else.

### The installer's manners

- **Guarded**: each desktop integration checks whether the target file
  manager / desktop is actually there, and skips politely if not.
- **Idempotent**: re-running changes nothing (checked by name for
  Thunar actions, by marker for the alias block, by command for
  keybinds).
- **Backed up**: every file it edits gets a `.bak-lockd` copy first.
- **The user's own stuff wins**: if a user already defines
  `lock`/`unlock`/`erase` aliases outside lockd's guarded block, the
  installer warns and walks away.
- On Debian-family boxes with missing packages it offers to install;
  everywhere else it prints the exact command for pacman/dnf/zypper/apk.

Package-name mapping is honest about its limits: names drift between
releases, so anything the map doesn't know is *skipped from the
suggestion* rather than guessed.

### Uninstall parity

Reversibility is a tenet. `uninstall.sh` removes every piece the
installer can create — command, desktop entries, icon, mime type,
alias block, right-click scripts, service menus, Thunar actions, and
all three keybinds (each only if it points at lockd). Keys and config
survive unless `--purge` is given, and `--purge` says plainly that
encrypted files elsewhere become unreadable forever.

### The icon

A bundled padlock SVG lands in
`~/.local/share/icons/hicolor/scalable/apps/lockd.svg` — no more
theme-dependent blank squares in the menu. Desktop entries carry
`Icon=lockd`, `Keywords=` for menu search, and are checked with
`desktop-file-validate` when present.

---

## The bugs we found (the part worth stealing)

These are the field lessons, with mechanisms, because they will bite
anyone building shell tools with traps and temp files.

### 1. A function-local variable in an EXIT trap

The original code:

```bash
do_encrypt() {
    local tmpid; tmpid=$(unlock_identity)
    trap 'shred -uzn1 "$tmpid"; ...' EXIT
    ...
}
```

The EXIT trap fires when the *script* exits — long after
`do_encrypt()` returned, with its locals long gone. Under `set -u`
the trap hit "unbound variable" **every single run**, which meant:

- every successful encrypt/decrypt **exited rc=1** (nobody noticed —
  GUI users never see an exit code), and
- the trap's first job — shredding the *unlocked plaintext key* that
  lives in a temp dir — **never ran**. Unlocked keys were piling up
  in /tmp.

Fix: the temp identity path lives in a global (`TMPID`), and a
`cleanup_ids()` helper does shred + rmdir on every exit path, success,
failure, or cancel.

**Lesson: an EXIT trap runs after every function has returned. Anything
the trap needs must outlive them.**

### 2. errexit applies inside trap handlers

The selftest cleaned up with:

```bash
trap "shred -uzn1 '$t'/* 2>/dev/null; rm -rf '$t'" EXIT
```

Once the test dir contained *directories* (it did — the directory
roundtrip test), `shred` errored on them. Under `set -e`, a failing
plain command **inside the trap handler** aborts the remaining
statements — so `rm -rf` never ran, every selftest run leaked its temp
dir, *and the failure code replaced the test result*: the screen said
PASS while the exit code said 1.

That second half is the dangerous one: anything that **gates on the
selftest's exit code** (our restore kit wires lockd in only after
`lockd --selftest` succeeds) was silently reading a lie.

Fix:

```bash
trap "set +e; find '$t' -type f -exec shred -uzn1 {} + 2>/dev/null; rm -rf '$t'" EXIT
```

`set +e` lets the cleanup run to completion regardless; `find -type f`
shreds nested files (payloads included) instead of a top-level glob.

**Lesson: put `set +e` at the top of any trap handler that must finish,
and never trust a gate that reads an exit code produced *by* a trap.**

### 3. Anchors can be first

The Thunar (uca.xml) action inserter searched *upwards* from its
anchor line for the enclosing `</action>`. When the anchor happened to
be the **first** action in the file, the upward search found nothing,
an empty string went into `int('')`, and the installer crashed. The
fix searches *downwards* for the anchor's own closing tag when the
upward search comes up empty — and the test fixture now includes that
edge (anchor-first) on purpose.

### 4. Small residue leaks

Two one-liners found by testing cancel paths: a cancelled passphrase
dialog left an empty temp workdir behind (the cancel `die` skipped the
cleanup), and temp dirs were hardcoded to `/tmp` (they now honor
`$TMPDIR`, which also makes the selftest's residue check race-free).

---

## Requirements

**Hard** (lockd will not run without them — in every distro's repos):

| Tool | Package (Debian) | Comes from |
|---|---|---|
| `age` | age | encryption |
| `age-keygen` | age | key birth |
| `shred` | coreutils | wipe semantics |
| `script` | bsdutils / util-linux | passphrase-via-pty (age reads passphrases from a terminal only) |
| `tar`, `gzip` | core of any distro | directory archives |

**Soft** (lockd degrades gracefully; the installer reports and
suggests):

| Tool | Package | If missing |
|---|---|---|
| `yad` / `zenity` / `kdialog` | any one | terminal mode only |
| `wl-clipboard` / `xclip` / `xsel` | any one | "copy public key" offer skipped |
| `notify-send` | libnotify | notifications skipped |
| `xmllint` | libxml2-utils | xml validation skipped (backups still made) |
| `desktop-file-validate` | desktop-file-utils | validation check skipped |

## What the installer touches on a user's box

| Changes | Leaves alone (if present) |
|---|---|
| `~/.local/bin/lockd` or `~/bin/lockd` | existing lock/unlock/erase aliases |
| mime type `application/x-age` | existing Thunar actions |
| bundled hicolor icon | existing Ctrl+Alt+E bindings |
| two `.desktop` entries (menu + double-click handler) | anything not lockd's |
| alias block, right-click scripts, service menus | |
| keybind (openbox / xfconf / gsettings) | |

Everything installed is user-level. Nothing needs root; the only sudo
in the installer is the optional package install, which asks first.

## Baking it into a distro or restore kit

- Put `age` plus one dialog tool plus a clipboard helper in your
  package list; the installer finds whatever it finds and tells the
  user what it skipped.
- **Gate the wiring on `lockd --selftest`** — and gate on the *exit
  code*, which is exactly why bug #2 above matters.
- If you vendor the script rather than installing from upstream, that
  is a fine pattern (our own restore kit does): embed a known snapshot,
  verify it with the selftest at wiring time, and adopt upstream
  changes on your own schedule. Bug fixes in the vendored copy should
  follow the same rules as upstream: no residue, honest exit codes.
- The key never gets born during installation — it happens on the
  user's first run, so the passphrase never passes through anything
  but the user's own hands.

## How it was tested without a stack of other desktops

The portability work happened on one openbox box. The cross-DE paths
were proven with **stub binaries and throwaway homes**:

- a fake `gsettings` / `xfconf-query` / `nautilus` on PATH ahead of
  the real ones, writing to state files the test asserts on;
- a real `desktop-file-validate` and `xmllint` for format honesty;
- a full `gsettings` state file mimicking real behavior (string values
  come back single-quoted; an empty array reads as `@as []`), which
  caught three fidelity bugs in the stubs before they could become
  bugs in the code;
- every desktop integration tested for its skip path too (the file
  manager absent → polite skip, no litter);
- install → idempotent re-run → uninstall → `--purge` as one
  roundtrip, asserting after each stage.

And the crypto + flow proof: the selftest's isolated-HOME real-flow
run, plus a seven-scenario end-to-end (key birth, encrypt+wipe,
decrypt keeping the source, fast path, directory archive restored
in place, `--keep`, and the wrong-passphrase case where the original
must survive).

## Do we track age upstream?

No — and that is deliberate. The real contract is the **age file
format**, which is frozen and versioned by design (`age-encryption.org/v1`
in every header): whatever age 1.x locks, age 1.x decrypts, forever.
Packaging and security tracking are the distro's side of the deal.
lockd leans on a handful of age CLI behaviors (`-r`, `-p -o`, `-d -i`,
and passphrases arriving via a real terminal — hence `script(1)`), and
any drift there fails **loudly at the first dialog**, not silently as
corrupt files. The selftest re-proves the roundtrip at wiring time, and
the format has independent implementations (rage and others), so the
"WILL decrypt" promise has insurance beyond any one distro.

## The Desktop backup and the one notice (2026-09-05)

The cuppa question that forced this into being: *"if I cp my key file to a
dump and copy it back into a fresh install, will filemarkers — dates,
modified times, permissions — disturb the process?"*

**The answer is no, and now it is machine-checked.** The identity file is
an age passphrase-encrypted byte blob; age decrypts bytes and nothing else.
A copy with a 1999 mtime and 777 permissions decrypts exactly like the
original. lockd additionally self-heals the real key's permissions on
every run (dir 700, identity 600), so a rough copy-back is tidied without
anyone asking.

**What shipped:** key birth now drops a dated tarball on the Desktop —
`lockd-key-YYYY-MM-DD.tar.gz`, never overwriting an earlier backup — and
the user is told exactly once, in the words they need: *safeguard it (and
the passphrase) now*. The notice is one delayed `notify-send` (6 seconds
in, 10 seconds up), backgrounded so the flow never waits on it; terminal
and SSH births get the same words on stdout. Headless boxes with no
Desktop get an honest skip line, and a failed backup can never fail the
birth — the key exists and is verified regardless.

**The honest hierarchy of what can be lost:** the identity file (now
backed up at birth, user's job to safeguard), and the passphrase (no
reset, no escrow — by design, and the notice says so). Ciphertexts bind
to the key that made them: a fresh install's new key opens nothing old;
the restored backup opens everything.

**No README section, no `--backup` flag, no reminders.** The people who
reach for encryption already know they are wearing a purple shirt. The
selftest carries the proof instead: backup → destroy → restore → decrypt,
then restore with hostile metadata → still decrypts — forever.

## Environment variables

| Variable | Meaning | Default |
|---|---|---|
| `LOCKD_DIALOG` | force a dialog backend: `yad`, `zenity`, `kdialog`, `tty` | auto: yad → zenity → kdialog → tty |
| `LOCKD_MAILER` | mailer for the "email it" offer | xdg-email → claws-mail |

lockd is MIT licensed. Take it, fold it in, make it yours — and if the
selftest fails, believe it.
