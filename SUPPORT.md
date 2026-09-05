# Support — the honest posture

lockd is a one-person tool, built in the open, MIT. This is what support
means here. No Discord, no forum software to babysit — the channel is
GitHub, public and archived.

## Where to go

- **Questions, usage, ideas** → [GitHub Discussions](https://github.com/rabmach/lockd/discussions)
- **Bugs** → [GitHub Issues](https://github.com/rabmach/lockd/issues) —
  run `lockd --selftest` first and paste the output, plus your desktop and
  dialog backend (yad/zenity/kdialog/tty). That one file answers most of
  triage before a human reads it.
- **Data-loss or security reports** → private first, please: use GitHub's
  **Report a vulnerability** on this repo. A wipe-path bug debugged in a
  public issue can hurt people following along. Reports stay private until
  a fix is tagged.

## What you can expect

- Issues read and answered as time allows — batched, no SLA.
- Honest triage: fixed, or marked won't-fix with the reason. No silence.
- Scope: Linux desktops with `age`, `shred`, and `script` — any dialog
  backend. Not Windows, not macOS, not exotic.

## If lockd wiped something you think it shouldn't have

Read THE RULE in the README first: originals are shredded only after the
ciphertext verifies byte-for-byte, and a failed verification keeps the
original by design. If that didn't happen for you, that is a bug and we
want the `--selftest` output and the exact command you ran.
