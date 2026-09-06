# lockd — lazy, kind encryption


Command line: $ lock (whatever), handy right-click in your file manager, or keybind: Ctrl+Alt+E. `age` does the cryptography
(Debian-packaged, MIT, modern); lockd does the *everything else* — people don't encrypt because 'complicated'. Nah.

[![lockd command line — click to play](cmdlnlockd_t35.jpg)](https://github.com/user-attachments/assets/43247bdc-fa3a-42a3-826e-e79db5341cc5)

```
lockd                        → pick file(s) → password → done
lockd somedir                → the directory becomes one archive, locked
lockd -d thing.age           → unlock it
lockd --keep                 → encrypt but never wipe the originals
lockd --fast                 → this run: no offers, just lock it
lockd --selftest             → prove the roundtrip + the plumbing, headless
```

The installer adds these aliases to **.bash_aliases** (guarded, yours win):

- alias lock='lockd'
- alias unlock='lockd -d'
- alias erase='lockd --shred'


## Real-world usage

```
touch rambler1.txt && lockd rambler1.txt
lock *.jpg receipt.pdf
lock taxes/                           # -> taxes.tar.gz.age
unlock rambler1.txt.age
unlock taxes.tar.gz.age --open        # decrypted result opened for you
lock --keep rambler1.txt              # original survives, verification still runs
erase old-notes.txt                   # just shred, no crypto
erase from-iphone/                    # a directory: every file inside
                                      # shredded, tree removed, gone.
```

`erase` asks nothing. Shred is issued to make a thing gone, so it goes —
no confirm, no ceremony — and the whole report arrives in one line,
three seconds on screen: **and just like that...gone**. Invoking shred
is the confirmation.
```


## THE RULE

**The original is wiped by default.**

1. lockd encrypts.
2. lockd decrypts the ciphertext back and byte-compares it against the
   original.
3. Only on a perfect match does it shred the original.
4. If verification fails for *any* reason: the original survives, the bad
   ciphertext is destroyed, and lockd says so loudly.

`--keep` skips the wipe for the faint of heart. No flag ever skips the
verification.

## The first run

No default key? lockd makes one (passphrase-protected, living at
`~/.config/lockd/identity.txt`) and remembers it. From then on, the password
you type unlocks that key. Your public key gets offered to the clipboard and
to a Place of your choosing.

[![lockd right-click — click to play](rclockd.jpg)](https://github.com/user-attachments/assets/dbd00926-2615-418f-ba5d-03d2fdc552f4)

## Fast, clean, out of your face

The password window carries a checkbox: **"No other options going forward"**.
Check it once and lockd's offers go away forever — encrypt, verify, wipe,
done. (`lockd --full` brings the offers back for one run.) zenity and
kdialog have no checkbox widget — there the choice is asked **once**, then
the window is one shot: credentials, enter, done.

## Places

The "what now?" offers read your bookmarks — GTK bookmarks (`Places` in
Thunar) and KDE's `user-places.xbel` — copy the locked file to any of them
with one pick, or hand it to your mail client.

## Any desktop, or none

lockd is not married to a desktop. Every window and menu goes through a
backend chain, resolved once per run:

- **dialogs**: `$LOCKD_DIALOG` (override) → `yad` → `zenity` → `kdialog` → plain terminal
- **clipboard**: `wl-copy` → `xclip` → `xsel`
- **mailer**: `$LOCKD_MAILER` (override) → `xdg-email` → `claws-mail`
- **right-click**: Thunar, Nautilus, Caja, Nemo (Scripts menu) and Dolphin (service menu) — the installer drops only what your desktop actually uses
- **menu + double-click**: `.desktop` entries with a bundled icon — freedesktop standard, works everywhere

The terminal fallback is real, not a consolation prize: `lockd` over SSH
asks for the passphrase right on the command line and the whole flow —
key birth included — works with zero GUI installed.

```
LOCKD_DIALOG=tty lockd file.txt      # force terminal mode on a GUI box
LOCKD_DIALOG=zenity lockd file.txt   # force zenity instead of yad
LOCKD_MAILER=mutt lockd file.txt     # hand the offer to a different mailer
```

## Keybind (Ctrl+Alt+E)

The installer sets **Ctrl+Alt+E** on openbox, XFCE (xfconf) and GNOME
(gsettings) — always guarded: if you already use that combo, lockd leaves
it alone. i3/sway users, one line each:

```
# i3 (~/.config/i3/config)
bindsym $mod+Ctrl+e exec --no-startup-id ~/.local/bin/lockd

# sway (~/.config/sway/config)
bindsym $mod+Ctrl+e exec ~/.local/bin/lockd
```

KDE: System Settings → Shortcuts → add Custom Shortcut → command
`~/.local/bin/lockd`, trigger Ctrl+Alt+E.

## Requirements

`age`, `shred`, `script` — hard requirements, in every distro's repos.
Everything else is soft and the installer says what it found: a dialog
tool (`yad`/`zenity`/`kdialog`), a clipboard helper (`wl-clipboard`/
`xclip`/`xsel`), `libnotify` for the notifications. Missing the soft
stuff just means lockd skips that offer — or runs in terminal mode.

**Distro maker?** PACKAGING.md in this repo is your whole on-ramp:
system-wide artifacts, `/etc/skel` templates, merge rules that never
clobber user configs, smoke test. Bundle lockd without ever thinking
about it again.

## Phase 2 (parked on purpose)

**Encrypted email-to-self** — lock the file, your mail client attaches
the `.age`, and the mailbox becomes a backup the provider cannot read
(claws-mail leads; mutt from the CLI; evolution/kmail later). Mail
**signing** is a different animal: age keys cannot sign — that's
deliberate in age's design — so signing stays with OpenPGP/gpg in your
mail client, where it already works. Plus: contact-card (vcf) key
sharing. The name: yes, the kernel's NFS `lockd` owns that
string in some contexts — accepted; nothing collides at the binary
level. And in george, lockd is a chip: one line in `buttons.toml`.

## License

MIT
